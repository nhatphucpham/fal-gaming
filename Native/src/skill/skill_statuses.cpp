#include "skill_statuses.h"

#include "battle/battle_sim.h"

#include <algorithm>

namespace battle {

namespace {

const char *const STATUS_IDS[STATUS_COUNT] = {
	"status.taunted",
	"status.guard",
	"status.armor_break",
	"status.stun",
	"status.petrified",
};

void emit_status_ended(BattleSim &p_sim, int p_unit, StatusKind p_kind, int p_cause) {
	BattleEvent event;
	event.type = EventType::STATUS_ENDED;
	event.unit = p_unit;
	event.status = p_kind;
	event.cause = p_cause;
	p_sim.emit_event(event);
}

} // namespace

const char *get_status_id(StatusKind p_kind) {
	return STATUS_IDS[static_cast<int>(p_kind)];
}

void apply_status(BattleSim &p_sim, int p_unit, StatusKind p_kind, int p_amount, int p_duration_ticks, int p_source, int p_cause) {
	if (!p_sim.get_units()[p_unit].is_alive || p_duration_ticks <= 0) {
		return;
	}
	StatusSlot &slot = p_sim.edit_skill_state(p_unit).statuses[static_cast<int>(p_kind)];
	const int end_tick = p_sim.get_tick() + p_duration_ticks;
	slot.end_tick = slot.is_active ? std::max(slot.end_tick, end_tick) : end_tick;
	slot.amount = slot.is_active ? std::max(slot.amount, p_amount) : p_amount;
	slot.source = p_source;
	slot.is_active = true;

	BattleEvent event;
	event.type = EventType::STATUS_APPLIED;
	event.unit = p_unit;
	event.status = p_kind;
	event.source = p_source;
	event.end_tick = slot.end_tick;
	event.amount = slot.amount;
	event.cause = p_cause;
	p_sim.emit_event(event);
}

void end_status(BattleSim &p_sim, int p_unit, StatusKind p_kind, int p_cause) {
	StatusSlot &slot = p_sim.edit_skill_state(p_unit).statuses[static_cast<int>(p_kind)];
	if (!slot.is_active) {
		return;
	}
	slot = StatusSlot();
	emit_status_ended(p_sim, p_unit, p_kind, p_cause);
}

void expire_statuses(BattleSim &p_sim) {
	const int unit_count = static_cast<int>(p_sim.get_units().size());
	for (int unit = 0; unit < unit_count; unit++) {
		for (int kind = 0; kind < STATUS_COUNT; kind++) {
			const StatusSlot &slot = p_sim.get_units()[unit].skills.statuses[kind];
			if (slot.is_active && p_sim.get_tick() >= slot.end_tick) {
				end_status(p_sim, unit, static_cast<StatusKind>(kind), 0);
			}
		}
	}
}

void end_taunts_from(BattleSim &p_sim, int p_source) {
	const int unit_count = static_cast<int>(p_sim.get_units().size());
	for (int unit = 0; unit < unit_count; unit++) {
		const StatusSlot &slot = p_sim.get_units()[unit].skills.statuses[static_cast<int>(StatusKind::TAUNTED)];
		if (slot.is_active && slot.source == p_source) {
			end_status(p_sim, unit, StatusKind::TAUNTED, 0);
		}
	}
}

bool has_status(const UnitState &p_unit, StatusKind p_kind) {
	return p_unit.skills.statuses[static_cast<int>(p_kind)].is_active;
}

int get_status_amount(const UnitState &p_unit, StatusKind p_kind) {
	const StatusSlot &slot = p_unit.skills.statuses[static_cast<int>(p_kind)];
	return slot.is_active ? slot.amount : 0;
}

int get_taunt_source(const BattleSim &p_sim, const UnitState &p_unit) {
	const StatusSlot &slot = p_unit.skills.statuses[static_cast<int>(StatusKind::TAUNTED)];
	if (!slot.is_active || slot.source == NO_UNIT || !p_sim.get_units()[slot.source].is_alive) {
		return NO_UNIT;
	}
	return slot.source;
}

} // namespace battle
