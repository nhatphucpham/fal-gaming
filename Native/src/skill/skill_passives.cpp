#include "skill_passives.h"

#include "battle/battle_board.h"
#include "battle/battle_sim.h"

namespace battle {

namespace {

struct TriggerEntry {
	const char *id;
	PassiveTrigger trigger;
};

const TriggerEntry TRIGGERS[] = {
	{ "trigger.basic_attack_landed", PassiveTrigger::BASIC_ATTACK_LANDED },
	{ "trigger.damaged", PassiveTrigger::DAMAGED },
	{ "trigger.arrow_blocked", PassiveTrigger::ARROW_BLOCKED },
	{ "trigger.melee_hit_taken", PassiveTrigger::MELEE_HIT_TAKEN },
	{ "trigger.charge_impact_incoming", PassiveTrigger::CHARGE_IMPACT_INCOMING },
	{ "trigger.charge_impact", PassiveTrigger::CHARGE_IMPACT },
	{ "trigger.element_reaction", PassiveTrigger::ELEMENT_REACTION },
};

bool check_within_radius(const BattleSim &, const UnitState &p_owner, const PassiveDef &p_passive, const PassiveContext &p_context) {
	return get_distance_cells(p_owner.cell, p_context.cell) <= p_passive.condition_radius;
}

// The owner is the victim, or the trigger's cell is within its range.
bool check_victim_or_in_range(const BattleSim &p_sim, const UnitState &p_owner, const PassiveDef &, const PassiveContext &p_context) {
	return p_context.victim == p_owner.index || get_distance_cells(p_owner.cell, p_context.cell) <= p_sim.get_class_def(p_owner).range_cells;
}

const ConditionHandler CONDITION_HANDLERS[] = {
	{ "condition.within_radius", check_within_radius },
	{ "condition.victim_or_in_range", check_victim_or_in_range },
};

uint64_t source_bit(int p_source) {
	return p_source >= 0 && p_source < 64 ? (uint64_t(1) << p_source) : 0;
}

} // namespace

const ConditionHandler *find_condition_handler(const std::string &p_id) {
	for (const ConditionHandler &handler : CONDITION_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

bool find_passive_trigger(const std::string &p_id, PassiveTrigger *r_trigger) {
	for (const TriggerEntry &entry : TRIGGERS) {
		if (p_id == entry.id) {
			*r_trigger = entry.trigger;
			return true;
		}
	}
	return false;
}

void fire_passive(BattleSim &p_sim, int p_unit, PassiveTrigger p_trigger, PassiveContext &p_context) {
	const UnitState &owner = p_sim.get_units()[p_unit];
	if (!owner.is_alive || !owner.skills.has_passive) {
		return;
	}
	const PassiveDef &passive = p_sim.get_passive(p_unit);
	if (passive.trigger != p_trigger || (passive.condition != nullptr && !passive.condition->check(p_sim, owner, passive, p_context))) {
		return;
	}
	PassiveCounters &counters = p_sim.edit_skill_state(p_unit).passive;
	const uint64_t bit = source_bit(p_context.source);
	if ((passive.once_per_source && (counters.used_sources & bit) != 0) || (passive.limit_per_battle > 0 && counters.fire_count >= passive.limit_per_battle)) {
		return;
	}
	counters.trigger_count++;
	if (counters.trigger_count % passive.every_nth != 0) {
		return;
	}
	counters.fire_count++;
	if (passive.once_per_source) {
		counters.used_sources |= bit;
	}

	BattleEvent event;
	event.type = EventType::PASSIVE_TRIGGERED;
	event.unit = p_unit;
	event.skill_id = passive.id;
	event.cause = p_context.cause;
	EffectContext effect_context;
	effect_context.sim = &p_sim;
	effect_context.caster = p_unit;
	effect_context.source_id = passive.id;
	effect_context.cause = p_sim.emit_event(event);
	effect_context.anchor = owner.cell;
	effect_context.passive = &p_context;
	passive.effect.handler->apply(effect_context, passive.effect);
}

} // namespace battle
