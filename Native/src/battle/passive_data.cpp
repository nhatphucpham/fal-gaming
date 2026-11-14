#include "passive_data.h"

using namespace godot;

bool PassiveData::to_passive_def(battle::PassiveDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->trigger_id = to_std_string(trigger);
	r_def->condition_id = to_std_string(condition);
	r_def->condition_radius = condition_radius;
	r_def->every_nth = every_nth;
	r_def->limit_per_battle = limit_per_battle;
	r_def->once_per_source = once_per_source;
	r_def->window_ticks = window_ticks;
	if (effect.is_null()) {
		*r_error = r_def->id + " has no effect";
		return false;
	}
	r_def->effect = effect->to_effect_def();
	return true;
}

void PassiveData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(PassiveData, id);
	BATTLE_BIND_ACCESSORS(PassiveData, name_key);
	BATTLE_BIND_ACCESSORS(PassiveData, description_key);
	BATTLE_BIND_ACCESSORS(PassiveData, trigger);
	BATTLE_BIND_ACCESSORS(PassiveData, condition);
	BATTLE_BIND_ACCESSORS(PassiveData, condition_radius);
	BATTLE_BIND_ACCESSORS(PassiveData, every_nth);
	BATTLE_BIND_ACCESSORS(PassiveData, limit_per_battle);
	BATTLE_BIND_ACCESSORS(PassiveData, once_per_source);
	BATTLE_BIND_ACCESSORS(PassiveData, window_ticks);
	BATTLE_BIND_ACCESSORS(PassiveData, effect);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "trigger"), "set_trigger", "get_trigger");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "condition"), "set_condition", "get_condition");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "condition_radius", PROPERTY_HINT_RANGE, "0,8,1"), "set_condition_radius", "get_condition_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "every_nth", PROPERTY_HINT_RANGE, "1,100,1"), "set_every_nth", "get_every_nth");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "limit_per_battle", PROPERTY_HINT_RANGE, "0,100,1"), "set_limit_per_battle", "get_limit_per_battle");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "once_per_source"), "set_once_per_source", "get_once_per_source");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "window_ticks", PROPERTY_HINT_RANGE, "0,10000,1"), "set_window_ticks", "get_window_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "effect", PROPERTY_HINT_RESOURCE_TYPE, "SkillEffectData"), "set_effect", "get_effect");
}
