#include "tactics_ai.h"

#include "tactics_brain.h"
#include "tactics_combat.h"
#include "tactics_paths.h"
#include "tactics_sim.h"
#include "tactics_skills.h"

namespace tactics {

namespace {

// The enemy with the shortest path (zones of control ignored) to a cell
// the leader could attack it from; ties to the lower index.
int find_nearest_enemy(const TacticsSim &p_sim, int p_leader) {
	const PathField field = find_paths(p_sim, p_leader, UNLIMITED_COST, ZocMode::IGNORE);
	int best = NO_UNIT;
	int best_cost = UNREACHABLE;
	for (const UnitState &enemy : p_sim.get_units()) {
		if (!enemy.is_alive || enemy.side == p_sim.get_units()[p_leader].side) {
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

struct Aim {
	int target = NO_UNIT;
	// The cell to strike from this phase, NO_CELL when out of reach.
	Cell strike_cell = NO_CELL;
};

// What the leader goes for: among enemies it can strike this phase without
// dying to the counter for nothing, a leader before a soldier, a kill
// before a hit, then the lowest hp, struck from the safest cell; else the
// nearest enemy by path.
Aim pick_ai_aim(const TacticsSim &p_sim, int p_leader) {
	Aim aim;
	const PathField field = find_paths(p_sim, p_leader, p_sim.get_stats(p_leader).move_points, ZocMode::APPLY);
	const std::vector<Strike> strikes = list_strikes(p_sim, p_leader, field, [](const Cell &) { return true; });
	std::vector<int> best_key;
	for (const Strike &strike : strikes) {
		if (strike.result.is_attacker_dead && !strike.result.is_defender_dead) {
			continue;
		}
		const UnitState &enemy = p_sim.get_units()[strike.target];
		const std::vector<int> key = { p_sim.is_leader(enemy.index) ? 0 : 1, strike.result.is_defender_dead ? 0 : 1, enemy.hp, enemy.index };
		if (aim.target == NO_UNIT || key < best_key) {
			aim.target = enemy.index;
			best_key = key;
		}
	}
	if (aim.target == NO_UNIT) {
		aim.target = find_nearest_enemy(p_sim, p_leader);
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
	if (intent.target == NO_UNIT) {
		return can_cast_on_own_cell(p_sim, p_leader, intent.destination) ? cast_on_own_cell(intent, intent.destination) : intent;
	}
	const Cell target_cell = p_sim.get_units()[intent.target].cell;
	intent.target_cell = target_cell;
	const PathField field = find_paths(p_sim, p_leader, p_sim.get_stats(p_leader).move_points, ZocMode::APPLY);
	const std::vector<Cell> attack_cells = get_attack_cells(p_sim, p_leader, intent.target);
	const std::vector<int> distance = find_goal_distances(p_sim, p_leader, attack_cells);
	// Attack cells have distance 0, so a reachable one always wins.
	intent.destination = aim.strike_cell != NO_CELL ? aim.strike_cell : pick_reachable_cell(p_sim, p_leader, field, [&](const Cell &p_cell) { return distance[p_sim.get_cell_index(p_cell)]; });
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
	} else if (is_in_range_from(p_sim, p_leader, intent.destination, target_cell)) {
		intent.action = IntentAction::ATTACK;
	}
	return intent;
}

Cell resolve_intent_destination(const TacticsSim &p_sim, int p_leader, const Intent &p_intent) {
	const PathField field = find_paths(p_sim, p_leader, p_sim.get_stats(p_leader).move_points, ZocMode::APPLY);
	const Cell declared = p_intent.destination;
	return pick_reachable_cell(p_sim, p_leader, field, [&](const Cell &p_cell) { return get_manhattan(p_cell, declared); });
}

Intent resolve_intent_action(const TacticsSim &p_sim, int p_leader, const Intent &p_intent) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	Intent action = p_intent;
	if (p_intent.action == IntentAction::SKILL && can_cast_on_own_cell(p_sim, p_leader, leader.cell)) {
		return cast_on_own_cell(action, leader.cell);
	}
	const bool has_target = p_intent.target != NO_UNIT && p_sim.get_units()[p_intent.target].is_alive;
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
	for (const UnitState &enemy : p_sim.get_units()) {
		if (can_attack(p_sim, p_leader, enemy.index) && (action.target == NO_UNIT || enemy.hp < p_sim.get_units()[action.target].hp)) {
			action.action = IntentAction::ATTACK;
			action.target = enemy.index;
			action.target_cell = enemy.cell;
		}
	}
	return action;
}

} // namespace tactics
