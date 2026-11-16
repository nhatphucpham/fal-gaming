#include "tactics_scenario_data.h"

using namespace godot;

void TacticsScenarioData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, id);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, rules);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, map);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, leaders_a);
	BATTLE_BIND_ACCESSORS(TacticsScenarioData, leaders_b);
	ClassDB::bind_method(D_METHOD("get_leaders", "side"), &TacticsScenarioData::get_leaders);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "rules", PROPERTY_HINT_RESOURCE_TYPE, "TacticsRulesData"), "set_rules", "get_rules");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "map", PROPERTY_HINT_RESOURCE_TYPE, "TacticsMapData"), "set_map", "get_map");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "leaders_a", PROPERTY_HINT_ARRAY_TYPE, "TacticsLeaderData"), "set_leaders_a", "get_leaders_a");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "leaders_b", PROPERTY_HINT_ARRAY_TYPE, "TacticsLeaderData"), "set_leaders_b", "get_leaders_b");
}
