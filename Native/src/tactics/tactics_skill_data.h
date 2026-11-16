#pragma once

#include "tactics_zone_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <string>

namespace godot {

// One effect of a tactics skill: a handler id (tactics_skill_effects.cpp)
// and the numbers it reads. Usually a sub-resource of its skill.
class TacticsSkillEffectData : public Resource {
	GDCLASS(TacticsSkillEffectData, Resource)

	StringName handler;
	int coefficient_pct = 100;
	// A ClassData.DamageKind value.
	int damage_kind = 0;
	int amount_pct = 0;
	int duration_rounds = 0;
	Ref<TacticsZoneData> zone;

protected:
	static void _bind_methods();

public:
	bool to_effect_def(tactics::SkillEffectDef *r_def, std::string *r_error) const;

	void set_handler(const StringName &p_value) { handler = p_value; }
	StringName get_handler() const { return handler; }
	void set_coefficient_pct(int64_t p_value) { coefficient_pct = clamp_to_int(p_value); }
	int get_coefficient_pct() const { return coefficient_pct; }
	void set_damage_kind(int64_t p_value) { damage_kind = clamp_to_int(p_value); }
	int get_damage_kind() const { return damage_kind; }
	void set_amount_pct(int64_t p_value) { amount_pct = clamp_to_int(p_value); }
	int get_amount_pct() const { return amount_pct; }
	void set_duration_rounds(int64_t p_value) { duration_rounds = clamp_to_int(p_value); }
	int get_duration_rounds() const { return duration_rounds; }
	void set_zone(const Ref<TacticsZoneData> &p_value) { zone = p_value; }
	Ref<TacticsZoneData> get_zone() const { return zone; }
};

// A leader's skill: how it charges, what it targets and its effects. One
// file per skill in Data/Tactics/Skills/. Schema in Docs/systems/tactics.md.
class TacticsSkillData : public Resource {
	GDCLASS(TacticsSkillData, Resource)

	StringName id;
	String name_key;
	String description_key;
	StringName charge;
	int charge_threshold = 1;
	StringName target;
	int cast_range_cells = 1;
	int area_radius_cells = 0;
	int chain_count = 1;
	int chain_jump_cells = 1;
	int chain_falloff_pct = 0;
	TypedArray<TacticsSkillEffectData> effects;

protected:
	static void _bind_methods();

public:
	// False and r_error on an unknown handler or an empty effect.
	bool to_skill_def(tactics::SkillDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_charge(const StringName &p_value) { charge = p_value; }
	StringName get_charge() const { return charge; }
	void set_charge_threshold(int64_t p_value) { charge_threshold = clamp_to_int(p_value); }
	int get_charge_threshold() const { return charge_threshold; }
	void set_target(const StringName &p_value) { target = p_value; }
	StringName get_target() const { return target; }
	void set_cast_range_cells(int64_t p_value) { cast_range_cells = clamp_to_int(p_value); }
	int get_cast_range_cells() const { return cast_range_cells; }
	void set_area_radius_cells(int64_t p_value) { area_radius_cells = clamp_to_int(p_value); }
	int get_area_radius_cells() const { return area_radius_cells; }
	void set_chain_count(int64_t p_value) { chain_count = clamp_to_int(p_value); }
	int get_chain_count() const { return chain_count; }
	void set_chain_jump_cells(int64_t p_value) { chain_jump_cells = clamp_to_int(p_value); }
	int get_chain_jump_cells() const { return chain_jump_cells; }
	void set_chain_falloff_pct(int64_t p_value) { chain_falloff_pct = clamp_to_int(p_value); }
	int get_chain_falloff_pct() const { return chain_falloff_pct; }
	void set_effects(const TypedArray<TacticsSkillEffectData> &p_value) { effects = p_value; }
	TypedArray<TacticsSkillEffectData> get_effects() const { return effects; }
};

} // namespace godot
