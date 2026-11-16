#pragma once

// Range checks for the tactics rules, map and unit definitions. They run
// once when data enters the simulation; later code trusts the data.

#include "tactics_types.h"

#include <string>

namespace tactics {

constexpr int MAX_MAP_CELLS_PER_AXIS = 32;
constexpr int MAX_MOVE_COST = 20;
constexpr int MAX_STAT = 100000;
constexpr int MAX_RANGE_CELLS = 12;
constexpr int MAX_MOVE_POINTS = 20;
constexpr int MAX_PASSIVES = 3;
constexpr int MAX_PERCENT_MODIFIER = 100;
// Ratios between two amounts, such as the AI's strength ratios.
constexpr int MAX_RATIO_PCT = 1000;
constexpr int MAX_HITS_PER_ENGAGEMENT = 10;
constexpr int MAX_ROUNDS = 1000;
constexpr int MAX_DURATION_ROUNDS = 100;
// Keyword amounts (percents, extra move cost) and passive amounts.
constexpr int MAX_KEYWORD_AMOUNT = 1000;
constexpr int MAX_PASSIVE_AMOUNT = 1000;
// The battle damage pipeline clamps coefficients to this.
constexpr int MAX_COEFFICIENT_PCT = 1000;
constexpr int MAX_BUFF_PCT = 1000;
constexpr int MAX_ADJACENT_CELLS = 4;
constexpr int MAX_TRAITS = 2;
constexpr int MAX_INCIDENT_WEIGHT = 1000;
// Vision radii, terrain vision changes, sight blocks and lights.
constexpr int MAX_VISION_CELLS = 16;

bool validate_rules(const Rules &p_rules, std::string *r_error);
bool validate_map(const MapDef &p_map, std::string *r_error);
// Also checks the unit's keywords, passives and skill.
bool validate_unit_def(const UnitDef &p_unit, std::string *r_error);
// Seed counts, odds and every incident's numbers; each incident once.
bool validate_incident_rules(const IncidentRules &p_rules, std::string *r_error);
// Weathers (ranges, a wind along an axis), the weather change round and
// the times of day.
bool validate_environment(const EnvironmentDef &p_environment, std::string *r_error);

} // namespace tactics
