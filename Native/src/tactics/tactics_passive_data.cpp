#include "tactics_passive_data.h"

#include "tactics_passives.h"

using namespace godot;

bool TacticsPassiveData::to_passive_def(tactics::PassiveDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->handler = tactics::find_passive_handler(to_std_string(handler));
	if (r_def->handler == nullptr) {
		*r_error = r_def->id + " has unknown handler " + to_std_string(handler);
		return false;
	}
	r_def->stat = tactics::find_stat_kind(to_std_string(stat));
	if (!String(stat).is_empty() && r_def->stat == tactics::StatKind::NONE) {
		*r_error = r_def->id + " has unknown stat " + to_std_string(stat);
		return false;
	}
	r_def->amount = amount;
	r_def->condition_terrain_id = to_std_string(condition_terrain_id);
	r_def->condition_adjacent_allies = condition_adjacent_allies;
	r_def->extra_capacity = extra_capacity;
	r_def->radius_cells = radius_cells;
	r_def->duration_rounds = duration_rounds;
	r_def->has_keyword = keyword.is_valid();
	if (r_def->has_keyword && !keyword->to_keyword_def(&r_def->keyword, r_error)) {
		*r_error = r_def->id + ": " + *r_error;
		return false;
	}
	r_def->has_zone = zone.is_valid();
	if (r_def->has_zone && !zone->to_zone_def(&r_def->zone, r_error)) {
		*r_error = r_def->id + ": " + *r_error;
		return false;
	}
	return true;
}

void TacticsPassiveData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, id);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, handler);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, stat);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, amount);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, condition_terrain_id);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, condition_adjacent_allies);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, keyword);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, extra_capacity);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, zone);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsPassiveData, duration_rounds);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "handler"), "set_handler", "get_handler");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "stat"), "set_stat", "get_stat");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "amount"), "set_amount", "get_amount");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "condition_terrain_id"), "set_condition_terrain_id", "get_condition_terrain_id");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "condition_adjacent_allies", PROPERTY_HINT_RANGE, "0,4,1"), "set_condition_adjacent_allies", "get_condition_adjacent_allies");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "keyword", PROPERTY_HINT_RESOURCE_TYPE, "TacticsKeywordData"), "set_keyword", "get_keyword");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "extra_capacity", PROPERTY_HINT_RANGE, "0,8,1"), "set_extra_capacity", "get_extra_capacity");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "zone", PROPERTY_HINT_RESOURCE_TYPE, "TacticsZoneData"), "set_zone", "get_zone");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "radius_cells", PROPERTY_HINT_RANGE, "0,32,1"), "set_radius_cells", "get_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "duration_rounds", PROPERTY_HINT_RANGE, "0,100,1"), "set_duration_rounds", "get_duration_rounds");
}
