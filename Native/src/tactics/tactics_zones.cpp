#include "tactics_zones.h"

#include "tactics_sim.h"

namespace tactics {

namespace {

// zone_effect.ranged_ward (wind): ranged hits into the zone deal `amount`
// percent less.
void ranged_ward_incoming(const ZoneDef &p_zone, const HitContext &p_context, HitModifiers &r_mods) {
	if (p_context.kind == AttackKind::RANGED) {
		r_mods.taken_pct -= p_zone.amount;
	}
}

// zone_effect.burn (fire): `amount` damage, not mitigated, to every unit
// standing in it at the start of its side's phase.
void burn_phase_start(TacticsSim &p_sim, const ZoneState &p_zone, int p_unit, int p_cause) {
	p_sim.deal_damage(p_zone.source, p_unit, p_zone.def.amount, p_zone.def.id, false, p_cause);
}

const ZoneHandler ZONE_HANDLERS[] = {
	{ "zone_effect.ranged_ward", ranged_ward_incoming, nullptr },
	{ "zone_effect.burn", nullptr, burn_phase_start },
};

} // namespace

const ZoneHandler *find_zone_handler(const std::string &p_id) {
	for (const ZoneHandler &handler : ZONE_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

bool is_cell_in_zone(const ZoneState &p_zone, const Cell &p_cell) {
	for (const Cell &cell : p_zone.cells) {
		if (cell == p_cell) {
			return true;
		}
	}
	return false;
}

void apply_zones_to_hit(const TacticsSim &p_sim, const HitContext &p_context, HitModifiers &r_mods) {
	const Cell &cell = p_sim.get_units()[p_context.defender].cell;
	for (const ZoneState &zone : p_sim.get_zones()) {
		if (zone.def.handler->modify_incoming != nullptr && is_cell_in_zone(zone, cell)) {
			zone.def.handler->modify_incoming(zone.def, p_context, r_mods);
		}
	}
}

} // namespace tactics
