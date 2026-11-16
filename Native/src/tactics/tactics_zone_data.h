#pragma once

#include "tactics_types.h"

#include "battle/bridge_strings.h"

#include <godot_cpp/classes/resource.hpp>

#include <string>

namespace godot {

// A timed cell effect (`zone.wind`, `zone.fire`): its effect handler id
// (tactics_zones.cpp) and amount. One file per zone in Data/Tactics/Zones/;
// skill effects and passives reference the zone they create.
class TacticsZoneData : public Resource {
	GDCLASS(TacticsZoneData, Resource)

	StringName id;
	String name_key;
	StringName effect;
	int amount = 0;

protected:
	static void _bind_methods();

public:
	// False and r_error when the effect handler is unknown.
	bool to_zone_def(tactics::ZoneDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_effect(const StringName &p_value) { effect = p_value; }
	StringName get_effect() const { return effect; }
	void set_amount(int64_t p_value) { amount = clamp_to_int(p_value); }
	int get_amount() const { return amount; }
};

} // namespace godot
