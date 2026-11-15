#pragma once

// Unit keywords (`keyword.long_weapon`, ...), looked up by id. A keyword is
// a set of optional hooks; add one by writing its hooks and listing it in
// the registry in the .cpp. Its numbers come from its KeywordDef (data).

#include "tactics_types.h"

#include <string>
#include <vector>

namespace tactics {

class TacticsSim;

// How a unit crosses the map; built from its keywords before a path search.
struct MoveProfile {
	bool ignores_terrain_cost = false;
	bool ignores_impassable = false;
	bool ignores_zone_of_control = false;
	// Extra cost to enter each terrain of the map, by terrain index.
	std::vector<int> extra_cost_by_terrain;
};

// One direction of an engagement or a skill hit, as the hooks see it.
struct HitContext {
	const TacticsSim *sim = nullptr;
	int attacker = NO_UNIT;
	int defender = NO_UNIT;
	AttackKind kind = AttackKind::MELEE;
	bool is_counter = false;
};

// Adjustments gathered before one hit's damage is computed.
struct HitModifiers {
	// The attacker's bonus damage, percent.
	int increase_pct = 0;
	// Signed: above 0 the defender takes more, below 0 less.
	int taken_pct = 0;
	int armor_break_pct = 0;
	// Strongest cover among adjacent allies (not summed).
	int cover_pct = 0;
};

struct KeywordHandler {
	const char *id;
	void (*modify_movement)(const KeywordDef &p_keyword, const MapDef &p_map, MoveProfile &r_profile);
	void (*modify_outgoing)(const KeywordDef &p_keyword, const HitContext &p_context, HitModifiers &r_mods);
	// Called for keywords of allies orthogonally next to the defender.
	void (*modify_incoming_as_ally)(const KeywordDef &p_keyword, const HitContext &p_context, HitModifiers &r_mods);
	// True: this defender's counter lands before the attacker's hits.
	bool (*strikes_first)(const KeywordDef &p_keyword, AttackKind p_incoming);
};

// nullptr when the id is not registered.
const KeywordHandler *find_keyword_handler(const std::string &p_id);

MoveProfile build_move_profile(const TacticsSim &p_sim, int p_unit);

} // namespace tactics
