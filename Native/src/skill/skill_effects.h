#pragma once

// Skill and passive effect handlers, looked up by id (`effect.damage`, ...).
// A skill applies up to three in order when it resolves; a passive applies
// one when it fires. Add one by writing an apply function and listing it in
// the table in skill_effects.cpp. See Docs/systems/skill.md.

#include "skill_types.h"

#include <string>
#include <vector>

namespace battle {

class BattleSim;

// What a passive's trigger knows; modifier effects write into it.
struct PassiveContext {
	// The other unit of the trigger (the attacker, the charger, the blocked
	// archer), or NO_UNIT.
	int source = NO_UNIT;
	// The unit hit by the trigger's attack (charge victims).
	int victim = NO_UNIT;
	// The cell the trigger happened at (a charger's stopping cell).
	Cell cell;
	int cause = 0;
	// Cells run before a charge impact.
	int cells_run = 0;
	// Modifiers for the attack being made.
	bool is_crit = false;
	int increase_pct = 0;
};

struct EffectContext {
	BattleSim *sim = nullptr;
	int caster = NO_UNIT;
	// The skill or passive id, for damage events.
	std::string source_id;
	// The skill_resolved or passive_triggered event.
	int cause = 0;
	Cell anchor;
	const std::vector<Cell> *cells = nullptr;
	// Set for passives, nullptr for skills.
	PassiveContext *passive = nullptr;
};

using ApplyEffectFn = void (*)(EffectContext &p_context, const EffectDef &p_effect);

struct EffectHandler {
	const char *id;
	ApplyEffectFn apply;
};

// nullptr when the id is not registered.
const EffectHandler *find_effect_handler(const std::string &p_id);

// The units an effect acts on, by its target: enemies in the cells, the
// caster, or the passive's source. Only living units.
std::vector<int> get_effect_targets(const EffectContext &p_context, const EffectDef &p_effect);
// The effect's count at the caster's star (star3_count at 3 stars).
int get_effect_count(const EffectContext &p_context, const EffectDef &p_effect);
// A damage coefficient: skills scale by star (Rules::star_skill_pct),
// passives do not.
int get_effect_coefficient(const EffectContext &p_context, const EffectDef &p_effect);

// Dedicated handlers too special for the generic blocks (skill_effects_special.cpp).
void apply_charge_column(EffectContext &p_context, const EffectDef &p_effect);
void apply_arrow_volley(EffectContext &p_context, const EffectDef &p_effect);

} // namespace battle
