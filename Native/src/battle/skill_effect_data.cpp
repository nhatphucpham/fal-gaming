#include "skill_effect_data.h"

using namespace godot;

battle::EffectDef SkillEffectData::to_effect_def() const {
	battle::EffectDef def;
	def.id = to_std_string(id);
	// Out-of-range codes are kept: resolve_skill() rejects them by name.
	def.target = static_cast<battle::EffectTarget>(target);
	def.damage_kind = static_cast<battle::DamageKind>(damage_kind);
	def.value = value;
	def.duration_ticks = duration_ticks;
	def.count = count;
	def.star3_count = star3_count;
	return def;
}

void SkillEffectData::_bind_methods() {
	BIND_ENUM_CONSTANT(TARGET_AREA);
	BIND_ENUM_CONSTANT(TARGET_SELF);
	BIND_ENUM_CONSTANT(TARGET_SOURCE);

	BATTLE_BIND_ACCESSORS(SkillEffectData, id);
	BATTLE_BIND_ACCESSORS(SkillEffectData, target);
	BATTLE_BIND_ACCESSORS(SkillEffectData, value);
	BATTLE_BIND_ACCESSORS(SkillEffectData, duration_ticks);
	BATTLE_BIND_ACCESSORS(SkillEffectData, count);
	BATTLE_BIND_ACCESSORS(SkillEffectData, star3_count);
	BATTLE_BIND_ACCESSORS(SkillEffectData, damage_kind);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "target", PROPERTY_HINT_ENUM, "Area,Self,Source"), "set_target", "get_target");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "value", PROPERTY_HINT_RANGE, "0,1000,1"), "set_value", "get_value");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "duration_ticks", PROPERTY_HINT_RANGE, "0,10000,1"), "set_duration_ticks", "get_duration_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "count", PROPERTY_HINT_RANGE, "0,20,1"), "set_count", "get_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "star3_count", PROPERTY_HINT_RANGE, "-1,20,1"), "set_star3_count", "get_star3_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "damage_kind", PROPERTY_HINT_ENUM, "Physical,Magic"), "set_damage_kind", "get_damage_kind");
}
