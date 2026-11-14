// BattleSim: what one unit does in a tick (targeting, attacking, moving).
// The tick loop and setup are in battle_sim.cpp.

#include "battle_sim.h"

#include "battle_damage.h"
#include "battle_openings.h"
#include "battle_shapes.h"
#include "battle_targeting.h"

#include "skill/skill_cast.h"
#include "skill/skill_charge.h"
#include "skill/skill_passives.h"
#include "skill/skill_statuses.h"

#include <algorithm>

namespace battle {

namespace {

AttackKind get_attack_kind(const ClassDef &p_def) {
	if (p_def.damage_kind == DamageKind::MAGIC) {
		return AttackKind::MAGIC;
	}
	return p_def.is_ranged ? AttackKind::RANGED : AttackKind::MELEE;
}

bool is_counter(const ClassDef &p_attacker, const ClassDef &p_victim) {
	return std::find(p_attacker.counter_ids.begin(), p_attacker.counter_ids.end(), p_victim.id) != p_attacker.counter_ids.end();
}

} // namespace

void BattleSim::act(int p_unit) {
	UnitState &unit = units[p_unit];
	if (!unit.is_alive) {
		return;
	}
	const int charge_full = get_attack_charge_full(rules);
	unit.attack_charge = std::min(unit.attack_charge + get_class_def(unit).attacks_per_100s, charge_full);
	// A stunned unit keeps its Khí and does nothing else.
	if (has_status(unit, StatusKind::STUN) || run_cast_action(*this, p_unit)) {
		return;
	}
	if (unit.skills.charge.is_active && unit.skills.charge.is_skill) {
		advance_charge(*this, p_unit);
		return;
	}

	const OpeningHandler *opening = classes[unit.class_index].opening;
	if (unit.is_opening_active && opening != nullptr) {
		if (opening->run(*this, p_unit) == OpeningResult::ACTED) {
			return;
		}
		deactivate_opening(p_unit);
	}
	act_normally(p_unit);
}

void BattleSim::act_normally(int p_unit) {
	update_target(p_unit);
	const UnitState &unit = units[p_unit];
	if (unit.target == NO_UNIT || is_moving(unit)) {
		return;
	}
	if (!attack_if_ready(p_unit)) {
		move_toward_target(p_unit);
	}
}

void BattleSim::update_target(int p_unit) {
	UnitState &unit = units[p_unit];
	if (unit.target != NO_UNIT && !units[unit.target].is_alive) {
		unit.target = NO_UNIT;
	}
	// Taunt overrides every targeting rule.
	const int taunter = get_taunt_source(*this, unit);
	if (taunter != NO_UNIT) {
		if (unit.target != taunter) {
			set_target(p_unit, taunter);
		}
		unit.has_seen_target_in_range = unit.has_seen_target_in_range || is_in_range(unit, units[taunter]);
		return;
	}
	if (unit.target != NO_UNIT && is_in_range(unit, units[unit.target])) {
		unit.has_seen_target_in_range = true;
		unit.target_out_of_range_ticks = 0;
		return;
	}
	const TargetingHandler *targeting = classes[unit.class_index].targeting;
	// Never ignore an enemy in range for one out of reach.
	if (has_enemy_in_range(unit)) {
		set_target(p_unit, targeting->pick(*this, unit, TargetPool::IN_RANGE));
		return;
	}
	// The lost-target count starts only once the target was in range.
	if (unit.target != NO_UNIT && (!unit.has_seen_target_in_range || ++unit.target_out_of_range_ticks <= rules.target_lost_ticks)) {
		return;
	}
	set_target(p_unit, targeting->pick(*this, unit, TargetPool::ALL));
}

void BattleSim::set_target(int p_unit, int p_target) {
	UnitState &unit = units[p_unit];
	unit.target = p_target;
	unit.target_out_of_range_ticks = 0;
	unit.no_path_ticks = 0;
	unit.has_seen_target_in_range = p_target != NO_UNIT && is_in_range(unit, units[p_target]);
}

bool BattleSim::attack_if_ready(int p_unit) {
	UnitState &unit = units[p_unit];
	const int charge_full = get_attack_charge_full(rules);
	const TargetingHandler *targeting = classes[unit.class_index].targeting;
	if (targeting->reevaluates_on_attack && unit.attack_charge >= charge_full && has_enemy_in_range(unit) && get_taunt_source(*this, unit) == NO_UNIT) {
		set_target(p_unit, targeting->pick(*this, unit, TargetPool::IN_RANGE));
	}
	if (unit.target == NO_UNIT || !is_in_range(unit, units[unit.target])) {
		return false;
	}
	if (unit.attack_charge >= charge_full) {
		unit.attack_charge -= charge_full;
		perform_attack(p_unit, unit.target, 0);
	}
	return true;
}

void BattleSim::move_toward_target(int p_unit) {
	UnitState &unit = units[p_unit];
	Cell step;
	if (find_step_toward(p_unit, unit.target, &step)) {
		unit.no_path_ticks = 0;
		start_move(p_unit, step, rules.move_ticks_per_cell, MoveKind::WALK, 0);
		return;
	}
	if (++unit.no_path_ticks < rules.repath_ticks) {
		return;
	}
	unit.no_path_ticks = 0;
	const int reachable = pick_nearest_reachable_enemy(p_unit);
	if (reachable != NO_UNIT) {
		set_target(p_unit, reachable);
	}
}

bool BattleSim::find_step_toward(int p_unit, int p_target, Cell *r_step) const {
	const UnitState &unit = units[p_unit];
	PathQuery query;
	query.start = unit.cell;
	query.target = units[p_target].cell;
	query.range_cells = get_class_def(unit).range_cells;
	query.side = unit.side;
	return find_first_step(board, query, r_step);
}

int BattleSim::pick_nearest_reachable_enemy(int p_unit) const {
	const UnitState &unit = units[p_unit];
	int best = NO_UNIT;
	for (const UnitState &candidate : units) {
		Cell step;
		if (!candidate.is_alive || candidate.side == unit.side || !find_step_toward(p_unit, candidate.index, &step)) {
			continue;
		}
		const int distance = get_distance_cells(unit.cell, candidate.cell);
		const int best_distance = best == NO_UNIT ? 0 : get_distance_cells(unit.cell, units[best].cell);
		if (best == NO_UNIT || distance < best_distance || (distance == best_distance && is_preferred_candidate(unit, candidate, units[best]))) {
			best = candidate.index;
		}
	}
	return best;
}

int BattleSim::perform_attack(int p_unit, int p_target, int p_cause, int p_increase_pct) {
	const UnitState &attacker = units[p_unit];
	const RegisteredClass &attacker_class = classes[attacker.class_index];
	BattleEvent event;
	event.type = EventType::UNIT_ATTACKED;
	event.cause = p_cause;
	event.unit = p_unit;
	event.target = p_target;
	event.attack_kind = get_attack_kind(attacker_class.def);
	event.to = units[p_target].cell;
	const int attack_event = emit_event(event);

	// Fired before the damage so a modifier (a crit) applies to this attack.
	PassiveContext landed;
	landed.source = p_target;
	landed.victim = p_target;
	landed.cell = units[p_target].cell;
	landed.cause = attack_event;
	fire_passive(*this, p_unit, PassiveTrigger::BASIC_ATTACK_LANDED, landed);

	std::vector<Hit> hits;
	attacker_class.shape->collect_hits(*this, attacker, p_target, &hits);
	for (const Hit &hit : hits) {
		if (!units[p_unit].is_alive) {
			break;
		}
		apply_hit(p_unit, hit.victim, hit.blocked_by, attack_event, landed.is_crit, p_increase_pct + landed.increase_pct);
		if (hit.blocked_by != NO_UNIT) {
			PassiveContext blocked;
			blocked.source = p_unit;
			blocked.cell = units[hit.blocked_by].cell;
			blocked.cause = attack_event;
			fire_passive(*this, hit.blocked_by, PassiveTrigger::ARROW_BLOCKED, blocked);
		}
	}
	// Once per attack, even when it hit several units or was blocked.
	add_qi(*this, p_unit, rules.qi_per_attack, attack_event);
	return attack_event;
}

void BattleSim::apply_hit(int p_attacker, int p_victim, int p_blocked_by, int p_attack_event, bool p_is_crit, int p_increase_pct) {
	const ClassDef &attacker_class = get_class_def(units[p_attacker]);
	DamageSpec spec;
	spec.source = p_attacker;
	spec.victim = p_victim;
	spec.kind = attacker_class.damage_kind;
	spec.is_crit = p_is_crit;
	spec.increase_pct = p_increase_pct;
	spec.blocked_by = p_blocked_by;
	spec.cause = p_attack_event;
	spec.is_melee_attack = get_attack_kind(attacker_class) == AttackKind::MELEE;
	deal_damage(spec);
}

int BattleSim::deal_damage(const DamageSpec &p_spec) {
	UnitState &victim = units[p_spec.victim];
	if (!victim.is_alive) {
		return 0;
	}
	const UnitState &source = units[p_spec.source];
	const ClassDef &source_class = get_class_def(source);
	const ClassDef &victim_class = get_class_def(victim);
	DamageRequest request;
	request.attack = source.attack;
	request.coefficient_pct = p_spec.coefficient_pct;
	request.kind = p_spec.kind;
	request.is_counter = is_counter(source_class, victim_class);
	request.counter_bonus_pct = rules.counter_bonus_pct;
	request.is_crit = p_spec.is_crit;
	request.crit_multiplier_pct = rules.crit_multiplier_pct;
	request.increase_pct = p_spec.increase_pct;
	request.decrease_pct = get_status_amount(victim, StatusKind::GUARD);
	request.armor = victim_class.armor;
	request.magic_resist = victim_class.magic_resist;
	request.armor_break_pct = get_status_amount(victim, StatusKind::ARMOR_BREAK);
	const DamageResult result = compute_damage(request);
	victim.hp = std::max(victim.hp - result.amount, 0);

	BattleEvent event;
	event.type = EventType::DAMAGE_DEALT;
	event.cause = p_spec.cause;
	event.source = p_spec.source;
	event.target = p_spec.victim;
	event.amount = result.amount;
	event.hp_after = victim.hp;
	event.is_counter = result.is_counter;
	event.is_crit = result.is_crit;
	event.blocked_by = p_spec.blocked_by;
	event.skill_id = p_spec.skill_id;
	const int damage_event = emit_event(event);
	if (victim.hp == 0) {
		kill(p_spec.victim, p_spec.source, damage_event);
	} else {
		react_to_damage(p_spec, damage_event);
	}
	return damage_event;
}

// Khí and passives of a victim that survived a hit.
void BattleSim::react_to_damage(const DamageSpec &p_spec, int p_damage_event) {
	if (units[p_spec.source].side != units[p_spec.victim].side) {
		add_qi(*this, p_spec.victim, rules.qi_per_hit_taken, p_damage_event);
	}
	PassiveContext context;
	context.source = p_spec.source;
	context.victim = p_spec.victim;
	context.cell = units[p_spec.source].cell;
	context.cause = p_damage_event;
	fire_passive(*this, p_spec.victim, PassiveTrigger::DAMAGED, context);
	if (p_spec.is_melee_attack) {
		fire_passive(*this, p_spec.victim, PassiveTrigger::MELEE_HIT_TAKEN, context);
	}
}

bool BattleSim::knock_back(int p_unit, const Cell &p_to, int p_cause) {
	const UnitState &unit = units[p_unit];
	const ClassDef &unit_class = get_class_def(unit);
	if (!unit.is_alive || unit_class.immune_to_knockback || unit_class.stops_charge || !board.is_free(p_to)) {
		return false;
	}
	start_move(p_unit, p_to, rules.charge_ticks_per_cell, MoveKind::KNOCKBACK, p_cause);
	return true;
}

void BattleSim::kill(int p_victim, int p_killer, int p_damage_event) {
	UnitState &victim = units[p_victim];
	victim.is_alive = false;
	victim.move_end_tick = 0;
	victim.target = NO_UNIT;
	// Nothing of a dead unit resolves later: no cast, charge or status.
	const int qi = victim.skills.qi;
	const int qi_max = victim.skills.qi_max;
	victim.skills = UnitSkillState();
	victim.skills.qi = qi;
	victim.skills.qi_max = qi_max;
	board.remove(victim.cell);
	BattleEvent event;
	event.type = EventType::UNIT_DIED;
	event.cause = p_damage_event;
	event.unit = p_victim;
	event.killer = p_killer;
	emit_event(event);
	end_taunts_from(*this, p_victim);
}

int BattleSim::start_move(int p_unit, const Cell &p_to, int p_duration_ticks, MoveKind p_kind, int p_cause) {
	UnitState &unit = units[p_unit];
	BattleEvent event;
	event.type = EventType::UNIT_MOVED;
	event.cause = p_cause;
	event.unit = p_unit;
	event.from = unit.cell;
	event.to = p_to;
	event.duration_ticks = p_duration_ticks;
	event.move_kind = p_kind;
	board.remove(unit.cell);
	board.place(p_to, p_unit);
	unit.cell = p_to;
	unit.move_end_tick = tick + p_duration_ticks;
	return emit_event(event);
}

bool BattleSim::is_in_range(const UnitState &p_unit, const UnitState &p_target) const {
	return get_distance_cells(p_unit.cell, p_target.cell) <= get_class_def(p_unit).range_cells;
}

bool BattleSim::has_enemy_in_range(const UnitState &p_unit) const {
	for (const UnitState &other : units) {
		if (other.is_alive && other.side != p_unit.side && is_in_range(p_unit, other)) {
			return true;
		}
	}
	return false;
}

bool BattleSim::is_targeted_by_enemy(int p_unit) const {
	for (const UnitState &other : units) {
		if (other.is_alive && other.side != units[p_unit].side && other.target == p_unit) {
			return true;
		}
	}
	return false;
}

bool BattleSim::is_moving(const UnitState &p_unit) const {
	return tick < p_unit.move_end_tick;
}

int BattleSim::get_move_ticks_left(const UnitState &p_unit) const {
	return is_moving(p_unit) ? p_unit.move_end_tick - tick : 0;
}

void BattleSim::deactivate_opening(int p_unit) {
	units[p_unit].is_opening_active = false;
}

} // namespace battle
