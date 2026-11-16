#include "tactics_rules_data.h"

using namespace godot;

void TacticsRulesData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsRulesData, hits_per_engagement);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, anticipation_shift_cells);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, help_radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, max_leaders_per_side);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, max_rounds);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, leash_follow_cells);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, leash_vanguard_cells);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, leash_flank_cells);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, retreat_hp_pct);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, shield_leader_hp_pct);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, free_threat_limit);
	BATTLE_BIND_ACCESSORS(TacticsRulesData, role_slot_weight);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "hits_per_engagement", PROPERTY_HINT_RANGE, "1,10,1"), "set_hits_per_engagement", "get_hits_per_engagement");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "anticipation_shift_cells", PROPERTY_HINT_RANGE, "0,20,1"), "set_anticipation_shift_cells", "get_anticipation_shift_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "help_radius_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_help_radius_cells", "get_help_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_leaders_per_side", PROPERTY_HINT_RANGE, "1,8,1"), "set_max_leaders_per_side", "get_max_leaders_per_side");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_rounds", PROPERTY_HINT_RANGE, "1,1000,1"), "set_max_rounds", "get_max_rounds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "leash_follow_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_leash_follow_cells", "get_leash_follow_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "leash_vanguard_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_leash_vanguard_cells", "get_leash_vanguard_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "leash_flank_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_leash_flank_cells", "get_leash_flank_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "retreat_hp_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_retreat_hp_pct", "get_retreat_hp_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "shield_leader_hp_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_shield_leader_hp_pct", "get_shield_leader_hp_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "free_threat_limit", PROPERTY_HINT_RANGE, "1,64,1"), "set_free_threat_limit", "get_free_threat_limit");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "role_slot_weight", PROPERTY_HINT_RANGE, "0,100,1"), "set_role_slot_weight", "get_role_slot_weight");
}
