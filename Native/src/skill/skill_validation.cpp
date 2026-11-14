#include "skill_validation.h"

#include "skill_areas.h"
#include "skill_effects.h"
#include "skill_passives.h"
#include "skill_selectors.h"

namespace battle {

namespace {

bool fail(const std::string &p_message, std::string *r_error) {
	if (r_error != nullptr) {
		*r_error = p_message;
	}
	return false;
}

bool check_range(const std::string &p_owner, const char *p_field, int p_value, int p_min, int p_max, std::string *r_error) {
	if (p_value >= p_min && p_value <= p_max) {
		return true;
	}
	return fail(p_owner + " " + p_field + " must be " + std::to_string(p_min) + ".." + std::to_string(p_max) + ", got " + std::to_string(p_value), r_error);
}

bool resolve_effect(const std::string &p_owner, EffectDef *r_effect, std::string *r_error) {
	r_effect->handler = find_effect_handler(r_effect->id);
	if (r_effect->handler == nullptr) {
		return fail(p_owner + " has unknown effect '" + r_effect->id + "'", r_error);
	}
	const std::string owner = p_owner + " " + r_effect->id;
	return check_range(owner, "target", static_cast<int>(r_effect->target), 0, static_cast<int>(EffectTarget::SOURCE), r_error)
			&& check_range(owner, "damage_kind", static_cast<int>(r_effect->damage_kind), 0, static_cast<int>(DamageKind::MAGIC), r_error)
			&& check_range(owner, "value", r_effect->value, 0, MAX_EFFECT_VALUE, r_error)
			&& check_range(owner, "duration_ticks", r_effect->duration_ticks, 0, MAX_EFFECT_TICKS, r_error)
			&& check_range(owner, "count", r_effect->count, 0, MAX_EFFECT_COUNT, r_error)
			&& check_range(owner, "star3_count", r_effect->star3_count, SAME_AS_BASE, MAX_EFFECT_COUNT, r_error);
}

bool resolve_area(const std::string &p_owner, const char *p_field, const std::string &p_id, const AreaHandler **r_area, std::string *r_error) {
	*r_area = find_area_handler(p_id);
	return *r_area != nullptr || fail(p_owner + " has unknown " + p_field + " '" + p_id + "'", r_error);
}

// p_is_optional: an empty selector means "reuse the main step's cells".
bool resolve_step(const std::string &p_owner, SkillStepDef *r_step, bool p_is_optional, std::string *r_error) {
	if (!(p_is_optional && r_step->selector_id.empty())) {
		r_step->selector = find_selector_handler(r_step->selector_id);
		if (r_step->selector == nullptr) {
			return fail(p_owner + " has unknown selector '" + r_step->selector_id + "'", r_error);
		}
		if (!resolve_area(p_owner, "area", r_step->area_id, &r_step->area, r_error)) {
			return false;
		}
	}
	const int min_effects = p_is_optional ? 0 : 1;
	if (!check_range(p_owner, "selector_range", r_step->selector_range, 0, MAX_AREA_SIZE, r_error)
			|| !check_range(p_owner, "area_size", r_step->area_size, 0, MAX_AREA_SIZE, r_error)
			|| !check_range(p_owner, "effect count", static_cast<int>(r_step->effects.size()), min_effects, MAX_SKILL_EFFECTS, r_error)) {
		return false;
	}
	for (EffectDef &effect : r_step->effects) {
		if (!resolve_effect(p_owner, &effect, r_error)) {
			return false;
		}
	}
	return true;
}

} // namespace

bool resolve_skill(SkillDef *r_skill, std::string *r_error) {
	const std::string &owner = r_skill->id;
	if (owner.empty()) {
		return fail("a skill has an empty id", r_error);
	}
	if (!check_range(owner, "qi_cost", r_skill->qi_cost, 1, MAX_QI_COST, r_error) || !resolve_step(owner, &r_skill->main, false, r_error)) {
		return false;
	}
	r_skill->star3_area = nullptr;
	if (!r_skill->star3_area_id.empty() && !resolve_area(owner, "star3_area", r_skill->star3_area_id, &r_skill->star3_area, r_error)) {
		return false;
	}
	if (!check_range(owner, "star3_area_size", r_skill->star3_area_size, SAME_AS_BASE, MAX_AREA_SIZE, r_error)) {
		return false;
	}
	if (!r_skill->has_after_skill) {
		return true;
	}
	return check_range(owner, "after_delay_ticks", r_skill->after_delay_ticks, 0, MAX_EFFECT_TICKS, r_error) && resolve_step(owner + " after", &r_skill->after, true, r_error);
}

bool resolve_passive(PassiveDef *r_passive, std::string *r_error) {
	const std::string &owner = r_passive->id;
	if (owner.empty()) {
		return fail("a passive has an empty id", r_error);
	}
	if (!find_passive_trigger(r_passive->trigger_id, &r_passive->trigger)) {
		return fail(owner + " has unknown trigger '" + r_passive->trigger_id + "'", r_error);
	}
	r_passive->condition = nullptr;
	if (!r_passive->condition_id.empty()) {
		r_passive->condition = find_condition_handler(r_passive->condition_id);
		if (r_passive->condition == nullptr) {
			return fail(owner + " has unknown condition '" + r_passive->condition_id + "'", r_error);
		}
	}
	return check_range(owner, "condition_radius", r_passive->condition_radius, 0, MAX_AREA_SIZE, r_error)
			&& check_range(owner, "every_nth", r_passive->every_nth, 1, MAX_PASSIVE_EVERY_NTH, r_error)
			&& check_range(owner, "limit_per_battle", r_passive->limit_per_battle, 0, MAX_PASSIVE_LIMIT, r_error)
			&& check_range(owner, "window_ticks", r_passive->window_ticks, 0, MAX_EFFECT_TICKS, r_error)
			&& resolve_effect(owner, &r_passive->effect, r_error);
}

} // namespace battle
