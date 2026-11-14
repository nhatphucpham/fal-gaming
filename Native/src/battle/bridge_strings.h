#pragma once

// Small helpers shared by the battle bridge classes.

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <climits>
#include <cstdint>
#include <string>

// Binds the set_<name>/get_<name> pair of a property.
#define BATTLE_BIND_ACCESSORS(m_class, m_name) \
	godot::ClassDB::bind_method(godot::D_METHOD("set_" #m_name, #m_name), &m_class::set_##m_name); \
	godot::ClassDB::bind_method(godot::D_METHOD("get_" #m_name), &m_class::get_##m_name)

namespace godot {

// GDScript ints are 64-bit. Saturating keeps an out-of-range value out of
// range, so validation rejects it instead of seeing a wrapped one.
inline int clamp_to_int(int64_t p_value) {
	return p_value < INT_MIN ? INT_MIN : (p_value > INT_MAX ? INT_MAX : static_cast<int>(p_value));
}

inline std::string to_std_string(const String &p_text) {
	return std::string(p_text.utf8().get_data());
}

inline std::string to_std_string(const StringName &p_text) {
	return to_std_string(String(p_text));
}

inline String to_godot_string(const std::string &p_text) {
	return String::utf8(p_text.c_str());
}

} // namespace godot
