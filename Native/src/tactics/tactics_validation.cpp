#include "tactics_validation.h"

#include "tactics_orders.h"
#include "tactics_passives.h"
#include "tactics_skills.h"

namespace tactics {

namespace {

bool check_range(const std::string &p_owner, const char *p_field, int p_value, int p_min, int p_max, std::string *r_error) {
	if (p_value >= p_min && p_value <= p_max) {
		return true;
	}
	*r_error = p_owner + " has " + p_field + " " + std::to_string(p_value) + ", expected " + std::to_string(p_min) + ".." + std::to_string(p_max);
	return false;
}

bool is_direction(const Cell &p_cell) {
	for (const Cell &direction : DIRECTIONS) {
		if (direction == p_cell) {
			return true;
		}
	}
	return false;
}

bool validate_terrain(const TerrainDef &p_terrain, std::string *r_error) {
	return check_range(p_terrain.id, "move_cost", p_terrain.move_cost, 1, MAX_MOVE_COST, r_error) &&
			check_range(p_terrain.id, "armor_bonus", p_terrain.armor_bonus, -MAX_STAT, MAX_STAT, r_error) &&
			check_range(p_terrain.id, "damage_taken_pct", p_terrain.damage_taken_pct, -MAX_PERCENT_MODIFIER, MAX_PERCENT_MODIFIER, r_error) &&
			check_range(p_terrain.id, "ranged_damage_taken_pct", p_terrain.ranged_damage_taken_pct, -MAX_PERCENT_MODIFIER, MAX_PERCENT_MODIFIER, r_error) &&
			check_range(p_terrain.id, "ranged_range_bonus", p_terrain.ranged_range_bonus, 0, MAX_RANGE_CELLS, r_error);
}

bool validate_keyword(const std::string &p_owner, const KeywordDef &p_keyword, std::string *r_error) {
	if (p_keyword.handler == nullptr) {
		*r_error = p_owner + " has unknown keyword " + p_keyword.id;
		return false;
	}
	return check_range(p_keyword.id, "amount", p_keyword.amount, 0, MAX_KEYWORD_AMOUNT, r_error) &&
			check_range(p_keyword.id, "min_cells", p_keyword.min_cells, 0, MAX_MOVE_POINTS, r_error);
}

bool validate_zone(const std::string &p_owner, const ZoneDef &p_zone, std::string *r_error) {
	if (p_zone.handler == nullptr) {
		*r_error = p_owner + " has a zone with an unknown effect: " + p_zone.id;
		return false;
	}
	return check_range(p_zone.id, "amount", p_zone.amount, 0, MAX_STAT, r_error);
}

bool validate_skill_effect(const SkillDef &p_skill, const SkillEffectDef &p_effect, std::string *r_error) {
	if (p_effect.handler == nullptr) {
		*r_error = p_skill.id + " has an unknown effect handler " + p_effect.handler_id;
		return false;
	}
	if (p_effect.handler->needs_zone && !p_effect.has_zone) {
		*r_error = p_skill.id + ": " + p_effect.handler_id + " needs a zone";
		return false;
	}
	if (p_effect.has_zone && !validate_zone(p_skill.id, p_effect.zone, r_error)) {
		return false;
	}
	const std::string owner = p_skill.id + " " + p_effect.handler_id;
	return check_range(owner, "duration_rounds", p_effect.duration_rounds, 0, MAX_DURATION_ROUNDS, r_error) &&
			check_range(owner, "coefficient_pct", p_effect.coefficient_pct, 0, MAX_COEFFICIENT_PCT, r_error) &&
			check_range(owner, "amount_pct", p_effect.amount_pct, 0, MAX_BUFF_PCT, r_error);
}

bool validate_skill(const UnitDef &p_unit, std::string *r_error) {
	const SkillDef &skill = p_unit.skill;
	if (skill.charge == nullptr || skill.target == nullptr) {
		*r_error = skill.id + " of " + p_unit.id + " has an unknown charge or target handler";
		return false;
	}
	if (skill.effects.empty()) {
		*r_error = skill.id + " of " + p_unit.id + " has no effects";
		return false;
	}
	for (const SkillEffectDef &effect : skill.effects) {
		if (!validate_skill_effect(skill, effect, r_error)) {
			return false;
		}
	}
	return check_range(skill.id, "charge_threshold", skill.charge_threshold, 1, MAX_STAT, r_error) &&
			check_range(skill.id, "cast_range_cells", skill.cast_range_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(skill.id, "area_radius_cells", skill.area_radius_cells, 0, MAX_MAP_CELLS_PER_AXIS, r_error) &&
			check_range(skill.id, "chain_count", skill.chain_count, 1, MAX_SQUAD_SIZE * 2, r_error) &&
			check_range(skill.id, "chain_jump_cells", skill.chain_jump_cells, 1, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(skill.id, "chain_falloff_pct", skill.chain_falloff_pct, 0, MAX_PERCENT_MODIFIER, r_error);
}

bool validate_passive(const UnitDef &p_unit, const PassiveDef &p_passive, std::string *r_error) {
	if (p_passive.handler == nullptr) {
		*r_error = p_passive.id + " of " + p_unit.id + " has an unknown handler";
		return false;
	}
	if (p_passive.handler->needs_zone && !p_passive.has_zone) {
		*r_error = p_passive.id + " of " + p_unit.id + " needs a zone";
		return false;
	}
	if (p_passive.handler->needs_stat && p_passive.stat == StatKind::NONE) {
		*r_error = p_passive.id + " of " + p_unit.id + " needs a stat";
		return false;
	}
	if ((p_passive.has_zone && !validate_zone(p_passive.id, p_passive.zone, r_error)) || (p_passive.has_keyword && !validate_keyword(p_passive.id, p_passive.keyword, r_error))) {
		return false;
	}
	const int min_amount = p_passive.handler->needs_unsigned_amount ? 0 : -MAX_PASSIVE_AMOUNT;
	return check_range(p_passive.id, "amount", p_passive.amount, min_amount, MAX_PASSIVE_AMOUNT, r_error) &&
			check_range(p_passive.id, "condition_adjacent_allies", p_passive.condition_adjacent_allies, 0, MAX_ADJACENT_CELLS, r_error) &&
			check_range(p_passive.id, "extra_capacity", p_passive.extra_capacity, 0, MAX_SQUAD_SIZE, r_error) &&
			check_range(p_passive.id, "radius_cells", p_passive.radius_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(p_passive.id, "duration_rounds", p_passive.duration_rounds, 0, MAX_DURATION_ROUNDS, r_error);
}

bool validate_leader_parts(const UnitDef &p_unit, std::string *r_error) {
	if (!check_range(p_unit.id, "passive count", static_cast<int>(p_unit.passives.size()), 0, MAX_PASSIVES, r_error) ||
			!check_range(p_unit.id, "lead_capacity", p_unit.lead_capacity, 0, MAX_SQUAD_SIZE, r_error)) {
		return false;
	}
	for (size_t index = 0; index < p_unit.passives.size(); index++) {
		if (!validate_passive(p_unit, p_unit.passives[index], r_error)) {
			return false;
		}
		for (size_t other = 0; other < index; other++) {
			if (p_unit.passives[other].id == p_unit.passives[index].id) {
				*r_error = p_unit.id + " lists passive " + p_unit.passives[index].id + " twice";
				return false;
			}
		}
	}
	if (p_unit.default_order < 0 || p_unit.default_order >= get_order_count()) {
		*r_error = p_unit.id + " has an unknown default_order";
		return false;
	}
	return !p_unit.has_skill || validate_skill(p_unit, r_error);
}

} // namespace

bool validate_rules(const Rules &p_rules, std::string *r_error) {
	const std::string owner = "rules";
	return check_range(owner, "hits_per_engagement", p_rules.hits_per_engagement, 1, MAX_HITS_PER_ENGAGEMENT, r_error) &&
			check_range(owner, "anticipation_shift_cells", p_rules.anticipation_shift_cells, 0, MAX_MOVE_POINTS, r_error) &&
			check_range(owner, "help_radius_cells", p_rules.help_radius_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "max_leaders_per_side", p_rules.max_leaders_per_side, 1, MAX_SQUAD_SIZE, r_error) &&
			check_range(owner, "max_rounds", p_rules.max_rounds, 1, MAX_ROUNDS, r_error);
}

bool validate_map(const MapDef &p_map, std::string *r_error) {
	if (!check_range(p_map.id, "width", p_map.width, 1, MAX_MAP_CELLS_PER_AXIS, r_error) ||
			!check_range(p_map.id, "height", p_map.height, 1, MAX_MAP_CELLS_PER_AXIS, r_error)) {
		return false;
	}
	if (p_map.terrains.empty() || static_cast<int>(p_map.cell_terrain.size()) != p_map.width * p_map.height) {
		*r_error = p_map.id + " needs one terrain per cell (" + std::to_string(p_map.width * p_map.height) + ")";
		return false;
	}
	for (int terrain : p_map.cell_terrain) {
		if (terrain < 0 || terrain >= static_cast<int>(p_map.terrains.size())) {
			*r_error = p_map.id + " has terrain index " + std::to_string(terrain) + " out of range";
			return false;
		}
	}
	for (const TerrainDef &terrain : p_map.terrains) {
		if (!validate_terrain(terrain, r_error)) {
			return false;
		}
	}
	const bool is_objective_on_map = p_map.objective.col >= 0 && p_map.objective.col < p_map.width && p_map.objective.row >= 0 && p_map.objective.row < p_map.height;
	if (p_map.has_objective && !is_objective_on_map) {
		*r_error = p_map.id + " has its objective off the map";
		return false;
	}
	if (!is_direction(p_map.facing[SIDE_A]) || !is_direction(p_map.facing[SIDE_B])) {
		*r_error = p_map.id + " has a facing that is not one of (0,-1), (1,0), (0,1), (-1,0)";
		return false;
	}
	return check_range(p_map.id, "objective_side", p_map.objective_side, SIDE_A, SIDE_B, r_error);
}

bool validate_unit_def(const UnitDef &p_unit, std::string *r_error) {
	const bool are_stats_valid = check_range(p_unit.id, "max_hp", p_unit.max_hp, 1, MAX_STAT, r_error) &&
			check_range(p_unit.id, "attack", p_unit.attack, 0, MAX_STAT, r_error) &&
			check_range(p_unit.id, "armor", p_unit.armor, 0, MAX_STAT, r_error) &&
			check_range(p_unit.id, "magic_resist", p_unit.magic_resist, 0, MAX_STAT, r_error) &&
			check_range(p_unit.id, "min_range_cells", p_unit.min_range_cells, 1, MAX_RANGE_CELLS, r_error) &&
			check_range(p_unit.id, "max_range_cells", p_unit.max_range_cells, p_unit.min_range_cells, MAX_RANGE_CELLS, r_error) &&
			check_range(p_unit.id, "move_points", p_unit.move_points, 0, MAX_MOVE_POINTS, r_error);
	if (!are_stats_valid) {
		return false;
	}
	for (size_t index = 0; index < p_unit.keywords.size(); index++) {
		if (!validate_keyword(p_unit.id, p_unit.keywords[index], r_error)) {
			return false;
		}
		// A keyword listed twice would apply twice (charge +60%, heavy +2).
		for (size_t other = 0; other < index; other++) {
			if (p_unit.keywords[other].id == p_unit.keywords[index].id) {
				*r_error = p_unit.id + " lists keyword " + p_unit.keywords[index].id + " twice";
				return false;
			}
		}
	}
	return p_unit.role != UnitRole::LEADER || validate_leader_parts(p_unit, r_error);
}

} // namespace tactics
