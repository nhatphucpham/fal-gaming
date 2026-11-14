#pragma once

#include "battle_rules.h"
#include "bridge_strings.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

namespace godot {

// Every battle tuning number, in ticks and percent. The project uses one
// file, Data/Rules/battle_rules.tres; tests may duplicate it and change
// values. Read by Battle.set_rules().
class BattleRulesData : public Resource {
	GDCLASS(BattleRulesData, Resource)

	battle::Rules rules;

protected:
	static void _bind_methods();

public:
	// The simulation's copy of the values.
	battle::Rules to_rules() const { return rules; }
	// Derived, not stored: 100 * ticks_per_second (see battle_rules.h).
	int get_attack_charge_full() const { return battle::get_attack_charge_full(rules); }

	void set_ticks_per_second(int64_t p_value) { rules.ticks_per_second = clamp_to_int(p_value); }
	int get_ticks_per_second() const { return rules.ticks_per_second; }
	// Exactly five values, for costs 1..5; other sizes are rejected.
	void set_cost_multipliers_pct(const PackedInt64Array &p_values);
	PackedInt64Array get_cost_multipliers_pct() const;
	void set_star_multiplier_pct(int64_t p_value) { rules.star_multiplier_pct = clamp_to_int(p_value); }
	int get_star_multiplier_pct() const { return rules.star_multiplier_pct; }
	void set_counter_bonus_pct(int64_t p_value) { rules.counter_bonus_pct = clamp_to_int(p_value); }
	int get_counter_bonus_pct() const { return rules.counter_bonus_pct; }
	void set_move_ticks_per_cell(int64_t p_value) { rules.move_ticks_per_cell = clamp_to_int(p_value); }
	int get_move_ticks_per_cell() const { return rules.move_ticks_per_cell; }
	void set_charge_ticks_per_cell(int64_t p_value) { rules.charge_ticks_per_cell = clamp_to_int(p_value); }
	int get_charge_ticks_per_cell() const { return rules.charge_ticks_per_cell; }
	void set_time_limit_ticks(int64_t p_value) { rules.time_limit_ticks = clamp_to_int(p_value); }
	int get_time_limit_ticks() const { return rules.time_limit_ticks; }
	void set_target_lost_ticks(int64_t p_value) { rules.target_lost_ticks = clamp_to_int(p_value); }
	int get_target_lost_ticks() const { return rules.target_lost_ticks; }
	void set_repath_ticks(int64_t p_value) { rules.repath_ticks = clamp_to_int(p_value); }
	int get_repath_ticks() const { return rules.repath_ticks; }
	void set_hold_line_max_ticks(int64_t p_value) { rules.hold_line_max_ticks = clamp_to_int(p_value); }
	int get_hold_line_max_ticks() const { return rules.hold_line_max_ticks; }
	void set_hold_line_grace_ticks(int64_t p_value) { rules.hold_line_grace_ticks = clamp_to_int(p_value); }
	int get_hold_line_grace_ticks() const { return rules.hold_line_grace_ticks; }
	void set_max_units_per_side(int64_t p_value) { rules.max_units_per_side = clamp_to_int(p_value); }
	int get_max_units_per_side() const { return rules.max_units_per_side; }
	void set_qi_per_attack(int64_t p_value) { rules.qi_per_attack = clamp_to_int(p_value); }
	int get_qi_per_attack() const { return rules.qi_per_attack; }
	void set_qi_per_hit_taken(int64_t p_value) { rules.qi_per_hit_taken = clamp_to_int(p_value); }
	int get_qi_per_hit_taken() const { return rules.qi_per_hit_taken; }
	void set_cast_ticks(int64_t p_value) { rules.cast_ticks = clamp_to_int(p_value); }
	int get_cast_ticks() const { return rules.cast_ticks; }
	// Exactly three values, for stars 1..3; other sizes are rejected.
	void set_star_skill_pct(const PackedInt64Array &p_values);
	PackedInt64Array get_star_skill_pct() const;
	void set_crit_multiplier_pct(int64_t p_value) { rules.crit_multiplier_pct = clamp_to_int(p_value); }
	int get_crit_multiplier_pct() const { return rules.crit_multiplier_pct; }
};

} // namespace godot
