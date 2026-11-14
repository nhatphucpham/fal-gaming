#pragma once

// Damage pipeline: base, counter, crit, bonus groups, mitigation. Integer math;
// every multiplication happens before the divisions, so it truncates once.

#include "battle_types.h"

namespace battle {

constexpr int BASIC_ATTACK_COEFFICIENT_PCT = 100;
constexpr int CRIT_MULTIPLIER_PCT = 150;
constexpr int MIN_DAMAGE = 1;
// Inputs are clamped to these before the math (see battle_damage.cpp for
// the overflow bound). Validated classes and rules stay well inside them.
constexpr int MAX_DAMAGE_ATTACK = 1000000;
constexpr int MAX_COEFFICIENT_PCT = 1000;
constexpr int MAX_DAMAGE_COUNTER_BONUS_PCT = 100;
constexpr int MAX_INCREASE_PCT = 200;
constexpr int MAX_DECREASE_PCT = 100;
constexpr int MAX_DAMAGE_MITIGATION = 10000;

// Open for later milestones: skills set the coefficient, formations and
// elements fill the bonus groups.
struct DamageRequest {
	int attack = 0;
	int coefficient_pct = BASIC_ATTACK_COEFFICIENT_PCT;
	DamageKind kind = DamageKind::PHYSICAL;
	bool is_counter = false;
	int counter_bonus_pct = 0;
	bool is_crit = false;
	int increase_pct = 0;
	int decrease_pct = 0;
	int armor = 0;
	int magic_resist = 0;
};

struct DamageResult {
	int amount = MIN_DAMAGE;
	bool is_counter = false;
	bool is_crit = false;
};

// Damage dealt by one hit, at least MIN_DAMAGE.
DamageResult compute_damage(const DamageRequest &p_request);

} // namespace battle
