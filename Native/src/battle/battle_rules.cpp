#include "battle_rules.h"

#include "battle_types.h"

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

bool validate_rules(const Rules &p_rules, std::string *r_error) {
	if (p_rules.ticks_per_second < 1) {
		return fail("rules ticks_per_second must be at least 1, got " + std::to_string(p_rules.ticks_per_second), r_error);
	}
	for (int multiplier : p_rules.cost_multipliers_pct) {
		if (multiplier < 1) {
			return fail("rules cost_multipliers_pct must be positive, got " + std::to_string(multiplier), r_error);
		}
	}
	if (p_rules.star_multiplier_pct < 1 || p_rules.counter_bonus_pct < 0) {
		return fail("rules star_multiplier_pct must be positive and counter_bonus_pct not negative", r_error);
	}
	if (p_rules.move_ticks_per_cell < 1 || p_rules.charge_ticks_per_cell < 1) {
		return fail("rules move_ticks_per_cell and charge_ticks_per_cell must be at least 1", r_error);
	}
	if (p_rules.time_limit_ticks < 1 || p_rules.repath_ticks < 1 || p_rules.target_lost_ticks < 0) {
		return fail("rules time_limit_ticks and repath_ticks must be at least 1, target_lost_ticks not negative", r_error);
	}
	if (p_rules.hold_line_max_ticks < 0 || p_rules.hold_line_grace_ticks < 0) {
		return fail("rules hold_line ticks must not be negative", r_error);
	}
	if (p_rules.max_units_per_side < 1 || p_rules.max_units_per_side > BOARD_COLS * SIDE_RANKS) {
		return fail("rules max_units_per_side must be 1.." + std::to_string(BOARD_COLS * SIDE_RANKS) + ", got " + std::to_string(p_rules.max_units_per_side), r_error);
	}
	return true;
}

} // namespace battle
