#pragma once

// Modifier and rule handlers, looked up by id. A modifier (`mod.*`) is a
// battle effect: the battle sums or checks modifiers of one kind at a fixed
// hook point (Docs/systems/synergy.md lists them). A rule (`rule.*`) bends
// formation matching or levels instead and never reaches the battle. Add a
// modifier of an existing kind as data; a new kind needs a table entry here
// and its hook in the battle.

#include <string>

namespace rules {

enum class ModifierKind {
	STAT_ADD,
	BLOCK_FIRST_HIT,
	DAMAGE_DEALT_PCT,
	QI_ON_ATTACK,
	REFLECT_MELEE_PCT,
	RANGE_ADD_IF_FRONT,
	PIERCE_BEHIND,
	CHARGE_IMPACT_PCT,
	KNOCKBACK_CELLS,
	ATTACK_SPEED_PCT,
	FIRST_ATTACK_CRIT,
	ATTACK_SHAPE,
	SKILL_DAMAGE_PCT,
	RANGED_PHYSICAL_TAKEN_PCT,
	VOLLEY,
	CHARGE_SPEED_UNTIL_ATTACK,
	NTH_ATTACK_BONUS_PCT,
	CHARGE_IMMUNITY,
	DAMAGE_TAKEN_PCT,
	SPLIT_FIRST_HIT,
	START_QI,
	MAX_HP_PCT,
	QI_ON_ALLY_KILL,
};

// The stat a `mod.stat_add` raises (its param).
enum class StatId {
	ARMOR = 0,
	MAGIC_RESIST = 1,
};

enum class RuleKind {
	// +value formation levels when at least `count` members are of the
	// milestone's race; the biggest one applies.
	FORMATION_LEVEL,
	// A `count`-unit formation may miss one member when a unit of the
	// milestone's race holds its middle slot.
	FORMATION_MISSING_MIDDLE,
	// A `count`-unit formation may miss any one member.
	FORMATION_MISSING_ANY,
};

struct ModifierHandler {
	const char *id;
	ModifierKind kind;
	// The modifier needs `param` (a stat name or a shape id).
	bool needs_param;
};

struct RuleHandler {
	const char *id;
	RuleKind kind;
};

// nullptr when the id is not registered.
const ModifierHandler *find_modifier_handler(const std::string &p_id);
const RuleHandler *find_rule_handler(const std::string &p_id);
// False for an unknown stat name (`armor`, `magic_resist`).
bool find_stat_id(const std::string &p_name, StatId *r_stat);

} // namespace rules
