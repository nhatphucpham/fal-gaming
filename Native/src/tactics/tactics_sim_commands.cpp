#include "tactics_sim.h"

#include "tactics_brain.h"
#include "tactics_combat.h"
#include "tactics_orders.h"
#include "tactics_passives.h"
#include "tactics_paths.h"
#include "tactics_skills.h"

// The commands of the active side, and the forecast and preview queries,
// which run the same code on a copy of the battle.

namespace tactics {

namespace {

std::string describe_cell(const Cell &p_cell) {
	return "(" + std::to_string(p_cell.col) + ", " + std::to_string(p_cell.row) + ")";
}

int get_sign(int p_value) {
	return p_value > 0 ? 1 : (p_value < 0 ? -1 : 0);
}

// Sums a skill hit into the preview's result for its target.
void add_preview_damage(SkillPreview &r_preview, const Event &p_event) {
	for (SkillTargetResult &result : r_preview.results) {
		if (result.unit == p_event.target) {
			result.amount += p_event.amount;
			result.hp_after = p_event.hp_after;
			result.is_dead = p_event.hp_after <= 0;
			return;
		}
	}
	SkillTargetResult result;
	result.unit = p_event.target;
	result.amount = p_event.amount;
	result.hp_after = p_event.hp_after;
	result.is_dead = p_event.hp_after <= 0;
	r_preview.results.push_back(result);
}

} // namespace

bool TacticsSim::check_command(int p_unit, std::string *r_error) const {
	if (!started || finished) {
		*r_error = "commands need a running battle";
		return false;
	}
	if (p_unit < 0 || p_unit >= static_cast<int>(units.size()) || !is_leader(p_unit)) {
		*r_error = "unit " + std::to_string(p_unit) + " is not a leader";
		return false;
	}
	if (!units[p_unit].is_alive || units[p_unit].side != active_side) {
		*r_error = "leader " + std::to_string(p_unit) + " is dead or not on the active side " + std::to_string(active_side);
		return false;
	}
	return true;
}

bool TacticsSim::check_leader_can_act(int p_unit, std::string *r_error) const {
	if (!check_command(p_unit, r_error)) {
		return false;
	}
	if (units[p_unit].has_acted) {
		*r_error = "leader " + std::to_string(p_unit) + " has already acted this phase";
		return false;
	}
	return true;
}

bool TacticsSim::check_leader_move(int p_unit, const Cell &p_cell, std::string *r_error) const {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	if (units[p_unit].has_moved) {
		*r_error = "leader " + std::to_string(p_unit) + " has already moved this phase";
		return false;
	}
	for (const Cell &cell : get_reachable_cells(*this, p_unit)) {
		if (cell == p_cell) {
			return true;
		}
	}
	*r_error = "leader " + std::to_string(p_unit) + " cannot reach " + describe_cell(p_cell);
	return false;
}

bool TacticsSim::move_leader(int p_unit, const Cell &p_cell, std::string *r_error) {
	if (!check_leader_move(p_unit, p_cell, r_error)) {
		return false;
	}
	clear_undo();
	// Only a human phase can take a move back; the AI never needs it.
	std::shared_ptr<TacticsSim> before;
	if (!side_is_ai[active_side]) {
		before = std::make_shared<TacticsSim>(*this);
	}
	const size_t first_event = events.size();
	const int move_id = apply_leader_move(p_unit, p_cell, 0);
	if (!finished) {
		run_squad_step(p_unit, move_id);
	}
	bool is_plain = before != nullptr && !finished;
	for (size_t index = first_event; index < events.size() && is_plain; index++) {
		is_plain = events[index].type == EventType::UNIT_MOVED || events[index].type == EventType::SKILL_CHARGE_CHANGED;
	}
	if (is_plain) {
		undo_state = before;
		undo_leader = p_unit;
	}
	return true;
}

void TacticsSim::clear_undo() {
	undo_state.reset();
	undo_leader = NO_UNIT;
}

bool TacticsSim::can_undo_move(int p_unit) const {
	return undo_state != nullptr && undo_leader == p_unit && !finished;
}

bool TacticsSim::undo_move(int p_unit, std::string *r_error) {
	if (!can_undo_move(p_unit)) {
		*r_error = "leader " + std::to_string(p_unit) + " has no move to take back";
		return false;
	}
	const std::shared_ptr<const TacticsSim> state = undo_state;
	// The events of the move were already taken; the copy has none pending.
	*this = *state;
	events.clear();
	clear_undo();
	return true;
}

// Passives that react to the move are caused by the leader's unit_moved.
int TacticsSim::apply_leader_move(int p_unit, const Cell &p_cell, int p_cause) {
	const PathField field = find_paths(*this, p_unit, get_stats(p_unit).move_points, ZocMode::APPLY);
	const std::vector<Cell> path = get_path(*this, field, p_cell);
	update_heading(p_unit, units[p_unit].cell, p_cell);
	units[p_unit].has_moved = true;
	units[p_unit].straight_cells = get_trailing_straight_cells(path);
	const int move_id = relocate_unit(p_unit, path, "move", p_cause);
	check_objective_taken(p_unit, move_id);
	// The move may have taken the objective: nothing happens after the end.
	if (finished) {
		return move_id;
	}
	const std::vector<PassiveDef> passives = units[p_unit].def.passives;
	for (const PassiveDef &passive : passives) {
		if (passive.handler->on_leader_moved != nullptr) {
			passive.handler->on_leader_moved(*this, p_unit, passive, move_id);
		}
	}
	note_leader_moved(*this, p_unit, move_id);
	return move_id;
}

// Heading: the dominant axis of the move; on a tie the current heading
// stays if it points along one of the two axes, else the row axis wins.
void TacticsSim::update_heading(int p_unit, const Cell &p_from, const Cell &p_to) {
	UnitState &unit = units[p_unit];
	const Cell by_col = { get_sign(p_to.col - p_from.col), 0 };
	const Cell by_row = { 0, get_sign(p_to.row - p_from.row) };
	const int cols = abs_int(p_to.col - p_from.col);
	const int rows = abs_int(p_to.row - p_from.row);
	Cell heading = cols > rows ? by_col : by_row;
	if (cols == rows && (unit.heading == by_col || unit.heading == by_row)) {
		heading = unit.heading;
	}
	unit.heading_streak = heading == unit.heading && unit.heading_streak > 0 ? unit.heading_streak + 1 : 1;
	unit.heading = heading;
}

bool TacticsSim::attack(int p_unit, int p_target, std::string *r_error) {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	clear_undo();
	if (p_target < 0 || p_target >= static_cast<int>(units.size()) || !can_attack(*this, p_unit, p_target)) {
		*r_error = "leader " + std::to_string(p_unit) + " cannot attack unit " + std::to_string(p_target);
		return false;
	}
	const EngagementResult result = resolve_engagement(*this, p_unit, p_target, 0);
	if (!result.is_attacker_dead && !finished) {
		const std::vector<PassiveDef> passives = units[p_unit].def.passives;
		for (const PassiveDef &passive : passives) {
			if (passive.handler->after_basic_attack != nullptr) {
				passive.handler->after_basic_attack(*this, p_unit, p_target, passive, result.event_id);
			}
		}
	}
	finish_leader_action(p_unit, result.event_id);
	return true;
}

bool TacticsSim::use_skill(int p_unit, const Cell &p_cell, std::string *r_error) {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	clear_undo();
	if (!is_skill_ready(units[p_unit])) {
		*r_error = "leader " + std::to_string(p_unit) + " has no skill ready";
		return false;
	}
	const int skill_id = cast_skill(*this, p_unit, p_cell, 0, r_error);
	if (skill_id == 0) {
		return false;
	}
	finish_leader_action(p_unit, skill_id);
	return true;
}

bool TacticsSim::wait(int p_unit, std::string *r_error) {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	clear_undo();
	Event event;
	event.type = EventType::LEADER_WAITED;
	event.unit = p_unit;
	finish_leader_action(p_unit, emit(event));
	return true;
}

bool TacticsSim::set_order(int p_unit, int p_order, std::string *r_error) {
	if (!check_command(p_unit, r_error)) {
		return false;
	}
	if (p_order < 0 || p_order >= get_order_count()) {
		*r_error = "set_order() got an unknown order";
		return false;
	}
	clear_undo();
	units[p_unit].order = p_order;
	Event event;
	event.type = EventType::ORDER_CHANGED;
	event.unit = p_unit;
	event.content_id = get_order_handler(p_order).id;
	emit(event);
	return true;
}

// Acting ends the leader's phase; a squad that has not stepped yet (the
// leader did not move) steps right after the action, caused by p_cause.
void TacticsSim::finish_leader_action(int p_unit, int p_cause) {
	if (finished) {
		return;
	}
	units[p_unit].has_acted = true;
	if (!units[p_unit].has_squad_acted) {
		run_squad_step(p_unit, p_cause);
	}
}

void TacticsSim::run_squad_step(int p_leader, int p_cause) {
	units[p_leader].has_squad_acted = true;
	move_squad(*this, p_leader, p_cause);
	attack_with_squad(*this, p_leader, p_cause);
}

void TacticsSim::run_squad_moves(int p_leader, int p_cause) {
	move_squad(*this, p_leader, p_cause);
}

EngagementResult TacticsSim::forecast_engagement(int p_attacker, int p_defender) const {
	const int count = static_cast<int>(units.size());
	if (finished || p_attacker < 0 || p_attacker >= count || p_defender < 0 || p_defender >= count || !can_attack(*this, p_attacker, p_defender)) {
		return EngagementResult();
	}
	TacticsSim copy = *this;
	return resolve_engagement(copy, p_attacker, p_defender, 0);
}

std::vector<std::pair<int, Cell>> TacticsSim::preview_squad(int p_leader, const Cell &p_cell, std::string *r_error) const {
	std::vector<std::pair<int, Cell>> placements;
	if (!check_leader_move(p_leader, p_cell, r_error)) {
		return placements;
	}
	TacticsSim copy = *this;
	copy.apply_leader_move(p_leader, p_cell, 0);
	copy.run_squad_moves(p_leader, 0);
	for (int soldier : copy.units[p_leader].soldiers) {
		if (copy.units[soldier].is_alive) {
			placements.push_back({ soldier, copy.units[soldier].cell });
		}
	}
	return placements;
}

Cell TacticsSim::get_strike_cell(int p_unit, int p_target) const {
	if (!can_leader_act(p_unit) || p_target < 0 || p_target >= static_cast<int>(units.size())) {
		return NO_CELL;
	}
	if (!can_leader_move(p_unit)) {
		return can_attack(*this, p_unit, p_target) ? units[p_unit].cell : NO_CELL;
	}
	const PathField field = find_paths(*this, p_unit, get_stats(p_unit).move_points, ZocMode::APPLY);
	const std::vector<Strike> strikes = list_strikes(*this, p_unit, field, [&](const Cell &p_cell) {
		return is_in_range_from(*this, p_unit, p_cell, units[p_target].cell);
	});
	return pick_safest_strike_cell(*this, strikes, count_enemy_reach(*this, units[p_unit].side), p_target);
}

std::vector<int> TacticsSim::get_strike_targets(int p_unit) const {
	std::vector<int> targets;
	if (!can_leader_act(p_unit)) {
		return targets;
	}
	if (!can_leader_move(p_unit)) {
		return get_attack_targets(p_unit);
	}
	const PathField field = find_paths(*this, p_unit, get_stats(p_unit).move_points, ZocMode::APPLY);
	std::vector<bool> is_target(units.size(), false);
	for (const Strike &strike : list_strikes(*this, p_unit, field, [](const Cell &) { return true; })) {
		is_target[strike.target] = true;
	}
	for (size_t index = 0; index < units.size(); index++) {
		if (is_target[index]) {
			targets.push_back(static_cast<int>(index));
		}
	}
	return targets;
}

bool TacticsSim::simulate_move(int p_unit, const Cell &p_cell, TacticsSim *r_copy, std::string *r_error) const {
	*r_copy = *this;
	r_copy->clear_undo();
	if (p_cell == units[p_unit].cell) {
		return check_leader_can_act(p_unit, r_error);
	}
	// No undo copy inside the copy.
	const bool was_ai = r_copy->side_is_ai[active_side];
	r_copy->side_is_ai[active_side] = true;
	const bool is_moved = r_copy->move_leader(p_unit, p_cell, r_error);
	r_copy->side_is_ai[active_side] = was_ai;
	return is_moved;
}

bool TacticsSim::can_leader_act(int p_unit) const {
	std::string error;
	return check_leader_can_act(p_unit, &error);
}

bool TacticsSim::can_leader_move(int p_unit) const {
	return can_leader_act(p_unit) && !units[p_unit].has_moved;
}

std::vector<int> TacticsSim::get_attack_targets(int p_unit) const {
	std::vector<int> targets;
	if (!can_leader_act(p_unit)) {
		return targets;
	}
	for (const UnitState &unit : units) {
		if (can_attack(*this, p_unit, unit.index)) {
			targets.push_back(unit.index);
		}
	}
	return targets;
}

std::vector<Cell> TacticsSim::get_skill_cells(int p_unit) const {
	std::vector<Cell> cells;
	if (!can_leader_act(p_unit) || !is_skill_ready(units[p_unit])) {
		return cells;
	}
	const UnitState &caster = units[p_unit];
	const int cell_count = map.width * map.height;
	for (int index = 0; index < cell_count; index++) {
		SkillSelection selection;
		std::string error;
		const Cell cell = get_cell_at(index);
		if (caster.def.skill.target->select(*this, p_unit, caster.cell, cell, selection, &error)) {
			cells.push_back(cell);
		}
	}
	return cells;
}

// The copy casts exactly as use_skill() would; its events say what changed.
bool TacticsSim::preview_skill(int p_unit, const Cell &p_cell, SkillPreview *r_preview, std::string *r_error) const {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	if (!is_skill_ready(units[p_unit])) {
		*r_error = "leader " + std::to_string(p_unit) + " has no skill ready";
		return false;
	}
	TacticsSim copy = *this;
	copy.events.clear();
	if (cast_skill(copy, p_unit, p_cell, 0, r_error) == 0) {
		return false;
	}
	const std::string &skill_id = units[p_unit].def.skill.id;
	for (const Event &event : copy.events) {
		if (event.type == EventType::SKILL_USED) {
			r_preview->cells = event.cells;
			r_preview->targets = event.units;
		} else if (event.type == EventType::DAMAGE_DEALT && event.content_id == skill_id) {
			add_preview_damage(*r_preview, event);
		} else if (event.type == EventType::BUFF_APPLIED) {
			r_preview->buffed.push_back(event.unit);
		} else if (event.type == EventType::ZONE_CREATED) {
			r_preview->zone_cells.insert(r_preview->zone_cells.end(), event.cells.begin(), event.cells.end());
		}
	}
	return true;
}

} // namespace tactics
