#include "battle_rules_data.h"

#include "bridge_strings.h"

#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void BattleRulesData::set_cost_multipliers_pct(const PackedInt32Array &p_values) {
	ERR_FAIL_COND_MSG(p_values.size() != battle::MAX_COST, vformat("Battle: cost_multipliers_pct needs %d values, got %d", battle::MAX_COST, p_values.size()));
	for (int index = 0; index < battle::MAX_COST; index++) {
		rules.cost_multipliers_pct[index] = p_values[index];
	}
}

PackedInt32Array BattleRulesData::get_cost_multipliers_pct() const {
	PackedInt32Array values;
	for (int value : rules.cost_multipliers_pct) {
		values.push_back(value);
	}
	return values;
}

void BattleRulesData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_attack_charge_full"), &BattleRulesData::get_attack_charge_full);
	BATTLE_BIND_ACCESSORS(BattleRulesData, ticks_per_second);
	BATTLE_BIND_ACCESSORS(BattleRulesData, cost_multipliers_pct);
	BATTLE_BIND_ACCESSORS(BattleRulesData, star_multiplier_pct);
	BATTLE_BIND_ACCESSORS(BattleRulesData, counter_bonus_pct);
	BATTLE_BIND_ACCESSORS(BattleRulesData, move_ticks_per_cell);
	BATTLE_BIND_ACCESSORS(BattleRulesData, charge_ticks_per_cell);
	BATTLE_BIND_ACCESSORS(BattleRulesData, time_limit_ticks);
	BATTLE_BIND_ACCESSORS(BattleRulesData, target_lost_ticks);
	BATTLE_BIND_ACCESSORS(BattleRulesData, repath_ticks);
	BATTLE_BIND_ACCESSORS(BattleRulesData, hold_line_max_ticks);
	BATTLE_BIND_ACCESSORS(BattleRulesData, hold_line_grace_ticks);
	BATTLE_BIND_ACCESSORS(BattleRulesData, max_units_per_side);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "ticks_per_second", PROPERTY_HINT_RANGE, "1,240,1"), "set_ticks_per_second", "get_ticks_per_second");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "cost_multipliers_pct"), "set_cost_multipliers_pct", "get_cost_multipliers_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "star_multiplier_pct", PROPERTY_HINT_RANGE, "1,300,1"), "set_star_multiplier_pct", "get_star_multiplier_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "counter_bonus_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_counter_bonus_pct", "get_counter_bonus_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "move_ticks_per_cell", PROPERTY_HINT_RANGE, "1,1000,1"), "set_move_ticks_per_cell", "get_move_ticks_per_cell");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "charge_ticks_per_cell", PROPERTY_HINT_RANGE, "1,1000,1"), "set_charge_ticks_per_cell", "get_charge_ticks_per_cell");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "time_limit_ticks", PROPERTY_HINT_RANGE, "1,100000,1"), "set_time_limit_ticks", "get_time_limit_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "target_lost_ticks", PROPERTY_HINT_RANGE, "0,10000,1"), "set_target_lost_ticks", "get_target_lost_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "repath_ticks", PROPERTY_HINT_RANGE, "1,10000,1"), "set_repath_ticks", "get_repath_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "hold_line_max_ticks", PROPERTY_HINT_RANGE, "0,10000,1"), "set_hold_line_max_ticks", "get_hold_line_max_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "hold_line_grace_ticks", PROPERTY_HINT_RANGE, "0,10000,1"), "set_hold_line_grace_ticks", "get_hold_line_grace_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_units_per_side", PROPERTY_HINT_RANGE, "1,28,1"), "set_max_units_per_side", "get_max_units_per_side");
}
