#include "tactics_validation.h"

#include "tactics_incidents.h"
#include "tactics_orders.h"
#include "tactics_passives.h"
#include "tactics_sites.h"
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
	return check_range(p_terrain.id, "vision_bonus", p_terrain.vision_bonus, -MAX_VISION_CELLS, MAX_VISION_CELLS, r_error) &&
			check_range(p_terrain.id, "sight_block", p_terrain.sight_block, 0, MAX_VISION_CELLS, r_error) &&
			check_range(p_terrain.id, "light_cells", p_terrain.light_cells, 0, MAX_VISION_CELLS, r_error) &&
			check_range(p_terrain.id, "move_cost", p_terrain.move_cost, 1, MAX_MOVE_COST, r_error) &&
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

bool validate_trait(const UnitDef &p_unit, const TraitDef &p_trait, std::string *r_error) {
	if (p_trait.incident_ids.size() != p_trait.weight_pcts.size()) {
		*r_error = p_trait.id + " of " + p_unit.id + " needs one weight_pct per incident id";
		return false;
	}
	for (size_t index = 0; index < p_trait.incident_ids.size(); index++) {
		if (find_incident_handler(p_trait.incident_ids[index]) == nullptr) {
			*r_error = p_trait.id + " of " + p_unit.id + " names unknown incident " + p_trait.incident_ids[index];
			return false;
		}
		if (!check_range(p_trait.id, "weight_pct", p_trait.weight_pcts[index], -MAX_PERCENT_MODIFIER, MAX_INCIDENT_WEIGHT, r_error)) {
			return false;
		}
	}
	return true;
}

bool validate_incident(const IncidentDef &p_def, std::string *r_error) {
	if (p_def.handler == nullptr) {
		*r_error = "incident rules list unknown incident " + p_def.id;
		return false;
	}
	return check_range(p_def.id, "base_weight", p_def.base_weight, 0, MAX_INCIDENT_WEIGHT, r_error) &&
			check_range(p_def.id, "threshold_pct", p_def.threshold_pct, 0, MAX_PERCENT_MODIFIER, r_error) &&
			check_range(p_def.id, "threshold_count", p_def.threshold_count, 0, MAX_SQUAD_SIZE, r_error) &&
			check_range(p_def.id, "radius_cells", p_def.radius_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(p_def.id, "calm_radius_cells", p_def.calm_radius_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(p_def.id, "amount", p_def.amount, -MAX_PASSIVE_AMOUNT, MAX_PASSIVE_AMOUNT, r_error) &&
			check_range(p_def.id, "secondary_amount", p_def.secondary_amount, -MAX_PASSIVE_AMOUNT, MAX_PASSIVE_AMOUNT, r_error) &&
			check_range(p_def.id, "duration_rounds", p_def.duration_rounds, 0, MAX_DURATION_ROUNDS, r_error) &&
			check_range(p_def.id, "unseen_waver_pct", p_def.unseen_waver_pct, 0, MAX_PERCENT_MODIFIER, r_error);
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
	if (!check_range(p_unit.id, "trait count", static_cast<int>(p_unit.traits.size()), 0, MAX_TRAITS, r_error)) {
		return false;
	}
	for (const TraitDef &trait : p_unit.traits) {
		if (!validate_trait(p_unit, trait, r_error)) {
			return false;
		}
	}
	return !p_unit.has_skill || validate_skill(p_unit, r_error);
}

} // namespace

bool validate_incident_rules(const IncidentRules &p_rules, std::string *r_error) {
	const std::string owner = "incident rules";
	const bool are_numbers_valid = check_range(owner, "min_seeds", p_rules.min_seeds, 0, MAX_SQUAD_SIZE, r_error) &&
			check_range(owner, "max_seeds", p_rules.max_seeds, p_rules.min_seeds, MAX_SQUAD_SIZE, r_error) &&
			check_range(owner, "ai_min_seeds", p_rules.ai_min_seeds, 0, MAX_SQUAD_SIZE, r_error) &&
			check_range(owner, "ai_max_seeds", p_rules.ai_max_seeds, p_rules.ai_min_seeds, MAX_SQUAD_SIZE, r_error) &&
			check_range(owner, "marked_soldier_weight", p_rules.marked_soldier_weight, 0, MAX_INCIDENT_WEIGHT, r_error) &&
			check_range(owner, "mark_polarity_weight", p_rules.mark_polarity_weight, 0, MAX_INCIDENT_WEIGHT, r_error) &&
			check_range(owner, "karma_weight_per_point", p_rules.karma_weight_per_point, 0, MAX_INCIDENT_WEIGHT, r_error) &&
			check_range(owner, "karma_weight_cap", p_rules.karma_weight_cap, 0, MAX_INCIDENT_WEIGHT, r_error) &&
			check_range(owner, "bait_distance_cells", p_rules.bait_distance_cells, 1, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "rescue_hp_pct", p_rules.rescue_hp_pct, 0, MAX_PERCENT_MODIFIER, r_error);
	if (!are_numbers_valid) {
		return false;
	}
	for (size_t index = 0; index < p_rules.incidents.size(); index++) {
		if (!validate_incident(p_rules.incidents[index], r_error)) {
			return false;
		}
		for (size_t other = 0; other < index; other++) {
			if (p_rules.incidents[other].id == p_rules.incidents[index].id) {
				*r_error = "incident rules list " + p_rules.incidents[index].id + " twice";
				return false;
			}
		}
	}
	return true;
}

bool validate_rules(const Rules &p_rules, std::string *r_error) {
	const std::string owner = "rules";
	return check_range(owner, "hits_per_engagement", p_rules.hits_per_engagement, 1, MAX_HITS_PER_ENGAGEMENT, r_error) &&
			check_range(owner, "anticipation_shift_cells", p_rules.anticipation_shift_cells, 0, MAX_MOVE_POINTS, r_error) &&
			check_range(owner, "help_radius_cells", p_rules.help_radius_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "max_leaders_per_side", p_rules.max_leaders_per_side, 1, MAX_SQUAD_SIZE, r_error) &&
			check_range(owner, "max_rounds", p_rules.max_rounds, 1, MAX_ROUNDS, r_error) &&
			check_range(owner, "leash_follow_cells", p_rules.leash_follow_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "leash_vanguard_cells", p_rules.leash_vanguard_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "leash_flank_cells", p_rules.leash_flank_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "retreat_hp_pct", p_rules.retreat_hp_pct, 0, MAX_PERCENT_MODIFIER, r_error) &&
			check_range(owner, "shield_leader_hp_pct", p_rules.shield_leader_hp_pct, 0, MAX_PERCENT_MODIFIER, r_error) &&
			check_range(owner, "free_threat_limit", p_rules.free_threat_limit, 1, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "role_slot_weight", p_rules.role_slot_weight, 0, MAX_PERCENT_MODIFIER, r_error) &&
			check_range(owner, "ai_strength_radius_cells", p_rules.ai_strength_radius_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "ai_attack_ratio_pct", p_rules.ai_attack_ratio_pct, 0, MAX_RATIO_PCT, r_error) &&
			check_range(owner, "ai_advance_ratio_pct", p_rules.ai_advance_ratio_pct, 0, MAX_RATIO_PCT, r_error) &&
			check_range(owner, "ai_hold_radius_cells", p_rules.ai_hold_radius_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "leader_light_cells", p_rules.leader_light_cells, 0, MAX_VISION_CELLS, r_error) &&
			check_range(owner, "intent_read_cells", p_rules.intent_read_cells, 0, MAX_MAP_CELLS_PER_AXIS * 2, r_error) &&
			check_range(owner, "reveal_cells", p_rules.reveal_cells, 1, MAX_VISION_CELLS, r_error) &&
			check_range(owner, "attack_reveal_phases", p_rules.attack_reveal_phases, 0, MAX_DURATION_ROUNDS, r_error);
}

namespace {

bool validate_weather(const WeatherDef &p_weather, std::string *r_error) {
	const std::string owner = p_weather.id.empty() ? std::string("weather") : p_weather.id;
	if (p_weather.wind != Cell{ 0, 0 } && !is_direction(p_weather.wind)) {
		*r_error = owner + " has a wind that is not one step along an axis";
		return false;
	}
	return check_range(owner, "vision_delta", p_weather.vision_delta, -MAX_VISION_CELLS, MAX_VISION_CELLS, r_error) &&
			check_range(owner, "ranged_range_delta", p_weather.ranged_range_delta, -MAX_RANGE_CELLS, MAX_RANGE_CELLS, r_error) &&
			check_range(owner, "burn_pct", p_weather.burn_pct, 0, MAX_RATIO_PCT, r_error) &&
			check_range(owner, "cost_delta", p_weather.cost_delta, 0, MAX_MOVE_COST, r_error) &&
			check_range(owner, "wind_range_delta", p_weather.wind_range_delta, 0, MAX_RANGE_CELLS, r_error) &&
			check_range(owner, "waver_pct", p_weather.waver_pct, 0, MAX_PERCENT_MODIFIER, r_error);
}

} // namespace

bool validate_environment(const EnvironmentDef &p_environment, std::string *r_error) {
	if (!validate_weather(p_environment.weather, r_error) || (p_environment.has_weather_change && !validate_weather(p_environment.weather_after, r_error))) {
		return false;
	}
	if (p_environment.has_weather_change && !check_range("environment", "weather_change_round", p_environment.weather_change_round, 2, MAX_ROUNDS, r_error)) {
		return false;
	}
	const int count = static_cast<int>(p_environment.daytimes.size());
	if (!check_range("environment", "daytime_step_rounds", p_environment.daytime_step_rounds, 1, MAX_ROUNDS, r_error) ||
			!check_range("environment", "daytime_start_index", p_environment.daytime_start_index, 0, count > 0 ? count - 1 : 0, r_error)) {
		return false;
	}
	for (const DaytimeDef &daytime : p_environment.daytimes) {
		if (!check_range(daytime.id, "vision_delta", daytime.vision_delta, -MAX_VISION_CELLS, MAX_VISION_CELLS, r_error) ||
				!check_range(daytime.id, "waver_pct", daytime.waver_pct, 0, MAX_PERCENT_MODIFIER, r_error)) {
			return false;
		}
	}
	return true;
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
	for (const Cell &cell : p_map.guard_cells) {
		if (cell.col < 0 || cell.col >= p_map.width || cell.row < 0 || cell.row >= p_map.height) {
			*r_error = p_map.id + " has guard cell (" + std::to_string(cell.col) + ", " + std::to_string(cell.row) + ") off the map";
			return false;
		}
	}
	for (size_t index = 0; index < p_map.sites.size(); index++) {
		const SitePlacement &site = p_map.sites[index];
		if (!validate_site(site, p_map.width, p_map.height, r_error)) {
			return false;
		}
		for (size_t other = 0; other < index; other++) {
			if (p_map.sites[other].cell == site.cell) {
				*r_error = p_map.id + " has two sites on one cell";
				return false;
			}
		}
		for (const UnitDef &recruit : site.def.recruits) {
			if (recruit.role != UnitRole::SOLDIER || !validate_unit_def(recruit, r_error)) {
				*r_error = recruit.role != UnitRole::SOLDIER ? site.def.id + " offers a recruit that is not a soldier" : *r_error;
				return false;
			}
		}
		const bool is_leader_valid = !site.def.has_reinforcement || (site.def.reinforce_leader.role == UnitRole::LEADER && validate_unit_def(site.def.reinforce_leader, r_error));
		if (!is_leader_valid) {
			return false;
		}
		for (const UnitDef &soldier : site.def.reinforce_squad) {
			if (!validate_unit_def(soldier, r_error)) {
				return false;
			}
		}
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
			check_range(p_unit.id, "move_points", p_unit.move_points, 0, MAX_MOVE_POINTS, r_error) &&
			check_range(p_unit.id, "vision_cells", p_unit.vision_cells, 1, MAX_VISION_CELLS, r_error);
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
