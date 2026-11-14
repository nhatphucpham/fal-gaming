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

// Rows from the unit to p_cell along its forward direction; above 0 ahead.
int get_rows_ahead(const UnitState &p_unit, const Cell &p_cell) {
	return (p_cell.row - p_unit.cell.row) * get_forward_row_step(p_unit.side);
}

// The nearest living enemy ahead of the unit in column p_col, or NO_UNIT.
int find_nearest_ahead_in_column(const BattleSim &p_sim, const UnitState &p_unit, int p_col) {
	const int forward = get_forward_row_step(p_unit.side);
	for (Cell cell = { p_col, p_unit.cell.row + forward }; is_on_board(cell); cell.row += forward) {
		const int occupant = p_sim.get_board().get_occupant(cell);
		if (occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_unit.side) {
			return occupant;
		}
	}
	return NO_UNIT;
}

// No unit stands in the unit's column between it and the row before p_row.
bool is_lane_clear(const BattleSim &p_sim, const UnitState &p_unit, int p_row) {
	const int forward = get_forward_row_step(p_unit.side);
	for (Cell cell = { p_unit.cell.col, p_unit.cell.row + forward }; cell.row != p_row; cell.row += forward) {
		if (p_sim.get_board().get_occupant(cell) != NO_UNIT) {
			return false;
		}
	}
	return true;
}

// The charge still runs at p_target: alive, ahead and at most one column off.
bool is_lane_target(const BattleSim &p_sim, const UnitState &p_unit, int p_target) {
	if (p_target == NO_UNIT || !p_sim.get_units()[p_target].is_alive) {
		return false;
	}
	const Cell &cell = p_sim.get_units()[p_target].cell;
	return get_rows_ahead(p_unit, cell) >= 1 && std::abs(cell.col - p_unit.cell.col) <= 1;
}

void end_charge(BattleSim &p_sim, int p_unit, int p_hit, int p_cause) {
	ChargeState &charge = p_sim.edit_skill_state(p_unit).charge;
	// An opening that never left its cell and hit nothing was no charge:
	// no event, so the screen plays no charge effects for it.
	if (charge.is_skill || charge.cells_run > 0 || p_hit != NO_UNIT) {
		BattleEvent event;
		event.type = EventType::CHARGE_ENDED;
		event.unit = p_unit;
		event.hit = p_hit;
		event.cause = p_cause;
		p_sim.emit_event(event);
	}
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
	charge.target = get_frontmost_enemy_in_column(p_sim, unit.side, next_col);
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
	// mod.charge_immunity: no impact damage and no push, the charge just stops.
	const ActiveModifier *guard = p_sim.find_modifier(p_victim, rules::ModifierKind::CHARGE_IMMUNITY);
	if (guard != nullptr) {
		end_charge(p_sim, p_unit, p_victim, p_sim.emit_modifier_triggered(p_victim, *guard, charge.cause));
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
		// Opening impacts only: the charge_impact_pct milestones and formations.
		const int impact_pct = p_sim.sum_modifiers(p_unit, rules::ModifierKind::CHARGE_IMPACT_PCT);
		hit_event = p_sim.perform_attack(p_unit, p_victim, charge.cause, own.increase_pct + impact_pct);
	}
	if (!p_sim.get_units()[p_unit].is_alive) {
		return;
	}
	const int push_cells = 1 + p_sim.sum_modifiers(p_unit, rules::ModifierKind::KNOCKBACK_CELLS);
	p_sim.knock_back_cells(p_victim, get_forward_row_step(p_sim.get_units()[p_unit].side), push_cells, hit_event);
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
	// Already in the column on its own side of the enemy: just run. A unit
	// behind that enemy (deep in the enemy half) moves back in front of it.
	if (enemy == NO_UNIT || (unit.cell.col == p_col && get_rows_ahead(unit, p_sim.get_units()[enemy].cell) >= 1)) {
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
	if (!is_lane_target(p_sim, unit, charge.target)) {
		// The target died or left the lane: pick again from here.
		charge.target = pick_lane_target(p_sim, p_unit);
		if (charge.target == NO_UNIT) {
			end_charge(p_sim, p_unit, NO_UNIT, charge.cause);
			return;
		}
	}
	// In front of the target, straight or diagonal: the impact. Otherwise the
	// target is at least two rows ahead, so the next cell is on the board and
	// the run never passes the target's row.
	if (get_rows_ahead(unit, p_sim.get_units()[charge.target].cell) == 1) {
		impact(p_sim, p_unit, charge.target);
		return;
	}
	const Cell next = { unit.cell.col, unit.cell.row + get_forward_row_step(unit.side) };
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
	// An enemy stepped into the lane: it takes the charge.
	impact(p_sim, p_unit, blocker);
}

int pick_lane_target(const BattleSim &p_sim, int p_unit) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	int target = find_nearest_ahead_in_column(p_sim, unit, unit.cell.col);
	if (target == NO_UNIT) {
		const int own_left = unit.side == SIDE_A ? -1 : 1;
		for (int offset : { own_left, -own_left }) {
			const int col = unit.cell.col + offset;
			if (col < 0 || col >= BOARD_COLS) {
				continue;
			}
			const int candidate = find_nearest_ahead_in_column(p_sim, unit, col);
			// Strictly nearer wins, so the own-left column keeps a tie.
			if (candidate != NO_UNIT && (target == NO_UNIT || get_rows_ahead(unit, p_sim.get_units()[candidate].cell) < get_rows_ahead(unit, p_sim.get_units()[target].cell))) {
				target = candidate;
			}
		}
	}
	if (target == NO_UNIT || !is_lane_clear(p_sim, unit, p_sim.get_units()[target].cell.row)) {
		return NO_UNIT;
	}
	return target;
}

} // namespace battle
