// BattleSim: what synergy modifiers change in a unit's own attack (crits,
// every-Nth bonuses, pierce) and the multi-cell push of formation charges.
// The rest of an attack is in battle_sim_actions.cpp.

#include "battle_sim.h"

#include "battle_shapes.h"

#include "skill/skill_effects.h"

namespace battle {

// First-attack crits and every-Nth bonuses of the attack being made.
void BattleSim::apply_attack_modifiers(int p_unit, int p_attack_event, PassiveContext *r_landed) {
	const int attack_number = units[p_unit].basic_attacks;
	if (attack_number == 1 && find_modifier(p_unit, rules::ModifierKind::FIRST_ATTACK_CRIT) != nullptr) {
		r_landed->is_crit = true;
	}
	const ActiveModifier *nth = find_modifier(p_unit, rules::ModifierKind::NTH_ATTACK_BONUS_PCT);
	if (nth != nullptr && attack_number % nth->count == 0) {
		r_landed->increase_pct += nth->value;
		emit_modifier_triggered(p_unit, *nth, p_attack_event);
	}
}

// mod.pierce_behind: the enemy directly behind the first unit hit (one
// more cell along the attacker's forward direction) is hit too.
void BattleSim::add_pierce_hit(int p_unit, std::vector<Hit> *r_hits) const {
	const Cell first = units[(*r_hits)[0].victim].cell;
	const Cell behind = { first.col, first.row + get_forward_row_step(units[p_unit].side) };
	if (!is_on_board(behind)) {
		return;
	}
	const int occupant = board.get_occupant(behind);
	if (occupant == NO_UNIT || units[occupant].side == units[p_unit].side) {
		return;
	}
	for (const Hit &hit : *r_hits) {
		if (hit.victim == occupant) {
			return;
		}
	}
	r_hits->push_back({ occupant, NO_UNIT });
}

bool BattleSim::knock_back_cells(int p_unit, int p_row_step, int p_cells, int p_cause) {
	const UnitState &unit = units[p_unit];
	const ClassDef &unit_class = get_class_def(unit);
	if (!unit.is_alive || unit_class.immune_to_knockback || unit_class.stops_charge) {
		return false;
	}
	int moved = 0;
	Cell destination = unit.cell;
	for (int step = 1; step <= p_cells; step++) {
		const Cell next = { unit.cell.col, unit.cell.row + p_row_step * step };
		if (!is_on_board(next) || !board.is_free(next)) {
			break;
		}
		destination = next;
		moved = step;
	}
	if (moved == 0) {
		return false;
	}
	start_move(p_unit, destination, rules.charge_ticks_per_cell * moved, MoveKind::KNOCKBACK, p_cause);
	return true;
}

} // namespace battle
