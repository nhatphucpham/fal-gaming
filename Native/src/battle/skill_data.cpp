#include "skill_data.h"

using namespace godot;

bool godot::copy_effect_defs(const TypedArray<SkillEffectData> &p_effects, std::vector<battle::EffectDef> *r_defs) {
	r_defs->clear();
	for (int64_t index = 0; index < p_effects.size(); index++) {
		const Ref<SkillEffectData> effect = p_effects[index];
		if (effect.is_null()) {
			return false;
		}
		r_defs->push_back(effect->to_effect_def());
	}
	return true;
}

bool SkillData::to_skill_def(battle::SkillDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->qi_cost = qi_cost;
	r_def->main.selector_id = to_std_string(selector);
	r_def->main.selector_range = selector_range;
	r_def->main.area_id = to_std_string(area);
	r_def->main.area_size = area_size;
	r_def->star3_area_id = to_std_string(star3_area);
	r_def->star3_area_size = star3_area_size;
	r_def->has_after_skill = has_after_skill;
	r_def->after_delay_ticks = after_delay_ticks;
	r_def->after.selector_id = to_std_string(after_selector);
	r_def->after.area_id = to_std_string(after_area);
	r_def->after.area_size = after_area_size;
	if (!copy_effect_defs(effects, &r_def->main.effects) || !copy_effect_defs(after_effects, &r_def->after.effects)) {
		*r_error = r_def->id + " has an empty effect entry";
		return false;
	}
	return true;
}

void SkillData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(SkillData, id);
	BATTLE_BIND_ACCESSORS(SkillData, name_key);
	BATTLE_BIND_ACCESSORS(SkillData, description_key);
	BATTLE_BIND_ACCESSORS(SkillData, qi_cost);
	BATTLE_BIND_ACCESSORS(SkillData, selector);
	BATTLE_BIND_ACCESSORS(SkillData, selector_range);
	BATTLE_BIND_ACCESSORS(SkillData, area);
	BATTLE_BIND_ACCESSORS(SkillData, area_size);
	BATTLE_BIND_ACCESSORS(SkillData, effects);
	BATTLE_BIND_ACCESSORS(SkillData, star3_area);
	BATTLE_BIND_ACCESSORS(SkillData, star3_area_size);
	BATTLE_BIND_ACCESSORS(SkillData, has_after_skill);
	BATTLE_BIND_ACCESSORS(SkillData, after_delay_ticks);
	BATTLE_BIND_ACCESSORS(SkillData, after_selector);
	BATTLE_BIND_ACCESSORS(SkillData, after_area);
	BATTLE_BIND_ACCESSORS(SkillData, after_area_size);
	BATTLE_BIND_ACCESSORS(SkillData, after_effects);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "qi_cost", PROPERTY_HINT_RANGE, "1,1000,1"), "set_qi_cost", "get_qi_cost");
	ADD_GROUP("Aim", "");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "selector"), "set_selector", "get_selector");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "selector_range", PROPERTY_HINT_RANGE, "0,8,1"), "set_selector_range", "get_selector_range");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "area"), "set_area", "get_area");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "area_size", PROPERTY_HINT_RANGE, "0,8,1"), "set_area_size", "get_area_size");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "effects", PROPERTY_HINT_ARRAY_TYPE, "SkillEffectData"), "set_effects", "get_effects");
	ADD_GROUP("Three stars", "");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "star3_area"), "set_star3_area", "get_star3_area");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "star3_area_size", PROPERTY_HINT_RANGE, "-1,8,1"), "set_star3_area_size", "get_star3_area_size");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "has_after_skill"), "set_has_after_skill", "get_has_after_skill");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "after_delay_ticks", PROPERTY_HINT_RANGE, "0,10000,1"), "set_after_delay_ticks", "get_after_delay_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "after_selector"), "set_after_selector", "get_after_selector");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "after_area"), "set_after_area", "get_after_area");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "after_area_size", PROPERTY_HINT_RANGE, "0,8,1"), "set_after_area_size", "get_after_area_size");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "after_effects", PROPERTY_HINT_ARRAY_TYPE, "SkillEffectData"), "set_after_effects", "get_after_effects");
}
