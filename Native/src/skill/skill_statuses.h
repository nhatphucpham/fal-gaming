#pragma once

// Timed statuses on units (taunted, guard, armor break, stun): applying,
// ending, expiring and reading them. Each is a slot on the unit with an end
// tick; applying an active one again keeps the later end and the larger
// amount and takes the new source.

#include "skill_types.h"

namespace battle {

class BattleSim;
struct UnitState;

// `status.taunted`, `status.guard`, ...
const char *get_status_id(StatusKind p_kind);
void apply_status(BattleSim &p_sim, int p_unit, StatusKind p_kind, int p_amount, int p_duration_ticks, int p_source, int p_cause);
// Ends an active status early (emits status_ended); nothing if inactive.
void end_status(BattleSim &p_sim, int p_unit, StatusKind p_kind, int p_cause);
// Ends every status whose end tick has come. Called at the start of a tick.
void expire_statuses(BattleSim &p_sim);
// Ends the taunts that p_source put on others (it died).
void end_taunts_from(BattleSim &p_sim, int p_source);

bool has_status(const UnitState &p_unit, StatusKind p_kind);
// The amount of an active status, or 0.
int get_status_amount(const UnitState &p_unit, StatusKind p_kind);
// The living unit taunting p_unit, or NO_UNIT.
int get_taunt_source(const BattleSim &p_sim, const UnitState &p_unit);

} // namespace battle
