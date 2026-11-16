#include "tactics_skills.h"

#include "tactics_sim.h"

namespace tactics {

namespace {

constexpr int PERCENT = 100;

// charge.turns: one per phase of the leader's side.
ChargeUpdate update_turns(ChargeTrigger p_trigger, int p_amount) {
	(void)p_amount;
	return { p_trigger == ChargeTrigger::PHASE_END ? 1 : 0, false };
}

// charge.engagements: one per engagement the leader fought (either role).
ChargeUpdate update_engagements(ChargeTrigger p_trigger, int p_amount) {
	(void)p_amount;
	return { p_trigger == ChargeTrigger::ENGAGEMENT ? 1 : 0, false };
}

// charge.focus: one per phase the leader ended without moving; lost when
// it moves or is displaced.
ChargeUpdate update_focus(ChargeTrigger p_trigger, int p_amount) {
	if (p_trigger == ChargeTrigger::DISPLACED) {
		return { 0, true };
	}
	return { p_trigger == ChargeTrigger::PHASE_END && p_amount == 0 ? 1 : 0, false };
}

// charge.damage_taken: one per point of damage the leader took.
ChargeUpdate update_damage_taken(ChargeTrigger p_trigger, int p_amount) {
	return { p_trigger == ChargeTrigger::DAMAGE_TAKEN ? p_amount : 0, false };
}

// charge.soldiers_lost: one per soldier of the leader's squad that died.
ChargeUpdate update_soldiers_lost(ChargeTrigger p_trigger, int p_amount) {
	(void)p_amount;
	return { p_trigger == ChargeTrigger::SOLDIER_LOST ? 1 : 0, false };
}

const ChargeHandler CHARGE_HANDLERS[] = {
	{ "charge.turns", update_turns },
	{ "charge.engagements", update_engagements },
	{ "charge.focus", update_focus },
	{ "charge.damage_taken", update_damage_taken },
	{ "charge.soldiers_lost", update_soldiers_lost },
};

bool is_enemy_at(const TacticsSim &p_sim, int p_caster, const Cell &p_cell) {
	const int occupant = p_sim.get_occupant(p_cell);
	return occupant != NO_UNIT && p_sim.get_units()[occupant].side != p_sim.get_units()[p_caster].side;
}

bool check_cast_range(const TacticsSim &p_sim, int p_caster, const Cell &p_from, const Cell &p_cell, std::string *r_error) {
	const UnitState &caster = p_sim.get_units()[p_caster];
	if (!p_sim.is_on_map(p_cell) || get_manhattan(p_from, p_cell) > caster.def.skill.cast_range_cells) {
		*r_error = caster.def.skill.id + " cannot reach (" + std::to_string(p_cell.col) + ", " + std::to_string(p_cell.row) + ")";
		return false;
	}
	return true;
}

// skill_target.single: the enemy on the cell.
bool select_single(const TacticsSim &p_sim, int p_caster, const Cell &p_from, const Cell &p_cell, SkillSelection &r_selection, std::string *r_error) {
	if (!check_cast_range(p_sim, p_caster, p_from, p_cell, r_error)) {
		return false;
	}
	if (!is_enemy_at(p_sim, p_caster, p_cell)) {
		*r_error = p_sim.get_units()[p_caster].def.skill.id + " needs an enemy on the target cell";
		return false;
	}
	r_selection.cells.push_back(p_cell);
	r_selection.targets.push_back(p_sim.get_occupant(p_cell));
	r_selection.target_pcts.push_back(PERCENT);
	return true;
}

// skill_target.area: a square of area_radius_cells (plus growth) around the
// cell; every enemy inside, in row-major order.
bool select_area(const TacticsSim &p_sim, int p_caster, const Cell &p_from, const Cell &p_cell, SkillSelection &r_selection, std::string *r_error) {
	if (!check_cast_range(p_sim, p_caster, p_from, p_cell, r_error)) {
		return false;
	}
	const UnitState &caster = p_sim.get_units()[p_caster];
	const int radius = caster.def.skill.area_radius_cells + caster.skill_area_bonus;
	const int cell_count = p_sim.get_map().width * p_sim.get_map().height;
	for (int index = 0; index < cell_count; index++) {
		const Cell cell = p_sim.get_cell_at(index);
		if (get_chebyshev(cell, p_cell) > radius) {
			continue;
		}
		r_selection.cells.push_back(cell);
		if (is_enemy_at(p_sim, p_caster, cell)) {
			r_selection.targets.push_back(p_sim.get_occupant(cell));
			r_selection.target_pcts.push_back(PERCENT);
		}
	}
	return true;
}

bool is_selected(const SkillSelection &p_selection, int p_unit) {
	for (int target : p_selection.targets) {
		if (target == p_unit) {
			return true;
		}
	}
	return false;
}

// skill_target.chain: the enemy on the cell, then up to chain_count - 1
// more, each the nearest enemy not yet hit within chain_jump_cells of the
// previous one; every jump keeps (100 - chain_falloff_pct) percent.
bool select_chain(const TacticsSim &p_sim, int p_caster, const Cell &p_from, const Cell &p_cell, SkillSelection &r_selection, std::string *r_error) {
	if (!select_single(p_sim, p_caster, p_from, p_cell, r_selection, r_error)) {
		return false;
	}
	const SkillDef &skill = p_sim.get_units()[p_caster].def.skill;
	while (static_cast<int>(r_selection.targets.size()) < skill.chain_count) {
		const Cell from = p_sim.get_units()[r_selection.targets.back()].cell;
		int best = NO_UNIT;
		for (const UnitState &unit : p_sim.get_units()) {
			if (!unit.is_alive || unit.side == p_sim.get_units()[p_caster].side || is_selected(r_selection, unit.index)) {
				continue;
			}
			const int distance = get_manhattan(from, unit.cell);
			if (distance <= skill.chain_jump_cells && (best == NO_UNIT || distance < get_manhattan(from, p_sim.get_units()[best].cell))) {
				best = unit.index;
			}
		}
		if (best == NO_UNIT) {
			break;
		}
		r_selection.cells.push_back(p_sim.get_units()[best].cell);
		r_selection.targets.push_back(best);
		r_selection.target_pcts.push_back(r_selection.target_pcts.back() * (PERCENT - skill.chain_falloff_pct) / PERCENT);
	}
	return true;
}

const SkillTargetHandler SKILL_TARGET_HANDLERS[] = {
	{ "skill_target.single", select_single },
	{ "skill_target.area", select_area },
	{ "skill_target.chain", select_chain },
};

} // namespace

const ChargeHandler *find_charge_handler(const std::string &p_id) {
	for (const ChargeHandler &handler : CHARGE_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

const SkillTargetHandler *find_skill_target_handler(const std::string &p_id) {
	for (const SkillTargetHandler &handler : SKILL_TARGET_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

void trigger_skill_charge(TacticsSim &p_sim, int p_leader, ChargeTrigger p_trigger, int p_amount, int p_cause) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	if (!leader.def.has_skill) {
		return;
	}
	const ChargeUpdate update = leader.def.skill.charge->update(p_trigger, p_amount);
	if (update.delta != 0 || update.resets) {
		p_sim.change_skill_charge(p_leader, update.delta, update.resets, p_cause);
	}
}

bool is_skill_ready(const UnitState &p_leader) {
	return p_leader.def.has_skill && p_leader.skill_charge >= p_leader.def.skill.charge_threshold;
}

bool is_skill_for_own_side(const SkillDef &p_skill) {
	for (const SkillEffectDef &effect : p_skill.effects) {
		if (effect.handler->affects_enemies(effect)) {
			return false;
		}
	}
	return true;
}

int cast_skill(TacticsSim &p_sim, int p_caster, const Cell &p_cell, int p_cause, std::string *r_error) {
	const SkillDef &skill = p_sim.get_units()[p_caster].def.skill;
	SkillSelection selection;
	selection.center = p_cell;
	if (!skill.target->select(p_sim, p_caster, p_sim.get_units()[p_caster].cell, p_cell, selection, r_error)) {
		return 0;
	}
	Event used;
	used.type = EventType::SKILL_USED;
	used.unit = p_caster;
	used.content_id = skill.id;
	used.to = p_cell;
	used.cells = selection.cells;
	used.units = selection.targets;
	used.cause = p_cause;
	const int cause = p_sim.emit(used);

	std::vector<SkillTargetResult> results;
	for (const SkillEffectDef &effect : skill.effects) {
		effect.handler->apply(p_sim, p_caster, effect, selection, cause, results);
		// A kill that ended the battle: no later effect, result or charge.
		if (p_sim.is_finished()) {
			return cause;
		}
	}
	Event resolved;
	resolved.type = EventType::SKILL_RESOLVED;
	resolved.unit = p_caster;
	resolved.content_id = skill.id;
	resolved.results = results;
	resolved.cause = cause;
	p_sim.emit(resolved);
	p_sim.change_skill_charge(p_caster, 0, true, cause);
	return cause;
}

} // namespace tactics
