#pragma once

#include "synergy_tier_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

// A class or race milestone (Nghề, Tộc): what it counts and its tiers. One
// file per milestone in Data/Synergies/. Schema in Docs/systems/synergy.md.
class MilestoneData : public Resource {
	GDCLASS(MilestoneData, Resource)

	StringName id;
	String name_key;
	// `class` or `race`.
	StringName counted_kind = "class";
	StringName counted_id;
	bool counts_distinct_units = true;
	int double_from_cost = 0;
	TypedArray<SynergyTierData> tiers;

protected:
	static void _bind_methods();

public:
	bool to_milestone_def(rules::MilestoneDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_counted_kind(const StringName &p_value) { counted_kind = p_value; }
	StringName get_counted_kind() const { return counted_kind; }
	void set_counted_id(const StringName &p_value) { counted_id = p_value; }
	StringName get_counted_id() const { return counted_id; }
	void set_counts_distinct_units(bool p_value) { counts_distinct_units = p_value; }
	bool get_counts_distinct_units() const { return counts_distinct_units; }
	void set_double_from_cost(int64_t p_value) { double_from_cost = clamp_to_int(p_value); }
	int get_double_from_cost() const { return double_from_cost; }
	void set_tiers(const TypedArray<SynergyTierData> &p_value) { tiers = p_value; }
	TypedArray<SynergyTierData> get_tiers() const { return tiers; }
};

} // namespace godot
