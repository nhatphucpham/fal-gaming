#pragma once

#include "tactics_map_data.h"
#include "tactics_rules_data.h"
#include "tactics_unit_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// A ready-to-play tactics battle: rules, map and the leaders of each side,
// placed on the map's spawn cells in order, each with its own squad. One
// file per scenario in Data/Tactics/Scenarios/, id `scenario.<name>`.
// TacticsBattle.load_scenario() reads it.
class TacticsScenarioData : public Resource {
	GDCLASS(TacticsScenarioData, Resource)

	StringName id;
	String name_key;
	Ref<TacticsRulesData> rules;
	Ref<TacticsMapData> map;
	TypedArray<TacticsLeaderData> leaders_a;
	TypedArray<TacticsLeaderData> leaders_b;

protected:
	static void _bind_methods();

public:
	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_rules(const Ref<TacticsRulesData> &p_value) { rules = p_value; }
	Ref<TacticsRulesData> get_rules() const { return rules; }
	void set_map(const Ref<TacticsMapData> &p_value) { map = p_value; }
	Ref<TacticsMapData> get_map() const { return map; }
	void set_leaders_a(const TypedArray<TacticsLeaderData> &p_value) { leaders_a = p_value; }
	TypedArray<TacticsLeaderData> get_leaders_a() const { return leaders_a; }
	void set_leaders_b(const TypedArray<TacticsLeaderData> &p_value) { leaders_b = p_value; }
	TypedArray<TacticsLeaderData> get_leaders_b() const { return leaders_b; }
	// The leaders of a side (0 or 1).
	TypedArray<TacticsLeaderData> get_leaders(int64_t p_side) const { return p_side == 0 ? leaders_a : leaders_b; }
};

} // namespace godot
