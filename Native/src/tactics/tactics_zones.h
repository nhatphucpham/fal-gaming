#pragma once

// Timed cell effects (`zone_effect.ranged_ward`, `zone_effect.burn`), looked
// up by id. A ZoneDef (Data/Tactics/Zones/) names its handler and amount;
// skills and passives create zones on cells for a number of rounds.

#include "tactics_keywords.h"
#include "tactics_state.h"

#include <string>

namespace tactics {

class TacticsSim;

// Which units a zone acts on, relative to the side that made it.
enum class ZoneAffects {
	ALLIES = 0,
	ENEMIES = 1,
};

struct ZoneHandler {
	const char *id;
	ZoneAffects affects;
	// Damage taken by a unit standing in the zone.
	void (*modify_incoming)(const ZoneDef &p_zone, const HitContext &p_context, HitModifiers &r_mods);
	// At the start of the phase of p_unit's side, for a unit in the zone.
	void (*on_phase_start)(TacticsSim &p_sim, const ZoneState &p_zone, int p_unit, int p_cause);
};

// nullptr when the id is not registered.
const ZoneHandler *find_zone_handler(const std::string &p_id);

bool is_cell_in_zone(const ZoneState &p_zone, const Cell &p_cell);
// The zone acts on p_unit: on its cell and on the side its handler affects.
bool does_zone_affect(const TacticsSim &p_sim, const ZoneState &p_zone, int p_unit);
// Applies every zone covering the defender's cell to one hit.
void apply_zones_to_hit(const TacticsSim &p_sim, const HitContext &p_context, HitModifiers &r_mods);

} // namespace tactics
