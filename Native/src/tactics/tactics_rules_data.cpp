#include "tactics_rules_data.h"

using namespace godot;

void TacticsRulesData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsRulesData, hits_per_engagement);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, anticipation_shift_cells);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, help_radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, max_leaders_per_side);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, max_rounds);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "hits_per_engagement", PROPERTY_HINT_RANGE, "1,10,1"), "set_hits_per_engagement", "get_hits_per_engagement");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "anticipation_shift_cells", PROPERTY_HINT_RANGE, "0,20,1"), "set_anticipation_shift_cells", "get_anticipation_shift_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "help_radius_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_help_radius_cells", "get_help_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_leaders_per_side", PROPERTY_HINT_RANGE, "1,8,1"), "set_max_leaders_per_side", "get_max_leaders_per_side");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_rounds", PROPERTY_HINT_RANGE, "1,1000,1"), "set_max_rounds", "get_max_rounds");
}
