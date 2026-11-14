#include "battle_openings.h"

#include "battle_board.h"
#include "battle_sim.h"

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
	if (p_sim.get_units()[p_unit].move_ticks_left == 0) {
		p_sim.attack_if_ready(p_unit);
	}
	return OpeningResult::ACTED;
}

void end_charge(BattleSim &p_sim, int p_unit, int p_hit, int p_cause) {
	BattleEvent event;
	event.type = EventType::CHARGE_ENDED;
	event.unit = p_unit;
	event.hit = p_hit;
	event.cause = p_cause;
	p_sim.emit_event(event);
	p_sim.deactivate_opening(p_unit);
}

bool can_knock_back(const BattleSim &p_sim, const UnitState &p_victim, const Cell &p_to) {
	const ClassDef &victim_class = p_sim.get_class_def(p_victim);
	return p_victim.is_alive && !victim_class.immune_to_knockback && !victim_class.stops_charge && p_sim.get_board().is_free(p_to);
}

// Runs straight forward; on reaching an enemy, hits it once and pushes it
// back one cell when it can be pushed.
OpeningResult run_charge(BattleSim &p_sim, int p_unit) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	if (unit.move_ticks_left > 0) {
		return OpeningResult::ACTED;
	}
	const int forward = get_forward_row_step(unit.side);
	const Cell next = { unit.cell.col, unit.cell.row + forward };
	if (!is_on_board(next)) {
		end_charge(p_sim, p_unit, NO_UNIT, 0);
		return OpeningResult::ACTED;
	}
	const int blocker = p_sim.get_board().get_occupant(next);
	if (blocker == NO_UNIT) {
		p_sim.start_move(p_unit, next, p_sim.get_rules().charge_ticks_per_cell, MoveKind::CHARGE, 0);
		return OpeningResult::ACTED;
	}
	if (p_sim.get_units()[blocker].side == unit.side) {
		end_charge(p_sim, p_unit, NO_UNIT, 0);
		return OpeningResult::ACTED;
	}

	const int attack_event = p_sim.perform_attack(p_unit, blocker, 0);
	const Cell pushed_to = { next.col, next.row + forward };
	if (can_knock_back(p_sim, p_sim.get_units()[blocker], pushed_to)) {
		p_sim.start_move(blocker, pushed_to, p_sim.get_rules().charge_ticks_per_cell, MoveKind::KNOCKBACK, attack_event);
	}
	end_charge(p_sim, p_unit, blocker, attack_event);
	return OpeningResult::ACTED;
}

const OpeningHandler OPENING_HANDLERS[] = {
	{ "opening.hold_line", run_hold_line },
	{ "opening.charge", run_charge },
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
