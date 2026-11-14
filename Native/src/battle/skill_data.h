#pragma once

#include "bridge_strings.h"
#include "skill_effect_data.h"

#include "skill/skill_types.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <string>

namespace godot {

// A skill (chiêu): Khí cost, a selector and an area that say where it lands,
// up to three effects, star-3 overrides and an optional Hậu chiêu. One file
// per skill in Data/Skills/, referenced by ClassData.skill (or
// UnitData.skill_override). Schema in Docs/systems/skill.md.
class SkillData : public Resource {
	GDCLASS(SkillData, Resource)

	StringName id;
	String name_key;
	String description_key;
	int qi_cost = 100;
	StringName selector = "select.self";
	int selector_range = 0;
	StringName area = "area.single";
	int area_size = 0;
	TypedArray<SkillEffectData> effects;
	StringName star3_area;
	int star3_area_size = battle::SAME_AS_BASE;
	bool has_after_skill = false;
	int after_delay_ticks = 0;
	StringName after_selector;
	StringName after_area;
	int after_area_size = 0;
	TypedArray<SkillEffectData> after_effects;

protected:
	static void _bind_methods();

public:
	// The simulation's struct; false and r_error on an empty effect entry.
	// Handler ids are checked later by the battle.
	bool to_skill_def(battle::SkillDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_id) { id = p_id; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_qi_cost(int64_t p_value) { qi_cost = clamp_to_int(p_value); }
	int get_qi_cost() const { return qi_cost; }
	void set_selector(const StringName &p_value) { selector = p_value; }
	StringName get_selector() const { return selector; }
	void set_selector_range(int64_t p_value) { selector_range = clamp_to_int(p_value); }
	int get_selector_range() const { return selector_range; }
	void set_area(const StringName &p_value) { area = p_value; }
	StringName get_area() const { return area; }
	void set_area_size(int64_t p_value) { area_size = clamp_to_int(p_value); }
	int get_area_size() const { return area_size; }
	void set_effects(const TypedArray<SkillEffectData> &p_value) { effects = p_value; }
	TypedArray<SkillEffectData> get_effects() const { return effects; }
	void set_star3_area(const StringName &p_value) { star3_area = p_value; }
	StringName get_star3_area() const { return star3_area; }
	void set_star3_area_size(int64_t p_value) { star3_area_size = clamp_to_int(p_value); }
	int get_star3_area_size() const { return star3_area_size; }
	void set_has_after_skill(bool p_value) { has_after_skill = p_value; }
	bool get_has_after_skill() const { return has_after_skill; }
	void set_after_delay_ticks(int64_t p_value) { after_delay_ticks = clamp_to_int(p_value); }
	int get_after_delay_ticks() const { return after_delay_ticks; }
	void set_after_selector(const StringName &p_value) { after_selector = p_value; }
	StringName get_after_selector() const { return after_selector; }
	void set_after_area(const StringName &p_value) { after_area = p_value; }
	StringName get_after_area() const { return after_area; }
	void set_after_area_size(int64_t p_value) { after_area_size = clamp_to_int(p_value); }
	int get_after_area_size() const { return after_area_size; }
	void set_after_effects(const TypedArray<SkillEffectData> &p_value) { after_effects = p_value; }
	TypedArray<SkillEffectData> get_after_effects() const { return after_effects; }
};

// Copies effect resources into plain structs; false on an empty entry.
bool copy_effect_defs(const TypedArray<SkillEffectData> &p_effects, std::vector<battle::EffectDef> *r_defs);

} // namespace godot
