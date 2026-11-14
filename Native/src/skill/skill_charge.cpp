#include "skill_charge.h"

#include "skill_passives.h"
#include "skill_selectors.h"

#include "battle/battle_board.h"
#include "battle/battle_rules.h"
#include "battle/battle_sim.h"

#include <cstdlib>

namespace battle {

namespace {

// The neighbouring column with more enemies (ties: the unit's own left), or
// -1 when neither holds one.
int pick_next_column(const BattleSim &p_sim, const UnitState &p_unit) {
	const int own_left = p_unit.side == SIDE_A ? -1 : 1;
	int best_col = -1;
	int best_count = 0;
	for (int offset : { own_left, -own_left }) {
		const int col = p_unit.cell.col + offset;
		if (col < 0 || col >= BOARD_COLS) {
			continue;
		}
		const int count = count_enemies_in_column(p_sim, p_unit.side, col);
		if (count > best_count) {
			best_col = col;
			best_count = count;
		}
	}
	return best_col;
}

void end_charge(BattleSim &p_sim, int p_unit, int p_hit, int p_cause) {
	BattleEvent event;
	event.type = EventType::CHARGE_ENDED;
	event.unit = p_unit;
	event.hit = p_hit;
	event.cause = p_cause;
	p_sim.emit_event(event);
	ChargeState &charge = p_sim.edit_skill_state(p_unit).charge;
	if (!charge.is_skill) {
		charge = ChargeState();
		p_sim.deactivate_opening(p_unit);
		return;
	}
	const UnitState &unit = p_sim.get_units()[p_unit];
	const int next_col = unit.is_alive && charge.columns_left > 0 ? pick_next_column(p_sim, unit) : -1;
	if (next_col < 0) {
		charge = ChargeState();
		return;
	}
	charge.columns_left--;
	charge.cells_run = 0;
	reposition_for_column(p_sim, p_unit, next_col, charge.reposition_ticks, p_cause);
}

// Spears and the like strike the charger before it hits; returns false when
// the charger died from it.
bool resolve_incoming(BattleSim &p_sim, int p_unit, int p_victim, int p_cause) {
	PassiveContext context;
	context.source = p_unit;
	context.victim = p_victim;
	context.cell = p_sim.get_units()[p_unit].cell;
	context.cause = p_cause;
	const int unit_count = static_cast<int>(p_sim.get_units().size());
	for (int other = 0; other < unit_count; other++) {
		if (p_sim.get_units()[other].side != p_sim.get_units()[p_unit].side) {
			fire_passive(p_sim, other, PassiveTrigger::CHARGE_IMPACT_INCOMING, context);
		}
		if (!p_sim.get_units()[p_unit].is_alive) {
			return false;
		}
	}
	return true;
}

void impact(BattleSim &p_sim, int p_unit, int p_victim) {
	const ChargeState charge = p_sim.get_units()[p_unit].skills.charge;
	if (!resolve_incoming(p_sim, p_unit, p_victim, charge.cause)) {
		return;
	}
	PassiveContext own;
	own.source = p_victim;
	own.victim = p_victim;
	own.cell = p_sim.get_units()[p_unit].cell;
	own.cells_run = charge.cells_run;
	own.cause = charge.cause;
	fire_passive(p_sim, p_unit, PassiveTrigger::CHARGE_IMPACT, own);

	int hit_event = 0;
	if (charge.is_skill) {
		DamageSpec spec;
		spec.source = p_unit;
		spec.victim = p_victim;
		spec.coefficient_pct = scale_skill_coefficient(charge.coefficient_pct, p_sim.get_units()[p_unit].star, p_sim.get_rules());
		spec.increase_pct = own.increase_pct;
		spec.skill_id = p_sim.get_skill(p_unit).id;
		spec.cause = charge.cause;
		hit_event = p_sim.deal_damage(spec);
	} else {
		hit_event = p_sim.perform_attack(p_unit, p_victim, charge.cause, own.increase_pct);
	}
	if (!p_sim.get_units()[p_unit].is_alive) {
		return;
	}
	const Cell at = p_sim.get_units()[p_victim].cell;
	p_sim.knock_back(p_victim, { at.col, at.row + get_forward_row_step(p_sim.get_units()[p_unit].side) }, hit_event);
	end_charge(p_sim, p_unit, p_victim, hit_event);
}

} // namespace

void begin_charge(BattleSim &p_sim, int p_unit, const ChargeState &p_state) {
	if (p_state.is_skill) {
		p_sim.deactivate_opening(p_unit);
	}
	ChargeState &charge = p_sim.edit_skill_state(p_unit).charge;
	charge = p_state;
	charge.is_active = true;
}

void reposition_for_column(BattleSim &p_sim, int p_unit, int p_col, int p_ticks, int p_cause) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	const int enemy = get_frontmost_enemy_in_column(p_sim, unit.side, p_col);
	if (enemy == NO_UNIT || unit.cell.col == p_col) {
		return;
	}
	const int enemy_row = p_sim.get_units()[enemy].cell.row;
	const int forward = get_forward_row_step(unit.side);
	bool found = false;
	Cell best;
	for (int row = enemy_row - forward; is_on_board({ p_col, row }); row -= forward) {
		const Cell cell = { p_col, row };
		if (!p_sim.get_board().is_free(cell)) {
			continue;
		}
		// Rows go from the enemy backward, so `<=` lets the cell further
		// from the enemy win a tie: a longer run-up.
		if (!found || get_distance_cells(unit.cell, cell) <= get_distance_cells(unit.cell, best)) {
			best = cell;
			found = true;
		}
	}
	if (found) {
		p_sim.start_move(p_unit, best, p_ticks, MoveKind::CHARGE, p_cause);
	}
}

void advance_charge(BattleSim &p_sim, int p_unit) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	if (p_sim.is_moving(unit)) {
		return;
	}
	ChargeState &charge = p_sim.edit_skill_state(p_unit).charge;
	const Cell next = { unit.cell.col, unit.cell.row + get_forward_row_step(unit.side) };
	if (!is_on_board(next)) {
		end_charge(p_sim, p_unit, NO_UNIT, charge.cause);
		return;
	}
	const int blocker = p_sim.get_board().get_occupant(next);
	if (blocker == NO_UNIT) {
		p_sim.start_move(p_unit, next, p_sim.get_rules().charge_ticks_per_cell, MoveKind::CHARGE, charge.cause);
		charge.cells_run++;
		return;
	}
	if (p_sim.get_units()[blocker].side == unit.side) {
		end_charge(p_sim, p_unit, NO_UNIT, charge.cause);
		return;
	}
	impact(p_sim, p_unit, blocker);
}

} // namespace battle
