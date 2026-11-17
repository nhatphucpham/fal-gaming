#pragma once

// Fog of war (Docs/systems/tactics_vision.md): what each side sees. A unit
// sees a cell when the sight cost of the line to it (the Manhattan distance
// plus the sight_block of every cell strictly between, on an integer
// Bresenham line) is within its vision radius: its vision_cells, plus its
// terrain's vision_bonus, plus the weather's and the time of day's changes.
// At night a lit cell is seen as far as by day. Units on terrain that
// hides them show only to enemies right next to them, to scouts, or after
// they attacked. Integer math only; the same state gives the same vision.

#include "tactics_state.h"

#include <cstdint>
#include <vector>

namespace tactics {

class TacticsSim;

// The sight cost from p_from to p_to; stops counting (and returns a value
// over p_limit) once it passes p_limit.
int get_sight_cost(const TacticsSim &p_sim, const Cell &p_from, const Cell &p_to, int p_limit);
// The unit's vision radius standing on p_cell now; p_by_day leaves the time
// of day out (how far it sees a lit cell). At least 1.
int get_vision_radius(const TacticsSim &p_sim, int p_unit, const Cell &p_cell, bool p_by_day);
// Cells lit now (row-major): around lit terrain and around living leaders.
std::vector<uint8_t> compute_lit_cells(const TacticsSim &p_sim);
// Marks in r_cells (row-major) every cell p_unit sees standing on p_from.
void mark_unit_sight(const TacticsSim &p_sim, int p_unit, const Cell &p_from, const std::vector<uint8_t> &p_lit, std::vector<uint8_t> &r_cells);
// The unit carries the scout keyword; its amount is how close it reads an
// enemy leader's intent at night or in fog (0 when not a scout).
bool is_scout(const TacticsSim &p_sim, int p_unit);
int get_scout_read_cells(const TacticsSim &p_sim, int p_unit);
// Fills visible, scout_visible and unit_visible of r_vision for p_side
// from the state now; leaves seen and last_seen alone.
void compute_side_vision(const TacticsSim &p_sim, int p_side, const std::vector<uint8_t> &p_lit, SideVision &r_vision);
// Whether p_viewer, standing where it is, sees p_cell now (lit cells too).
bool does_unit_see_cell(const TacticsSim &p_sim, int p_viewer, const Cell &p_cell);

} // namespace tactics
