#pragma once

// Opening handlers, looked up by id (`opening.hold_line`, `opening.charge`).
// An opening decides a unit's action from the first tick until it ends; then
// the unit behaves normally.

#include <string>

namespace battle {

class BattleSim;

enum class OpeningResult {
	// The opening used this tick's action.
	ACTED,
	// The opening is over; the unit acts normally this tick.
	ENDED,
};

using RunOpeningFn = OpeningResult (*)(BattleSim &p_sim, int p_unit);
// Called once per unit when the battle starts, before any unit acts, in
// unit index order; may end the opening at once.
using StartOpeningFn = void (*)(BattleSim &p_sim, int p_unit);

struct OpeningHandler {
	const char *id;
	RunOpeningFn run;
	// nullptr when the opening needs no setup.
	StartOpeningFn start;
};

// nullptr when the id is not registered.
const OpeningHandler *find_opening_handler(const std::string &p_id);

} // namespace battle
