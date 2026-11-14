#include "battle_sim.h"

// The battle's state hash: everything that changes during a battle, so two
// runs of the same line-ups agree tick by tick (Docs/systems/battle.md).

namespace battle {

namespace {

constexpr uint64_t FNV_OFFSET_BASIS = 14695981039346656037ULL;
constexpr uint64_t FNV_PRIME = 1099511628211ULL;

// Hashes the value as 8 little-endian bytes, so the result does not depend
// on the platform's byte order.
void hash_value(uint64_t *r_hash, int64_t p_value) {
	const uint64_t bits = static_cast<uint64_t>(p_value);
	for (int byte = 0; byte < 8; byte++) {
		*r_hash ^= (bits >> (byte * 8)) & 0xFFu;
		*r_hash *= FNV_PRIME;
	}
}

void hash_cells(uint64_t *r_hash, const std::vector<Cell> &p_cells) {
	hash_value(r_hash, static_cast<int64_t>(p_cells.size()));
	for (const Cell &cell : p_cells) {
		hash_value(r_hash, cell.col);
		hash_value(r_hash, cell.row);
	}
}

} // namespace

uint64_t BattleSim::get_state_hash() const {
	uint64_t hash = FNV_OFFSET_BASIS;
	hash_value(&hash, tick);
	hash_value(&hash, finished ? 1 : 0);
	hash_value(&hash, winner);
	for (const UnitState &unit : units) {
		hash_value(&hash, unit.is_alive ? 1 : 0);
		hash_value(&hash, unit.hp);
		hash_value(&hash, unit.cell.col);
		hash_value(&hash, unit.cell.row);
		hash_value(&hash, unit.attack_charge);
		hash_value(&hash, get_move_ticks_left(unit));
		hash_value(&hash, unit.target);
		hash_value(&hash, unit.has_seen_target_in_range ? 1 : 0);
		hash_value(&hash, unit.target_out_of_range_ticks);
		hash_value(&hash, unit.no_path_ticks);
		hash_value(&hash, unit.is_opening_active ? 1 : 0);
		hash_value(&hash, unit.max_hp);
		hash_value(&hash, unit.basic_attacks);
		hash_value(&hash, unit.range_bonus);
		hash_skill_state(&hash, unit);
	}
	hash_synergy_state(&hash);
	hash_value(&hash, static_cast<int64_t>(scheduled_steps.size()));
	for (const ScheduledStep &step : scheduled_steps) {
		hash_value(&hash, step.tick);
		hash_value(&hash, step.caster);
		hash_cells(&hash, step.cells);
	}
	return hash;
}

void BattleSim::hash_skill_state(uint64_t *r_hash, const UnitState &p_unit) const {
	const UnitSkillState &skills = p_unit.skills;
	hash_value(r_hash, skills.qi);
	hash_value(r_hash, skills.cast.is_casting ? skills.cast.end_tick - tick : -1);
	hash_cells(r_hash, skills.cast.cells);
	hash_value(r_hash, skills.charge.is_active ? 1 : 0);
	hash_value(r_hash, skills.charge.is_skill ? 1 : 0);
	hash_value(r_hash, skills.charge.cells_run);
	hash_value(r_hash, skills.charge.columns_left);
	hash_value(r_hash, skills.passive.trigger_count);
	hash_value(r_hash, skills.passive.fire_count);
	hash_value(r_hash, static_cast<int64_t>(skills.passive.used_sources));
	hash_value(r_hash, static_cast<int64_t>(skills.passive.window_hits.size()));
	for (int hit : skills.passive.window_hits) {
		hash_value(r_hash, tick - hit);
	}
	for (const StatusSlot &slot : skills.statuses) {
		hash_value(r_hash, slot.is_active ? slot.end_tick - tick : -1);
		hash_value(r_hash, slot.is_active ? slot.amount : 0);
		hash_value(r_hash, slot.is_active ? slot.source : NO_UNIT);
	}
}

void BattleSim::hash_synergy_state(uint64_t *r_hash) const {
	hash_value(r_hash, static_cast<int64_t>(sources.size()));
	for (const SynergySource &source : sources) {
		hash_value(r_hash, source.is_active ? 1 : 0);
		hash_value(r_hash, source.is_split_used ? 1 : 0);
		hash_value(r_hash, source.level);
	}
	hash_value(r_hash, static_cast<int64_t>(modifiers.size()));
	for (const ActiveModifier &modifier : modifiers) {
		hash_value(r_hash, modifier.unit);
		hash_value(r_hash, static_cast<int64_t>(modifier.kind));
		hash_value(r_hash, modifier.value);
		hash_value(r_hash, modifier.uses);
	}
}

} // namespace battle
