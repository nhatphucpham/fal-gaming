#pragma once

#include "tactics_types.h"

#include "battle/bridge_strings.h"

#include <godot_cpp/classes/resource.hpp>

namespace godot {

// Every tuning number of the tactics turn loop. The project uses one file,
// Data/Tactics/Rules/tactics_rules.tres; tests may duplicate it and change
// values. Read by TacticsBattle.setup().
class TacticsRulesData : public Resource {
	GDCLASS(TacticsRulesData, Resource)

	tactics::Rules rules;

protected:
	static void _bind_methods();

public:
	tactics::Rules to_rules() const { return rules; }

	void set_hits_per_engagement(int64_t p_value) { rules.hits_per_engagement = clamp_to_int(p_value); }
	int get_hits_per_engagement() const { return rules.hits_per_engagement; }
	void set_anticipation_shift_cells(int64_t p_value) { rules.anticipation_shift_cells = clamp_to_int(p_value); }
	int get_anticipation_shift_cells() const { return rules.anticipation_shift_cells; }
	void set_help_radius_cells(int64_t p_value) { rules.help_radius_cells = clamp_to_int(p_value); }
	int get_help_radius_cells() const { return rules.help_radius_cells; }
	void set_max_leaders_per_side(int64_t p_value) { rules.max_leaders_per_side = clamp_to_int(p_value); }
	int get_max_leaders_per_side() const { return rules.max_leaders_per_side; }
	void set_max_rounds(int64_t p_value) { rules.max_rounds = clamp_to_int(p_value); }
	int get_max_rounds() const { return rules.max_rounds; }
	void set_leash_follow_cells(int64_t p_value) { rules.leash_follow_cells = clamp_to_int(p_value); }
	int get_leash_follow_cells() const { return rules.leash_follow_cells; }
	void set_leash_vanguard_cells(int64_t p_value) { rules.leash_vanguard_cells = clamp_to_int(p_value); }
	int get_leash_vanguard_cells() const { return rules.leash_vanguard_cells; }
	void set_leash_flank_cells(int64_t p_value) { rules.leash_flank_cells = clamp_to_int(p_value); }
	int get_leash_flank_cells() const { return rules.leash_flank_cells; }
	void set_retreat_hp_pct(int64_t p_value) { rules.retreat_hp_pct = clamp_to_int(p_value); }
	int get_retreat_hp_pct() const { return rules.retreat_hp_pct; }
	void set_shield_leader_hp_pct(int64_t p_value) { rules.shield_leader_hp_pct = clamp_to_int(p_value); }
	int get_shield_leader_hp_pct() const { return rules.shield_leader_hp_pct; }
	void set_free_threat_limit(int64_t p_value) { rules.free_threat_limit = clamp_to_int(p_value); }
	int get_free_threat_limit() const { return rules.free_threat_limit; }
	void set_role_slot_weight(int64_t p_value) { rules.role_slot_weight = clamp_to_int(p_value); }
	int get_role_slot_weight() const { return rules.role_slot_weight; }
	void set_ai_strength_radius_cells(int64_t p_value) { rules.ai_strength_radius_cells = clamp_to_int(p_value); }
	int get_ai_strength_radius_cells() const { return rules.ai_strength_radius_cells; }
	void set_ai_attack_ratio_pct(int64_t p_value) { rules.ai_attack_ratio_pct = clamp_to_int(p_value); }
	int get_ai_attack_ratio_pct() const { return rules.ai_attack_ratio_pct; }
	void set_ai_advance_ratio_pct(int64_t p_value) { rules.ai_advance_ratio_pct = clamp_to_int(p_value); }
	int get_ai_advance_ratio_pct() const { return rules.ai_advance_ratio_pct; }
	void set_ai_hold_radius_cells(int64_t p_value) { rules.ai_hold_radius_cells = clamp_to_int(p_value); }
	int get_ai_hold_radius_cells() const { return rules.ai_hold_radius_cells; }
};

} // namespace godot
