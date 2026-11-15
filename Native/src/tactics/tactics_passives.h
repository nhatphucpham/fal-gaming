#pragma once

// Leader passives, looked up by handler id. Each handler belongs to one of
// five kinds (stat modifier, squad modifier, environment, special weapon,
// skill growth) and fills only the hooks it needs. Add one by writing its
// hooks and listing it in the registry in the .cpp; its numbers come from
// the PassiveDef (Data/Tactics/Passives/).

#include "tactics_types.h"

#include <string>
#include <vector>

namespace tactics {

class TacticsSim;

// Additions to a unit's base stats; attack is a percent, the rest flat.
struct StatModifiers {
	int attack_pct = 0;
	int armor = 0;
	int magic_resist = 0;
	int move_points = 0;
	int max_range_cells = 0;
};

void add_stat_modifier(StatKind p_stat, int p_amount, StatModifiers &r_mods);
// nullptr id or StatKind::NONE when unknown; ids are `stat.attack_pct`, ...
StatKind find_stat_kind(const std::string &p_id);
const char *get_stat_id(StatKind p_stat);

struct PassiveHandler {
	const char *id;
	// stat_modifier, squad_modifier, environment, special_weapon or skill_growth.
	const char *kind;
	// The handler reads PassiveDef::zone, so the passive must have one.
	bool needs_zone;
	void (*modify_own_stats)(const TacticsSim &p_sim, int p_unit, const Cell &p_cell, const PassiveDef &p_passive, StatModifiers &r_mods);
	void (*modify_soldier_stats)(const TacticsSim &p_sim, int p_soldier, const PassiveDef &p_passive, StatModifiers &r_mods);
	void (*grant_soldier_keywords)(const PassiveDef &p_passive, std::vector<const KeywordDef *> &r_keywords);
	int (*get_extra_capacity)(const PassiveDef &p_passive);
	void (*on_leader_moved)(TacticsSim &p_sim, int p_leader, const PassiveDef &p_passive, int p_cause);
	// After the leader's own attack (not counters, not soldiers' attacks).
	void (*after_basic_attack)(TacticsSim &p_sim, int p_leader, int p_target, const PassiveDef &p_passive, int p_cause);
	void (*on_enemy_defeated)(TacticsSim &p_sim, int p_leader, int p_victim, const PassiveDef &p_passive, int p_cause);
};

// nullptr when the id is not registered.
const PassiveHandler *find_passive_handler(const std::string &p_id);

} // namespace tactics
