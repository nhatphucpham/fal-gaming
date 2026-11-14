#pragma once

// Skill area handlers, looked up by id (`area.square`, `area.front3`, ...):
// they turn an anchor cell into the cells a skill covers. Add one by writing
// a collect function and listing it in the table in the .cpp.

#include "battle/battle_basic_types.h"

#include <string>
#include <vector>

namespace battle {

// Appends the covered cells that lie on the board, in a fixed order.
// p_side is the caster's side (it decides "forward"); p_size is the area's
// size parameter.
using CollectCellsFn = void (*)(const Cell &p_anchor, int p_side, int p_size, std::vector<Cell> *r_cells);

struct AreaHandler {
	const char *id;
	CollectCellsFn collect;
};

// nullptr when the id is not registered.
const AreaHandler *find_area_handler(const std::string &p_id);

} // namespace battle
