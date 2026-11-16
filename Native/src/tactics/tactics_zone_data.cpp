#include "tactics_zone_data.h"

#include "tactics_zones.h"

using namespace godot;

bool TacticsZoneData::to_zone_def(tactics::ZoneDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->handler = tactics::find_zone_handler(to_std_string(effect));
	r_def->amount = amount;
	if (r_def->handler == nullptr) {
		*r_error = r_def->id + " has unknown effect " + to_std_string(effect);
		return false;
	}
	return true;
}

void TacticsZoneData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsZoneData, id);
	BATTLE_BIND_ACCESSORS(TacticsZoneData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsZoneData, effect);
	BATTLE_BIND_ACCESSORS(TacticsZoneData, amount);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "effect"), "set_effect", "get_effect");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "amount"), "set_amount", "get_amount");
}
