#include "formation_data.h"

using namespace godot;

bool FormationData::to_formation_def(rules::FormationDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->pattern.handler_id = to_std_string(pattern);
	r_def->pattern.anchor_col = anchor_col;
	r_def->pattern.anchor_rank = anchor_rank;
	r_def->pattern.is_mirrored = is_mirrored;
	r_def->pattern.needs_distinct_classes = needs_distinct_classes;
	r_def->pattern.middle_slot = middle_slot;
	r_def->pattern.slots.clear();
	for (int64_t index = 0; index < cells.size(); index++) {
		const Vector2i offset = cells[index];
		formation::Slot slot;
		slot.dcol = offset.x;
		slot.drank = offset.y;
		r_def->pattern.slots.push_back(slot);
	}
	r_def->slot_class_ids.clear();
	for (int64_t index = 0; index < slot_classes.size(); index++) {
		r_def->slot_class_ids.push_back(to_std_string(slot_classes[index]));
	}
	if (!copy_modifier_defs(modifiers, &r_def->modifiers)) {
		*r_error = r_def->id + " has an empty modifier entry";
		return false;
	}
	return true;
}

void FormationData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(FormationData, id);
	BATTLE_BIND_ACCESSORS(FormationData, name_key);
	BATTLE_BIND_ACCESSORS(FormationData, description_key);
	BATTLE_BIND_ACCESSORS(FormationData, pattern);
	BATTLE_BIND_ACCESSORS(FormationData, cells);
	BATTLE_BIND_ACCESSORS(FormationData, slot_classes);
	BATTLE_BIND_ACCESSORS(FormationData, anchor_col);
	BATTLE_BIND_ACCESSORS(FormationData, anchor_rank);
	BATTLE_BIND_ACCESSORS(FormationData, is_mirrored);
	BATTLE_BIND_ACCESSORS(FormationData, needs_distinct_classes);
	BATTLE_BIND_ACCESSORS(FormationData, middle_slot);
	BATTLE_BIND_ACCESSORS(FormationData, color);
	BATTLE_BIND_ACCESSORS(FormationData, modifiers);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_GROUP("Pattern", "");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "pattern"), "set_pattern", "get_pattern");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_cells", "get_cells");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "slot_classes"), "set_slot_classes", "get_slot_classes");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "anchor_col", PROPERTY_HINT_RANGE, "0,7,1"), "set_anchor_col", "get_anchor_col");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "anchor_rank", PROPERTY_HINT_RANGE, "0,4,1"), "set_anchor_rank", "get_anchor_rank");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_mirrored"), "set_is_mirrored", "get_is_mirrored");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "needs_distinct_classes"), "set_needs_distinct_classes", "get_needs_distinct_classes");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "middle_slot", PROPERTY_HINT_RANGE, "-1,5,1"), "set_middle_slot", "get_middle_slot");
	ADD_GROUP("Look", "");
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, "color"), "set_color", "get_color");
	ADD_GROUP("Effect", "");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "modifiers", PROPERTY_HINT_ARRAY_TYPE, "ModifierData"), "set_modifiers", "get_modifiers");
}
