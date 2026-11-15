#include "tactics_sim.h"

// The tactics battle's state hash: the rules and map, and everything that
// can change during a battle, so two replays of the same commands agree
// after every command.

namespace tactics {

namespace {

constexpr uint64_t FNV_OFFSET_BASIS = 14695981039346656037ULL;
constexpr uint64_t FNV_PRIME = 1099511628211ULL;

// Hashes the value as 8 little-endian bytes, independent of byte order.
void hash_value(uint64_t *r_hash, int64_t p_value) {
	const uint64_t bits = static_cast<uint64_t>(p_value);
	for (int byte = 0; byte < 8; byte++) {
		*r_hash ^= (bits >> (byte * 8)) & 0xFFu;
		*r_hash *= FNV_PRIME;
	}
}

void hash_text(uint64_t *r_hash, const std::string &p_text) {
	hash_value(r_hash, static_cast<int64_t>(p_text.size()));
	for (char character : p_text) {
		hash_value(r_hash, static_cast<unsigned char>(character));
	}
}

void hash_cell(uint64_t *r_hash, const Cell &p_cell) {
	hash_value(r_hash, p_cell.col);
	hash_value(r_hash, p_cell.row);
}

} // namespace

void TacticsSim::hash_unit(uint64_t *r_hash, const UnitState &p_unit) const {
	// Identity first: two setups with the same cells and hp but other unit
	// types or squads play differently.
	hash_text(r_hash, p_unit.def.id);
	hash_value(r_hash, p_unit.side);
	hash_value(r_hash, p_unit.leader);
	hash_value(r_hash, p_unit.is_alive ? 1 : 0);
	hash_value(r_hash, p_unit.hp);
	hash_cell(r_hash, p_unit.cell);
	hash_value(r_hash, p_unit.has_moved ? 1 : 0);
	hash_value(r_hash, p_unit.has_acted ? 1 : 0);
	hash_value(r_hash, p_unit.has_squad_acted ? 1 : 0);
	hash_value(r_hash, p_unit.straight_cells);
	hash_value(r_hash, p_unit.order);
	hash_cell(r_hash, p_unit.heading);
	hash_value(r_hash, p_unit.heading_streak);
	hash_value(r_hash, p_unit.skill_charge);
	hash_value(r_hash, p_unit.skill_area_bonus);
	hash_value(r_hash, p_unit.was_attacked_since_move ? 1 : 0);
	hash_value(r_hash, p_unit.last_attacker);
}

// Rules and map: other rules or terrain play differently from the same
// units on the same cells.
void TacticsSim::hash_setup(uint64_t *r_hash) const {
	hash_value(r_hash, rules.hits_per_engagement);
	hash_value(r_hash, rules.anticipation_shift_cells);
	hash_value(r_hash, rules.help_radius_cells);
	hash_value(r_hash, rules.max_leaders_per_side);
	hash_value(r_hash, rules.max_rounds);
	hash_text(r_hash, map.id);
	hash_value(r_hash, map.width);
	hash_value(r_hash, map.height);
	for (int terrain : map.cell_terrain) {
		hash_text(r_hash, map.terrains[terrain].id);
	}
	hash_value(r_hash, map.has_objective ? 1 : 0);
	hash_cell(r_hash, map.objective);
	hash_value(r_hash, map.objective_side);
	hash_cell(r_hash, map.facing[SIDE_A]);
	hash_cell(r_hash, map.facing[SIDE_B]);
}

uint64_t TacticsSim::get_state_hash() const {
	uint64_t hash = FNV_OFFSET_BASIS;
	hash_setup(&hash);
	hash_value(&hash, round);
	hash_value(&hash, turn);
	hash_value(&hash, active_side);
	hash_value(&hash, finished ? 1 : 0);
	hash_value(&hash, winner);
	hash_text(&hash, end_reason);
	hash_value(&hash, side_is_ai[SIDE_A] ? 1 : 0);
	hash_value(&hash, side_is_ai[SIDE_B] ? 1 : 0);
	// The next event's id: it numbers every later event and cause.
	hash_value(&hash, next_event_id);
	hash_value(&hash, static_cast<int64_t>(units.size()));
	for (const UnitState &unit : units) {
		hash_unit(&hash, unit);
	}
	hash_value(&hash, static_cast<int64_t>(zones.size()));
	for (const ZoneState &zone : zones) {
		hash_text(&hash, zone.def.id);
		hash_value(&hash, zone.side);
		hash_value(&hash, zone.source);
		hash_value(&hash, zone.end_round);
		hash_value(&hash, zone.end_turn);
		hash_value(&hash, static_cast<int64_t>(zone.cells.size()));
		for (const Cell &cell : zone.cells) {
			hash_cell(&hash, cell);
		}
	}
	hash_value(&hash, static_cast<int64_t>(buffs.size()));
	for (const BuffState &buff : buffs) {
		hash_value(&hash, buff.unit);
		hash_value(&hash, static_cast<int64_t>(buff.stat));
		hash_value(&hash, buff.amount);
		hash_value(&hash, buff.end_round);
		hash_value(&hash, buff.end_turn);
		hash_text(&hash, buff.source_id);
	}
	hash_value(&hash, static_cast<int64_t>(intents.size()));
	for (const Intent &intent : intents) {
		hash_value(&hash, intent.leader);
		hash_cell(&hash, intent.destination);
		hash_value(&hash, static_cast<int64_t>(intent.action));
		hash_value(&hash, intent.target);
		hash_cell(&hash, intent.target_cell);
	}
	return hash;
}

} // namespace tactics
