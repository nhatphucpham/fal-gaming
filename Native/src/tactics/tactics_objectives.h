#pragma once

// Objectives (Docs/systems/tactics_objectives.md): what a scenario is won
// by, one handler per kind in the registry of the .cpp (take the pass, hold
// the city, escort, break the siege, bring down the general), tuned by an
// ObjectiveDef; and the secondary goals a won battle can meet. Handlers act
// through hooks the turn loop calls and tell the AI what each side goes for.

#include "tactics_types.h"

#include <string>
#include <vector>

namespace tactics {

class TacticsSim;

struct ObjectiveHandler {
	const char *id;
	// The side that holds its ground and strikes only with an edge (the
	// guard AI), NO_INDEX for none.
	int guard_side;
	// After the leaders are placed and the seeds planted (the convoy).
	void (*on_start)(TacticsSim &p_sim, int p_cause);
	// After the units of p_side are ready for their phase (waves).
	void (*on_phase_start)(TacticsSim &p_sim, int p_side, int p_cause);
	// At the end of p_side's phase, after the squads and incidents: the
	// convoy's walk, the round's checks. May end the battle.
	void (*on_phase_end)(TacticsSim &p_sim, int p_side, int p_cause);
	// A leader's own move ended (exits, a fleeing general).
	void (*on_leader_moved)(TacticsSim &p_sim, int p_leader, int p_cause);
	// A unit fell (the convoy, the general).
	void (*on_unit_died)(TacticsSim &p_sim, int p_unit, int p_cause);
	// p_side has no leader on the map: the winner, or NO_WINNER to keep
	// fighting (a wave is still to come); nullptr for a plain rout.
	int (*get_rout_winner)(const TacticsSim &p_sim, int p_side);
	// A cell a leader of p_side moves to without striking from it (an exit).
	bool (*is_exit_cell)(const TacticsSim &p_sim, int p_side, const Cell &p_cell);
	// The cells the leader marches for when it has no strike (empty: none).
	std::vector<Cell> (*get_march_goals)(const TacticsSim &p_sim, int p_leader);
	// The unit p_side strikes before any other (the convoy, the general).
	int (*get_priority_target)(const TacticsSim &p_sim, int p_side);
	bool (*validate)(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error);
};

struct GoalHandler {
	const char *id;
	// Met, side A having won.
	bool (*is_met)(const TacticsSim &p_sim, const GoalDef &p_goal);
};

const ObjectiveHandler *find_objective_handler(const std::string &p_id);
const GoalHandler *find_goal_handler(const std::string &p_id);
bool validate_objective(const ObjectiveDef &p_def, const MapDef &p_map, std::string *r_error);
// The goals met at the end of a battle side A won, in the order given.
std::vector<int> find_met_goals(const TacticsSim &p_sim);

} // namespace tactics
