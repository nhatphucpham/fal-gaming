#pragma once

// Plain data of the tactics simulation: cells, directions, rules and the
// definitions (terrain, keywords, zones, passives, skills, units) the bridge
// copies out of Data/Tactics/. No Godot headers, no floating point.

#include "battle/battle_basic_types.h"

#include <string>
#include <vector>

namespace tactics {

constexpr int NO_UNIT = -1;
constexpr int NO_WINNER = -1;
constexpr int NO_INDEX = -1;
constexpr int SIDE_A = 0;
constexpr int SIDE_B = 1;
constexpr int SIDE_COUNT = 2;

using DamageKind = battle::DamageKind;

// A map cell: col 0..width-1, row 0..height-1 (row 0 at the top).
struct Cell {
	int col = 0;
	int row = 0;
};

// "No cell", for an intent without a target.
constexpr Cell NO_CELL = { -1, -1 };

inline bool operator==(const Cell &p_a, const Cell &p_b) {
	return p_a.col == p_b.col && p_a.row == p_b.row;
}

inline bool operator!=(const Cell &p_a, const Cell &p_b) {
	return !(p_a == p_b);
}

inline Cell operator+(const Cell &p_a, const Cell &p_b) {
	return { p_a.col + p_b.col, p_a.row + p_b.row };
}

inline int abs_int(int p_value) {
	return p_value < 0 ? -p_value : p_value;
}

inline int get_manhattan(const Cell &p_a, const Cell &p_b) {
	return abs_int(p_a.col - p_b.col) + abs_int(p_a.row - p_b.row);
}

inline int get_chebyshev(const Cell &p_a, const Cell &p_b) {
	const int cols = abs_int(p_a.col - p_b.col);
	const int rows = abs_int(p_a.row - p_b.row);
	return cols > rows ? cols : rows;
}

// The four headings; a heading is a unit step (col, row).
constexpr int DIRECTION_COUNT = 4;
const Cell DIRECTIONS[DIRECTION_COUNT] = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } };

enum class UnitRole {
	LEADER = 0,
	SOLDIER = 1,
};

enum class AttackKind {
	MELEE = 0,
	RANGED = 1,
	SKILL = 2,
};

// Every tuning number of the turn loop, from Data/Tactics/Rules/.
struct Rules {
	int hits_per_engagement = 4;
	int anticipation_shift_cells = 1;
	int help_radius_cells = 4;
	int max_leaders_per_side = 5;
	int max_rounds = 30;
	// Soldier brains (Docs/systems/tactics.md, Soldiers): how far from its
	// leader a soldier may step out to strike, per formation order.
	int leash_follow_cells = 2;
	int leash_vanguard_cells = 4;
	int leash_flank_cells = 4;
	// A soldier at or under this % of its hp falls back.
	int retreat_hp_pct = 35;
	// A leader at or under this % of its hp with an enemy in reach gets a
	// shield.
	int shield_leader_hp_pct = 50;
	// A `free` soldier does not end its step where this many enemies can
	// reach it (more than allies next to it) unless it fights there.
	int free_threat_limit = 2;
	// Weight of a soldier's role (ranged rear, sturdy front) against the
	// walking distance (10 per cell) when slots are shared out.
	int role_slot_weight = 12;
	// The AI of the side that defends an objective (Docs/systems/tactics.md,
	// AI): it strikes where its hp within this radius of the strike is at
	// least ai_attack_ratio_pct % of the enemy's hp around the target,
	// leaves its posts once its whole side's hp is at least
	// ai_advance_ratio_pct % of the enemy's, and holds within
	// ai_hold_radius_cells of its post until then.
	int ai_strength_radius_cells = 4;
	int ai_attack_ratio_pct = 100;
	int ai_advance_ratio_pct = 120;
	int ai_hold_radius_cells = 1;
};

struct KeywordHandler;
struct IncidentHandler;
struct ZoneHandler;
struct PassiveHandler;
struct ChargeHandler;
struct SkillTargetHandler;
struct SkillEffectHandler;

struct TerrainDef {
	std::string id;
	int move_cost = 1;
	bool is_impassable = false;
	int armor_bonus = 0;
	// Signed percents: +25 means 25% more damage taken, -30 means 30% less.
	int damage_taken_pct = 0;
	int ranged_damage_taken_pct = 0;
	// Extra max range for a ranged unit standing here.
	int ranged_range_bonus = 0;
};

struct KeywordDef {
	std::string id;
	const KeywordHandler *handler = nullptr;
	int amount = 0;
	int min_cells = 0;
	std::vector<std::string> terrain_ids;
};

struct ZoneDef {
	std::string id;
	const ZoneHandler *handler = nullptr;
	int amount = 0;
};

enum class StatKind {
	NONE = 0,
	ATTACK_PCT,
	ARMOR,
	MAGIC_RESIST,
	MOVE_POINTS,
	MAX_RANGE,
};

struct PassiveDef {
	std::string id;
	const PassiveHandler *handler = nullptr;
	StatKind stat = StatKind::NONE;
	int amount = 0;
	std::string condition_terrain_id;
	int condition_adjacent_allies = 0;
	bool has_keyword = false;
	KeywordDef keyword;
	int extra_capacity = 0;
	bool has_zone = false;
	ZoneDef zone;
	int radius_cells = 0;
	int duration_rounds = 0;
};

struct SkillEffectDef {
	const SkillEffectHandler *handler = nullptr;
	std::string handler_id;
	int coefficient_pct = 100;
	DamageKind damage_kind = DamageKind::PHYSICAL;
	int amount_pct = 0;
	int duration_rounds = 0;
	bool has_zone = false;
	ZoneDef zone;
};

struct SkillDef {
	std::string id;
	const ChargeHandler *charge = nullptr;
	std::string charge_id;
	int charge_threshold = 1;
	const SkillTargetHandler *target = nullptr;
	int cast_range_cells = 1;
	int area_radius_cells = 0;
	int chain_count = 1;
	int chain_jump_cells = 1;
	int chain_falloff_pct = 0;
	std::vector<SkillEffectDef> effects;
};

// A leader trait (`trait.strict`): percent changes to the odds of the
// incidents seeded in its soldiers, one per incident id.
struct TraitDef {
	std::string id;
	std::vector<std::string> incident_ids;
	std::vector<int> weight_pcts;
};

// One incident (Biến cố) a seed can grow into; the handler gives the rules
// and polarity, these numbers tune it (Docs/systems/tactics.md, Incidents).
struct IncidentDef {
	std::string id;
	const IncidentHandler *handler = nullptr;
	int base_weight = 0;
	// The AI side's soldiers may carry it.
	bool seeds_ai_side = false;
	int threshold_pct = 0;
	int threshold_count = 0;
	int radius_cells = 0;
	// A living leader this close at the end of the phase calms it; 0 never.
	int calm_radius_cells = 0;
	int amount = 0;
	int secondary_amount = 0;
	int duration_rounds = 0;
};

// Seeds, odds and karma; `enabled` is false for a battle without incidents.
struct IncidentRules {
	bool enabled = false;
	int min_seeds = 1;
	int max_seeds = 3;
	int ai_min_seeds = 0;
	int ai_max_seeds = 2;
	int marked_soldier_weight = 3;
	int mark_polarity_weight = 10;
	int karma_weight_per_point = 5;
	int karma_weight_cap = 60;
	int bait_distance_cells = 4;
	int rescue_hp_pct = 50;
	std::vector<IncidentDef> incidents;
};

// One leader or soldier type, stats already derived from its base class.
struct UnitDef {
	std::string id;
	std::string base_unit_id;
	UnitRole role = UnitRole::SOLDIER;
	int max_hp = 1;
	int attack = 0;
	int armor = 0;
	int magic_resist = 0;
	DamageKind damage_kind = DamageKind::PHYSICAL;
	bool is_ranged = false;
	int min_range_cells = 1;
	int max_range_cells = 1;
	int move_points = 1;
	std::vector<KeywordDef> keywords;
	// Leaders only.
	int lead_capacity = 0;
	int default_order = 0;
	std::vector<PassiveDef> passives;
	bool has_skill = false;
	SkillDef skill;
	std::vector<TraitDef> traits;
};

struct MapDef {
	std::string id;
	int width = 0;
	int height = 0;
	std::vector<TerrainDef> terrains;
	// Index into terrains, row-major.
	std::vector<int> cell_terrain;
	bool has_objective = false;
	Cell objective;
	// The side that wins by holding the objective with a leader.
	int objective_side = SIDE_A;
	// Starting headings, one of DIRECTIONS.
	Cell facing[SIDE_COUNT] = { { 0, -1 }, { 0, 1 } };
	// Posts the side that defends the objective holds while it is weaker.
	std::vector<Cell> guard_cells;
};

} // namespace tactics
