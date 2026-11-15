#include "tactics_keyword_data.h"

#include "tactics_keywords.h"

using namespace godot;

bool TacticsKeywordData::to_keyword_def(tactics::KeywordDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->handler = tactics::find_keyword_handler(r_def->id);
	r_def->amount = amount;
	r_def->min_cells = min_cells;
	r_def->terrain_ids.clear();
	for (int64_t index = 0; index < terrain_ids.size(); index++) {
		r_def->terrain_ids.push_back(to_std_string(StringName(terrain_ids[index])));
	}
	if (r_def->handler == nullptr) {
		*r_error = "unknown keyword " + r_def->id;
		return false;
	}
	return true;
}

void TacticsKeywordData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsKeywordData, id);
	BATTLE_BIND_ACCESSORS(TacticsKeywordData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsKeywordData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsKeywordData, amount);
	BATTLE_BIND_ACCESSORS(TacticsKeywordData, min_cells);
	BATTLE_BIND_ACCESSORS(TacticsKeywordData, terrain_ids);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "amount"), "set_amount", "get_amount");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "min_cells", PROPERTY_HINT_RANGE, "0,20,1"), "set_min_cells", "get_min_cells");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "terrain_ids", PROPERTY_HINT_ARRAY_TYPE, "StringName"), "set_terrain_ids", "get_terrain_ids");
}
