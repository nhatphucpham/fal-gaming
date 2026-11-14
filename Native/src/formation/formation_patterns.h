#pragma once

// Pattern handlers, looked up by id (`pattern.shape`): each turns a
// PatternDef into the list of candidate placements, in the matching order
// (front rank first, then lower column, then the plain before the mirrored
// shape). Add one by writing a function and listing it in the table in
// formation_patterns.cpp.

#include "formation_types.h"

#include <string>
#include <vector>

namespace formation {

// One placement: the cell of each slot, all on the board.
using Placement = std::vector<LocalCell>;

using PlacementsFn = void (*)(const PatternDef &p_pattern, std::vector<Placement> *r_placements);

struct PatternHandler {
	const char *id;
	PlacementsFn collect_placements;
};

// nullptr when the id is not registered.
const PatternHandler *find_pattern_handler(const std::string &p_id);

bool is_local_cell_on_board(const LocalCell &p_cell);

} // namespace formation
