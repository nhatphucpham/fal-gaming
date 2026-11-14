#include "battle_damage.h"

namespace battle {

namespace {

constexpr int64_t PERCENT = 100;

int64_t clamp_value(int p_value, int p_max) {
	return p_value < 0 ? 0 : (p_value > p_max ? p_max : p_value);
}

} // namespace

DamageResult compute_damage(const DamageRequest &p_request) {
	const int64_t attack = clamp_value(p_request.attack, MAX_DAMAGE_ATTACK);
	const int64_t coefficient_pct = clamp_value(p_request.coefficient_pct, MAX_COEFFICIENT_PCT);
	const int64_t counter_pct = PERCENT + (p_request.is_counter ? clamp_value(p_request.counter_bonus_pct, MAX_DAMAGE_COUNTER_BONUS_PCT) : 0);
	const int64_t crit_pct = p_request.is_crit ? CRIT_MULTIPLIER_PCT : PERCENT;
	const int64_t increase_pct = PERCENT + clamp_value(p_request.increase_pct, MAX_INCREASE_PCT);
	const int64_t decrease_pct = PERCENT - clamp_value(p_request.decrease_pct, MAX_DECREASE_PCT);
	const int64_t mitigation = clamp_value(p_request.kind == DamageKind::MAGIC ? p_request.magic_resist : p_request.armor, MAX_DAMAGE_MITIGATION);

	// Stages in the order of Docs/systems/battle.md, all multiplications
	// first so only the final division truncates. The mitigation's * 100
	// cancels one / 100. Bound: 1e6 * 1000 * 200 * 150 * 300 * 100 = 9e17,
	// below INT64_MAX (about 9.2e18).
	int64_t numerator = attack * coefficient_pct;
	numerator *= counter_pct * crit_pct;
	numerator *= increase_pct * decrease_pct;
	const int64_t denominator = PERCENT * PERCENT * PERCENT * PERCENT * (PERCENT + mitigation);

	DamageResult result;
	const int64_t amount = numerator / denominator;
	result.amount = amount < MIN_DAMAGE ? MIN_DAMAGE : static_cast<int>(amount);
	result.is_counter = p_request.is_counter;
	result.is_crit = p_request.is_crit;
	return result;
}

} // namespace battle
