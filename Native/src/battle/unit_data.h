#pragma once

#include "bridge_strings.h"

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
};

} // namespace godot
