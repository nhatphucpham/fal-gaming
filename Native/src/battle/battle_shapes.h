#pragma once

// Attack shape handlers, looked up by id (`shape.single`, `shape.row3`): they
// turn one attack on a target into the list of units it hits.

#include "battle_types.h"

#include <string>
#include <vector>

namespace battle {

class BattleSim;

struct Hit {
	int victim = NO_UNIT;
	// The unit that took an arrow meant for another one, or NO_UNIT.
	int blocked_by = NO_UNIT;
};

using CollectHitsFn = void (*)(const BattleSim &p_sim, const UnitState &p_attacker, int p_target, std::vector<Hit> *r_hits);

struct ShapeHandler {
	const char *id;
	CollectHitsFn collect_hits;
};

// nullptr when the id is not registered.
const ShapeHandler *find_shape_handler(const std::string &p_id);

} // namespace battle
