#pragma once

// Passive triggers and conditions, and firing a unit's passive. The battle
// calls fire_passive() at fixed points (an attack landing, damage, a blocked
// arrow, a melee hit, a charge about to hit, a charge impact). Triggers and
// conditions are looked up by id (`trigger.melee_hit_taken`,
// `condition.within_radius`) when the passive is registered.

#include "skill_effects.h"
#include "skill_types.h"

#include <string>

namespace battle {

class BattleSim;
struct UnitState;

using CheckConditionFn = bool (*)(const BattleSim &p_sim, const UnitState &p_owner, const PassiveDef &p_passive, const PassiveContext &p_context);

struct ConditionHandler {
	const char *id;
	CheckConditionFn check;
};

const ConditionHandler *find_condition_handler(const std::string &p_id);
// False when the id is not registered.
bool find_passive_trigger(const std::string &p_id, PassiveTrigger *r_trigger);

// Fires p_unit's passive if it listens to p_trigger and its condition,
// counter and limits allow: emits passive_triggered and applies the effect
// (which may write modifiers into p_context).
void fire_passive(BattleSim &p_sim, int p_unit, PassiveTrigger p_trigger, PassiveContext &p_context);

} // namespace battle
