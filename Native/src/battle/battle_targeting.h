#pragma once

// Targeting handlers, looked up by id (`target.nearest`, ...). Add a handler
// by writing a pick function and listing it in the registry in the .cpp.

#include "battle_types.h"

#include <string>

namespace battle {

class BattleSim;

// Returns the chosen enemy's index, or NO_UNIT when no enemy is alive.
using PickTargetFn = int (*)(const BattleSim &p_sim, const UnitState &p_attacker);

struct TargetingHandler {
	const char *id;
	PickTargetFn pick;
	// True: the target is picked again before each attack while an enemy is
	// in range, instead of being kept.
	bool reevaluates_on_attack;
};

// nullptr when the id is not registered.
const TargetingHandler *find_targeting_handler(const std::string &p_id);

// True when p_a should be chosen over p_b at an equal score: same column as
// the attacker, lower hp, nearer the centre column, further to the
// attacker's left, lower index.
bool is_preferred_candidate(const UnitState &p_attacker, const UnitState &p_a, const UnitState &p_b);

int pick_nearest_enemy(const BattleSim &p_sim, const UnitState &p_attacker);

} // namespace battle
