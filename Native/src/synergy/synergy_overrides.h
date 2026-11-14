#pragma once

#include "rules/synergy_types.h"

#include <godot_cpp/variant/array.hpp>

#include <string>

namespace godot {

// Kỳ Ngộ overrides: per-run changes to one side's milestones, given as data
// (Dictionaries) so the prep screen (Synergy.evaluate) and the battle
// (Battle.set_synergy_overrides) build the same configuration. Each entry:
//   {"milestone": &"milestone.class_shield", "tier": 1, "at": 3}
//   {"milestone": &"milestone.class_archer", "tier": 0, "modifiers": [ModifierData, ...]}
// `tier` is the tier's index; `at` (optional) replaces its threshold and
// `modifiers` (optional) replaces its modifiers. See Docs/systems/epiphany.md.
// Copies p_base, applies the overrides and resolves the result; false and
// r_error on an unknown milestone or tier, a bad entry, or tiers out of order.
bool apply_synergy_overrides(const rules::SynergyConfig &p_base, const Array &p_overrides, rules::SynergyConfig *r_config, std::string *r_error);

} // namespace godot
