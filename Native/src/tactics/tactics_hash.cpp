#include "tactics_sim.h"

// The tactics battle's state hash: the rules and map, and everything that
// can change during a battle, so two replays of the same commands agree
// after every command.

namespace tactics {

namespace {

constexpr uint64_t FNV_OFFSET_BASIS = 14695981039346656037ULL;
constexpr uint64_t FNV_PRIME = 1099511628211ULL;

// Hashes the value as 8 little-endian bytes, independent of byte order.
void hash_value(uint64_t *r_hash, int64_t p_value) {
	const uint64_t bits = static_cast<uint64_t>(p_value);
	for (int byte = 0; byte < 8; byte++) {
		*r_hash ^= (bits >> (byte * 8)) & 0xFFu;
		*r_hash *= FNV_PRIME;
	}
}

void hash_text(uint64_t *r_hash, const std::string &p_text) {
	hash_value(r_hash, static_cast<int64_t>(p_text.size()));
	for (char character : p_text) {
		hash_value(r_hash, static_cast<unsigned char>(character));
	}
}

void hash_cell(uint64_t *r_hash, const Cell &p_cell) {
	hash_value(r_hash, p_cell.col);
	hash_value(r_hash, p_cell.row);
}

} // namespace

void TacticsSim::hash_unit(uint64_t *r_hash, const UnitState &p_unit) const {
	// Identity first: two setups with the same cells and hp but other unit
	// types or squads play differently.
	hash_text(r_hash, p_unit.def.id);
	hash_value(r_hash, p_unit.side);
	hash_value(r_hash, p_unit.leader);
	hash_value(r_hash, p_unit.is_alive ? 1 : 0);
	hash_value(r_hash, p_unit.hp);
	hash_cell(r_hash, p_unit.cell);
	hash_value(r_hash, p_unit.has_moved ? 1 : 0);
	hash_value(r_hash, p_unit.has_attacked ? 1 : 0);
	hash_value(r_hash, p_unit.has_cast ? 1 : 0);
	hash_value(r_hash, p_unit.has_waited ? 1 : 0);
	hash_value(r_hash, p_unit.has_squad_struck ? 1 : 0);
	hash_value(r_hash, p_unit.has_rescued ? 1 : 0);
	hash_value(r_hash, p_unit.move_points_left);
	hash_value(r_hash, p_unit.is_held_by_zoc ? 1 : 0);
	hash_value(r_hash, p_unit.straight_cells);
	hash_cell(r_hash, p_unit.last_step);
	hash_value(r_hash, p_unit.order);
	hash_cell(r_hash, p_unit.heading);
	hash_value(r_hash, p_unit.heading_streak);
	hash_cell(r_hash, p_unit.phase_start_cell);
	hash_cell(r_hash, p_unit.phase_start_heading);
	hash_value(r_hash, p_unit.phase_start_streak);
	hash_value(r_hash, p_unit.skill_charge);
	hash_value(r_hash, p_unit.skill_area_bonus);
	hash_value(r_hash, p_unit.was_attacked_since_move ? 1 : 0);
	hash_value(r_hash, p_unit.last_attacker);
	hash_value(r_hash, p_unit.record_id);
	hash_value(r_hash, p_unit.good_marks);
	hash_value(r_hash, p_unit.bad_marks);
	hash_value(r_hash, p_unit.start_side);
	hash_value(r_hash, p_unit.seed);
	hash_value(r_hash, static_cast<int64_t>(p_unit.stage));
	hash_value(r_hash, p_unit.has_fled ? 1 : 0);
	hash_value(r_hash, p_unit.bait_count);
	hash_value(r_hash, p_unit.last_baited_turn);
	hash_value(r_hash, p_unit.ally_fell_turn);
	hash_value(r_hash, p_unit.guard_leader);
	hash_value(r_hash, p_unit.guard_end_turn);
	hash_value(r_hash, p_unit.hold_end_turn);
	hash_value(r_hash, p_unit.free_end_turn);
	hash_value(r_hash, p_unit.revealed_end_turn);
	hash_value(r_hash, p_unit.is_unseen_waver ? 1 : 0);
	hash_value(r_hash, p_unit.def.vision_cells);
	hash_value(r_hash, p_unit.has_used_site ? 1 : 0);
	hash_value(r_hash, p_unit.has_escaped ? 1 : 0);
	hash_text(r_hash, p_unit.arrival_kind);
	hash_value(r_hash, static_cast<int64_t>(p_unit.soldiers.size()));
	for (int soldier : p_unit.soldiers) {
		hash_value(r_hash, soldier);
	}
	hash_value(r_hash, static_cast<int64_t>(p_unit.marks.size()));
	for (const MarkState &mark : p_unit.marks) {
		hash_value(r_hash, mark.incident);
		hash_text(r_hash, mark.leader_id);
		hash_text(r_hash, mark.terrain_id);
		hash_cell(r_hash, mark.cell);
		hash_value(r_hash, mark.round);
	}
}

// Incident rules, the generator and karma: the same units with other odds
// or another seed play differently.
void TacticsSim::hash_incidents(uint64_t *r_hash) const {
	hash_value(r_hash, incident_rules.enabled ? 1 : 0);
	hash_value(r_hash, static_cast<int64_t>(incident_seed));
	hash_value(r_hash, static_cast<int64_t>(random.state));
	for (const IncidentDef &incident : incident_rules.incidents) {
		hash_text(r_hash, incident.id);
		for (int value : { incident.base_weight, incident.seeds_ai_side ? 1 : 0, incident.threshold_pct, incident.threshold_count, incident.radius_cells,
					 incident.calm_radius_cells, incident.amount, incident.secondary_amount, incident.duration_rounds }) {
			hash_value(r_hash, value);
		}
	}
	for (int value : { incident_rules.min_seeds, incident_rules.max_seeds, incident_rules.ai_min_seeds, incident_rules.ai_max_seeds, incident_rules.marked_soldier_weight,
				 incident_rules.mark_polarity_weight, incident_rules.karma_weight_per_point, incident_rules.karma_weight_cap, incident_rules.bait_distance_cells,
				 incident_rules.rescue_hp_pct }) {
		hash_value(r_hash, value);
	}
	for (int side = 0; side < SIDE_COUNT; side++) {
		for (int kind = 0; kind < 2; kind++) {
			hash_value(r_hash, carried_karma[side][kind]);
			hash_value(r_hash, battle_karma[side][kind]);
		}
	}
	hash_value(r_hash, static_cast<int64_t>(forced_seeds.size()));
	for (const std::pair<int, int> &forced : forced_seeds) {
		hash_value(r_hash, forced.first);
		hash_value(r_hash, forced.second);
	}
}

// Rules and map: other rules or terrain play differently from the same
// units on the same cells.
void TacticsSim::hash_setup(uint64_t *r_hash) const {
	hash_value(r_hash, rules.hits_per_engagement);
	hash_value(r_hash, rules.anticipation_shift_cells);
	hash_value(r_hash, rules.help_radius_cells);
	hash_value(r_hash, rules.max_leaders_per_side);
	hash_value(r_hash, rules.max_rounds);
	for (int value : { rules.leash_follow_cells, rules.leash_vanguard_cells, rules.leash_flank_cells, rules.retreat_hp_pct, rules.shield_leader_hp_pct, rules.free_threat_limit,
				 rules.role_slot_weight, rules.ai_strength_radius_cells, rules.ai_attack_ratio_pct, rules.ai_advance_ratio_pct, rules.ai_hold_radius_cells }) {
		hash_value(r_hash, value);
	}
	hash_text(r_hash, map.id);
	hash_value(r_hash, map.width);
	hash_value(r_hash, map.height);
	for (int terrain : map.cell_terrain) {
		hash_text(r_hash, map.terrains[terrain].id);
	}
	hash_value(r_hash, map.has_objective ? 1 : 0);
	hash_cell(r_hash, map.objective);
	hash_value(r_hash, map.objective_side);
	hash_cell(r_hash, map.facing[SIDE_A]);
	hash_cell(r_hash, map.facing[SIDE_B]);
	hash_value(r_hash, static_cast<int64_t>(map.guard_cells.size()));
	for (const Cell &cell : map.guard_cells) {
		hash_cell(r_hash, cell);
	}
}

// The environment (it decides vision, ranges and costs) and what each side
// remembers; what it sees now follows from the rest of the state.
void TacticsSim::hash_vision(uint64_t *r_hash) const {
	hash_value(r_hash, environment.fog_of_war ? 1 : 0);
	hash_text(r_hash, environment.weather.id);
	hash_value(r_hash, environment.has_weather_change ? environment.weather_change_round : 0);
	hash_text(r_hash, environment.has_weather_change ? environment.weather_after.id : std::string());
	hash_value(r_hash, static_cast<int64_t>(environment.daytimes.size()));
	for (const DaytimeDef &daytime : environment.daytimes) {
		hash_text(r_hash, daytime.id);
	}
	hash_value(r_hash, environment.daytime_step_rounds);
	hash_value(r_hash, environment.daytime_start_index);
	for (const SideVision &side : vision) {
		hash_value(r_hash, static_cast<int64_t>(side.seen.size()));
		for (uint8_t value : side.seen) {
			hash_value(r_hash, value);
		}
		hash_value(r_hash, static_cast<int64_t>(side.last_seen.size()));
		for (const Cell &cell : side.last_seen) {
			hash_cell(r_hash, cell);
		}
	}
}

namespace {

void hash_site(uint64_t *r_hash, const SiteState &p_site) {
	for (int value : { static_cast<int>(p_site.status), p_site.owner, p_site.uses, p_site.capture_side, p_site.capture_progress, p_site.owned_round,
				 p_site.has_reinforced ? 1 : 0, p_site.burned_by, p_site.is_known ? 1 : 0 }) {
		hash_value(r_hash, value);
	}
}

} // namespace

// The sites placed (their ids and cells), their state and what each side
// remembers of them; the objective and where it stands.
void TacticsSim::hash_sites(uint64_t *r_hash) const {
	hash_value(r_hash, static_cast<int64_t>(map.sites.size()));
	for (size_t index = 0; index < map.sites.size(); index++) {
		hash_text(r_hash, map.sites[index].def.id);
		hash_cell(r_hash, map.sites[index].cell);
		hash_site(r_hash, sites[index]);
	}
	for (const std::vector<SiteState> &memory : site_memory) {
		hash_value(r_hash, static_cast<int64_t>(memory.size()));
		for (const SiteState &site : memory) {
			hash_site(r_hash, site);
		}
	}
	hash_text(r_hash, objective.id);
	for (int value : { objective.site, objective.rounds, objective.count, objective.required_leader, objective.general, objective.flee_hp_pct, convoy_unit,
				 convoy_holds ? 1 : 0, general_unit, general_fleeing ? 1 : 0, waves_sent, supplies[SIDE_A], supplies[SIDE_B] }) {
		hash_value(r_hash, value);
	}
	hash_cell(r_hash, general_post);
	hash_value(r_hash, static_cast<int64_t>(met_goals.size()));
	for (int goal : met_goals) {
		hash_value(r_hash, goal);
	}
}

uint64_t TacticsSim::get_state_hash() const {
	uint64_t hash = FNV_OFFSET_BASIS;
	hash_setup(&hash);
	hash_value(&hash, round);
	hash_value(&hash, turn);
	hash_value(&hash, active_side);
	hash_value(&hash, finished ? 1 : 0);
	hash_value(&hash, winner);
	hash_text(&hash, end_reason);
	hash_value(&hash, side_is_ai[SIDE_A] ? 1 : 0);
	hash_value(&hash, side_is_ai[SIDE_B] ? 1 : 0);
	// The next event's id: it numbers every later event and cause.
	hash_value(&hash, next_event_id);
	hash_incidents(&hash);
	hash_vision(&hash);
	hash_value(&hash, static_cast<int64_t>(units.size()));
	for (const UnitState &unit : units) {
		hash_unit(&hash, unit);
	}
	hash_value(&hash, static_cast<int64_t>(zones.size()));
	for (const ZoneState &zone : zones) {
		hash_text(&hash, zone.def.id);
		hash_value(&hash, zone.side);
		hash_value(&hash, zone.source);
		hash_value(&hash, zone.end_round);
		hash_value(&hash, zone.end_turn);
		hash_value(&hash, static_cast<int64_t>(zone.cells.size()));
		for (const Cell &cell : zone.cells) {
			hash_cell(&hash, cell);
		}
	}
	hash_value(&hash, static_cast<int64_t>(buffs.size()));
	for (const BuffState &buff : buffs) {
		hash_value(&hash, buff.unit);
		hash_value(&hash, static_cast<int64_t>(buff.stat));
		hash_value(&hash, buff.amount);
		hash_value(&hash, buff.end_round);
		hash_value(&hash, buff.end_turn);
		hash_text(&hash, buff.source_id);
	}
	hash_sites(&hash);
	// Only a battle with bonds set hashes them, so older replays keep theirs.
	if (bonds_enabled) {
		hash_value(&hash, bond_rules.radius_cells);
		hash_value(&hash, bond_rules.attack_pct_per_level);
		hash_value(&hash, bond_rules.max_level);
		hash_value(&hash, static_cast<int64_t>(bonds.size()));
		for (const BondDef &bond : bonds) {
			hash_value(&hash, bond.unit_a);
			hash_value(&hash, bond.unit_b);
			hash_value(&hash, bond.level);
		}
		hash_value(&hash, static_cast<int64_t>(bond_tallies.size()));
		for (const BondTally &tally : bond_tallies) {
			hash_value(&hash, tally.unit_a);
			hash_value(&hash, tally.unit_b);
			hash_value(&hash, tally.phases);
		}
	}
	hash_value(&hash, static_cast<int64_t>(intents.size()));
	for (const Intent &intent : intents) {
		hash_value(&hash, intent.site);
		hash_value(&hash, intent.leader);
		hash_cell(&hash, intent.destination);
		hash_value(&hash, static_cast<int64_t>(intent.action));
		hash_value(&hash, intent.target);
		hash_cell(&hash, intent.target_cell);
	}
	return hash;
}

} // namespace tactics
