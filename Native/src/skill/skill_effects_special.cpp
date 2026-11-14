// Effect handlers too special for the generic blocks: the cavalry's
// re-charge has to run over many ticks through the shared charge runner,
// and the arrow volley re-aims every arrow at the column's new front. See
// Docs/systems/skill.md ("Dedicated handlers").

#include "skill_charge.h"
#include "skill_effects.h"
#include "skill_selectors.h"

#include "battle/battle_sim.h"
#include "battle/battle_targeting.h"

namespace battle {

// value: impact coefficient; count: columns (star3_count at 3 stars);
// duration_ticks: the repositioning move.
void apply_charge_column(EffectContext &p_context, const EffectDef &p_effect) {
	ChargeState charge;
	charge.is_skill = true;
	charge.coefficient_pct = p_effect.value;
	charge.columns_left = get_effect_count(p_context, p_effect) - 1;
	charge.reposition_ticks = p_effect.duration_ticks;
	charge.cause = p_context.cause;
	charge.target = get_frontmost_enemy_in_column(*p_context.sim, p_context.sim->get_units()[p_context.caster].side, p_context.anchor.col);
	begin_charge(*p_context.sim, p_context.caster, charge);
	reposition_for_column(*p_context.sim, p_context.caster, p_context.anchor.col, p_effect.duration_ticks, p_context.cause);
}

// count arrows of value percent, one by one, each at the frontmost living
// enemy of the anchor's column; once it is empty, at the nearest enemy.
// Arrows fall from above, so arrow block does not apply.
void apply_arrow_volley(EffectContext &p_context, const EffectDef &p_effect) {
	BattleSim &sim = *p_context.sim;
	const int arrows = get_effect_count(p_context, p_effect);
	for (int arrow = 0; arrow < arrows; arrow++) {
		const UnitState &caster = sim.get_units()[p_context.caster];
		if (!caster.is_alive) {
			return;
		}
		int target = get_frontmost_enemy_in_column(sim, caster.side, p_context.anchor.col);
		if (target == NO_UNIT) {
			target = pick_nearest_enemy(sim, caster, TargetPool::ALL);
		}
		if (target == NO_UNIT) {
			return;
		}
		DamageSpec spec;
		spec.source = p_context.caster;
		spec.victim = target;
		spec.coefficient_pct = get_effect_coefficient(p_context, p_effect);
		spec.kind = p_effect.damage_kind;
		spec.skill_id = p_context.source_id;
		spec.cause = p_context.cause;
		sim.deal_damage(spec);
	}
}

} // namespace battle
