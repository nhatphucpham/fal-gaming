#include "tactics_combat.h"

#include "tactics_keywords.h"
#include "tactics_sim.h"
#include "tactics_skills.h"
#include "tactics_zones.h"

#include "battle/battle_damage.h"

namespace tactics {

namespace {

constexpr int BASIC_COEFFICIENT_PCT = 100;

void gather_hit_modifiers(const TacticsSim &p_sim, const HitContext &p_context, HitModifiers &r_mods) {
	for (const KeywordDef *keyword : p_sim.collect_keywords(p_context.attacker)) {
		if (keyword->handler->modify_outgoing != nullptr) {
			keyword->handler->modify_outgoing(*keyword, p_context, r_mods);
		}
	}
	const UnitState &defender = p_sim.get_units()[p_context.defender];
	for (const Cell &direction : DIRECTIONS) {
		const Cell next = defender.cell + direction;
		if (!p_sim.is_on_map(next)) {
			continue;
		}
		const int ally = p_sim.get_occupant(next);
		if (ally == NO_UNIT || p_sim.get_units()[ally].side != defender.side) {
			continue;
		}
		for (const KeywordDef *keyword : p_sim.collect_keywords(ally)) {
			if (keyword->handler->modify_incoming_as_ally != nullptr) {
				keyword->handler->modify_incoming_as_ally(*keyword, p_context, r_mods);
			}
		}
	}
	const TerrainDef &terrain = p_sim.get_terrain(defender.cell);
	r_mods.taken_pct += terrain.damage_taken_pct;
	if (p_context.kind == AttackKind::RANGED) {
		r_mods.taken_pct += terrain.ranged_damage_taken_pct;
	}
	apply_zones_to_hit(p_sim, p_context, r_mods);
	r_mods.taken_pct -= r_mods.cover_pct;
}

bool has_first_strike(const TacticsSim &p_sim, int p_defender, AttackKind p_incoming) {
	for (const KeywordDef *keyword : p_sim.collect_keywords(p_defender)) {
		if (keyword->handler->strikes_first != nullptr && keyword->handler->strikes_first(*keyword, p_incoming)) {
			return true;
		}
	}
	return false;
}

// Lands up to p_hits hits while the target lives; returns how many landed.
int land_hits(TacticsSim &p_sim, int p_source, int p_target, int p_hits, int p_damage, bool p_is_counter, int p_cause) {
	int landed = 0;
	for (int hit = 0; hit < p_hits && p_sim.get_units()[p_target].is_alive && p_sim.get_units()[p_source].is_alive; hit++) {
		p_sim.deal_damage(p_source, p_target, p_damage, std::string(), p_is_counter, p_cause);
		landed++;
	}
	return landed;
}

} // namespace

AttackKind get_attack_kind(const UnitState &p_unit) {
	return p_unit.def.is_ranged ? AttackKind::RANGED : AttackKind::MELEE;
}

bool is_in_range_from(const TacticsSim &p_sim, int p_attacker, const Cell &p_from, const Cell &p_target) {
	const Stats stats = p_sim.get_stats_at(p_attacker, p_from);
	const int distance = get_manhattan(p_from, p_target);
	return distance >= stats.min_range_cells && distance <= stats.max_range_cells;
}

bool can_attack(const TacticsSim &p_sim, int p_attacker, int p_target) {
	const UnitState &attacker = p_sim.get_units()[p_attacker];
	const UnitState &target = p_sim.get_units()[p_target];
	return attacker.is_alive && target.is_alive && attacker.side != target.side && is_in_range_from(p_sim, p_attacker, attacker.cell, target.cell);
}

int compute_hit_damage(const TacticsSim &p_sim, int p_attacker, int p_defender, AttackKind p_kind, bool p_is_counter, int p_coefficient_pct, DamageKind p_damage_kind) {
	HitContext context;
	context.sim = &p_sim;
	context.attacker = p_attacker;
	context.defender = p_defender;
	context.kind = p_kind;
	context.is_counter = p_is_counter;
	HitModifiers mods;
	gather_hit_modifiers(p_sim, context, mods);
	const Stats attacker = p_sim.get_stats(p_attacker);
	const Stats defender = p_sim.get_stats(p_defender);
	battle::DamageRequest request;
	request.attack = attacker.attack;
	request.coefficient_pct = p_coefficient_pct;
	request.kind = p_damage_kind;
	request.increase_pct = mods.increase_pct + (mods.taken_pct > 0 ? mods.taken_pct : 0);
	request.decrease_pct = mods.taken_pct < 0 ? -mods.taken_pct : 0;
	request.armor = defender.armor;
	request.magic_resist = defender.magic_resist;
	request.armor_break_pct = mods.armor_break_pct;
	return battle::compute_damage(request).amount;
}

namespace {

// Who strikes, whether a counter comes and the damage of each hit, fixed
// before the first hit.
EngagementResult plan_engagement(const TacticsSim &p_sim, int p_attacker, int p_defender) {
	const UnitState &attacker = p_sim.get_units()[p_attacker];
	const UnitState &defender = p_sim.get_units()[p_defender];
	EngagementResult result;
	result.is_valid = true;
	result.attacker = p_attacker;
	result.defender = p_defender;
	result.kind = get_attack_kind(attacker);
	result.can_counter = can_attack(p_sim, p_defender, p_attacker);
	result.is_first_strike = result.can_counter && has_first_strike(p_sim, p_defender, result.kind);
	result.attacker_damage_per_hit = compute_hit_damage(p_sim, p_attacker, p_defender, result.kind, false, BASIC_COEFFICIENT_PCT, attacker.def.damage_kind);
	if (result.can_counter) {
		result.defender_damage_per_hit = compute_hit_damage(p_sim, p_defender, p_attacker, get_attack_kind(defender), true, BASIC_COEFFICIENT_PCT, defender.def.damage_kind);
	}
	return result;
}

void land_engagement_hits(TacticsSim &p_sim, EngagementResult &r_result) {
	const int hits = p_sim.get_rules().hits_per_engagement;
	const int attacker = r_result.attacker;
	const int defender = r_result.defender;
	if (r_result.is_first_strike) {
		r_result.defender_hits = land_hits(p_sim, defender, attacker, hits, r_result.defender_damage_per_hit, true, r_result.event_id);
		r_result.attacker_hits = land_hits(p_sim, attacker, defender, hits, r_result.attacker_damage_per_hit, false, r_result.event_id);
	} else {
		r_result.attacker_hits = land_hits(p_sim, attacker, defender, hits, r_result.attacker_damage_per_hit, false, r_result.event_id);
		if (r_result.can_counter) {
			r_result.defender_hits = land_hits(p_sim, defender, attacker, hits, r_result.defender_damage_per_hit, true, r_result.event_id);
		}
	}
	r_result.attacker_hp_after = p_sim.get_units()[attacker].hp;
	r_result.defender_hp_after = p_sim.get_units()[defender].hp;
	r_result.is_attacker_dead = !p_sim.get_units()[attacker].is_alive;
	r_result.is_defender_dead = !p_sim.get_units()[defender].is_alive;
}

// What the engagement leaves behind: the attacked soldier remembers its
// attacker, leaders gain charge, and engagement_ended closes it.
void close_engagement(TacticsSim &p_sim, const EngagementResult &p_result) {
	if (!p_sim.is_leader(p_result.defender)) {
		UnitState &soldier = p_sim.edit_unit(p_result.defender);
		soldier.was_attacked_since_move = true;
		soldier.last_attacker = p_result.attacker;
	}
	for (int unit : { p_result.attacker, p_result.defender }) {
		if (p_sim.is_leader(unit) && p_sim.get_units()[unit].is_alive) {
			trigger_skill_charge(p_sim, unit, ChargeTrigger::ENGAGEMENT, 1, p_result.event_id);
		}
	}
	Event ended;
	ended.type = EventType::ENGAGEMENT_ENDED;
	ended.unit = p_result.attacker;
	ended.target = p_result.defender;
	ended.amount = p_result.attacker_hits * p_result.attacker_damage_per_hit;
	ended.value = p_result.defender_hits * p_result.defender_damage_per_hit;
	ended.cause = p_result.event_id;
	p_sim.emit(ended);
}

} // namespace

EngagementResult resolve_engagement(TacticsSim &p_sim, int p_attacker, int p_defender, int p_cause) {
	EngagementResult result = plan_engagement(p_sim, p_attacker, p_defender);
	Event started;
	started.type = EventType::ENGAGEMENT_STARTED;
	started.unit = p_attacker;
	started.target = p_defender;
	started.kind = result.kind == AttackKind::RANGED ? "ranged" : "melee";
	started.is_first_strike = result.is_first_strike;
	started.cause = p_cause;
	result.event_id = p_sim.emit(started);
	land_engagement_hits(p_sim, result);
	// A death that ended the battle ends the events too: battle_ended is last.
	if (!p_sim.is_finished()) {
		close_engagement(p_sim, result);
	}
	return result;
}

} // namespace tactics
