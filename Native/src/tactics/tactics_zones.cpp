#include "tactics_zones.h"

#include "tactics_sim.h"

namespace tactics {

namespace {

// zone_effect.ranged_ward (wind): ranged hits on the maker's allies in the
// zone deal `amount` percent less.
void ranged_ward_incoming(const ZoneDef &p_zone, const HitContext &p_context, HitModifiers &r_mods) {
	if (p_context.kind == AttackKind::RANGED) {
		r_mods.taken_pct -= p_zone.amount;
	}
}

// zone_effect.burn (fire): `amount` damage, not mitigated, to each enemy of
// the maker standing in it at the start of that enemy's phase.
void burn_phase_start(TacticsSim &p_sim, const ZoneState &p_zone, int p_unit, int p_cause) {
	p_sim.deal_damage(p_zone.source, p_unit, p_zone.def.amount, p_zone.def.id, false, p_cause);
}

const ZoneHandler ZONE_HANDLERS[] = {
	{ "zone_effect.ranged_ward", ZoneAffects::ALLIES, ranged_ward_incoming, nullptr },
	{ "zone_effect.burn", ZoneAffects::ENEMIES, nullptr, burn_phase_start },
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

bool does_zone_affect(const TacticsSim &p_sim, const ZoneState &p_zone, int p_unit) {
	const UnitState &unit = p_sim.get_units()[p_unit];
	const bool is_ally = unit.side == p_zone.side;
	const bool is_wanted_side = p_zone.def.handler->affects == ZoneAffects::ALLIES ? is_ally : !is_ally;
	return is_wanted_side && is_cell_in_zone(p_zone, unit.cell);
}

void apply_zones_to_hit(const TacticsSim &p_sim, const HitContext &p_context, HitModifiers &r_mods, std::vector<std::string> *r_sources) {
	for (const ZoneState &zone : p_sim.get_zones()) {
		if (zone.def.handler->modify_incoming != nullptr && does_zone_affect(p_sim, zone, p_context.defender)) {
			const HitModifiers before = r_mods;
			zone.def.handler->modify_incoming(zone.def, p_context, r_mods);
			note_hit_source(r_sources, before, r_mods, zone.def.id);
		}
	}
}

} // namespace tactics
