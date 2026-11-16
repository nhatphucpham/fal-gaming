#pragma once

#include "tactics_types.h"

#include "battle/bridge_strings.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <string>

namespace godot {

// A unit keyword (`keyword.charge`, ...): its id names the handler in
// tactics_keywords.cpp, the numbers are here. One file per keyword in
// Data/Tactics/Keywords/; troop and leader data list theirs.
class TacticsKeywordData : public Resource {
	GDCLASS(TacticsKeywordData, Resource)

	StringName id;
	String name_key;
	String description_key;
	int amount = 0;
	int min_cells = 0;
	TypedArray<StringName> terrain_ids;

protected:
	static void _bind_methods();

public:
	// False and r_error when no handler has this id.
	bool to_keyword_def(tactics::KeywordDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_amount(int64_t p_value) { amount = clamp_to_int(p_value); }
	int get_amount() const { return amount; }
	void set_min_cells(int64_t p_value) { min_cells = clamp_to_int(p_value); }
	int get_min_cells() const { return min_cells; }
	void set_terrain_ids(const TypedArray<StringName> &p_value) { terrain_ids = p_value; }
	TypedArray<StringName> get_terrain_ids() const { return terrain_ids; }
};

} // namespace godot
