#pragma once

// Skill target selectors, looked up by id (`select.self`, ...): they pick
// the anchor cell a skill's area is laid around, or report that the skill
// has nothing to aim at. Also the board queries several skill blocks share.

#include "skill_types.h"

#include <string>
#include <vector>

namespace battle {

class BattleSim;
struct UnitState;

// Sets r_anchor and returns true, or returns false when no valid anchor
// exists (the caster keeps its Khí and tries again next tick).
using SelectAnchorFn = bool (*)(const BattleSim &p_sim, const UnitState &p_caster, const SkillStepDef &p_step, const AreaHandler *p_area, int p_area_size, Cell *r_anchor);

struct SelectorHandler {
	const char *id;
	SelectAnchorFn select;
};

// nullptr when the id is not registered.
const SelectorHandler *find_selector_handler(const std::string &p_id);

// Living enemies of p_side standing in the cells, in cell order.
std::vector<int> get_enemies_in_cells(const BattleSim &p_sim, int p_side, const std::vector<Cell> &p_cells);
// Living enemies of p_side in the column.
int count_enemies_in_column(const BattleSim &p_sim, int p_side, int p_col);
// The living enemy of p_side in the column nearest to p_side's own back
// row, or NO_UNIT.
int get_frontmost_enemy_in_column(const BattleSim &p_sim, int p_side, int p_col);
// The column with the most living enemies of p_caster; ties: nearest to the
// caster's column, then the caster's own left. -1 when no enemy lives.
int pick_column_most_enemies(const BattleSim &p_sim, const UnitState &p_caster);

} // namespace battle
