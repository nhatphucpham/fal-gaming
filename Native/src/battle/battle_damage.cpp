#include "battle_damage.h"

namespace battle {

namespace {

constexpr int64_t PERCENT = 100;

} // namespace

DamageResult compute_damage(const DamageRequest &p_request) {
	const int64_t counter_pct = PERCENT + (p_request.is_counter ? p_request.counter_bonus_pct : 0);
	const int64_t crit_pct = p_request.is_crit ? CRIT_MULTIPLIER_PCT : PERCENT;
	const int64_t increase_pct = PERCENT + p_request.increase_pct;
	const int64_t decrease_pct = p_request.decrease_pct >= PERCENT ? 0 : PERCENT - p_request.decrease_pct;
	const int64_t mitigation = p_request.kind == DamageKind::MAGIC ? p_request.magic_resist : p_request.armor;

	// The order of the stages matches Docs/systems/battle.md; only the final
	// division truncates.
	int64_t numerator = static_cast<int64_t>(p_request.attack) * p_request.coefficient_pct;
	numerator *= counter_pct * crit_pct;
	numerator *= increase_pct * decrease_pct;
	numerator *= PERCENT;
	const int64_t denominator = PERCENT * PERCENT * PERCENT * PERCENT * PERCENT * (PERCENT + mitigation);

	DamageResult result;
	const int64_t amount = numerator / denominator;
	result.amount = amount < MIN_DAMAGE ? MIN_DAMAGE : static_cast<int>(amount);
	result.is_counter = p_request.is_counter;
	result.is_crit = p_request.is_crit;
	return result;
}

} // namespace battle
