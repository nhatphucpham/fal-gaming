#pragma once

// Finds every formation instance on one side's line-up, and the formations
// one unit short of completion.
//   std::vector<formation::Match> matches;
//   std::vector<formation::NearMiss> near;
//   formation::match_formations(patterns, pieces, options, &matches, &near);
// Patterns are tried in list order. Within a pattern, placements are taken
// greedily in the handler's order, complete ones first, then ones a
// MissingRule completes; one pattern's instances never share a piece, but a
// piece may belong to instances of different patterns.

#include "formation_types.h"

#include <vector>

namespace formation {

// Patterns must be resolved (handler set). r_near may be nullptr.
void match_formations(const std::vector<PatternDef> &p_patterns, const std::vector<Piece> &p_pieces, const MatchOptions &p_options, std::vector<Match> *r_matches, std::vector<NearMiss> *r_near);

} // namespace formation
