#include "tactics_orders.h"

#include "tactics_brain.h"
#include "tactics_combat.h"
#include "tactics_keywords.h"
#include "tactics_paths.h"
#include "tactics_sim.h"

#include <algorithm>
#include <functional>

// The soldiers' judgement is described in Docs/systems/tactics.md,
// Soldiers. Every choice is a pure function of the battle state taken in
// squad order, so preview_squad() (moves only, on a copy) shows exactly
// where the real step puts them.

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
	{ "order.follow", SquadMode::FORMATION, FOLLOW_SLOTS, &Rules::leash_follow_cells, false },
	{ "order.vanguard", SquadMode::FORMATION, VANGUARD_SLOTS, &Rules::leash_vanguard_cells, true },
	{ "order.flank", SquadMode::FORMATION, FLANK_SLOTS, &Rules::leash_flank_cells, false },
	{ "order.hold", SquadMode::HOLD, nullptr, nullptr, false },
	{ "order.free", SquadMode::FREE, nullptr, nullptr, false },
};
constexpr int ORDER_COUNT = sizeof(ORDER_HANDLERS) / sizeof(ORDER_HANDLERS[0]);

// Walking one cell weighs this much against a role or terrain preference.
constexpr int CELL_WEIGHT = 10;
constexpr int NO_LEASH = -1;
// Keys of a cell outside the leash, or in a wall of enemy reach.
constexpr int FAR_PENALTY = 1000000;
constexpr int REACH_WEIGHT = 10000;
constexpr int NO_SHOT_PENALTY = 5000;
constexpr int SAFE_DISTANCE_CELLS = 20;
constexpr int ALLY_SUPPORT_CELLS = 2;
// Role scores: ranged troops go to the rear, sturdy ones to the front.
constexpr int RANGED_FRONT_SCORE = -2;
constexpr int STURDY_FRONT_SCORE = 1;

struct SlotPlace {
	Cell cell;
	// Cells ahead of the leader along its heading (negative: behind).
	int depth = 0;
};

// What one squad step knows about the squad, worked out before anyone moves.
struct SquadContext {
	int leader = NO_UNIT;
	bool has_leader = false;
	Cell leader_cell = NO_CELL;
	int leash = NO_LEASH;
	// Per cell: enemies that could attack it next phase.
	std::vector<int> reach;
	// Enemies that could attack the leader next phase.
	std::vector<int> leader_threats;
	int shield = NO_UNIT;
	Cell shield_cell = NO_CELL;
	// The squad already struck this phase: no stepping out to strike.
	bool has_struck = false;
};

// A soldier walks within what is left of its own move points this phase,
// so a squad that steps after every leader move gains no distance from it.
void walk_to(TacticsSim &p_sim, int p_soldier, const PathField &p_field, const Cell &p_cell, int p_cause) {
	if (p_cell == p_sim.get_units()[p_soldier].cell) {
		return;
	}
	p_sim.walk_unit(p_soldier, get_path(p_sim, p_field, p_cell), p_field.cost[p_sim.get_cell_index(p_cell)], "squad", p_cause);
}

PathField find_step_paths(const TacticsSim &p_sim, int p_soldier) {
	return find_move_paths(p_sim, p_soldier);
}

std::vector<SlotPlace> build_slots(const TacticsSim &p_sim, int p_leader) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	const OrderHandler &order = get_order_handler(leader.order);
	std::vector<SlotPlace> slots;
	// A squad whose leader died fights as `free` (move_squad): no slots.
	if (!leader.is_alive || order.mode != SquadMode::FORMATION) {
		return slots;
	}
	int living = 0;
	for (int soldier : leader.soldiers) {
		living += p_sim.get_units()[soldier].is_alive ? 1 : 0;
	}
	const Cell forward = leader.heading;
	const Cell right = { -forward.row, forward.col };
	const int shift = leader.heading_streak >= 2 ? p_sim.get_rules().anticipation_shift_cells : 0;
	for (int index = 0; index < living && index < MAX_SQUAD_SIZE; index++) {
		const SlotOffset &offset = order.slots[index];
		const int ahead = offset.forward + shift;
		SlotPlace place;
		place.cell = { leader.cell.col + forward.col * ahead + right.col * offset.right, leader.cell.row + forward.row * ahead + right.row * offset.right };
		place.depth = offset.forward;
		slots.push_back(place);
	}
	return slots;
}

bool is_hurt(const TacticsSim &p_sim, int p_unit) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	return unit.hp * 100 <= unit.def.max_hp * p_sim.get_rules().retreat_hp_pct;
}

bool is_ranged(const TacticsSim &p_sim, int p_unit) {
	return p_sim.get_units()[p_unit].def.is_ranged || p_sim.get_stats(p_unit).max_range_cells > 1;
}

// A shield or first-strike keyword, or more armor than the squad's average.
bool is_sturdy(const TacticsSim &p_sim, int p_soldier, int p_average_armor) {
	for (const KeywordDef *keyword : p_sim.collect_keywords(p_soldier)) {
		if (keyword->handler->modify_incoming_as_ally != nullptr || keyword->handler->strikes_first != nullptr) {
			return true;
		}
	}
	return p_sim.get_stats(p_soldier).armor > p_average_armor;
}

int get_average_armor(const TacticsSim &p_sim, const std::vector<int> &p_soldiers) {
	int total = 0;
	for (int soldier : p_soldiers) {
		total += p_sim.get_stats(soldier).armor;
	}
	return p_soldiers.empty() ? 0 : total / static_cast<int>(p_soldiers.size());
}

int get_front_score(const TacticsSim &p_sim, int p_soldier, int p_average_armor) {
	if (is_ranged(p_sim, p_soldier)) {
		return RANGED_FRONT_SCORE;
	}
	return is_sturdy(p_sim, p_soldier, p_average_armor) ? STURDY_FRONT_SCORE : 0;
}

int count_bits(unsigned p_mask) {
	int count = 0;
	for (; p_mask != 0; p_mask &= p_mask - 1) {
		count++;
	}
	return count;
}

// The slot of each mover, matched for the lowest total of walking and role
// cost (an exact assignment over at most eight slots; ties keep the lower
// slot for the earlier soldier). Matching by total distance keeps paths
// from criss-crossing.
std::vector<int> assign_slots(const TacticsSim &p_sim, const std::vector<int> &p_movers, const std::vector<SlotPlace> &p_slots) {
	const int mover_count = static_cast<int>(p_movers.size());
	const int slot_count = static_cast<int>(p_slots.size());
	std::vector<int> assignment(mover_count, NO_INDEX);
	if (mover_count == 0 || slot_count < mover_count) {
		return assignment;
	}
	const int average_armor = get_average_armor(p_sim, p_movers);
	const int weight = p_sim.get_rules().role_slot_weight;
	std::vector<std::vector<int>> cost(mover_count, std::vector<int>(slot_count, 0));
	for (int mover = 0; mover < mover_count; mover++) {
		const Cell cell = p_sim.get_units()[p_movers[mover]].cell;
		const int front = get_front_score(p_sim, p_movers[mover], average_armor);
		for (int slot = 0; slot < slot_count; slot++) {
			cost[mover][slot] = get_manhattan(cell, p_slots[slot].cell) * CELL_WEIGHT - weight * front * p_slots[slot].depth;
		}
	}
	const unsigned full = 1u << slot_count;
	const int unset = UNREACHABLE;
	std::vector<int> best(full, unset);
	std::vector<int> came_from(full, NO_INDEX);
	std::vector<int> slot_taken(full, NO_INDEX);
	best[0] = 0;
	for (unsigned mask = 0; mask < full; mask++) {
		const int placed = count_bits(mask);
		if (best[mask] == unset || placed >= mover_count) {
			continue;
		}
		for (int slot = 0; slot < slot_count; slot++) {
			const unsigned next = mask | (1u << slot);
			if (next == mask) {
				continue;
			}
			const int total = best[mask] + cost[placed][slot];
			if (total < best[next]) {
				best[next] = total;
				came_from[next] = static_cast<int>(mask);
				slot_taken[next] = slot;
			}
		}
	}
	unsigned end = 0;
	bool found = false;
	for (unsigned mask = 0; mask < full; mask++) {
		if (count_bits(mask) == mover_count && best[mask] != unset && (!found || best[mask] < best[end])) {
			end = mask;
			found = true;
		}
	}
	for (int mover = mover_count - 1; mover >= 0; mover--) {
		assignment[mover] = slot_taken[end];
		end = static_cast<unsigned>(came_from[end]);
	}
	return assignment;
}

bool is_in_leash(const SquadContext &p_context, const Cell &p_cell) {
	return p_context.leash == NO_LEASH || get_manhattan(p_cell, p_context.leader_cell) <= p_context.leash;
}

bool contains(const std::vector<int> &p_list, int p_value) {
	for (int value : p_list) {
		if (value == p_value) {
			return true;
		}
	}
	return false;
}

// How much p_enemy threatens the leader: 0 it can strike it now, 1 it can
// reach it next phase, 2 neither.
int get_threat_rank(const TacticsSim &p_sim, int p_enemy, int p_leader, const std::vector<int> &p_threats) {
	if (p_leader != NO_UNIT && can_attack(p_sim, p_enemy, p_leader)) {
		return 0;
	}
	return contains(p_threats, p_enemy) ? 1 : 2;
}

int get_nearest_enemy_distance(const TacticsSim &p_sim, int p_side, const Cell &p_cell) {
	int nearest = SAFE_DISTANCE_CELLS;
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.is_alive && unit.side != p_side && p_sim.is_on_map(unit.cell) && p_sim.is_unit_seen_by(p_side, unit.index)) {
			const int distance = get_manhattan(unit.cell, p_cell);
			nearest = distance < nearest ? distance : nearest;
		}
	}
	return nearest;
}

bool has_target_from(const TacticsSim &p_sim, int p_unit, const Cell &p_cell) {
	const int side = p_sim.get_units()[p_unit].side;
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.is_alive && unit.side != side && p_sim.is_on_map(unit.cell) && p_sim.is_unit_seen_by(side, unit.index) && is_in_range_from(p_sim, p_unit, p_cell, unit.cell)) {
			return true;
		}
	}
	return false;
}

// A ranged soldier next to a living enemy cannot shoot it and is struck
// for free: it never steps onto such a cell. p_spared is an enemy the
// strike from there kills (it no longer counts).
bool is_exposed(const TacticsSim &p_sim, int p_soldier, const Cell &p_cell, int p_spared) {
	if (!is_ranged(p_sim, p_soldier)) {
		return false;
	}
	const int side = p_sim.get_units()[p_soldier].side;
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.is_alive && unit.side != side && unit.index != p_spared && p_sim.is_on_map(unit.cell) && p_sim.is_unit_seen_by(side, unit.index) && get_manhattan(unit.cell, p_cell) == 1) {
			return true;
		}
	}
	return false;
}

// The strikes that do not leave a ranged soldier next to an enemy.
std::vector<Strike> drop_exposed(const TacticsSim &p_sim, int p_soldier, const std::vector<Strike> &p_strikes) {
	std::vector<Strike> kept;
	for (const Strike &strike : p_strikes) {
		if (!is_exposed(p_sim, p_soldier, strike.cell, strike.result.is_defender_dead ? strike.target : NO_UNIT)) {
			kept.push_back(strike);
		}
	}
	return kept;
}

int get_reach_at(const SquadContext &p_context, const TacticsSim &p_sim, const Cell &p_cell) {
	return p_context.reach.empty() ? 0 : p_context.reach[p_sim.get_cell_index(p_cell)];
}

// The lowest key wins; equal keys keep the earlier strike (cell order).
const Strike *pick_strike(const std::vector<Strike> &p_strikes, const std::function<std::vector<int>(const Strike &)> &p_key) {
	const Strike *best = nullptr;
	std::vector<int> best_key;
	for (const Strike &strike : p_strikes) {
		if (!is_favourable(strike.result)) {
			continue;
		}
		const std::vector<int> key = p_key(strike);
		if (best == nullptr || key < best_key) {
			best = &strike;
			best_key = key;
		}
	}
	return best;
}

// A hurt soldier: the reachable cell the fewest enemies can reach, then (if
// ranged) one it can still shoot from, then the farthest from the nearest
// enemy, within the leash or no farther from the leader than p_anchor.
void fall_back(TacticsSim &p_sim, const SquadContext &p_context, int p_soldier, const PathField &p_field, const Cell &p_anchor, int p_cause) {
	const int side = p_sim.get_units()[p_soldier].side;
	const bool shoots = is_ranged(p_sim, p_soldier);
	const int limit = p_context.has_leader && p_context.leash != NO_LEASH ? std::max(p_context.leash, get_manhattan(p_anchor, p_context.leader_cell)) : NO_LEASH;
	const Cell cell = pick_reachable_cell(p_sim, p_soldier, p_field, [&](const Cell &p_cell) {
		int key = 0;
		if (limit != NO_LEASH) {
			const int over = get_manhattan(p_cell, p_context.leader_cell) - limit;
			key += over > 0 ? FAR_PENALTY * over : 0;
		}
		key += get_reach_at(p_context, p_sim, p_cell) * REACH_WEIGHT;
		key += shoots && !has_target_from(p_sim, p_soldier, p_cell) ? NO_SHOT_PENALTY : 0;
		key += (SAFE_DISTANCE_CELLS - get_nearest_enemy_distance(p_sim, side, p_cell)) * 100;
		const int anchor_distance = get_manhattan(p_cell, p_anchor);
		return key + (anchor_distance < 49 ? anchor_distance : 49);
	});
	walk_to(p_sim, p_soldier, p_field, cell, p_cause);
}

void move_in_formation(TacticsSim &p_sim, const SquadContext &p_context, int p_soldier, const Cell &p_slot, int p_cause) {
	const PathField field = find_step_paths(p_sim, p_soldier);
	if (p_soldier == p_context.shield) {
		const Cell block = p_context.shield_cell;
		const Cell cell = pick_reachable_cell(p_sim, p_soldier, field, [&](const Cell &p_cell) { return get_manhattan(p_cell, block); });
		walk_to(p_sim, p_soldier, field, cell, p_cause);
		return;
	}
	if (is_hurt(p_sim, p_soldier)) {
		fall_back(p_sim, p_context, p_soldier, field, p_slot, p_cause);
		return;
	}
	// The slot, or the nearest free cell to it, the better terrain on a tie;
	// a ranged soldier keeps clear of enemies (its own cell always is).
	const Cell slot_cell = pick_reachable_cell(p_sim, p_soldier, field, [&](const Cell &p_cell) {
		const int exposed = is_exposed(p_sim, p_soldier, p_cell, NO_UNIT) ? FAR_PENALTY : 0;
		return exposed + get_manhattan(p_cell, p_slot) * CELL_WEIGHT - get_terrain_fit(p_sim, p_soldier, p_cell);
	});
	std::vector<Strike> strikes;
	if (!p_context.has_struck) {
		strikes = drop_exposed(p_sim, p_soldier, list_strikes(p_sim, p_soldier, field, [&](const Cell &p_cell) { return is_in_leash(p_context, p_cell); }));
	}
	const Strike *best = pick_strike(strikes, [&](const Strike &p_strike) {
		return std::vector<int>{
			p_strike.cell == slot_cell ? 0 : 1,
			p_strike.result.is_defender_dead ? 0 : 1,
			get_threat_rank(p_sim, p_strike.target, p_context.has_leader ? p_context.leader : NO_UNIT, p_context.leader_threats),
			get_taken(p_strike.result) - get_dealt(p_strike.result),
			get_reach_at(p_context, p_sim, p_strike.cell),
			get_manhattan(p_strike.cell, p_slot),
			p_strike.cost,
		};
	});
	walk_to(p_sim, p_soldier, field, best != nullptr ? best->cell : slot_cell, p_cause);
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
		if (!enemy.is_alive || enemy.side == p_sim.get_units()[p_soldier].side || !p_sim.is_unit_seen_by(p_sim.get_units()[p_soldier].side, enemy.index)) {
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

// Another unit of the soldier's side already strikes p_target.
bool is_engaged_by_ally(const TacticsSim &p_sim, int p_soldier, int p_target) {
	const int side = p_sim.get_units()[p_soldier].side;
	for (const UnitState &ally : p_sim.get_units()) {
		if (ally.index != p_soldier && ally.is_alive && ally.side == side && can_attack(p_sim, ally.index, p_target)) {
			return true;
		}
	}
	return false;
}

int count_allies_near(const TacticsSim &p_sim, int p_soldier, const Cell &p_cell) {
	const int side = p_sim.get_units()[p_soldier].side;
	int count = 0;
	for (const UnitState &ally : p_sim.get_units()) {
		if (ally.index != p_soldier && ally.is_alive && ally.side == side && p_sim.is_on_map(ally.cell) && get_manhattan(ally.cell, p_cell) <= ALLY_SUPPORT_CELLS) {
			count++;
		}
	}
	return count;
}

void move_free(TacticsSim &p_sim, const SquadContext &p_context, int p_soldier, int p_cause) {
	const PathField field = find_step_paths(p_sim, p_soldier);
	const Cell own = p_sim.get_units()[p_soldier].cell;
	if (is_hurt(p_sim, p_soldier)) {
		SquadContext loose = p_context;
		loose.leash = NO_LEASH;
		fall_back(p_sim, loose, p_soldier, field, own, p_cause);
		return;
	}
	const int answer = find_enemy_to_answer(p_sim, p_soldier);
	std::vector<Strike> strikes;
	if (!p_context.has_struck) {
		strikes = drop_exposed(p_sim, p_soldier, list_strikes(p_sim, p_soldier, field, [](const Cell &) { return true; }));
	}
	const Strike *best = pick_strike(strikes, [&](const Strike &p_strike) {
		return std::vector<int>{
			p_strike.result.is_defender_dead ? 0 : 1,
			p_strike.target == answer ? 0 : 1,
			is_engaged_by_ally(p_sim, p_soldier, p_strike.target) ? 0 : 1,
			get_taken(p_strike.result) - get_dealt(p_strike.result),
			get_reach_at(p_context, p_sim, p_strike.cell),
			p_strike.cost,
		};
	});
	if (best != nullptr) {
		walk_to(p_sim, p_soldier, field, best->cell, p_cause);
		return;
	}
	const int goal = answer != NO_UNIT ? answer : find_nearest_enemy_by_path(p_sim, p_soldier);
	if (goal == NO_UNIT) {
		return;
	}
	// No fight worth taking: close in, but stop short of a cell that more
	// enemies can reach than allies stand by.
	const int limit = p_sim.get_rules().free_threat_limit;
	const std::vector<int> distance = find_goal_distances(p_sim, p_soldier, get_attack_cells(p_sim, p_soldier, goal));
	const Cell cell = pick_reachable_cell(p_sim, p_soldier, field, [&](const Cell &p_cell) {
		const int reach = get_reach_at(p_context, p_sim, p_cell);
		const bool is_walled = reach >= limit && reach > count_allies_near(p_sim, p_soldier, p_cell);
		const bool is_unsafe = is_walled || is_exposed(p_sim, p_soldier, p_cell, NO_UNIT);
		return (is_unsafe ? FAR_PENALTY : 0) + distance[p_sim.get_cell_index(p_cell)];
	});
	walk_to(p_sim, p_soldier, field, cell, p_cause);
}

// The cell next to the leader on the shortest way in for the nearest enemy
// that can reach it, and the squad's nearest sturdy soldier (else the
// nearest melee one) to stand there; nothing when no soldier fits.
void pick_shield(const TacticsSim &p_sim, const std::vector<int> &p_movers, SquadContext &r_context) {
	const UnitState &leader = p_sim.get_units()[r_context.leader];
	if (r_context.leader_threats.empty() || leader.hp * 100 > leader.def.max_hp * p_sim.get_rules().shield_leader_hp_pct) {
		return;
	}
	int enemy = NO_UNIT;
	for (int threat : r_context.leader_threats) {
		const Cell cell = p_sim.get_units()[threat].cell;
		if (enemy == NO_UNIT || get_manhattan(cell, leader.cell) < get_manhattan(p_sim.get_units()[enemy].cell, leader.cell)) {
			enemy = threat;
		}
	}
	const int average_armor = get_average_armor(p_sim, p_movers);
	int shield = NO_UNIT;
	int shield_rank = 0;
	for (int soldier : p_movers) {
		if (is_hurt(p_sim, soldier) || is_ranged(p_sim, soldier)) {
			continue;
		}
		const int front = get_front_score(p_sim, soldier, average_armor);
		const int rank = (front > 0 ? 0 : 1000) + get_manhattan(p_sim.get_units()[soldier].cell, leader.cell);
		if (shield == NO_UNIT || rank < shield_rank) {
			shield = soldier;
			shield_rank = rank;
		}
	}
	if (shield == NO_UNIT) {
		return;
	}
	const Cell enemy_cell = p_sim.get_units()[enemy].cell;
	Cell block = NO_CELL;
	for (const Cell &direction : DIRECTIONS) {
		const Cell cell = leader.cell + direction;
		if (!can_stop_at(p_sim, shield, cell)) {
			continue;
		}
		if (block == NO_CELL || get_manhattan(cell, enemy_cell) < get_manhattan(block, enemy_cell) ||
				(get_manhattan(cell, enemy_cell) == get_manhattan(block, enemy_cell) && p_sim.get_cell_index(cell) < p_sim.get_cell_index(block))) {
			block = cell;
		}
	}
	if (block == NO_CELL) {
		return;
	}
	r_context.shield = shield;
	r_context.shield_cell = block;
}

// The enemy p_soldier strikes now, given the squadmates still to strike.
int choose_target(const TacticsSim &p_sim, int p_soldier, const std::vector<int> &p_mates, bool p_risks, int p_leader, const std::vector<int> &p_threats) {
	int best = NO_UNIT;
	std::vector<int> best_key;
	for (const UnitState &enemy : p_sim.get_units()) {
		if (!can_attack(p_sim, p_soldier, enemy.index)) {
			continue;
		}
		const EngagementResult result = predict_engagement(p_sim, p_soldier, enemy.index);
		if (result.is_attacker_dead && !result.is_defender_dead && !p_risks) {
			continue;
		}
		bool can_finish = result.is_defender_dead;
		if (!can_finish) {
			int total = get_dealt(result);
			for (int mate : p_mates) {
				if (mate != p_soldier && can_attack(p_sim, mate, enemy.index)) {
					total += get_dealt(predict_engagement(p_sim, mate, enemy.index));
				}
			}
			can_finish = total >= enemy.hp;
		}
		const std::vector<int> key = {
			result.is_defender_dead ? 0 : 1,
			can_finish ? 0 : 1,
			get_threat_rank(p_sim, enemy.index, p_leader, p_threats),
			get_taken(result) - get_dealt(result),
			enemy.hp,
			enemy.index,
		};
		if (best == NO_UNIT || key < best_key) {
			best = enemy.index;
			best_key = key;
		}
	}
	return best;
}

bool does_risk_soldiers(const TacticsSim &p_sim, int p_leader) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	return leader.is_alive && get_order_handler(leader.order).risks_soldiers;
}

std::vector<int> find_leader_threats(const TacticsSim &p_sim, int p_leader) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	return leader.is_alive ? find_enemies_reaching(p_sim, leader.side, leader.cell) : std::vector<int>();
}

bool can_strike_anyone(const TacticsSim &p_sim, int p_soldier) {
	for (const UnitState &enemy : p_sim.get_units()) {
		if (can_attack(p_sim, p_soldier, enemy.index)) {
			return true;
		}
	}
	return false;
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
	std::vector<Cell> cells;
	for (const SlotPlace &place : build_slots(p_sim, p_leader)) {
		cells.push_back(place.cell);
	}
	return cells;
}

void move_squad(TacticsSim &p_sim, int p_leader, int p_cause) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	// A squad whose leader died fights on as if ordered `free`.
	const SquadMode mode = leader.is_alive ? get_order_handler(leader.order).mode : SquadMode::FREE;
	const std::vector<int> soldiers = leader.soldiers;
	SquadContext context;
	context.leader = p_leader;
	context.has_leader = leader.is_alive;
	context.has_struck = leader.has_squad_struck;
	context.leader_cell = leader.cell;
	const OrderHandler &order = get_order_handler(leader.order);
	if (leader.is_alive && order.leash_cells != nullptr) {
		context.leash = p_sim.get_rules().*order.leash_cells;
	}
	// Incidents: a wavering soldier hesitates (no step), one standing its
	// ground stays, a discontented one acts on its own
	// (Docs/systems/tactics.md, Incidents).
	std::vector<int> movers;
	bool has_thinker = false;
	for (int soldier : soldiers) {
		const UnitState &unit = p_sim.get_units()[soldier];
		if (!unit.is_alive || unit.stage == IncidentStage::WAVERING || p_sim.is_holding_ground(soldier)) {
			continue;
		}
		has_thinker = has_thinker || mode != SquadMode::HOLD || p_sim.is_acting_free(soldier);
		if (mode == SquadMode::FORMATION && !p_sim.is_acting_free(soldier)) {
			movers.push_back(soldier);
		}
	}
	if (has_thinker) {
		const Cell watch = leader.is_alive ? leader.cell : NO_CELL;
		context.reach = count_enemy_reach(p_sim, leader.side, watch, &context.leader_threats);
	}
	const std::vector<SlotPlace> slots = build_slots(p_sim, p_leader);
	const std::vector<int> assignment = assign_slots(p_sim, movers, slots);
	if (mode == SquadMode::FORMATION) {
		pick_shield(p_sim, movers, context);
	}
	for (int soldier : soldiers) {
		const UnitState &unit = p_sim.get_units()[soldier];
		if (!unit.is_alive || unit.stage == IncidentStage::WAVERING) {
			continue;
		}
		if (p_sim.is_holding_ground(soldier)) {
			continue;
		} else if (mode == SquadMode::FREE || p_sim.is_acting_free(soldier)) {
			move_free(p_sim, context, soldier, p_cause);
		} else if (mode == SquadMode::FORMATION) {
			int slot = NO_INDEX;
			for (size_t index = 0; index < movers.size(); index++) {
				slot = movers[index] == soldier ? assignment[index] : slot;
			}
			const Cell target = slot == NO_INDEX ? p_sim.get_units()[soldier].cell : slots[slot].cell;
			move_in_formation(p_sim, context, soldier, target, p_cause);
		}
	}
}

void attack_with_squad(TacticsSim &p_sim, int p_leader, int p_cause) {
	const std::vector<int> soldiers = p_sim.get_units()[p_leader].soldiers;
	// An attack on a soldier is answered by its free allies until its squad
	// strikes (which is after its last step that phase).
	for (int soldier : soldiers) {
		UnitState &unit = p_sim.edit_unit(soldier);
		if (unit.is_alive && unit.stage != IncidentStage::WAVERING) {
			unit.was_attacked_since_move = false;
			unit.last_attacker = NO_UNIT;
		}
	}
	const bool risks = does_risk_soldiers(p_sim, p_leader);
	// A wavering soldier hesitates: it neither strikes nor counts as a
	// squadmate that will strike (Docs/systems/tactics.md, Incidents).
	std::vector<int> remaining;
	bool any_strike = false;
	for (int soldier : soldiers) {
		if (p_sim.get_units()[soldier].is_alive && p_sim.get_units()[soldier].stage != IncidentStage::WAVERING) {
			remaining.push_back(soldier);
			any_strike = any_strike || can_strike_anyone(p_sim, soldier);
		}
	}
	if (!any_strike) {
		return;
	}
	const std::vector<int> threats = find_leader_threats(p_sim, p_leader);
	const int living_leader = p_sim.get_units()[p_leader].is_alive ? p_leader : NO_UNIT;
	for (int soldier : remaining) {
		if (p_sim.is_finished() || !p_sim.get_units()[soldier].is_alive) {
			continue;
		}
		std::vector<int> mates;
		bool is_past = false;
		for (int mate : remaining) {
			is_past = is_past || mate == soldier;
			if (is_past && mate != soldier && p_sim.get_units()[mate].is_alive) {
				mates.push_back(mate);
			}
		}
		const int target = choose_target(p_sim, soldier, mates, risks, living_leader, threats);
		if (target != NO_UNIT) {
			resolve_engagement(p_sim, soldier, target, p_cause);
		}
	}
}

} // namespace tactics
