#pragma once

// Timed cell effects (`zone_effect.ranged_ward`, `zone_effect.burn`), looked
// up by id. A ZoneDef (Data/Tactics/Zones/) names its handler and amount;
// skills and passives create zones on cells for a number of rounds.

#include "tactics_keywords.h"
#include "tactics_state.h"

#include <string>

namespace tactics {

struct ZoneHandler {
	const char *id;
	// Damage taken by a unit standing in the zone.
	void (*modify_incoming)(const ZoneDef &p_zone, const HitContext &p_context, HitModifiers &r_mods);
	// At the start of the phase of p_unit's side, for a unit in the zone.
	void (*on_phase_start)(TacticsSim &p_sim, const ZoneState &p_zone, int p_unit, int p_cause);
};

// nullptr when the id is not registered.
const ZoneHandler *find_zone_handler(const std::string &p_id);

bool is_cell_in_zone(const ZoneState &p_zone, const Cell &p_cell);
// Applies every zone covering the defender's cell to one hit.
void apply_zones_to_hit(const TacticsSim &p_sim, const HitContext &p_context, HitModifiers &r_mods);

} // namespace tactics
