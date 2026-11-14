#pragma once

// Targeting handlers, looked up by id (`target.nearest`, ...). Add a handler
// by writing a pick function and listing it in the registry in the .cpp.

#include "battle_types.h"

#include <string>

namespace battle {

class BattleSim;

// Which enemies a handler may choose from.
enum class TargetPool {
	ALL,
	// Only enemies within the attacker's range.
	IN_RANGE,
};

// Returns the chosen enemy's index, or NO_UNIT when the pool is empty.
using PickTargetFn = int (*)(const BattleSim &p_sim, const UnitState &p_attacker, TargetPool p_pool);

struct TargetingHandler {
	const char *id;
	PickTargetFn pick;
	// True: the target is picked again among enemies in range before each
	// attack, instead of being kept.
	bool reevaluates_on_attack;
};

// nullptr when the id is not registered.
const TargetingHandler *find_targeting_handler(const std::string &p_id);

// True when p_a should be chosen over p_b at an equal score: same column as
// the attacker, lower hp, nearer the centre column, further to the
// attacker's left, lower index.
bool is_preferred_candidate(const UnitState &p_attacker, const UnitState &p_a, const UnitState &p_b);

int pick_nearest_enemy(const BattleSim &p_sim, const UnitState &p_attacker, TargetPool p_pool);

} // namespace battle
