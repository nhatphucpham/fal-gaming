#include "tactics_sim.h"

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
	apply_leader_move(p_unit, p_cell, 0);
	if (!finished) {
		run_squad_step(p_unit, 0);
	}
	return true;
}

void TacticsSim::apply_leader_move(int p_unit, const Cell &p_cell, int p_cause) {
	const PathField field = find_paths(*this, p_unit, get_stats(p_unit).move_points, ZocMode::APPLY);
	const std::vector<Cell> path = get_path(*this, field, p_cell);
	update_heading(p_unit, units[p_unit].cell, p_cell);
	units[p_unit].has_moved = true;
	units[p_unit].straight_cells = get_trailing_straight_cells(path);
	relocate_unit(p_unit, path, "move", p_cause);
	// The move may have taken the objective: nothing happens after the end.
	if (finished) {
		return;
	}
	const std::vector<PassiveDef> passives = units[p_unit].def.passives;
	for (const PassiveDef &passive : passives) {
		if (passive.handler->on_leader_moved != nullptr) {
			passive.handler->on_leader_moved(*this, p_unit, passive, p_cause);
		}
	}
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
	if (p_target < 0 || p_target >= static_cast<int>(units.size()) || !can_attack(*this, p_unit, p_target)) {
		*r_error = "leader " + std::to_string(p_unit) + " cannot attack unit " + std::to_string(p_target);
		return false;
	}
	const EngagementResult result = resolve_engagement(*this, p_unit, p_target, 0);
	if (!result.is_attacker_dead && !finished) {
		const std::vector<PassiveDef> passives = units[p_unit].def.passives;
		for (const PassiveDef &passive : passives) {
			if (passive.handler->after_basic_attack != nullptr) {
				passive.handler->after_basic_attack(*this, p_unit, p_target, passive, 0);
			}
		}
	}
	finish_leader_action(p_unit, 0);
	return true;
}

bool TacticsSim::use_skill(int p_unit, const Cell &p_cell, std::string *r_error) {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	if (!is_skill_ready(units[p_unit])) {
		*r_error = "leader " + std::to_string(p_unit) + " has no skill ready";
		return false;
	}
	if (!cast_skill(*this, p_unit, p_cell, 0, r_error)) {
		return false;
	}
	finish_leader_action(p_unit, 0);
	return true;
}

bool TacticsSim::wait(int p_unit, std::string *r_error) {
	if (!check_leader_can_act(p_unit, r_error)) {
		return false;
	}
	Event event;
	event.type = EventType::LEADER_WAITED;
	event.unit = p_unit;
	emit(event);
	finish_leader_action(p_unit, 0);
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
	units[p_unit].order = p_order;
	Event event;
	event.type = EventType::ORDER_CHANGED;
	event.unit = p_unit;
	event.content_id = get_order_handler(p_order).id;
	emit(event);
	return true;
}

// Acting ends the leader's phase; a squad that has not stepped yet (the
// leader did not move) steps right after the action.
void TacticsSim::finish_leader_action(int p_unit, int p_cause) {
	units[p_unit].has_acted = true;
	if (!units[p_unit].has_squad_acted && !finished) {
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

} // namespace tactics
