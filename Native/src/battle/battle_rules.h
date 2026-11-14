#pragma once

// Battle tuning as a plain struct, filled from BattleRulesData by the bridge,
// and the integer stat derivation that uses it.

#include <array>
#include <string>

namespace battle {

constexpr int MIN_COST = 1;
constexpr int MAX_COST = 5;
constexpr int MIN_STAR = 1;
constexpr int MAX_STAR = 3;
// Class attack rates are given per 100 seconds (0.6 attacks/s is 60).
constexpr int ATTACK_RATE_PERIOD_SECONDS = 100;

struct Rules {
	int ticks_per_second = 20;
	std::array<int, MAX_COST> cost_multipliers_pct = { 100, 125, 155, 190, 230 };
	int star_multiplier_pct = 180;
	int counter_bonus_pct = 30;
	int move_ticks_per_cell = 10;
	int charge_ticks_per_cell = 7;
	int time_limit_ticks = 900;
	int target_lost_ticks = 40;
	int repath_ticks = 20;
	int hold_line_max_ticks = 200;
	int hold_line_grace_ticks = 20;
	int max_units_per_side = 10;
};

// Accumulator value at which a unit attacks: it gains attacks_per_100s per
// tick, so one attack every 100 s at a rate of 1.
int get_attack_charge_full(const Rules &p_rules);

// Scales a base hp or attack by cost, then once per star above 1. Truncates
// after each step.
int derive_scaled_stat(int p_base, int p_cost, int p_star, const Rules &p_rules);

// Returns false and sets r_error when a value is out of range.
bool validate_rules(const Rules &p_rules, std::string *r_error);

} // namespace battle
