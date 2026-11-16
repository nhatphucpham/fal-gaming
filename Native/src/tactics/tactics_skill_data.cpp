#include "tactics_skill_data.h"

#include "tactics_skills.h"

using namespace godot;

bool TacticsSkillEffectData::to_effect_def(tactics::SkillEffectDef *r_def, std::string *r_error) const {
	r_def->handler_id = to_std_string(handler);
	r_def->handler = tactics::find_skill_effect_handler(r_def->handler_id);
	if (r_def->handler == nullptr) {
		*r_error = "unknown skill effect " + r_def->handler_id;
		return false;
	}
	if (damage_kind != static_cast<int>(tactics::DamageKind::PHYSICAL) && damage_kind != static_cast<int>(tactics::DamageKind::MAGIC)) {
		*r_error = r_def->handler_id + " has unknown damage_kind " + std::to_string(damage_kind);
		return false;
	}
	r_def->coefficient_pct = coefficient_pct;
	r_def->damage_kind = static_cast<tactics::DamageKind>(damage_kind);
	r_def->amount_pct = amount_pct;
	r_def->duration_rounds = duration_rounds;
	r_def->has_zone = zone.is_valid();
	return !r_def->has_zone || zone->to_zone_def(&r_def->zone, r_error);
}

bool TacticsSkillData::to_skill_def(tactics::SkillDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->charge_id = to_std_string(charge);
	r_def->charge = tactics::find_charge_handler(r_def->charge_id);
	r_def->target = tactics::find_skill_target_handler(to_std_string(target));
	if (r_def->charge == nullptr || r_def->target == nullptr) {
		*r_error = r_def->id + " has unknown charge " + r_def->charge_id + " or target " + to_std_string(target);
		return false;
	}
	r_def->charge_threshold = charge_threshold;
	r_def->cast_range_cells = cast_range_cells;
	r_def->area_radius_cells = area_radius_cells;
	r_def->chain_count = chain_count;
	r_def->chain_jump_cells = chain_jump_cells;
	r_def->chain_falloff_pct = chain_falloff_pct;
	r_def->effects.clear();
	for (int64_t index = 0; index < effects.size(); index++) {
		const Ref<TacticsSkillEffectData> effect = effects[index];
		tactics::SkillEffectDef def;
		if (effect.is_null() || !effect->to_effect_def(&def, r_error)) {
			*r_error = r_def->id + " effect " + std::to_string(index) + ": " + (effect.is_null() ? std::string("empty") : *r_error);
			return false;
		}
		r_def->effects.push_back(def);
	}
	return true;
}

void TacticsSkillEffectData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsSkillEffectData, handler);
	BATTLE_BIND_ACCESSORS(TacticsSkillEffectData, coefficient_pct);
	BATTLE_BIND_ACCESSORS(TacticsSkillEffectData, damage_kind);
	BATTLE_BIND_ACCESSORS(TacticsSkillEffectData, amount_pct);
	BATTLE_BIND_ACCESSORS(TacticsSkillEffectData, duration_rounds);
	BATTLE_BIND_ACCESSORS(TacticsSkillEffectData, zone);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "handler"), "set_handler", "get_handler");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "coefficient_pct", PROPERTY_HINT_RANGE, "0,1000,1"), "set_coefficient_pct", "get_coefficient_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "damage_kind", PROPERTY_HINT_ENUM, "Physical,Magic"), "set_damage_kind", "get_damage_kind");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "amount_pct", PROPERTY_HINT_RANGE, "0,1000,1"), "set_amount_pct", "get_amount_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "duration_rounds", PROPERTY_HINT_RANGE, "0,100,1"), "set_duration_rounds", "get_duration_rounds");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "zone", PROPERTY_HINT_RESOURCE_TYPE, "TacticsZoneData"), "set_zone", "get_zone");
}

void TacticsSkillData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsSkillData, id);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, charge);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, charge_threshold);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, target);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, cast_range_cells);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, area_radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, chain_count);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, chain_jump_cells);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, chain_falloff_pct);
	BATTLE_BIND_ACCESSORS(TacticsSkillData, effects);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "charge"), "set_charge", "get_charge");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "charge_threshold", PROPERTY_HINT_RANGE, "1,100000,1"), "set_charge_threshold", "get_charge_threshold");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "target"), "set_target", "get_target");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cast_range_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_cast_range_cells", "get_cast_range_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "area_radius_cells", PROPERTY_HINT_RANGE, "0,32,1"), "set_area_radius_cells", "get_area_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chain_count", PROPERTY_HINT_RANGE, "1,16,1"), "set_chain_count", "get_chain_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chain_jump_cells", PROPERTY_HINT_RANGE, "1,64,1"), "set_chain_jump_cells", "get_chain_jump_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "chain_falloff_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_chain_falloff_pct", "get_chain_falloff_pct");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "effects", PROPERTY_HINT_ARRAY_TYPE, "TacticsSkillEffectData"), "set_effects", "get_effects");
}
