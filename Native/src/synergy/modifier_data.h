#pragma once

#include "battle/bridge_strings.h"

#include "rules/synergy_types.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <vector>

namespace godot {

// One battle modifier (`mod.*`) or matching rule (`rule.*`) of a milestone
// tier, formation or Hợp Lực tier, written as a sub-resource. What value,
// count, ticks and param mean depends on the handler; scope says who gets
// it (Docs/systems/synergy.md).
class ModifierData : public Resource {
	GDCLASS(ModifierData, Resource)

	StringName handler;
	StringName scope = "scope.counted";
	PackedInt32Array slots;
	int value = 0;
	int count = 0;
	int ticks = 0;
	StringName param;
	bool per_formation = false;

protected:
	static void _bind_methods();

public:
	rules::ModifierDef to_modifier_def() const;

	void set_handler(const StringName &p_value) { handler = p_value; }
	StringName get_handler() const { return handler; }
	void set_scope(const StringName &p_value) { scope = p_value; }
	StringName get_scope() const { return scope; }
	void set_slots(const PackedInt32Array &p_value) { slots = p_value; }
	PackedInt32Array get_slots() const { return slots; }
	void set_value(int64_t p_value) { value = clamp_to_int(p_value); }
	int get_value() const { return value; }
	void set_count(int64_t p_value) { count = clamp_to_int(p_value); }
	int get_count() const { return count; }
	void set_ticks(int64_t p_value) { ticks = clamp_to_int(p_value); }
	int get_ticks() const { return ticks; }
	void set_param(const StringName &p_value) { param = p_value; }
	StringName get_param() const { return param; }
	void set_per_formation(bool p_value) { per_formation = p_value; }
	bool get_per_formation() const { return per_formation; }
};

// Copies modifier resources into plain structs; false on an empty entry.
bool copy_modifier_defs(const TypedArray<ModifierData> &p_modifiers, std::vector<rules::ModifierDef> *r_defs);

} // namespace godot
