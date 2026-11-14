#include "milestone_data.h"

using namespace godot;

bool MilestoneData::to_milestone_def(rules::MilestoneDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	const String kind = counted_kind;
	if (kind != "class" && kind != "race") {
		*r_error = r_def->id + " has counted_kind '" + to_std_string(kind) + "', expected class or race";
		return false;
	}
	r_def->kind = kind == "class" ? rules::CountedKind::CLASS : rules::CountedKind::RACE;
	r_def->counted_id = to_std_string(counted_id);
	r_def->counts_distinct_units = counts_distinct_units;
	r_def->double_from_cost = double_from_cost;
	return copy_tier_defs(id, tiers, &r_def->tiers, r_error);
}

void MilestoneData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(MilestoneData, id);
	BATTLE_BIND_ACCESSORS(MilestoneData, name_key);
	BATTLE_BIND_ACCESSORS(MilestoneData, counted_kind);
	BATTLE_BIND_ACCESSORS(MilestoneData, counted_id);
	BATTLE_BIND_ACCESSORS(MilestoneData, counts_distinct_units);
	BATTLE_BIND_ACCESSORS(MilestoneData, double_from_cost);
	BATTLE_BIND_ACCESSORS(MilestoneData, tiers);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "counted_kind"), "set_counted_kind", "get_counted_kind");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "counted_id"), "set_counted_id", "get_counted_id");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "counts_distinct_units"), "set_counts_distinct_units", "get_counts_distinct_units");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "double_from_cost", PROPERTY_HINT_RANGE, "0,5,1"), "set_double_from_cost", "get_double_from_cost");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "tiers", PROPERTY_HINT_ARRAY_TYPE, "SynergyTierData"), "set_tiers", "get_tiers");
}
