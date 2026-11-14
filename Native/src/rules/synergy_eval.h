#pragma once

// Evaluates one side's line-up against a resolved synergy configuration:
// milestone counts, formations (with race rules and levels), near-misses and
// Hợp Lực; then turns everything active into per-piece modifier grants. The
// prep screen (Synergy.evaluate) and the battle (at start) call the same
// functions, so what the player sees is what the battle applies.
//   rules::SynergyResult result = rules::evaluate(config, pieces);
//   rules::collect_grants(config, result, pieces, &sources, &grants);

#include "synergy_types.h"

#include <vector>

namespace rules {

// The config must be resolved. Pieces in local coordinates of one side.
SynergyResult evaluate(const SynergyConfig &p_config, const std::vector<formation::Piece> &p_pieces);

// One source per milestone tier reached, per formation instance and (when a
// tier is reached) one for Hợp Lực; one grant per modifier and piece. A unit
// gets a formation's modifier only once even when it is in reach of two
// instances of that formation (the first one, in match order).
void collect_grants(const SynergyConfig &p_config, const SynergyResult &p_result, const std::vector<formation::Piece> &p_pieces, std::vector<Source> *r_sources, std::vector<Grant> *r_grants);

// A formation value at a level: value * (100 + step * (level - 1)) / 100.
int scale_by_level(int p_value, int p_level, int p_step_pct);

} // namespace rules
