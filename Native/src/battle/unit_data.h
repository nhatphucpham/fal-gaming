#pragma once

#include "bridge_strings.h"
#include "passive_data.h"
#include "skill_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

// One recruitable unit: its class, race, shop cost and element. Stats come
// from the class, scaled by cost and star. One file per unit in Data/Units/.
class UnitData : public Resource {
	GDCLASS(UnitData, Resource)

	StringName id;
	String name_key;
	StringName class_id;
	StringName race_id;
	int cost = 1;
	StringName element_id;
	// Replace the class skill or passive for this unit only (heroes,
	// variants); empty uses the class's.
	Ref<SkillData> skill_override;
	Ref<PassiveData> passive_override;
	// A boss (Cự Nham): never sold in the shop, drawn bigger, with a wide
	// hp bar. The simulation treats it like any unit.
	bool is_boss = false;

protected:
	static void _bind_methods();

public:
	void set_id(const StringName &p_id) { id = p_id; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_name_key) { name_key = p_name_key; }
	String get_name_key() const { return name_key; }
	void set_class_id(const StringName &p_class_id) { class_id = p_class_id; }
	StringName get_class_id() const { return class_id; }
	void set_race_id(const StringName &p_race_id) { race_id = p_race_id; }
	StringName get_race_id() const { return race_id; }
	void set_cost(int64_t p_cost) { cost = clamp_to_int(p_cost); }
	int get_cost() const { return cost; }
	void set_element_id(const StringName &p_element_id) { element_id = p_element_id; }
	StringName get_element_id() const { return element_id; }
	void set_skill_override(const Ref<SkillData> &p_value) { skill_override = p_value; }
	Ref<SkillData> get_skill_override() const { return skill_override; }
	void set_passive_override(const Ref<PassiveData> &p_value) { passive_override = p_value; }
	Ref<PassiveData> get_passive_override() const { return passive_override; }
	void set_is_boss(bool p_value) { is_boss = p_value; }
	bool get_is_boss() const { return is_boss; }
};

} // namespace godot
