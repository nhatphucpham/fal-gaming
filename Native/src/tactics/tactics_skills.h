#pragma once

// Leader skills: charge mechanisms (`charge.turns`, ...), targeting
// (`skill_target.single`, `skill_target.area`, `skill_target.chain`) and
// effects (`skill_effect.damage`, ...), each a registry looked up by id. A
// skill is never cast on its own: the player (or the AI) uses it once its
// charge reaches the threshold, which resets the charge.

#include "tactics_state.h"

#include <string>
#include <vector>

namespace tactics {

class TacticsSim;

enum class ChargeTrigger {
	// The end of the leader's own phase; p_amount is 1 if it moved.
	PHASE_END = 0,
	ENGAGEMENT,
	// p_amount is the damage taken.
	DAMAGE_TAKEN,
	SOLDIER_LOST,
	// Moved or pushed off its cell.
	DISPLACED,
};

struct ChargeUpdate {
	int delta = 0;
	bool resets = false;
};

struct ChargeHandler {
	const char *id;
	ChargeUpdate (*update)(ChargeTrigger p_trigger, int p_amount);
};

// The cells and units a skill reaches, with each target's percent of the
// effect (chain falloff).
struct SkillSelection {
	Cell center;
	std::vector<Cell> cells;
	std::vector<int> targets;
	std::vector<int> target_pcts;
};

struct SkillTargetHandler {
	const char *id;
	// False with r_error when p_cell is not a valid target for the caster
	// standing on p_from (its own cell, or where the AI plans to stand).
	bool (*select)(const TacticsSim &p_sim, int p_caster, const Cell &p_from, const Cell &p_cell, SkillSelection &r_selection, std::string *r_error);
};

struct SkillEffectHandler {
	const char *id;
	// The effect reads SkillEffectDef::zone, so it must have one.
	bool needs_zone;
	// True when the effect works against the caster's enemies (damage, an
	// enemy zone); a skill with no such effect is cast on the caster's cell.
	bool (*affects_enemies)(const SkillEffectDef &p_effect);
	void (*apply)(TacticsSim &p_sim, int p_caster, const SkillEffectDef &p_effect, const SkillSelection &p_selection, int p_cause, std::vector<SkillTargetResult> &r_results);
};

// nullptr when the id is not registered.
const ChargeHandler *find_charge_handler(const std::string &p_id);
const SkillTargetHandler *find_skill_target_handler(const std::string &p_id);
const SkillEffectHandler *find_skill_effect_handler(const std::string &p_id);

// Feeds one trigger to the leader's charge mechanism.
void trigger_skill_charge(TacticsSim &p_sim, int p_leader, ChargeTrigger p_trigger, int p_amount, int p_cause);
bool is_skill_ready(const UnitState &p_leader);
// No effect of the skill works against enemies: it helps the caster's side
// (rally_banner), so the AI casts it on its own cell.
bool is_skill_for_own_side(const SkillDef &p_skill);
// Casts the leader's skill at p_cell (charge checked by the caller); emits
// skill_used, the effects' events and skill_resolved. Returns the
// skill_used event id, or 0 with r_error when p_cell is not a valid target.
int cast_skill(TacticsSim &p_sim, int p_caster, const Cell &p_cell, int p_cause, std::string *r_error);

} // namespace tactics
