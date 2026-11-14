#include "battle_openings.h"

#include "battle_sim.h"

#include "skill/skill_charge.h"

namespace battle {

namespace {

// The unit stays put and attacks targets in range, until the time cap or,
// after the grace period, until no enemy targets it any more.
OpeningResult run_hold_line(BattleSim &p_sim, int p_unit) {
	const Rules &rules = p_sim.get_rules();
	const int tick = p_sim.get_tick();
	const bool is_over_time = tick >= rules.hold_line_max_ticks;
	if (is_over_time || (tick > rules.hold_line_grace_ticks && !p_sim.is_targeted_by_enemy(p_unit))) {
		return OpeningResult::ENDED;
	}

	p_sim.update_target(p_unit);
	if (!p_sim.is_moving(p_sim.get_units()[p_unit])) {
		p_sim.attack_if_ready(p_unit);
	}
	return OpeningResult::ACTED;
}

// Picks the lane target from the starting line-ups (see pick_lane_target).
// Without one the rider does not charge at all and walks like any melee unit.
void start_charge(BattleSim &p_sim, int p_unit) {
	ChargeState charge;
	charge.target = pick_lane_target(p_sim, p_unit);
	if (charge.target == NO_UNIT) {
		p_sim.deactivate_opening(p_unit);
		return;
	}
	begin_charge(p_sim, p_unit, charge);
}

// Runs forward through the shared charge runner (skill_charge.h) to the cell
// in front of its lane target, hits it once with a basic attack and pushes it
// back. The runner ends the opening when the charge ends.
OpeningResult run_charge(BattleSim &p_sim, int p_unit) {
	if (!p_sim.get_units()[p_unit].skills.charge.is_active) {
		return OpeningResult::ENDED;
	}
	advance_charge(p_sim, p_unit);
	return OpeningResult::ACTED;
}

const OpeningHandler OPENING_HANDLERS[] = {
	{ "opening.hold_line", run_hold_line, nullptr },
	{ "opening.charge", run_charge, start_charge },
};

} // namespace

const OpeningHandler *find_opening_handler(const std::string &p_id) {
	for (const OpeningHandler &handler : OPENING_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

} // namespace battle
