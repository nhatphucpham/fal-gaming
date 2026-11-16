#include "tactics_passives.h"

#include "tactics_paths.h"
#include "tactics_sim.h"

namespace tactics {

namespace {

struct StatEntry {
	const char *id;
	StatKind kind;
};

const StatEntry STAT_ENTRIES[] = {
	{ "stat.attack_pct", StatKind::ATTACK_PCT },
	{ "stat.armor", StatKind::ARMOR },
	{ "stat.magic_resist", StatKind::MAGIC_RESIST },
	{ "stat.move_points", StatKind::MOVE_POINTS },
	{ "stat.max_range", StatKind::MAX_RANGE },
};

int count_adjacent_allies(const TacticsSim &p_sim, int p_unit, const Cell &p_cell) {
	int count = 0;
	for (const Cell &direction : DIRECTIONS) {
		const Cell next = p_cell + direction;
		if (!p_sim.is_on_map(next)) {
			continue;
		}
		const int occupant = p_sim.get_occupant(next);
		if (occupant != NO_UNIT && occupant != p_unit && p_sim.get_units()[occupant].side == p_sim.get_units()[p_unit].side) {
			count++;
		}
	}
	return count;
}

// passive.stat_bonus (stat modifier): the leader's own stat, optionally only
// on one terrain and only with enough allies orthogonally next to it.
void stat_bonus_own(const TacticsSim &p_sim, int p_unit, const Cell &p_cell, const PassiveDef &p_passive, StatModifiers &r_mods) {
	if (!p_passive.condition_terrain_id.empty() && p_sim.get_terrain(p_cell).id != p_passive.condition_terrain_id) {
		return;
	}
	if (count_adjacent_allies(p_sim, p_unit, p_cell) < p_passive.condition_adjacent_allies) {
		return;
	}
	add_stat_modifier(p_passive.stat, p_passive.amount, r_mods);
}

// passive.squad_bonus (squad modifier): a stat, a keyword and extra lead
// capacity for the leader's own soldiers.
void squad_bonus_soldier(const TacticsSim &p_sim, int p_soldier, const PassiveDef &p_passive, StatModifiers &r_mods) {
	(void)p_sim;
	(void)p_soldier;
	add_stat_modifier(p_passive.stat, p_passive.amount, r_mods);
}

void squad_bonus_keywords(const PassiveDef &p_passive, std::vector<const KeywordDef *> &r_keywords) {
	if (p_passive.has_keyword) {
		r_keywords.push_back(&p_passive.keyword);
	}
}

int squad_bonus_capacity(const PassiveDef &p_passive) {
	return p_passive.extra_capacity;
}

// passive.trail_zone (environment): after each move the leader leaves its
// zone on the cells within radius_cells (Manhattan) of where it stopped.
void trail_zone_moved(TacticsSim &p_sim, int p_leader, const PassiveDef &p_passive, int p_cause) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	ZoneState zone;
	zone.def = p_passive.zone;
	zone.side = leader.side;
	zone.source = p_leader;
	const int cell_count = p_sim.get_map().width * p_sim.get_map().height;
	for (int index = 0; index < cell_count; index++) {
		const Cell cell = p_sim.get_cell_at(index);
		if (get_manhattan(cell, leader.cell) <= p_passive.radius_cells) {
			zone.cells.push_back(cell);
		}
	}
	p_sim.emit_passive_triggered(p_leader, p_passive.id, p_cause);
	p_sim.add_zone(zone, p_passive.duration_rounds, p_cause);
}

// passive.pull_strike (special weapon): the leader's attack pulls a target
// that survived up to `amount` cells toward the leader, along the longer
// axis between them (rows on a tie), stopping before anything in the way.
void pull_strike_after_attack(TacticsSim &p_sim, int p_leader, int p_target, const PassiveDef &p_passive, int p_cause) {
	const UnitState &target = p_sim.get_units()[p_target];
	// A soldier standing its ground (incident.stand) cannot be pulled.
	if (!target.is_alive || p_sim.is_holding_ground(p_target)) {
		return;
	}
	const Cell leader_cell = p_sim.get_units()[p_leader].cell;
	const int delta_col = leader_cell.col - target.cell.col;
	const int delta_row = leader_cell.row - target.cell.row;
	const bool is_along_cols = abs_int(delta_col) > abs_int(delta_row);
	const Cell step = is_along_cols ? Cell{ delta_col > 0 ? 1 : -1, 0 } : Cell{ 0, delta_row > 0 ? 1 : -1 };
	std::vector<Cell> path = { target.cell };
	for (int moved = 0; moved < p_passive.amount; moved++) {
		const Cell next = path.back() + step;
		if (next == leader_cell || !can_stop_at(p_sim, p_target, next)) {
			break;
		}
		path.push_back(next);
	}
	if (path.size() < 2) {
		return;
	}
	p_sim.emit_passive_triggered(p_leader, p_passive.id, p_cause);
	p_sim.relocate_unit(p_target, path, "pull", p_cause);
}

// passive.skill_growth (skill growth): each enemy leader the leader defeats
// widens its skill's area by `amount` cells for the rest of the battle.
void skill_growth_defeated(TacticsSim &p_sim, int p_leader, int p_victim, const PassiveDef &p_passive, int p_cause) {
	if (!p_sim.is_leader(p_victim)) {
		return;
	}
	UnitState &leader = p_sim.edit_unit(p_leader);
	leader.skill_area_bonus += p_passive.amount;
	p_sim.emit_passive_triggered(p_leader, p_passive.id, p_cause);
	Event event;
	event.type = EventType::SKILL_GREW;
	event.unit = p_leader;
	event.content_id = leader.def.skill.id;
	event.value = leader.skill_area_bonus;
	event.cause = p_cause;
	p_sim.emit(event);
}

const PassiveHandler PASSIVE_HANDLERS[] = {
	{ "passive.stat_bonus", "stat_modifier", false, true, false, stat_bonus_own, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr },
	{ "passive.squad_bonus", "squad_modifier", false, false, false, nullptr, squad_bonus_soldier, squad_bonus_keywords, squad_bonus_capacity, nullptr, nullptr, nullptr },
	{ "passive.trail_zone", "environment", true, false, false, nullptr, nullptr, nullptr, nullptr, trail_zone_moved, nullptr, nullptr },
	{ "passive.pull_strike", "special_weapon", false, false, true, nullptr, nullptr, nullptr, nullptr, nullptr, pull_strike_after_attack, nullptr },
	{ "passive.skill_growth", "skill_growth", false, false, true, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, skill_growth_defeated },
};

} // namespace

void add_stat_modifier(StatKind p_stat, int p_amount, StatModifiers &r_mods) {
	switch (p_stat) {
		case StatKind::ATTACK_PCT:
			r_mods.attack_pct += p_amount;
			break;
		case StatKind::ARMOR:
			r_mods.armor += p_amount;
			break;
		case StatKind::MAGIC_RESIST:
			r_mods.magic_resist += p_amount;
			break;
		case StatKind::MOVE_POINTS:
			r_mods.move_points += p_amount;
			break;
		case StatKind::MAX_RANGE:
			r_mods.max_range_cells += p_amount;
			break;
		case StatKind::NONE:
			break;
	}
}

StatKind find_stat_kind(const std::string &p_id) {
	for (const StatEntry &entry : STAT_ENTRIES) {
		if (p_id == entry.id) {
			return entry.kind;
		}
	}
	return StatKind::NONE;
}

const char *get_stat_id(StatKind p_stat) {
	for (const StatEntry &entry : STAT_ENTRIES) {
		if (entry.kind == p_stat) {
			return entry.id;
		}
	}
	return "";
}

const PassiveHandler *find_passive_handler(const std::string &p_id) {
	for (const PassiveHandler &handler : PASSIVE_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

} // namespace tactics
