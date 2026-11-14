#pragma once

// Charges: the cavalry opening and the Đột Trận skill share one runner. A
// charging unit runs forward one cell per Rules::charge_ticks_per_cell toward
// its lane target and stops in the cell in front of it (or diagonally in
// front); spears may strike it first (passive brace), its own passive may add
// momentum, then it hits and knocks the enemy back one cell. See
// Docs/systems/battle.md (Openings) and Docs/systems/skill.md.

#include "skill_types.h"

namespace battle {

class BattleSim;

// Makes p_state the unit's charge. A skill charge also ends the opening.
void begin_charge(BattleSim &p_sim, int p_unit, const ChargeState &p_state);
// Moves the unit (a charge move of p_ticks) to the free cell of column p_col
// nearest to it on its own side of that column's frontmost enemy; ties go
// to the cell further from that enemy. Stays put when there is none.
void reposition_for_column(BattleSim &p_sim, int p_unit, int p_col, int p_ticks, int p_cause);
// One action of an active charge: wait for the move, run a cell, or impact.
void advance_charge(BattleSim &p_sim, int p_unit);
// The enemy a charge from the unit's cell runs at: the nearest enemy ahead in
// its own column; else the nearest ahead in the column to either side (ties:
// the unit's own left first). NO_UNIT when there is none or an ally stands
// in the unit's column before the cell where the charge would stop.
int pick_lane_target(const BattleSim &p_sim, int p_unit);

} // namespace battle
