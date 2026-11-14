#pragma once

// Checks skill and passive definitions and resolves their handler ids, once,
// when a class is registered or a unit with an override is added.

#include "skill_types.h"

#include <string>

namespace battle {

constexpr int MAX_QI_COST = 1000;
// Times the highest star multiplier (400%) this stays within the damage
// pipeline's 1000% coefficient cap, so no skill is silently clamped.
constexpr int MAX_EFFECT_VALUE = 250;
constexpr int MAX_EFFECT_TICKS = 10000;
constexpr int MAX_EFFECT_COUNT = 20;
constexpr int MAX_AREA_SIZE = 8;
constexpr int MAX_PASSIVE_EVERY_NTH = 100;
constexpr int MAX_PASSIVE_LIMIT = 100;

// Fills the handler pointers; false and r_error (naming the skill and
// field) on an unknown id or a value out of range.
bool resolve_skill(SkillDef *r_skill, std::string *r_error);
bool resolve_passive(PassiveDef *r_passive, std::string *r_error);

} // namespace battle
