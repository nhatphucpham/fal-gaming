#include "tactics_combat.h"
#include "tactics_sim.h"
#include "tactics_skills.h"

// Skill effect handlers (`skill_effect.<name>`). Add one by writing its
// apply function and listing it in SKILL_EFFECT_HANDLERS.

namespace tactics {

namespace {

constexpr int PERCENT = 100;

// skill_effect.damage: one hit per target of coefficient_pct of the
// caster's attack (times the target's chain percent), mitigated by
// damage_kind and the target's terrain and zones.
void apply_damage(TacticsSim &p_sim, int p_caster, const SkillEffectDef &p_effect, const SkillSelection &p_selection, int p_cause, std::vector<SkillTargetResult> &r_results) {
	const std::string &skill_id = p_sim.get_units()[p_caster].def.skill.id;
	for (size_t index = 0; index < p_selection.targets.size(); index++) {
		const int target = p_selection.targets[index];
		if (!p_sim.get_units()[target].is_alive) {
			continue;
		}
		const int coefficient_pct = p_effect.coefficient_pct * p_selection.target_pcts[index] / PERCENT;
		const int amount = compute_hit_damage(p_sim, p_caster, target, AttackKind::SKILL, false, coefficient_pct, p_effect.damage_kind);
		p_sim.deal_damage(p_caster, target, amount, skill_id, false, p_cause);
		SkillTargetResult result;
		result.unit = target;
		result.amount = amount;
		result.hp_after = p_sim.get_units()[target].hp;
		result.is_dead = !p_sim.get_units()[target].is_alive;
		r_results.push_back(result);
	}
}

// skill_effect.squad_attack_buff: the caster's living soldiers deal
// amount_pct percent more for duration_rounds rounds.
void apply_squad_attack_buff(TacticsSim &p_sim, int p_caster, const SkillEffectDef &p_effect, const SkillSelection &p_selection, int p_cause, std::vector<SkillTargetResult> &r_results) {
	(void)p_selection;
	(void)r_results;
	const UnitState &caster = p_sim.get_units()[p_caster];
	for (int soldier : caster.soldiers) {
		if (!p_sim.get_units()[soldier].is_alive) {
			continue;
		}
		BuffState buff;
		buff.unit = soldier;
		buff.stat = StatKind::ATTACK_PCT;
		buff.amount = p_effect.amount_pct;
		buff.end_round = p_sim.get_round() + p_effect.duration_rounds;
		buff.source_id = caster.def.skill.id;
		p_sim.add_buff(buff, p_cause);
	}
}

// skill_effect.create_zone: the effect's zone on every selected cell for
// duration_rounds rounds.
void apply_create_zone(TacticsSim &p_sim, int p_caster, const SkillEffectDef &p_effect, const SkillSelection &p_selection, int p_cause, std::vector<SkillTargetResult> &r_results) {
	(void)r_results;
	ZoneState zone;
	zone.def = p_effect.zone;
	zone.side = p_sim.get_units()[p_caster].side;
	zone.source = p_caster;
	zone.cells = p_selection.cells;
	zone.end_round = p_sim.get_round() + p_effect.duration_rounds;
	p_sim.add_zone(zone, p_cause);
}

const SkillEffectHandler SKILL_EFFECT_HANDLERS[] = {
	{ "skill_effect.damage", false, apply_damage },
	{ "skill_effect.squad_attack_buff", false, apply_squad_attack_buff },
	{ "skill_effect.create_zone", true, apply_create_zone },
};

} // namespace

const SkillEffectHandler *find_skill_effect_handler(const std::string &p_id) {
	for (const SkillEffectHandler &handler : SKILL_EFFECT_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

} // namespace tactics
