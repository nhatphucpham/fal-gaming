#pragma once

#include "battle_types.h"

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

// The event's `type` as it appears in dictionaries and logs.
StringName get_event_type_name(battle::EventType p_type);
StringName get_end_reason_name(battle::EndReason p_reason);
// {id, tick, type, cause} plus the payload keys of the event's type.
Dictionary event_to_dictionary(const battle::BattleEvent &p_event);

} // namespace godot
