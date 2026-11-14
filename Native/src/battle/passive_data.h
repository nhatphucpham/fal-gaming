#pragma once

#include "bridge_strings.h"
#include "skill_effect_data.h"

#include "skill/skill_types.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <string>

namespace godot {

// A passive (nội tại): "when <trigger> (and <condition>), every Nth time,
// do <effect>", with an optional per-battle limit. One file per passive in
// Data/Passives/, referenced by ClassData.passive (or
// UnitData.passive_override). Schema in Docs/systems/skill.md.
class PassiveData : public Resource {
	GDCLASS(PassiveData, Resource)

	StringName id;
	String name_key;
	String description_key;
	StringName trigger;
	StringName condition;
	int condition_radius = 0;
	int every_nth = 1;
	int limit_per_battle = 0;
	bool once_per_source = false;
	int window_ticks = 0;
	Ref<SkillEffectData> effect;

protected:
	static void _bind_methods();

public:
	// The simulation's struct; false and r_error without an effect.
	bool to_passive_def(battle::PassiveDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_id) { id = p_id; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_trigger(const StringName &p_value) { trigger = p_value; }
	StringName get_trigger() const { return trigger; }
	void set_condition(const StringName &p_value) { condition = p_value; }
	StringName get_condition() const { return condition; }
	void set_condition_radius(int64_t p_value) { condition_radius = clamp_to_int(p_value); }
	int get_condition_radius() const { return condition_radius; }
	void set_every_nth(int64_t p_value) { every_nth = clamp_to_int(p_value); }
	int get_every_nth() const { return every_nth; }
	void set_limit_per_battle(int64_t p_value) { limit_per_battle = clamp_to_int(p_value); }
	int get_limit_per_battle() const { return limit_per_battle; }
	void set_once_per_source(bool p_value) { once_per_source = p_value; }
	bool get_once_per_source() const { return once_per_source; }
	void set_window_ticks(int64_t p_value) { window_ticks = clamp_to_int(p_value); }
	int get_window_ticks() const { return window_ticks; }
	void set_effect(const Ref<SkillEffectData> &p_value) { effect = p_value; }
	Ref<SkillEffectData> get_effect() const { return effect; }
};

} // namespace godot
