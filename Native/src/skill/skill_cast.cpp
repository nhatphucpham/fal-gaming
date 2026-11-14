#include "skill_cast.h"

#include "skill_areas.h"
#include "skill_effects.h"
#include "skill_selectors.h"

#include "battle/battle_sim.h"

#include <algorithm>

namespace battle {

namespace {

constexpr int THREE_STARS = 3;

void set_qi(BattleSim &p_sim, int p_unit, int p_qi, int p_cause) {
	UnitSkillState &skills = p_sim.edit_skill_state(p_unit);
	if (skills.qi == p_qi) {
		return;
	}
	skills.qi = p_qi;
	BattleEvent event;
	event.type = EventType::QI_CHANGED;
	event.unit = p_unit;
	event.qi = skills.qi;
	event.qi_max = skills.qi_max;
	event.cause = p_cause;
	p_sim.emit_event(event);
}

// Collects the cells of a step around a freshly selected anchor. False when
// the selector finds nothing.
bool select_cells(const BattleSim &p_sim, int p_caster, const SkillStepDef &p_step, const AreaHandler *p_area, int p_area_size, Cell *r_anchor, std::vector<Cell> *r_cells) {
	const UnitState &caster = p_sim.get_units()[p_caster];
	if (!p_step.selector->select(p_sim, caster, p_step, p_area, p_area_size, r_anchor)) {
		return false;
	}
	p_area->collect(*r_anchor, caster.side, p_area_size, r_cells);
	return true;
}

void resolve_step(BattleSim &p_sim, int p_caster, const std::vector<EffectDef> &p_effects, const Cell &p_anchor, const std::vector<Cell> &p_cells, bool p_is_after_skill, int p_cause) {
	const SkillDef &skill = p_sim.get_skill(p_caster);
	BattleEvent event;
	event.type = EventType::SKILL_RESOLVED;
	event.unit = p_caster;
	event.skill_id = skill.id;
	event.cells = p_cells;
	event.is_after_skill = p_is_after_skill;
	event.cause = p_cause;
	EffectContext context;
	context.sim = &p_sim;
	context.caster = p_caster;
	context.source_id = skill.id;
	context.cause = p_sim.emit_event(event);
	context.anchor = p_anchor;
	context.cells = &p_cells;
	for (const EffectDef &effect : p_effects) {
		// A caster killed by its own skill's consequences stops there.
		if (!p_sim.get_units()[p_caster].is_alive) {
			return;
		}
		effect.handler->apply(context, effect);
	}
}

void finish_cast(BattleSim &p_sim, int p_unit) {
	UnitSkillState &skills = p_sim.edit_skill_state(p_unit);
	skills.cast.is_casting = false;
	const int cast_event = skills.cast.event_id;
	const Cell anchor = skills.cast.anchor;
	const std::vector<Cell> cells = skills.cast.cells;
	skills.cast = CastState();
	set_qi(p_sim, p_unit, 0, cast_event);
	const SkillDef &skill = p_sim.get_skill(p_unit);
	resolve_step(p_sim, p_unit, skill.main.effects, anchor, cells, false, cast_event);
	if (skill.has_after_skill && p_sim.get_units()[p_unit].star >= THREE_STARS && p_sim.get_units()[p_unit].is_alive) {
		ScheduledStep step;
		step.tick = p_sim.get_tick() + skill.after_delay_ticks;
		step.caster = p_unit;
		step.cause = cast_event;
		// No after selector: the same cells again.
		if (skill.after.selector == nullptr) {
			step.cells = cells;
		}
		p_sim.schedule_step(step);
	}
}

bool try_start_cast(BattleSim &p_sim, int p_unit) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	if (unit.skills.qi < unit.skills.qi_max || p_sim.is_moving(unit)) {
		return false;
	}
	const SkillDef &skill = p_sim.get_skill(p_unit);
	const bool is_star3 = unit.star >= THREE_STARS;
	const AreaHandler *area = is_star3 && skill.star3_area != nullptr ? skill.star3_area : skill.main.area;
	const int area_size = is_star3 && skill.star3_area_size != SAME_AS_BASE ? skill.star3_area_size : skill.main.area_size;
	Cell anchor;
	std::vector<Cell> cells;
	if (!select_cells(p_sim, p_unit, skill.main, area, area_size, &anchor, &cells) || get_enemies_in_cells(p_sim, unit.side, cells).empty()) {
		return false;
	}
	BattleEvent event;
	event.type = EventType::SKILL_CAST_STARTED;
	event.unit = p_unit;
	event.skill_id = skill.id;
	event.cells = cells;
	event.end_tick = p_sim.get_tick() + p_sim.get_rules().cast_ticks - 1;
	UnitSkillState &skills = p_sim.edit_skill_state(p_unit);
	skills.cast.is_casting = true;
	skills.cast.end_tick = event.end_tick;
	skills.cast.anchor = anchor;
	skills.cast.cells = cells;
	skills.cast.event_id = p_sim.emit_event(event);
	return true;
}

} // namespace

void add_qi(BattleSim &p_sim, int p_unit, int p_amount, int p_cause) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	if (!unit.is_alive || !unit.skills.has_skill || unit.skills.cast.is_casting || p_amount <= 0) {
		return;
	}
	set_qi(p_sim, p_unit, std::min(unit.skills.qi + p_amount, unit.skills.qi_max), p_cause);
}

bool run_cast_action(BattleSim &p_sim, int p_unit) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	if (!unit.skills.has_skill) {
		return false;
	}
	if (!unit.skills.cast.is_casting && !try_start_cast(p_sim, p_unit)) {
		return false;
	}
	if (p_sim.get_tick() >= p_sim.get_units()[p_unit].skills.cast.end_tick) {
		finish_cast(p_sim, p_unit);
	}
	return true;
}

void cancel_cast(BattleSim &p_sim, int p_unit) {
	p_sim.edit_skill_state(p_unit).cast = CastState();
}

void run_scheduled_steps(BattleSim &p_sim) {
	for (const ScheduledStep &step : p_sim.take_due_steps()) {
		if (!p_sim.get_units()[step.caster].is_alive) {
			continue;
		}
		const SkillDef &skill = p_sim.get_skill(step.caster);
		const std::vector<EffectDef> &effects = skill.after.effects.empty() ? skill.main.effects : skill.after.effects;
		Cell anchor = p_sim.get_units()[step.caster].cell;
		std::vector<Cell> cells = step.cells;
		if (skill.after.selector != nullptr && !select_cells(p_sim, step.caster, skill.after, skill.after.area, skill.after.area_size, &anchor, &cells)) {
			continue;
		}
		resolve_step(p_sim, step.caster, effects, anchor, cells, true, step.cause);
	}
}

} // namespace battle
