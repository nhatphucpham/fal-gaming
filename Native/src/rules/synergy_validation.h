#pragma once

// Checks a synergy configuration and resolves its ids: handler ids to
// handlers, scope ids to scopes, class and race ids to indexes. Fails with
// a message naming the milestone, formation or tier and the field.

#include "synergy_types.h"

#include <string>

namespace rules {

constexpr int MAX_TIERS = 8;
constexpr int MAX_MODIFIER_VALUE = 1000;
constexpr int MAX_MODIFIER_COUNT = 100;
constexpr int MAX_MODIFIER_TICKS = 10000;
constexpr int MAX_LEVEL_STEP_PCT = 100;
constexpr int MAX_FORMATION_LEVEL = 10;

// Resolves r_config in place; false and r_error on the first problem.
bool resolve_config(SynergyConfig *r_config, std::string *r_error);

// Index of a class or race id in the configuration, NO_INDEX if unknown.
int find_class_index(const SynergyConfig &p_config, const std::string &p_class_id);
int find_race_index(const SynergyConfig &p_config, const std::string &p_race_id);

} // namespace rules
