#include "skill_effects.h"

#include "skill_cast.h"
#include "skill_selectors.h"
#include "skill_statuses.h"

#include "battle/battle_rules.h"
#include "battle/battle_sim.h"

namespace battle {

namespace {

constexpr int THREE_STARS = 3;

int get_step_toward(int p_from, int p_to) {
	return p_to > p_from ? 1 : (p_to < p_from ? -1 : 0);
}

void apply_damage(EffectContext &p_context, const EffectDef &p_effect) {
	for (int target : get_effect_targets(p_context, p_effect)) {
		if (!p_context.sim->get_units()[p_context.caster].is_alive) {
			return;
		}
		DamageSpec spec;
		spec.source = p_context.caster;
		spec.victim = target;
		spec.coefficient_pct = get_effect_coefficient(p_context, p_effect);
		spec.kind = p_effect.damage_kind;
		spec.skill_id = p_context.source_id;
		spec.cause = p_context.cause;
		p_context.sim->deal_damage(spec);
	}
}

void apply_status_effect(EffectContext &p_context, const EffectDef &p_effect, StatusKind p_kind) {
	for (int target : get_effect_targets(p_context, p_effect)) {
		apply_status(*p_context.sim, target, p_kind, p_effect.value, p_effect.duration_ticks, p_context.caster, p_context.cause);
	}
}

void apply_taunt(EffectContext &p_context, const EffectDef &p_effect) {
	apply_status_effect(p_context, p_effect, StatusKind::TAUNTED);
}

void apply_guard(EffectContext &p_context, const EffectDef &p_effect) {
	apply_status_effect(p_context, p_effect, StatusKind::GUARD);
}

void apply_armor_break(EffectContext &p_context, const EffectDef &p_effect) {
	apply_status_effect(p_context, p_effect, StatusKind::ARMOR_BREAK);
}

void apply_stun(EffectContext &p_context, const EffectDef &p_effect) {
	for (int target : get_effect_targets(p_context, p_effect)) {
		cancel_cast(*p_context.sim, target);
	}
	apply_status_effect(p_context, p_effect, StatusKind::STUN);
}

// Hóa Đá: the targets turn to stone, dropping a cast in progress.
void apply_petrify(EffectContext &p_context, const EffectDef &p_effect) {
	for (int target : get_effect_targets(p_context, p_effect)) {
		cancel_cast(*p_context.sim, target);
	}
	apply_status_effect(p_context, p_effect, StatusKind::PETRIFIED);
}

// Pushes each target one cell straight away from the caster.
void apply_knockback(EffectContext &p_context, const EffectDef &p_effect) {
	const Cell from = p_context.sim->get_units()[p_context.caster].cell;
	for (int target : get_effect_targets(p_context, p_effect)) {
		const Cell at = p_context.sim->get_units()[target].cell;
		const Cell to = { at.col + get_step_toward(from.col, at.col), at.row + get_step_toward(from.row, at.row) };
		if (to != at) {
			p_context.sim->knock_back(target, to, p_context.cause);
		}
	}
}

void apply_add_qi(EffectContext &p_context, const EffectDef &p_effect) {
	for (int target : get_effect_targets(p_context, p_effect)) {
		add_qi(*p_context.sim, target, p_effect.value, p_context.cause);
	}
}

// Passive modifier: the attack being made is a critical hit.
void apply_crit(EffectContext &p_context, const EffectDef &) {
	if (p_context.passive != nullptr) {
		p_context.passive->is_crit = true;
	}
}

// Passive modifier: value percent more impact damage per cell run.
void apply_impact_bonus_per_cell(EffectContext &p_context, const EffectDef &p_effect) {
	if (p_context.passive != nullptr) {
		p_context.passive->increase_pct += p_effect.value * p_context.passive->cells_run;
	}
}

const EffectHandler EFFECT_HANDLERS[] = {
	{ "effect.damage", apply_damage },
	{ "effect.taunt", apply_taunt },
	{ "effect.guard", apply_guard },
	{ "effect.armor_break", apply_armor_break },
	{ "effect.stun", apply_stun },
	{ "effect.petrify", apply_petrify },
	{ "effect.knockback", apply_knockback },
	{ "effect.add_qi", apply_add_qi },
	{ "effect.crit", apply_crit },
	{ "effect.impact_bonus_per_cell", apply_impact_bonus_per_cell },
	{ "effect.charge_column", apply_charge_column },
	{ "effect.arrow_volley", apply_arrow_volley },
};

} // namespace

const EffectHandler *find_effect_handler(const std::string &p_id) {
	for (const EffectHandler &handler : EFFECT_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

std::vector<int> get_effect_targets(const EffectContext &p_context, const EffectDef &p_effect) {
	const BattleSim &sim = *p_context.sim;
	const UnitState &caster = sim.get_units()[p_context.caster];
	std::vector<int> targets;
	switch (p_effect.target) {
		case EffectTarget::AREA:
			if (p_context.cells != nullptr) {
				targets = get_enemies_in_cells(sim, caster.side, *p_context.cells);
			}
			break;
		case EffectTarget::SELF:
			if (caster.is_alive) {
				targets.push_back(p_context.caster);
			}
			break;
		case EffectTarget::SOURCE:
			if (p_context.passive != nullptr && p_context.passive->source != NO_UNIT && sim.get_units()[p_context.passive->source].is_alive) {
				targets.push_back(p_context.passive->source);
			}
			break;
	}
	return targets;
}

int get_effect_count(const EffectContext &p_context, const EffectDef &p_effect) {
	const bool is_star3 = p_context.sim->get_units()[p_context.caster].star >= THREE_STARS;
	return is_star3 && p_effect.star3_count != SAME_AS_BASE ? p_effect.star3_count : p_effect.count;
}

int get_effect_coefficient(const EffectContext &p_context, const EffectDef &p_effect) {
	if (p_context.passive != nullptr) {
		return p_effect.value;
	}
	return scale_skill_coefficient(p_effect.value, p_context.sim->get_units()[p_context.caster].star, p_context.sim->get_rules());
}

} // namespace battle
