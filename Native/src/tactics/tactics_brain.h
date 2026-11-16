#pragma once

// Judgement shared by soldiers, the AI and the leader's attack-cell query
// (Docs/systems/tactics.md, Soldiers): where the enemy can strike next
// phase, which fights are worth taking, and the strikes a unit could make
// after a walk, worked out on a scratch copy. Everything is a pure function
// of the battle state, so the squad preview and the real step agree.

#include "tactics_paths.h"
#include "tactics_state.h"

#include <functional>
#include <vector>

namespace tactics {

class TacticsSim;

// Per cell (row-major): how many living units not on p_side could attack a
// unit standing there in their next phase (a move with zones of control,
// then their range from where they stop). With r_watchers, also lists the
// units that reach p_watch.
std::vector<int> count_enemy_reach(const TacticsSim &p_sim, int p_side, const Cell &p_watch = NO_CELL, std::vector<int> *r_watchers = nullptr);
// The units not on p_side that could attack p_cell in their next phase.
std::vector<int> find_enemies_reaching(const TacticsSim &p_sim, int p_side, const Cell &p_cell);

// Damage the attacker's and the counter's hits do in a predicted engagement.
int get_dealt(const EngagementResult &p_result);
int get_taken(const EngagementResult &p_result);
// Worth taking: it kills, or the attacker lives and deals more than it takes.
bool is_favourable(const EngagementResult &p_result);

// A strike a unit could make after walking to a cell.
struct Strike {
	Cell cell;
	int target = NO_UNIT;
	// Path cost to the cell.
	int cost = 0;
	EngagementResult result;
};

// Every strike p_unit could make from a cell of p_field it may stop on (its
// own included) that p_allow accepts, against every enemy in range from
// there, predicted on one scratch copy with the unit moved there. Empty
// without a copy when no enemy is near enough.
std::vector<Strike> list_strikes(const TacticsSim &p_sim, int p_unit, const PathField &p_field, const std::function<bool(const Cell &)> &p_allow);

// The best of p_strikes against p_target for a leader: one that does not get
// it killed, then the fewest enemies able to reach the cell, the least
// counter damage, the better terrain, the shortest walk, the lower cell
// index. NO_CELL when none is against p_target.
Cell pick_safest_strike_cell(const TacticsSim &p_sim, const std::vector<Strike> &p_strikes, const std::vector<int> &p_reach, int p_target);

// How a cell's terrain suits the unit, -9..9: higher range or cover for a
// ranged unit, armor for anyone, minus for extra damage taken. It only
// breaks ties between cells as near as each other.
int get_terrain_fit(const TacticsSim &p_sim, int p_unit, const Cell &p_cell);

} // namespace tactics
