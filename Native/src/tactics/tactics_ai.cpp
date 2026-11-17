#include "tactics_ai.h"

#include "tactics_brain.h"
#include "tactics_combat.h"
#include "tactics_paths.h"
#include "tactics_sim.h"
#include "tactics_skills.h"

namespace tactics {

namespace {

// The seen enemy with the shortest path (zones of control ignored) to a
// cell the leader could attack it from; ties to the lower index.
int find_nearest_enemy(const TacticsSim &p_sim, int p_leader) {
	const PathField field = find_paths(p_sim, p_leader, UNLIMITED_COST, ZocMode::IGNORE);
	const int side = p_sim.get_units()[p_leader].side;
	int best = NO_UNIT;
	int best_cost = UNREACHABLE;
	for (const UnitState &enemy : p_sim.get_units()) {
		if (!enemy.is_alive || enemy.side == side || !p_sim.is_unit_seen_by(side, enemy.index)) {
			continue;
		}
		for (const Cell &cell : get_attack_cells(p_sim, p_leader, enemy.index)) {
			const int cost = field.cost[p_sim.get_cell_index(cell)];
			if (cost < best_cost) {
				best = enemy.index;
				best_cost = cost;
			}
		}
	}
	return best;
}

// Where a leader that sees no enemy marches (Docs/systems/tactics_vision.md,
// AI): the nearest cell an enemy was last seen on, else the objective it
// must take, else the cells its side has never seen. Empty: it stays.
std::vector<Cell> find_search_goals(const TacticsSim &p_sim, int p_leader) {
	const int side = p_sim.get_units()[p_leader].side;
	const PathField field = find_paths(p_sim, p_leader, UNLIMITED_COST, ZocMode::IGNORE);
	Cell best = NO_CELL;
	int best_cost = UNREACHABLE;
	for (const UnitState &enemy : p_sim.get_units()) {
		const Cell last = p_sim.get_last_seen(side, enemy.index);
		if (last == NO_CELL || !p_sim.is_on_map(last)) {
			continue;
		}
		const int cost = field.cost[p_sim.get_cell_index(last)];
		if (best == NO_CELL || cost < best_cost) {
			best = last;
			best_cost = cost;
		}
	}
	if (best != NO_CELL) {
		return { best };
	}
	const MapDef &map = p_sim.get_map();
	if (map.has_objective && map.objective_side == side) {
		return { map.objective };
	}
	std::vector<Cell> unseen;
	for (int index = 0; index < map.width * map.height; index++) {
		if (!p_sim.is_cell_seen(side, p_sim.get_cell_at(index))) {
			unseen.push_back(p_sim.get_cell_at(index));
		}
	}
	return unseen;
}

// Hold-cell keys: leaving the post area outweighs the enemy reach, which
// outweighs the terrain fit (-9..9).
constexpr int HOLD_OUTSIDE_WEIGHT = 1000;
constexpr int HOLD_REACH_WEIGHT = 20;

bool is_fighting(const UnitState &p_unit) {
	return p_unit.is_alive && !p_unit.has_fled;
}

// Summed hp of p_side's fighting units within p_radius cells of p_cell
// (any distance when p_radius is negative), leaving p_skip out, as p_viewer
// knows them: an enemy it does not see counts where it was last seen, or
// not at all.
int sum_strength(const TacticsSim &p_sim, int p_viewer, int p_side, const Cell &p_cell, int p_radius, int p_skip = NO_UNIT) {
	int strength = 0;
	for (const UnitState &unit : p_sim.get_units()) {
		if (!is_fighting(unit) || unit.side != p_side || unit.index == p_skip || !p_sim.is_on_map(unit.cell)) {
			continue;
		}
		Cell cell = unit.cell;
		if (unit.side != p_viewer && !p_sim.is_unit_seen_by(p_viewer, unit.index)) {
			cell = p_sim.get_last_seen(p_viewer, unit.index);
			if (cell == NO_CELL) {
				continue;
			}
		}
		if (p_radius < 0 || get_manhattan(cell, p_cell) <= p_radius) {
			strength += unit.hp;
		}
	}
	return strength;
}

// The side that defends the map's objective plays the guard: it holds its
// posts while weaker and strikes only where it is locally stronger.
bool is_guard_side(const TacticsSim &p_sim, int p_side) {
	return p_sim.get_map().has_objective && p_sim.get_map().objective_side != p_side;
}

// The guard side has grown strong enough to leave its posts. Under fog it
// weighs the enemies it sees or remembers; seeing none, it does not know
// it is stronger and keeps its posts.
bool is_advancing(const TacticsSim &p_sim, int p_side) {
	const Rules &rules = p_sim.get_rules();
	const int ours = sum_strength(p_sim, p_side, p_side, NO_CELL, -1);
	const int theirs = sum_strength(p_sim, p_side, 1 - p_side, NO_CELL, -1);
	if (theirs == 0 && p_sim.has_fog_of_war()) {
		return false;
	}
	return static_cast<int64_t>(ours) * 100 >= static_cast<int64_t>(theirs) * rules.ai_advance_ratio_pct;
}

// The guard strikes where its hp around the strike cell (the leader's own
// included) is at least ai_attack_ratio_pct % of the enemy's around the
// target, or when the blow kills a leader.
bool has_local_edge(const TacticsSim &p_sim, int p_leader, const Strike &p_strike) {
	if (p_strike.result.is_defender_dead && p_sim.is_leader(p_strike.target)) {
		return true;
	}
	const Rules &rules = p_sim.get_rules();
	const UnitState &leader = p_sim.get_units()[p_leader];
	const int ours = leader.hp + sum_strength(p_sim, leader.side, leader.side, p_strike.cell, rules.ai_strength_radius_cells, p_leader);
	const int theirs = sum_strength(p_sim, leader.side, 1 - leader.side, p_sim.get_units()[p_strike.target].cell, rules.ai_strength_radius_cells);
	return static_cast<int64_t>(ours) * 100 >= static_cast<int64_t>(theirs) * rules.ai_attack_ratio_pct;
}

// The guard leader's post: the map's guard cells are shared out in unit
// order, each leader taking the nearest one not taken yet; the objective
// when none is left.
Cell find_post(const TacticsSim &p_sim, int p_leader) {
	const MapDef &map = p_sim.get_map();
	std::vector<bool> is_taken(map.guard_cells.size(), false);
	for (const UnitState &unit : p_sim.get_units()) {
		if (!is_fighting(unit) || !p_sim.is_leader(unit.index) || unit.side != p_sim.get_units()[p_leader].side) {
			continue;
		}
		int best = NO_INDEX;
		for (size_t index = 0; index < map.guard_cells.size(); index++) {
			if (!is_taken[index] && (best == NO_INDEX || get_manhattan(unit.cell, map.guard_cells[index]) < get_manhattan(unit.cell, map.guard_cells[best]))) {
				best = static_cast<int>(index);
			}
		}
		if (unit.index == p_leader) {
			return best == NO_INDEX ? map.objective : map.guard_cells[best];
		}
		if (best != NO_INDEX) {
			is_taken[best] = true;
		}
	}
	return map.objective;
}

// Where a guard leader waits: within ai_hold_radius_cells of its post
// (else as near as it gets), on the cell the fewest enemies can reach,
// then the best terrain.
Cell pick_hold_cell(const TacticsSim &p_sim, int p_leader, const PathField &p_field) {
	const Rules &rules = p_sim.get_rules();
	const MapDef &map = p_sim.get_map();
	const Cell post = find_post(p_sim, p_leader);
	std::vector<Cell> area;
	for (int index = 0; index < map.width * map.height; index++) {
		const Cell cell = p_sim.get_cell_at(index);
		if (get_manhattan(cell, post) <= rules.ai_hold_radius_cells) {
			area.push_back(cell);
		}
	}
	const std::vector<int> outside = find_goal_distances(p_sim, p_leader, area);
	const std::vector<int> reach = count_enemy_reach(p_sim, p_sim.get_units()[p_leader].side);
	return pick_reachable_cell(p_sim, p_leader, p_field, [&](const Cell &p_cell) {
		const int index = p_sim.get_cell_index(p_cell);
		const int away = outside[index] >= UNREACHABLE ? UNREACHABLE / (2 * HOLD_OUTSIDE_WEIGHT) : outside[index];
		return away * HOLD_OUTSIDE_WEIGHT + reach[index] * HOLD_REACH_WEIGHT - get_terrain_fit(p_sim, p_leader, p_cell);
	});
}

struct Aim {
	int target = NO_UNIT;
	// The cell to strike from this phase, NO_CELL when out of reach.
	Cell strike_cell = NO_CELL;
	// A guard with nothing worth striking that waits near its post.
	bool is_holding = false;
	// With no seen enemy: the cells it marches toward instead.
	std::vector<Cell> search_goals;
};

// What the leader goes for: among enemies it can strike this phase without
// dying to the counter for nothing (a guard: only with a local edge), a
// leader before a soldier, a kill before a hit, then (a guard) the target
// with the least help around it, then the lowest hp, struck from the
// safest cell; else the nearest enemy by path.
Aim pick_ai_aim(const TacticsSim &p_sim, int p_leader) {
	Aim aim;
	const PathField field = find_move_paths(p_sim, p_leader);
	const std::vector<Strike> all_strikes = list_strikes(p_sim, p_leader, field, [](const Cell &) { return true; });
	const int side = p_sim.get_units()[p_leader].side;
	const bool is_guard = is_guard_side(p_sim, side);
	std::vector<Strike> strikes;
	for (const Strike &strike : all_strikes) {
		if (!is_guard || has_local_edge(p_sim, p_leader, strike)) {
			strikes.push_back(strike);
		}
	}
	std::vector<int> best_key;
	for (const Strike &strike : strikes) {
		if (strike.result.is_attacker_dead && !strike.result.is_defender_dead) {
			continue;
		}
		const UnitState &enemy = p_sim.get_units()[strike.target];
		const int help = is_guard ? sum_strength(p_sim, side, enemy.side, enemy.cell, p_sim.get_rules().ai_strength_radius_cells, enemy.index) : 0;
		const std::vector<int> key = { p_sim.is_leader(enemy.index) ? 0 : 1, strike.result.is_defender_dead ? 0 : 1, help, enemy.hp, enemy.index };
		if (aim.target == NO_UNIT || key < best_key) {
			aim.target = enemy.index;
			best_key = key;
		}
	}
	if (aim.target == NO_UNIT) {
		aim.target = find_nearest_enemy(p_sim, p_leader);
		aim.is_holding = is_guard && !is_advancing(p_sim, side);
		if (aim.target == NO_UNIT && !aim.is_holding) {
			aim.search_goals = find_search_goals(p_sim, p_leader);
		}
		return aim;
	}
	aim.strike_cell = pick_safest_strike_cell(p_sim, strikes, count_enemy_reach(p_sim, p_sim.get_units()[p_leader].side), aim.target);
	return aim;
}

// The skill is ready once the leader stands on p_from: moving there first
// feeds the charge a displacement, which charge.focus loses.
bool is_skill_ready_on(const UnitState &p_leader, const Cell &p_from) {
	if (!is_skill_ready(p_leader) || p_from == p_leader.cell) {
		return is_skill_ready(p_leader);
	}
	const ChargeUpdate update = p_leader.def.skill.charge->update(ChargeTrigger::DISPLACED, 0);
	const int value = update.resets ? 0 : p_leader.skill_charge + update.delta;
	return value >= p_leader.def.skill.charge_threshold;
}

// A skill against enemies, ready on p_from, that reaches p_target from it.
bool can_skill_reach(const UnitState &p_leader, const Cell &p_from, const Cell &p_target) {
	return is_skill_ready_on(p_leader, p_from) && !is_skill_for_own_side(p_leader.def.skill) && get_manhattan(p_from, p_target) <= p_leader.def.skill.cast_range_cells;
}

// A skill for the leader's own side, ready on p_from, that it may cast on
// p_from, the cell it stands on then.
bool can_cast_on_own_cell(const TacticsSim &p_sim, int p_leader, const Cell &p_from) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	if (!is_skill_ready_on(leader, p_from) || !is_skill_for_own_side(leader.def.skill)) {
		return false;
	}
	SkillSelection selection;
	std::string error;
	return leader.def.skill.target->select(p_sim, p_leader, p_from, p_from, selection, &error);
}

Intent cast_on_own_cell(Intent p_intent, const Cell &p_cell) {
	p_intent.action = IntentAction::SKILL;
	p_intent.target = p_intent.leader;
	p_intent.target_cell = p_cell;
	return p_intent;
}

} // namespace

Intent plan_intent(const TacticsSim &p_sim, int p_leader) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	Intent intent;
	intent.leader = p_leader;
	intent.destination = leader.cell;
	const Aim aim = pick_ai_aim(p_sim, p_leader);
	intent.target = aim.target;
	if (intent.target == NO_UNIT && (aim.is_holding || !aim.search_goals.empty())) {
		const PathField field = find_move_paths(p_sim, p_leader);
		if (aim.is_holding) {
			intent.destination = pick_hold_cell(p_sim, p_leader, field);
		} else {
			const std::vector<int> distance = find_goal_distances(p_sim, p_leader, aim.search_goals);
			intent.destination = pick_reachable_cell(p_sim, p_leader, field, [&](const Cell &p_cell) { return distance[p_sim.get_cell_index(p_cell)]; });
		}
	}
	if (intent.target == NO_UNIT) {
		return can_cast_on_own_cell(p_sim, p_leader, intent.destination) ? cast_on_own_cell(intent, intent.destination) : intent;
	}
	const Cell target_cell = p_sim.get_units()[intent.target].cell;
	intent.target_cell = target_cell;
	const PathField field = find_move_paths(p_sim, p_leader);
	const std::vector<Cell> attack_cells = get_attack_cells(p_sim, p_leader, intent.target);
	const std::vector<int> distance = find_goal_distances(p_sim, p_leader, attack_cells);
	// Attack cells have distance 0, so a reachable one always wins.
	if (aim.strike_cell != NO_CELL) {
		intent.destination = aim.strike_cell;
	} else if (aim.is_holding) {
		intent.destination = pick_hold_cell(p_sim, p_leader, field);
	} else {
		intent.destination = pick_reachable_cell(p_sim, p_leader, field, [&](const Cell &p_cell) { return distance[p_sim.get_cell_index(p_cell)]; });
	}
	// A skill that moving would lose (charge.focus) is cast from where the
	// leader stands when it can be.
	const bool would_lose_skill = is_skill_ready(leader) && !is_skill_ready_on(leader, intent.destination);
	if (would_lose_skill && (can_cast_on_own_cell(p_sim, p_leader, leader.cell) || can_skill_reach(leader, leader.cell, target_cell))) {
		intent.destination = leader.cell;
	}
	if (can_cast_on_own_cell(p_sim, p_leader, intent.destination)) {
		return cast_on_own_cell(intent, intent.destination);
	}
	if (can_skill_reach(leader, intent.destination, target_cell)) {
		intent.action = IntentAction::SKILL;
	} else if (is_in_range_from(p_sim, p_leader, intent.destination, target_cell) && !aim.is_holding) {
		intent.action = IntentAction::ATTACK;
	} else if (aim.is_holding) {
		// A holding guard declares no target it will not strike.
		intent.target = NO_UNIT;
		intent.target_cell = NO_CELL;
	}
	return intent;
}

Cell resolve_intent_destination(const TacticsSim &p_sim, int p_leader, const Intent &p_intent) {
	const PathField field = find_move_paths(p_sim, p_leader);
	const Cell declared = p_intent.destination;
	return pick_reachable_cell(p_sim, p_leader, field, [&](const Cell &p_cell) { return get_manhattan(p_cell, declared); });
}

Intent resolve_intent_action(const TacticsSim &p_sim, int p_leader, const Intent &p_intent) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	Intent action = p_intent;
	if (p_intent.action == IntentAction::SKILL && can_cast_on_own_cell(p_sim, p_leader, leader.cell)) {
		return cast_on_own_cell(action, leader.cell);
	}
	const bool has_target = p_intent.target != NO_UNIT && p_sim.get_units()[p_intent.target].is_alive && p_sim.is_unit_seen_by(leader.side, p_intent.target);
	if (has_target) {
		action.target_cell = p_sim.get_units()[p_intent.target].cell;
		if (p_intent.action == IntentAction::SKILL && can_skill_reach(leader, leader.cell, action.target_cell)) {
			return action;
		}
		if (p_intent.action != IntentAction::WAIT && can_attack(p_sim, p_leader, p_intent.target)) {
			action.action = IntentAction::ATTACK;
			return action;
		}
	}
	action.action = IntentAction::WAIT;
	action.target = NO_UNIT;
	action.target_cell = NO_CELL;
	// A guard answers an enemy that came within range only in a fight worth
	// taking.
	const bool is_guard = is_guard_side(p_sim, leader.side);
	for (const UnitState &enemy : p_sim.get_units()) {
		if (is_guard && can_attack(p_sim, p_leader, enemy.index) && !is_favourable(predict_engagement(p_sim, p_leader, enemy.index))) {
			continue;
		}
		if (can_attack(p_sim, p_leader, enemy.index) && (action.target == NO_UNIT || enemy.hp < p_sim.get_units()[action.target].hp)) {
			action.action = IntentAction::ATTACK;
			action.target = enemy.index;
			action.target_cell = enemy.cell;
		}
	}
	return action;
}

} // namespace tactics
