#pragma once

#include "synergy_tier_data.h"

#include <godot_cpp/classes/resource.hpp>

namespace godot {

// Hợp Lực, the shared meter: its team-wide tiers, plus how formation levels
// scale (Data/Rules/hop_luc.tres). Schema in Docs/systems/synergy.md.
class HopLucData : public Resource {
	GDCLASS(HopLucData, Resource)

	TypedArray<SynergyTierData> tiers;
	int formation_level_step_pct = rules::DEFAULT_LEVEL_STEP_PCT;
	int max_formation_level = rules::DEFAULT_MAX_FORMATION_LEVEL;

protected:
	static void _bind_methods();

public:
	bool to_hop_luc_def(rules::HopLucDef *r_def, std::string *r_error) const;

	void set_tiers(const TypedArray<SynergyTierData> &p_value) { tiers = p_value; }
	TypedArray<SynergyTierData> get_tiers() const { return tiers; }
	void set_formation_level_step_pct(int64_t p_value) { formation_level_step_pct = clamp_to_int(p_value); }
	int get_formation_level_step_pct() const { return formation_level_step_pct; }
	void set_max_formation_level(int64_t p_value) { max_formation_level = clamp_to_int(p_value); }
	int get_max_formation_level() const { return max_formation_level; }
};

} // namespace godot
