#pragma once

// Direct combat: per-hit damage through the battle damage pipeline
// (battle::compute_damage) with terrain, keywords and zones, and the
// engagement (the attacker's hits, then the defender's counter).

#include "tactics_state.h"

namespace tactics {

class TacticsSim;

AttackKind get_attack_kind(const UnitState &p_unit);
// p_target stands within the attacker's range from p_from.
bool is_in_range_from(const TacticsSim &p_sim, int p_attacker, const Cell &p_from, const Cell &p_target);
bool can_attack(const TacticsSim &p_sim, int p_attacker, int p_target);
// One hit's damage with every modifier (at least 1). For SKILL hits,
// p_coefficient_pct and p_kind come from the skill effect.
int compute_hit_damage(const TacticsSim &p_sim, int p_attacker, int p_defender, AttackKind p_kind, bool p_is_counter, int p_coefficient_pct, DamageKind p_damage_kind);
// Resolves one engagement and emits its events. The caller checked range.
EngagementResult resolve_engagement(TacticsSim &p_sim, int p_attacker, int p_defender, int p_cause);

} // namespace tactics
