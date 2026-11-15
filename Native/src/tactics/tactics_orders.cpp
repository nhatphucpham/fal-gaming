#include "tactics_orders.h"

#include "tactics_combat.h"
#include "tactics_paths.h"
#include "tactics_sim.h"

namespace tactics {

namespace {

const SlotOffset FOLLOW_SLOTS[MAX_SQUAD_SIZE] = {
	{ -1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { -1, 1 }, { -2, 0 }, { -2, -1 }, { -2, 1 },
};
const SlotOffset VANGUARD_SLOTS[MAX_SQUAD_SIZE] = {
	{ 1, 0 }, { 1, -1 }, { 1, 1 }, { 2, 0 }, { 2, -1 }, { 2, 1 }, { 1, -2 }, { 1, 2 },
};
const SlotOffset FLANK_SLOTS[MAX_SQUAD_SIZE] = {
	{ 0, -1 }, { 0, 1 }, { 0, -2 }, { 0, 2 }, { -1, -1 }, { -1, 1 }, { -1, -2 }, { -1, 2 },
};

const OrderHandler ORDER_HANDLERS[] = {
	{ "order.follow", SquadMode::FORMATION, FOLLOW_SLOTS },
	{ "order.vanguard", SquadMode::FORMATION, VANGUARD_SLOTS },
	{ "order.flank", SquadMode::FORMATION, FLANK_SLOTS },
	{ "order.hold", SquadMode::HOLD, nullptr },
	{ "order.free", SquadMode::FREE, nullptr },
};
constexpr int ORDER_COUNT = sizeof(ORDER_HANDLERS) / sizeof(ORDER_HANDLERS[0]);

// The soldier took its squad step without leaving its cell.
void stay(TacticsSim &p_sim, int p_soldier) {
	UnitState &soldier = p_sim.edit_unit(p_soldier);
	soldier.was_attacked_since_move = false;
	soldier.last_attacker = NO_UNIT;
	soldier.straight_cells = 0;
}

void walk_to(TacticsSim &p_sim, int p_soldier, const PathField &p_field, const Cell &p_cell, int p_cause) {
	stay(p_sim, p_soldier);
	if (p_cell == p_sim.get_units()[p_soldier].cell) {
		return;
	}
	const std::vector<Cell> path = get_path(p_sim, p_field, p_cell);
	p_sim.edit_unit(p_soldier).straight_cells = get_trailing_straight_cells(path);
	p_sim.relocate_unit(p_soldier, path, "squad", p_cause);
}

void move_to_slot(TacticsSim &p_sim, int p_soldier, const Cell &p_slot, int p_cause) {
	const PathField field = find_paths(p_sim, p_soldier, p_sim.get_stats(p_soldier).move_points, ZocMode::APPLY);
	const Cell cell = pick_reachable_cell(p_sim, p_soldier, field, [&](const Cell &p_cell) { return get_manhattan(p_cell, p_slot); });
	walk_to(p_sim, p_soldier, field, cell, p_cause);
}

// An allied soldier within help_radius_cells that was attacked since its
// last move by a living enemy: that enemy, or NO_UNIT.
int find_enemy_to_answer(const TacticsSim &p_sim, int p_soldier) {
	const UnitState &self = p_sim.get_units()[p_soldier];
	int best_ally = NO_UNIT;
	for (const UnitState &ally : p_sim.get_units()) {
		if (ally.index == p_soldier || !ally.is_alive || ally.side != self.side || p_sim.is_leader(ally.index)) {
			continue;
		}
		if (!ally.was_attacked_since_move || ally.last_attacker == NO_UNIT || !p_sim.get_units()[ally.last_attacker].is_alive) {
			continue;
		}
		const int distance = get_manhattan(ally.cell, self.cell);
		if (distance <= p_sim.get_rules().help_radius_cells && (best_ally == NO_UNIT || distance < get_manhattan(p_sim.get_units()[best_ally].cell, self.cell))) {
			best_ally = ally.index;
		}
	}
	return best_ally == NO_UNIT ? NO_UNIT : p_sim.get_units()[best_ally].last_attacker;
}

// The enemy with the shortest path (zones of control ignored) to a cell
// the soldier could attack it from; ties to the lower index.
int find_nearest_enemy_by_path(const TacticsSim &p_sim, int p_soldier) {
	const PathField field = find_paths(p_sim, p_soldier, UNLIMITED_COST, ZocMode::IGNORE);
	int best = NO_UNIT;
	int best_cost = UNREACHABLE;
	for (const UnitState &enemy : p_sim.get_units()) {
		if (!enemy.is_alive || enemy.side == p_sim.get_units()[p_soldier].side) {
			continue;
		}
		for (const Cell &cell : get_attack_cells(p_sim, p_soldier, enemy.index)) {
			const int cost = field.cost[p_sim.get_cell_index(cell)];
			if (cost < best_cost) {
				best = enemy.index;
				best_cost = cost;
			}
		}
	}
	return best;
}

void move_free(TacticsSim &p_sim, int p_soldier, int p_cause) {
	int goal = find_enemy_to_answer(p_sim, p_soldier);
	if (goal == NO_UNIT) {
		goal = find_nearest_enemy_by_path(p_sim, p_soldier);
	}
	const PathField field = find_paths(p_sim, p_soldier, p_sim.get_stats(p_soldier).move_points, ZocMode::APPLY);
	if (goal == NO_UNIT) {
		stay(p_sim, p_soldier);
		return;
	}
	const std::vector<int> distance = find_goal_distances(p_sim, p_soldier, get_attack_cells(p_sim, p_soldier, goal));
	const Cell cell = pick_reachable_cell(p_sim, p_soldier, field, [&](const Cell &p_cell) { return distance[p_sim.get_cell_index(p_cell)]; });
	walk_to(p_sim, p_soldier, field, cell, p_cause);
}

} // namespace

int find_order_index(const std::string &p_id) {
	for (int index = 0; index < ORDER_COUNT; index++) {
		if (p_id == ORDER_HANDLERS[index].id) {
			return index;
		}
	}
	return NO_INDEX;
}

const OrderHandler &get_order_handler(int p_index) {
	return ORDER_HANDLERS[p_index];
}

int get_order_count() {
	return ORDER_COUNT;
}

std::vector<Cell> get_formation_slots(const TacticsSim &p_sim, int p_leader) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	const OrderHandler &order = get_order_handler(leader.order);
	std::vector<Cell> slots;
	if (order.mode != SquadMode::FORMATION) {
		return slots;
	}
	const Cell forward = leader.heading;
	const Cell right = { -forward.row, forward.col };
	const int shift = leader.heading_streak >= 2 ? p_sim.get_rules().anticipation_shift_cells : 0;
	for (size_t index = 0; index < leader.soldiers.size(); index++) {
		const SlotOffset &offset = order.slots[index];
		const int ahead = offset.forward + shift;
		slots.push_back({ leader.cell.col + forward.col * ahead + right.col * offset.right, leader.cell.row + forward.row * ahead + right.row * offset.right });
	}
	return slots;
}

void move_squad(TacticsSim &p_sim, int p_leader, int p_cause) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	// A squad whose leader died fights on as if ordered `free`.
	const SquadMode mode = leader.is_alive ? get_order_handler(leader.order).mode : SquadMode::FREE;
	const std::vector<Cell> slots = get_formation_slots(p_sim, p_leader);
	const std::vector<int> soldiers = leader.soldiers;
	for (size_t index = 0; index < soldiers.size(); index++) {
		const int soldier = soldiers[index];
		if (!p_sim.get_units()[soldier].is_alive) {
			continue;
		}
		if (mode == SquadMode::FORMATION) {
			move_to_slot(p_sim, soldier, slots[index], p_cause);
		} else if (mode == SquadMode::FREE) {
			move_free(p_sim, soldier, p_cause);
		} else {
			stay(p_sim, soldier);
		}
	}
}

int pick_soldier_target(const TacticsSim &p_sim, int p_soldier) {
	const int leader = p_sim.get_units()[p_soldier].leader;
	const bool has_leader = leader != NO_UNIT && p_sim.get_units()[leader].is_alive;
	int best = NO_UNIT;
	bool best_threatens = false;
	for (const UnitState &enemy : p_sim.get_units()) {
		if (!can_attack(p_sim, p_soldier, enemy.index)) {
			continue;
		}
		const bool threatens = has_leader && can_attack(p_sim, enemy.index, leader);
		if (best == NO_UNIT || (threatens && !best_threatens) || (threatens == best_threatens && enemy.hp < p_sim.get_units()[best].hp)) {
			best = enemy.index;
			best_threatens = threatens;
		}
	}
	return best;
}

void attack_with_squad(TacticsSim &p_sim, int p_leader, int p_cause) {
	const std::vector<int> soldiers = p_sim.get_units()[p_leader].soldiers;
	for (int soldier : soldiers) {
		if (p_sim.is_finished() || !p_sim.get_units()[soldier].is_alive) {
			continue;
		}
		const int target = pick_soldier_target(p_sim, soldier);
		if (target != NO_UNIT) {
			resolve_engagement(p_sim, soldier, target, p_cause);
		}
	}
}

} // namespace tactics
