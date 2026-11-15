#include "tactics_ai.h"

#include "tactics_combat.h"
#include "tactics_paths.h"
#include "tactics_sim.h"
#include "tactics_skills.h"

namespace tactics {

namespace {

// The enemy with the shortest path (zones of control ignored) to a cell
// the leader could attack it from; ties to the lower index.
int pick_ai_target(const TacticsSim &p_sim, int p_leader) {
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

bool can_skill_reach(const UnitState &p_leader, const Cell &p_from, const Cell &p_target) {
	return is_skill_ready(p_leader) && get_manhattan(p_from, p_target) <= p_leader.def.skill.cast_range_cells;
}

} // namespace

Intent plan_intent(const TacticsSim &p_sim, int p_leader) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	Intent intent;
	intent.leader = p_leader;
	intent.destination = leader.cell;
	intent.target = pick_ai_target(p_sim, p_leader);
	if (intent.target == NO_UNIT) {
		return intent;
	}
	const Cell target_cell = p_sim.get_units()[intent.target].cell;
	intent.target_cell = target_cell;
	const PathField field = find_paths(p_sim, p_leader, p_sim.get_stats(p_leader).move_points, ZocMode::APPLY);
	const std::vector<Cell> attack_cells = get_attack_cells(p_sim, p_leader, intent.target);
	const std::vector<int> distance = find_goal_distances(p_sim, p_leader, attack_cells);
	// Attack cells have distance 0, so a reachable one always wins.
	intent.destination = pick_reachable_cell(p_sim, p_leader, field, [&](const Cell &p_cell) { return distance[p_sim.get_cell_index(p_cell)]; });
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
