#pragma once

// Plain C++ types of the synergy rules: class and race milestones, formation
// definitions, Hợp Lực tiers, and what an evaluation of one line-up gives.
// No Godot headers, no floats. Filled from data by the Synergy bridge and
// resolved by resolve_config() (synergy_validation.h).
// See Docs/systems/synergy.md.

#include "formation/formation_types.h"
#include "rules/modifier_handlers.h"

#include <string>
#include <vector>

namespace rules {

constexpr int NO_INDEX = formation::NO_INDEX;
constexpr int DEFAULT_LEVEL_STEP_PCT = 40;
constexpr int DEFAULT_MAX_FORMATION_LEVEL = 4;

// Who a modifier lands on.
enum class ModifierScope {
	// The units a milestone counts (its class or race).
	COUNTED,
	// Every unit of the side.
	SIDE,
	// A formation's members.
	MEMBERS,
	// Listed slots of a formation.
	SLOTS,
	// Units standing directly behind a member (next rank, same column).
	BEHIND_MEMBERS,
};

struct ModifierDef {
	// `mod.*` or `rule.*`.
	std::string handler_id;
	std::string scope_id;
	std::vector<int> slots;
	int value = 0;
	int count = 0;
	int ticks = 0;
	std::string param;
	// A side modifier repeated once per active formation (and lost with it).
	bool is_per_formation = false;
	// Filled by resolve_config(): exactly one of handler and rule is set.
	ModifierScope scope = ModifierScope::SIDE;
	const ModifierHandler *handler = nullptr;
	const RuleHandler *rule = nullptr;
	// mod.stat_add: the StatId.
	int stat = 0;
};

struct TierDef {
	// Count (milestones) or points (Hợp Lực) at which the tier turns on.
	int at = 1;
	std::vector<ModifierDef> modifiers;
};

enum class CountedKind {
	CLASS,
	RACE,
};

struct MilestoneDef {
	std::string id;
	CountedKind kind = CountedKind::CLASS;
	std::string counted_id;
	// Copies of one unit id count once.
	bool counts_distinct_units = false;
	// Units of this cost or more count twice; 0 never.
	int double_from_cost = 0;
	std::vector<TierDef> tiers;
	int counted_index = NO_INDEX;
};

struct FormationDef {
	std::string id;
	formation::PatternDef pattern;
	// Per slot: the class id it needs, empty for any. Resolved into the
	// pattern's slot class indexes.
	std::vector<std::string> slot_class_ids;
	std::vector<ModifierDef> modifiers;
};

struct HopLucDef {
	std::vector<TierDef> tiers;
	// Each formation level above 1 adds this percent to its values.
	int level_step_pct = DEFAULT_LEVEL_STEP_PCT;
	int max_level = DEFAULT_MAX_FORMATION_LEVEL;
};

struct SynergyConfig {
	std::vector<MilestoneDef> milestones;
	std::vector<FormationDef> formations;
	HopLucDef hop_luc;
	// Every class and race id the configuration names, by index.
	std::vector<std::string> class_ids;
	std::vector<std::string> race_ids;
	bool is_resolved = false;
};

struct MilestoneState {
	int milestone = 0;
	int count = 0;
	// Tiers reached (each one is a Hợp Lực point).
	int reached = 0;
};

struct FormationState {
	formation::Match match;
	int level = 1;
};

struct SynergyResult {
	// One per milestone of the configuration, in its order.
	std::vector<MilestoneState> milestones;
	std::vector<FormationState> formations;
	std::vector<formation::NearMiss> near_misses;
	int points = 0;
	// Index of the highest Hợp Lực tier reached, or NO_INDEX.
	int tier = NO_INDEX;
	// Points of the next tier, 0 at the top.
	int next_tier_at = 0;
};

enum class SourceKind {
	CLASS,
	RACE,
	FORMATION,
	HOP_LUC,
};

// One active thing that grants modifiers (a milestone tier, a formation
// instance, the Hợp Lực bonuses).
struct Source {
	SourceKind kind = SourceKind::CLASS;
	std::string id;
	// Milestones: the tier number (1..); formations: the level; Hợp Lực: points.
	int level = 0;
	// Milestones: the count the tier needs; others 0.
	int threshold = 0;
	std::vector<int> pieces;
	std::vector<formation::LocalCell> cells;
};

// One modifier for one piece. def points into the configuration.
struct Grant {
	int piece = 0;
	const ModifierDef *def = nullptr;
	// The value after formation level scaling.
	int value = 0;
	int source = 0;
	// The milestone, formation or `hop_luc` the modifier comes from.
	std::string origin_id;
};

} // namespace rules
