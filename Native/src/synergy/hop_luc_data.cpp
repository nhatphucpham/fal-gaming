#include "hop_luc_data.h"

using namespace godot;

bool HopLucData::to_hop_luc_def(rules::HopLucDef *r_def, std::string *r_error) const {
	r_def->level_step_pct = formation_level_step_pct;
	r_def->max_level = max_formation_level;
	return copy_tier_defs("hop_luc", tiers, &r_def->tiers, r_error);
}

void HopLucData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(HopLucData, tiers);
	BATTLE_BIND_ACCESSORS(HopLucData, formation_level_step_pct);
	BATTLE_BIND_ACCESSORS(HopLucData, max_formation_level);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "tiers", PROPERTY_HINT_ARRAY_TYPE, "SynergyTierData"), "set_tiers", "get_tiers");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "formation_level_step_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_formation_level_step_pct", "get_formation_level_step_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_formation_level", PROPERTY_HINT_RANGE, "1,10,1"), "set_max_formation_level", "get_max_formation_level");
}
