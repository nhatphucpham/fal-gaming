#pragma once

#include "tactics_state.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// The event's `type` as it appears in dictionaries and logs.
StringName get_tactics_event_type_name(tactics::EventType p_type);
// {id, turn, round, type, cause} plus the payload keys of the event's type
// (Docs/systems/tactics.md).
Dictionary tactics_event_to_dictionary(const tactics::Event &p_event);
Vector2i to_vector2i(const tactics::Cell &p_cell);
// Read-only [Vector2i, ...].
Array tactics_cells_to_array(const std::vector<tactics::Cell> &p_cells);

} // namespace godot
