#include "tactics_sim.h"

#include "tactics_keywords.h"
#include "tactics_orders.h"
#include "tactics_passives.h"
#include "tactics_skills.h"

#include <algorithm>
#include <cstdint>

// State helpers shared by the rules modules: lookups, effective stats,
// damage, deaths, relocation, zones, buffs, skill charge and events.

namespace tactics {

namespace {

constexpr int PERCENT = 100;

int at_least(int p_value, int p_min) {
	return p_value < p_min ? p_min : p_value;
}

} // namespace

bool TacticsSim::is_on_map(const Cell &p_cell) const {
	return p_cell.col >= 0 && p_cell.col < map.width && p_cell.row >= 0 && p_cell.row < map.height;
}

const TerrainDef &TacticsSim::get_terrain(const Cell &p_cell) const {
	return map.terrains[map.cell_terrain[get_cell_index(p_cell)]];
}

int TacticsSim::get_occupant(const Cell &p_cell) const {
	return occupants[get_cell_index(p_cell)];
}

Stats TacticsSim::get_stats_at(int p_unit, const Cell &p_cell) const {
	const UnitState &unit = units[p_unit];
	StatModifiers mods;
	if (is_leader(p_unit)) {
		for (const PassiveDef &passive : unit.def.passives) {
			if (passive.handler->modify_own_stats != nullptr) {
				passive.handler->modify_own_stats(*this, p_unit, p_cell, passive, mods);
			}
		}
	} else if (unit.leader != NO_UNIT && units[unit.leader].is_alive) {
		for (const PassiveDef &passive : units[unit.leader].def.passives) {
			if (passive.handler->modify_soldier_stats != nullptr) {
				passive.handler->modify_soldier_stats(*this, p_unit, passive, mods);
			}
		}
	}
	for (const BuffState &buff : buffs) {
		if (buff.unit == p_unit) {
			add_stat_modifier(buff.stat, buff.amount, mods);
		}
	}
	Stats stats;
	// 64 bits: stacked buffs can push the percent high enough to overflow.
	const int64_t attack = static_cast<int64_t>(unit.def.attack) * at_least(PERCENT + mods.attack_pct, 0) / PERCENT;
	stats.attack = attack > INT32_MAX ? INT32_MAX : static_cast<int>(attack);
	stats.armor = at_least(unit.def.armor + mods.armor, 0);
	stats.magic_resist = at_least(unit.def.magic_resist + mods.magic_resist, 0);
	stats.move_points = at_least(unit.def.move_points + mods.move_points, 0);
	stats.min_range_cells = unit.def.min_range_cells;
	stats.max_range_cells = unit.def.max_range_cells + mods.max_range_cells;
	if (is_on_map(p_cell)) {
		const TerrainDef &terrain = get_terrain(p_cell);
		stats.armor = at_least(stats.armor + terrain.armor_bonus, 0);
		stats.max_range_cells += unit.def.is_ranged ? terrain.ranged_range_bonus : 0;
	}
	stats.max_range_cells = at_least(stats.max_range_cells, stats.min_range_cells);
	return stats;
}

namespace {

bool does_stat_matter(StatUse p_use, const StatModifiers &p_mods) {
	return p_use == StatUse::ATTACK ? p_mods.attack_pct != 0 : (p_mods.armor != 0 || p_mods.magic_resist != 0);
}

void add_unique_source(std::vector<std::string> &r_sources, const std::string &p_id) {
	if (std::find(r_sources.begin(), r_sources.end(), p_id) == r_sources.end()) {
		r_sources.push_back(p_id);
	}
}

} // namespace

// Runs the same hooks as get_stats_at(), one source at a time.
void TacticsSim::collect_stat_sources(int p_unit, StatUse p_use, std::vector<std::string> &r_sources) const {
	const UnitState &unit = units[p_unit];
	if (is_leader(p_unit)) {
		for (const PassiveDef &passive : unit.def.passives) {
			StatModifiers mods;
			if (passive.handler->modify_own_stats != nullptr) {
				passive.handler->modify_own_stats(*this, p_unit, unit.cell, passive, mods);
			}
			if (does_stat_matter(p_use, mods)) {
				add_unique_source(r_sources, passive.id);
			}
		}
	} else if (unit.leader != NO_UNIT && units[unit.leader].is_alive) {
		for (const PassiveDef &passive : units[unit.leader].def.passives) {
			StatModifiers mods;
			if (passive.handler->modify_soldier_stats != nullptr) {
				passive.handler->modify_soldier_stats(*this, p_unit, passive, mods);
			}
			if (does_stat_matter(p_use, mods)) {
				add_unique_source(r_sources, passive.id);
			}
		}
	}
	for (const BuffState &buff : buffs) {
		StatModifiers mods;
		add_stat_modifier(buff.stat, buff.amount, mods);
		if (buff.unit == p_unit && does_stat_matter(p_use, mods)) {
			add_unique_source(r_sources, buff.source_id);
		}
	}
	if (p_use == StatUse::DEFENCE && is_on_map(unit.cell) && get_terrain(unit.cell).armor_bonus != 0) {
		add_unique_source(r_sources, get_terrain(unit.cell).id);
	}
}

std::vector<const KeywordDef *> TacticsSim::collect_keywords(int p_unit) const {
	const UnitState &unit = units[p_unit];
	std::vector<const KeywordDef *> keywords;
	for (const KeywordDef &keyword : unit.def.keywords) {
		keywords.push_back(&keyword);
	}
	if (is_leader(p_unit) || unit.leader == NO_UNIT || !units[unit.leader].is_alive) {
		return keywords;
	}
	std::vector<const KeywordDef *> granted;
	for (const PassiveDef &passive : units[unit.leader].def.passives) {
		if (passive.handler->grant_soldier_keywords != nullptr) {
			passive.handler->grant_soldier_keywords(passive, granted);
		}
	}
	// A keyword the soldier already has is not added twice.
	for (const KeywordDef *keyword : granted) {
		bool is_known = false;
		for (const KeywordDef *known : keywords) {
			is_known = is_known || known->id == keyword->id;
		}
		if (!is_known) {
			keywords.push_back(keyword);
		}
	}
	return keywords;
}

int TacticsSim::get_squad_capacity(int p_leader) const {
	int capacity = units[p_leader].def.lead_capacity;
	for (const PassiveDef &passive : units[p_leader].def.passives) {
		if (passive.handler->get_extra_capacity != nullptr) {
			capacity += passive.handler->get_extra_capacity(passive);
		}
	}
	// Formations have MAX_SQUAD_SIZE slots, whatever the passives add.
	return capacity < MAX_SQUAD_SIZE ? capacity : MAX_SQUAD_SIZE;
}

int TacticsSim::emit(Event &r_event) {
	r_event.id = next_event_id++;
	r_event.turn = turn;
	r_event.round = round;
	events.push_back(r_event);
	return r_event.id;
}

std::vector<Event> TacticsSim::take_events() {
	std::vector<Event> taken;
	taken.swap(events);
	return taken;
}

int TacticsSim::deal_damage(int p_source, int p_target, int p_amount, const std::string &p_content_id, bool p_is_counter, int p_cause) {
	UnitState &target = units[p_target];
	if (finished || !target.is_alive) {
		return 0;
	}
	const int lost = p_amount < target.hp ? p_amount : target.hp;
	target.hp -= lost;
	Event event;
	event.type = EventType::DAMAGE_DEALT;
	event.unit = p_source;
	event.target = p_target;
	event.amount = p_amount;
	event.hp_after = target.hp;
	event.is_counter = p_is_counter;
	event.content_id = p_content_id;
	event.cause = p_cause;
	const int damage_id = emit(event);
	if (is_leader(p_target) && lost > 0) {
		trigger_skill_charge(*this, p_target, ChargeTrigger::DAMAGE_TAKEN, lost, damage_id);
	}
	if (target.hp == 0) {
		handle_death(p_target, p_source, damage_id);
	}
	return damage_id;
}

void TacticsSim::handle_death(int p_unit, int p_killer, int p_cause) {
	UnitState &unit = units[p_unit];
	unit.is_alive = false;
	occupants[get_cell_index(unit.cell)] = NO_UNIT;
	Event event;
	event.type = EventType::UNIT_DIED;
	event.unit = p_unit;
	event.target = p_killer;
	event.from = unit.cell;
	event.cause = p_cause;
	const int death_id = emit(event);
	buffs.erase(std::remove_if(buffs.begin(), buffs.end(), [&](const BuffState &p_buff) { return p_buff.unit == p_unit; }), buffs.end());
	intents.erase(std::remove_if(intents.begin(), intents.end(), [&](const Intent &p_intent) { return p_intent.leader == p_unit; }), intents.end());
	if (!is_leader(p_unit) && units[unit.leader].is_alive) {
		trigger_skill_charge(*this, unit.leader, ChargeTrigger::SOLDIER_LOST, 1, death_id);
	}
	if (p_killer != NO_UNIT && is_leader(p_killer) && units[p_killer].is_alive && units[p_killer].side != unit.side) {
		const std::vector<PassiveDef> passives = units[p_killer].def.passives;
		for (const PassiveDef &passive : passives) {
			if (passive.handler->on_enemy_defeated != nullptr) {
				passive.handler->on_enemy_defeated(*this, p_killer, p_unit, passive, death_id);
			}
		}
	}
	check_rout(death_id);
}

int TacticsSim::relocate_unit(int p_unit, const std::vector<Cell> &p_path, const std::string &p_kind, int p_cause) {
	UnitState &unit = units[p_unit];
	if (finished || p_path.size() < 2) {
		return 0;
	}
	const Cell from = unit.cell;
	occupants[get_cell_index(from)] = NO_UNIT;
	unit.cell = p_path.back();
	occupants[get_cell_index(unit.cell)] = p_unit;
	Event event;
	event.type = EventType::UNIT_MOVED;
	event.unit = p_unit;
	event.from = from;
	event.to = unit.cell;
	event.cells = p_path;
	event.kind = p_kind;
	event.cause = p_cause;
	const int move_id = emit(event);
	if (is_leader(p_unit)) {
		trigger_skill_charge(*this, p_unit, ChargeTrigger::DISPLACED, 0, move_id);
	}
	return move_id;
}

void TacticsSim::add_zone(ZoneState p_zone, int p_duration_rounds, int p_cause) {
	p_zone.end_round = round + p_duration_rounds;
	p_zone.end_turn = turn + SIDE_COUNT * p_duration_rounds;
	zones.push_back(p_zone);
	Event event;
	event.type = EventType::ZONE_CREATED;
	event.unit = p_zone.source;
	event.side = p_zone.side;
	event.content_id = p_zone.def.id;
	event.cells = p_zone.cells;
	event.end_round = p_zone.end_round;
	event.cause = p_cause;
	emit(event);
}

void TacticsSim::add_buff(BuffState p_buff, int p_duration_rounds, int p_cause) {
	p_buff.end_round = round + p_duration_rounds;
	p_buff.end_turn = turn + SIDE_COUNT * p_duration_rounds;
	buffs.push_back(p_buff);
	Event event;
	event.type = EventType::BUFF_APPLIED;
	event.unit = p_buff.unit;
	event.amount = p_buff.amount;
	event.end_round = p_buff.end_round;
	event.content_id = p_buff.source_id;
	event.kind = get_stat_id(p_buff.stat);
	event.cause = p_cause;
	emit(event);
}

void TacticsSim::change_skill_charge(int p_leader, int p_delta, bool p_resets, int p_cause) {
	UnitState &leader = units[p_leader];
	const int threshold = leader.def.skill.charge_threshold;
	int value = p_resets ? 0 : leader.skill_charge + p_delta;
	value = value < 0 ? 0 : (value > threshold ? threshold : value);
	if (value == leader.skill_charge) {
		return;
	}
	leader.skill_charge = value;
	Event event;
	event.type = EventType::SKILL_CHARGE_CHANGED;
	event.unit = p_leader;
	event.value = value;
	event.threshold = threshold;
	event.content_id = leader.def.skill.charge_id;
	event.cause = p_cause;
	emit(event);
}

void TacticsSim::emit_passive_triggered(int p_unit, const std::string &p_passive_id, int p_cause) {
	Event event;
	event.type = EventType::PASSIVE_TRIGGERED;
	event.unit = p_unit;
	event.content_id = p_passive_id;
	event.cause = p_cause;
	emit(event);
}

} // namespace tactics
