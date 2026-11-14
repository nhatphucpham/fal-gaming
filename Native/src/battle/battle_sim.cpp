#include "battle_sim.h"

#include "battle_openings.h"
#include "battle_shapes.h"
#include "battle_targeting.h"

#include "skill/skill_cast.h"
#include "skill/skill_statuses.h"
#include "skill/skill_validation.h"

#include <algorithm>
#include <cstdlib>

namespace battle {

namespace {

constexpr uint64_t FNV_OFFSET_BASIS = 14695981039346656037ULL;
constexpr uint64_t FNV_PRIME = 1099511628211ULL;
constexpr int64_t HP_SCORE_SCALE = 10000;

// Hashes the value as 8 little-endian bytes, so the result does not depend
// on the platform's byte order.
void hash_value(uint64_t *r_hash, int64_t p_value) {
	const uint64_t bits = static_cast<uint64_t>(p_value);
	for (int byte = 0; byte < 8; byte++) {
		*r_hash ^= (bits >> (byte * 8)) & 0xFFu;
		*r_hash *= FNV_PRIME;
	}
}

void hash_cells(uint64_t *r_hash, const std::vector<Cell> &p_cells) {
	hash_value(r_hash, static_cast<int64_t>(p_cells.size()));
	for (const Cell &cell : p_cells) {
		hash_value(r_hash, cell.col);
		hash_value(r_hash, cell.row);
	}
}

bool fail(const std::string &p_message, std::string *r_error) {
	if (r_error != nullptr) {
		*r_error = p_message;
	}
	return false;
}

bool validate_class(const ClassDef &p_def, std::string *r_error) {
	if (p_def.id.empty()) {
		return fail("class has an empty id", r_error);
	}
	const auto check = [&](const char *p_field, int p_value, int p_min, int p_max) {
		if (p_value >= p_min && p_value <= p_max) {
			return true;
		}
		return fail(p_def.id + " " + p_field + " must be " + std::to_string(p_min) + ".." + std::to_string(p_max) + ", got " + std::to_string(p_value), r_error);
	};
	return check("max_hp", p_def.max_hp, 1, MAX_CLASS_HP) && check("attack", p_def.attack, 0, MAX_CLASS_ATTACK)
			&& check("attacks_per_100s", p_def.attacks_per_100s, 1, MAX_CLASS_ATTACKS_PER_100S)
			&& check("range_cells", p_def.range_cells, 1, MAX_CLASS_RANGE_CELLS)
			&& check("armor", p_def.armor, 0, MAX_CLASS_MITIGATION) && check("magic_resist", p_def.magic_resist, 0, MAX_CLASS_MITIGATION);
}

} // namespace

bool BattleSim::set_rules(const Rules &p_rules, std::string *r_error) {
	if (!units.empty()) {
		return fail("rules cannot change after units were added", r_error);
	}
	if (!validate_rules(p_rules, r_error)) {
		return false;
	}
	rules = p_rules;
	has_rules = true;
	return true;
}

bool BattleSim::resolve_handlers(const ClassDef &p_def, RegisteredClass *r_class, std::string *r_error) const {
	r_class->def = p_def;
	r_class->targeting = find_targeting_handler(p_def.targeting_id);
	if (r_class->targeting == nullptr) {
		return fail(p_def.id + " has unknown targeting '" + p_def.targeting_id + "'", r_error);
	}
	r_class->shape = find_shape_handler(p_def.attack_shape_id);
	if (r_class->shape == nullptr) {
		return fail(p_def.id + " has unknown attack_shape '" + p_def.attack_shape_id + "'", r_error);
	}
	r_class->opening = nullptr;
	if (!p_def.opening_id.empty()) {
		r_class->opening = find_opening_handler(p_def.opening_id);
		if (r_class->opening == nullptr) {
			return fail(p_def.id + " has unknown opening '" + p_def.opening_id + "'", r_error);
		}
	}
	std::string skill_error;
	if (r_class->def.has_skill && !resolve_skill(&r_class->def.skill, &skill_error)) {
		return fail(p_def.id + " skill: " + skill_error, r_error);
	}
	if (r_class->def.has_passive && !resolve_passive(&r_class->def.passive, &skill_error)) {
		return fail(p_def.id + " passive: " + skill_error, r_error);
	}
	return true;
}

bool BattleSim::register_class(const ClassDef &p_def, std::string *r_error) {
	if (started) {
		return fail("cannot register " + p_def.id + " after the battle started", r_error);
	}
	RegisteredClass registered;
	if (!validate_class(p_def, r_error) || !resolve_handlers(p_def, &registered, r_error)) {
		return false;
	}
	const int existing = find_class_index(p_def.id);
	// Units copy stats and opening state from their class when added, so a
	// class in use must not change under them.
	for (const UnitState &unit : units) {
		if (unit.class_index == existing) {
			return fail("cannot replace " + p_def.id + ": unit " + std::to_string(unit.index) + " (" + unit.unit_id + ") uses it; clear() first", r_error);
		}
	}
	if (existing >= 0) {
		classes[existing] = registered;
	} else {
		classes.push_back(registered);
	}
	return true;
}

int BattleSim::find_class_index(const std::string &p_class_id) const {
	for (size_t index = 0; index < classes.size(); index++) {
		if (classes[index].def.id == p_class_id) {
			return static_cast<int>(index);
		}
	}
	return -1;
}

bool BattleSim::check_new_unit(int p_side, const UnitSpec &p_spec, int p_local_col, int p_local_rank, std::string *r_error) const {
	const std::string where = p_spec.unit_id + " at col " + std::to_string(p_local_col) + " rank " + std::to_string(p_local_rank);
	if (started) {
		return fail("cannot add " + where + " after the battle started", r_error);
	}
	if (!has_rules) {
		return fail("set the rules before adding " + where, r_error);
	}
	if (p_side != SIDE_A && p_side != SIDE_B) {
		return fail(where + " has invalid side " + std::to_string(p_side), r_error);
	}
	if (find_class_index(p_spec.class_id) < 0) {
		return fail(where + " has unregistered class '" + p_spec.class_id + "'", r_error);
	}
	if (p_spec.star < MIN_STAR || p_spec.star > MAX_STAR || p_spec.cost < MIN_COST || p_spec.cost > MAX_COST) {
		return fail(where + " needs star 1..3 and cost 1..5, got star " + std::to_string(p_spec.star) + " cost " + std::to_string(p_spec.cost), r_error);
	}
	if (!is_local_cell_valid(p_local_col, p_local_rank) || !board.is_free(local_to_global(p_side, p_local_col, p_local_rank))) {
		return fail(where + " is off the board or the cell is taken", r_error);
	}
	const int side_count = static_cast<int>(std::count_if(units.begin(), units.end(), [&](const UnitState &p_unit) { return p_unit.side == p_side; }));
	if (side_count >= rules.max_units_per_side) {
		return fail(where + ": side " + std::to_string(p_side) + " already has " + std::to_string(side_count) + " units", r_error);
	}
	return true;
}

int BattleSim::add_unit(int p_side, const UnitSpec &p_spec, int p_local_col, int p_local_rank, std::string *r_error) {
	if (!check_new_unit(p_side, p_spec, p_local_col, p_local_rank, r_error)) {
		return NO_UNIT;
	}
	const int class_index = find_class_index(p_spec.class_id);
	const RegisteredClass &unit_class = classes[class_index];
	UnitState unit;
	unit.index = static_cast<int>(units.size());
	unit.side = p_side;
	unit.class_index = class_index;
	unit.unit_id = p_spec.unit_id;
	unit.cost = p_spec.cost;
	unit.star = p_spec.star;
	unit.max_hp = derive_scaled_stat(unit_class.def.max_hp, p_spec.cost, p_spec.star, rules);
	if (unit.max_hp < 1) {
		fail(p_spec.unit_id + " would have max_hp " + std::to_string(unit.max_hp) + " at cost " + std::to_string(p_spec.cost) + " star " + std::to_string(p_spec.star) + "; raise the class max_hp or the multipliers", r_error);
		return NO_UNIT;
	}
	unit.hp = unit.max_hp;
	unit.attack = derive_scaled_stat(unit_class.def.attack, p_spec.cost, p_spec.star, rules);
	unit.cell = local_to_global(p_side, p_local_col, p_local_rank);
	unit.is_opening_active = unit_class.opening != nullptr;
	UnitLoadout loadout;
	std::string skill_error;
	unit.skills.has_skill = p_spec.has_skill_override || unit_class.def.has_skill;
	if (unit.skills.has_skill) {
		loadout.skill = p_spec.has_skill_override ? p_spec.skill_override : unit_class.def.skill;
		if (p_spec.has_skill_override && !resolve_skill(&loadout.skill, &skill_error)) {
			fail(p_spec.unit_id + " skill_override: " + skill_error, r_error);
			return NO_UNIT;
		}
		unit.skills.qi_max = loadout.skill.qi_cost;
	}
	unit.skills.has_passive = p_spec.has_passive_override || unit_class.def.has_passive;
	if (unit.skills.has_passive) {
		loadout.passive = p_spec.has_passive_override ? p_spec.passive_override : unit_class.def.passive;
		if (p_spec.has_passive_override && !resolve_passive(&loadout.passive, &skill_error)) {
			fail(p_spec.unit_id + " passive_override: " + skill_error, r_error);
			return NO_UNIT;
		}
	}
	board.place(unit.cell, unit.index);
	units.push_back(unit);
	loadouts.push_back(loadout);
	return unit.index;
}

void BattleSim::clear() {
	units.clear();
	loadouts.clear();
	scheduled_steps.clear();
	board.clear();
	events.clear();
	tick = 0;
	next_event_id = 1;
	started = false;
	finished = false;
	winner = NO_WINNER;
}

bool BattleSim::start(std::string *r_error) {
	if (started) {
		return fail("the battle already started", r_error);
	}
	if (!has_rules) {
		return fail("set the rules before starting", r_error);
	}
	started = true;
	return true;
}

const std::vector<BattleEvent> &BattleSim::step() {
	events.clear();
	if (!started || finished) {
		return events;
	}
	tick++;
	if (tick == 1) {
		BattleEvent event;
		event.type = EventType::BATTLE_STARTED;
		emit_event(event);
	}
	expire_statuses(*this);
	run_scheduled_steps(*this);
	for (int unit : get_action_order()) {
		act(unit);
	}
	check_end();
	return events;
}

std::vector<int> BattleSim::get_action_order() const {
	std::vector<int> order;
	for (const UnitState &unit : units) {
		if (unit.is_alive) {
			order.push_back(unit.index);
		}
	}
	// Side A first on even ticks, side B first on odd ticks.
	const int first_side = tick % 2 == 0 ? SIDE_A : SIDE_B;
	std::sort(order.begin(), order.end(), [&](int p_a, int p_b) { return acts_before(units[p_a], units[p_b], first_side); });
	return order;
}

bool BattleSim::acts_before(const UnitState &p_a, const UnitState &p_b, int p_first_side) const {
	if (p_a.side != p_b.side) {
		return p_a.side == p_first_side;
	}
	// Nearest the enemy first: A advances toward higher rows, B toward lower.
	const int a_depth = p_a.side == SIDE_A ? -p_a.cell.row : p_a.cell.row;
	const int b_depth = p_b.side == SIDE_A ? -p_b.cell.row : p_b.cell.row;
	if (a_depth != b_depth) {
		return a_depth < b_depth;
	}
	const int a_from_center = std::abs(p_a.cell.col - CENTER_COL);
	const int b_from_center = std::abs(p_b.cell.col - CENTER_COL);
	if (a_from_center != b_from_center) {
		return a_from_center < b_from_center;
	}
	if (p_a.cell.col != p_b.cell.col) {
		return p_a.side == SIDE_A ? p_a.cell.col < p_b.cell.col : p_a.cell.col > p_b.cell.col;
	}
	return p_a.index < p_b.index;
}

void BattleSim::check_end() {
	int alive_a = 0;
	int alive_b = 0;
	for (const UnitState &unit : units) {
		if (unit.is_alive) {
			(unit.side == SIDE_A ? alive_a : alive_b)++;
		}
	}
	if (alive_a == 0 || alive_b == 0) {
		end_battle(alive_a > 0 ? SIDE_A : SIDE_B, EndReason::ELIMINATION);
	} else if (tick >= rules.time_limit_ticks) {
		end_battle(get_time_limit_winner(), EndReason::TIME_LIMIT);
	}
}

// Higher total of hp * 10000 / max_hp wins, then more living units, then B.
int BattleSim::get_time_limit_winner() const {
	int64_t scores[2] = { 0, 0 };
	int alive[2] = { 0, 0 };
	for (const UnitState &unit : units) {
		if (unit.is_alive) {
			// add_unit refuses max_hp < 1; the guard keeps a bad state from trapping.
			scores[unit.side] += unit.max_hp > 0 ? static_cast<int64_t>(unit.hp) * HP_SCORE_SCALE / unit.max_hp : 0;
			alive[unit.side]++;
		}
	}
	if (scores[SIDE_A] != scores[SIDE_B]) {
		return scores[SIDE_A] > scores[SIDE_B] ? SIDE_A : SIDE_B;
	}
	return alive[SIDE_A] > alive[SIDE_B] ? SIDE_A : SIDE_B;
}

void BattleSim::end_battle(int p_winner, EndReason p_reason) {
	finished = true;
	winner = p_winner;
	BattleEvent event;
	event.type = EventType::BATTLE_ENDED;
	event.winner = p_winner;
	event.reason = p_reason;
	emit_event(event);
}

int BattleSim::emit_event(BattleEvent p_event) {
	p_event.id = next_event_id++;
	p_event.tick = tick;
	events.push_back(p_event);
	return p_event.id;
}

uint64_t BattleSim::get_state_hash() const {
	uint64_t hash = FNV_OFFSET_BASIS;
	hash_value(&hash, tick);
	hash_value(&hash, finished ? 1 : 0);
	hash_value(&hash, winner);
	for (const UnitState &unit : units) {
		hash_value(&hash, unit.is_alive ? 1 : 0);
		hash_value(&hash, unit.hp);
		hash_value(&hash, unit.cell.col);
		hash_value(&hash, unit.cell.row);
		hash_value(&hash, unit.attack_charge);
		hash_value(&hash, get_move_ticks_left(unit));
		hash_value(&hash, unit.target);
		hash_value(&hash, unit.has_seen_target_in_range ? 1 : 0);
		hash_value(&hash, unit.target_out_of_range_ticks);
		hash_value(&hash, unit.no_path_ticks);
		hash_value(&hash, unit.is_opening_active ? 1 : 0);
		hash_skill_state(&hash, unit);
	}
	hash_value(&hash, static_cast<int64_t>(scheduled_steps.size()));
	for (const ScheduledStep &step : scheduled_steps) {
		hash_value(&hash, step.tick);
		hash_value(&hash, step.caster);
		hash_cells(&hash, step.cells);
	}
	return hash;
}

void BattleSim::hash_skill_state(uint64_t *r_hash, const UnitState &p_unit) const {
	const UnitSkillState &skills = p_unit.skills;
	hash_value(r_hash, skills.qi);
	hash_value(r_hash, skills.cast.is_casting ? skills.cast.end_tick - tick : -1);
	hash_cells(r_hash, skills.cast.cells);
	hash_value(r_hash, skills.charge.is_active ? 1 : 0);
	hash_value(r_hash, skills.charge.is_skill ? 1 : 0);
	hash_value(r_hash, skills.charge.cells_run);
	hash_value(r_hash, skills.charge.columns_left);
	hash_value(r_hash, skills.passive.trigger_count);
	hash_value(r_hash, skills.passive.fire_count);
	hash_value(r_hash, static_cast<int64_t>(skills.passive.used_sources));
	for (const StatusSlot &slot : skills.statuses) {
		hash_value(r_hash, slot.is_active ? slot.end_tick - tick : -1);
		hash_value(r_hash, slot.is_active ? slot.amount : 0);
		hash_value(r_hash, slot.is_active ? slot.source : NO_UNIT);
	}
}

std::vector<ScheduledStep> BattleSim::take_due_steps() {
	std::vector<ScheduledStep> due;
	std::vector<ScheduledStep> later;
	for (const ScheduledStep &step : scheduled_steps) {
		(step.tick <= tick ? due : later).push_back(step);
	}
	scheduled_steps = later;
	return due;
}

const ClassDef &BattleSim::get_class_def(const UnitState &p_unit) const {
	return classes[p_unit.class_index].def;
}

} // namespace battle
