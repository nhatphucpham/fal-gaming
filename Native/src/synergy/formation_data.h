#pragma once

#include "modifier_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// A formation (trận đồ): a shape on the 7x4 half in local coordinates and
// its level-1 modifiers. One file per formation in Data/Formations/.
// `cells` holds each slot's offset from the anchor as (dcol, drank), drank
// growing toward the back; `slot_classes` the class each slot needs (empty
// for any). Schema in Docs/systems/formation.md.
class FormationData : public Resource {
	GDCLASS(FormationData, Resource)

	StringName id;
	String name_key;
	String description_key;
	StringName pattern = "pattern.shape";
	TypedArray<Vector2i> cells;
	PackedStringArray slot_classes;
	int anchor_col = 0;
	int anchor_rank = 0;
	bool is_mirrored = false;
	bool needs_distinct_classes = false;
	int middle_slot = -1;
	// The outline colour on the board.
	Color color = Color(1, 0.85, 0.4);
	TypedArray<ModifierData> modifiers;

protected:
	static void _bind_methods();

public:
	bool to_formation_def(rules::FormationDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_pattern(const StringName &p_value) { pattern = p_value; }
	StringName get_pattern() const { return pattern; }
	void set_cells(const TypedArray<Vector2i> &p_value) { cells = p_value; }
	TypedArray<Vector2i> get_cells() const { return cells; }
	void set_slot_classes(const PackedStringArray &p_value) { slot_classes = p_value; }
	PackedStringArray get_slot_classes() const { return slot_classes; }
	void set_anchor_col(int64_t p_value) { anchor_col = clamp_to_int(p_value); }
	int get_anchor_col() const { return anchor_col; }
	void set_anchor_rank(int64_t p_value) { anchor_rank = clamp_to_int(p_value); }
	int get_anchor_rank() const { return anchor_rank; }
	void set_is_mirrored(bool p_value) { is_mirrored = p_value; }
	bool get_is_mirrored() const { return is_mirrored; }
	void set_needs_distinct_classes(bool p_value) { needs_distinct_classes = p_value; }
	bool get_needs_distinct_classes() const { return needs_distinct_classes; }
	void set_middle_slot(int64_t p_value) { middle_slot = clamp_to_int(p_value); }
	int get_middle_slot() const { return middle_slot; }
	void set_color(const Color &p_value) { color = p_value; }
	Color get_color() const { return color; }
	void set_modifiers(const TypedArray<ModifierData> &p_value) { modifiers = p_value; }
	TypedArray<ModifierData> get_modifiers() const { return modifiers; }
};

} // namespace godot
