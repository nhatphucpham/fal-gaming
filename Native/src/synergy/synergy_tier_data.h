#pragma once

#include "modifier_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// One step of a milestone or of Hợp Lực: the count (or points) that turns
// it on, a one-line description key and its modifiers. A sub-resource of
// MilestoneData and HopLucData.
class SynergyTierData : public Resource {
	GDCLASS(SynergyTierData, Resource)

	int at = 1;
	String description_key;
	TypedArray<ModifierData> modifiers;

protected:
	static void _bind_methods();

public:
	// False on an empty modifier entry.
	bool to_tier_def(rules::TierDef *r_def) const;

	void set_at(int64_t p_value) { at = clamp_to_int(p_value); }
	int get_at() const { return at; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_modifiers(const TypedArray<ModifierData> &p_value) { modifiers = p_value; }
	TypedArray<ModifierData> get_modifiers() const { return modifiers; }
};

// Copies tier resources; false and r_error on an empty entry.
bool copy_tier_defs(const String &p_owner, const TypedArray<SynergyTierData> &p_tiers, std::vector<rules::TierDef> *r_defs, std::string *r_error);

} // namespace godot
