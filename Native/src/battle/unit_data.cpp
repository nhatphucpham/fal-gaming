#include "unit_data.h"

#include "bridge_strings.h"

using namespace godot;

void UnitData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(UnitData, id);
	BATTLE_BIND_ACCESSORS(UnitData, name_key);
	BATTLE_BIND_ACCESSORS(UnitData, class_id);
	BATTLE_BIND_ACCESSORS(UnitData, race_id);
	BATTLE_BIND_ACCESSORS(UnitData, cost);
	BATTLE_BIND_ACCESSORS(UnitData, element_id);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "class_id"), "set_class_id", "get_class_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "race_id"), "set_race_id", "get_race_id");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cost", PROPERTY_HINT_RANGE, "1,5,1"), "set_cost", "get_cost");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "element_id"), "set_element_id", "get_element_id");
}
