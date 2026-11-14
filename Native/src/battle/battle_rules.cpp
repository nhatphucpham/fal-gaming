#include "battle_rules.h"

#include "battle_types.h"

#include <cstdint>

namespace battle {

namespace {

constexpr int PERCENT = 100;

bool fail(const std::string &p_message, std::string *r_error) {
	if (r_error != nullptr) {
		*r_error = p_message;
	}
	return false;
}

} // namespace

int get_attack_charge_full(const Rules &p_rules) {
	return ATTACK_RATE_PERIOD_SECONDS * p_rules.ticks_per_second;
}

int derive_scaled_stat(int p_base, int p_cost, int p_star, const Rules &p_rules) {
	int64_t value = static_cast<int64_t>(p_base) * p_rules.cost_multipliers_pct[p_cost - MIN_COST] / PERCENT;
	for (int star = MIN_STAR; star < p_star; star++) {
		value = value * p_rules.star_multiplier_pct / PERCENT;
	}
	return static_cast<int>(value);
}

int scale_skill_coefficient(int p_coefficient_pct, int p_star, const Rules &p_rules) {
	const int star = p_star < MIN_STAR ? MIN_STAR : (p_star > MAX_STAR ? MAX_STAR : p_star);
	return static_cast<int>(static_cast<int64_t>(p_coefficient_pct) * p_rules.star_skill_pct[star - MIN_STAR] / PERCENT);
}

bool validate_rules(const Rules &p_rules, std::string *r_error) {
	const auto check = [&](const char *p_field, int p_value, int p_min, int p_max) {
		if (p_value >= p_min && p_value <= p_max) {
			return true;
		}
		return fail(std::string("rules ") + p_field + " must be " + std::to_string(p_min) + ".." + std::to_string(p_max) + ", got " + std::to_string(p_value), r_error);
	};
	for (int multiplier : p_rules.cost_multipliers_pct) {
		if (!check("cost_multipliers_pct", multiplier, 1, MAX_COST_MULTIPLIER_PCT)) {
			return false;
		}
	}
	for (int pct : p_rules.star_skill_pct) {
		if (!check("star_skill_pct", pct, 1, MAX_STAR_SKILL_PCT)) {
			return false;
		}
	}
	// Tick values stay far below INT_MAX, so tick + duration cannot overflow.
	return check("ticks_per_second", p_rules.ticks_per_second, 1, MAX_TICKS_PER_SECOND)
			&& check("star_multiplier_pct", p_rules.star_multiplier_pct, 1, MAX_STAR_MULTIPLIER_PCT)
			&& check("counter_bonus_pct", p_rules.counter_bonus_pct, 0, MAX_COUNTER_BONUS_PCT)
			&& check("move_ticks_per_cell", p_rules.move_ticks_per_cell, 1, MAX_MOVE_TICKS)
			&& check("charge_ticks_per_cell", p_rules.charge_ticks_per_cell, 1, MAX_MOVE_TICKS)
			&& check("time_limit_ticks", p_rules.time_limit_ticks, 1, MAX_TIME_LIMIT_TICKS)
			&& check("target_lost_ticks", p_rules.target_lost_ticks, 0, MAX_RULE_TICKS)
			&& check("repath_ticks", p_rules.repath_ticks, 1, MAX_RULE_TICKS)
			&& check("hold_line_max_ticks", p_rules.hold_line_max_ticks, 0, MAX_RULE_TICKS)
			&& check("hold_line_grace_ticks", p_rules.hold_line_grace_ticks, 0, MAX_RULE_TICKS)
			&& check("max_units_per_side", p_rules.max_units_per_side, 1, BOARD_COLS * SIDE_RANKS)
			&& check("qi_per_attack", p_rules.qi_per_attack, 0, MAX_QI_GAIN)
			&& check("qi_per_hit_taken", p_rules.qi_per_hit_taken, 0, MAX_QI_GAIN)
			&& check("cast_ticks", p_rules.cast_ticks, 1, MAX_CAST_TICKS)
			&& check("crit_multiplier_pct", p_rules.crit_multiplier_pct, MIN_CRIT_MULTIPLIER_PCT, MAX_CRIT_MULTIPLIER_PCT);
}

} // namespace battle
