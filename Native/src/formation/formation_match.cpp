#include "formation_match.h"

#include "formation_patterns.h"

#include <array>

namespace formation {

namespace {

// Near-misses need this many members already standing, so a lone unit does
// not outline every 2-unit formation it could start.
constexpr int MIN_NEAR_MISS_MEMBERS = 2;

class Grid {
	std::array<int, (COLS + 1) * (RANKS + 1)> cells;

public:
	explicit Grid(const std::vector<Piece> &p_pieces) {
		cells.fill(NO_INDEX);
		for (int index = 0; index < static_cast<int>(p_pieces.size()); index++) {
			const LocalCell cell = { p_pieces[index].col, p_pieces[index].rank };
			// A doubled cell keeps its first piece.
			if (is_local_cell_on_board(cell) && at(cell) == NO_INDEX) {
				cells[cell.rank * (COLS + 1) + cell.col] = index;
			}
		}
	}

	int at(const LocalCell &p_cell) const {
		return cells[p_cell.rank * (COLS + 1) + p_cell.col];
	}
};

// One placement checked against the line-up.
struct SlotCheck {
	std::vector<int> pieces;
	int unsatisfied = 0;
	int last_unsatisfied = NO_INDEX;
	bool has_distinct_classes = true;
};

SlotCheck check_placement(const PatternDef &p_pattern, const Placement &p_cells, const std::vector<Piece> &p_pieces, const Grid &p_grid, const std::vector<bool> &p_used) {
	SlotCheck check;
	for (int slot = 0; slot < static_cast<int>(p_cells.size()); slot++) {
		const int piece = p_grid.at(p_cells[slot]);
		const int needed = p_pattern.slots[slot].class_index;
		const bool fits = piece != NO_INDEX && !p_used[piece] && (needed == ANY || p_pieces[piece].class_index == needed);
		check.pieces.push_back(fits ? piece : NO_INDEX);
		if (!fits) {
			check.unsatisfied++;
			check.last_unsatisfied = slot;
		}
	}
	if (p_pattern.needs_distinct_classes) {
		for (size_t a = 0; a < check.pieces.size(); a++) {
			for (size_t b = a + 1; b < check.pieces.size(); b++) {
				const int first = check.pieces[a];
				const int second = check.pieces[b];
				if (first != NO_INDEX && second != NO_INDEX && p_pieces[first].class_index == p_pieces[second].class_index) {
					check.has_distinct_classes = false;
				}
			}
		}
	}
	return check;
}

bool allows_missing(const PatternDef &p_pattern, const MatchOptions &p_options, const SlotCheck &p_check, const std::vector<Piece> &p_pieces) {
	const int slot_count = static_cast<int>(p_pattern.slots.size());
	for (const MissingRule &rule : p_options.missing_rules) {
		if (rule.slot_count != slot_count) {
			continue;
		}
		if (rule.middle_race_index == NO_INDEX) {
			return true;
		}
		const int middle = p_pattern.middle_slot;
		if (middle != NO_INDEX && middle != p_check.last_unsatisfied && p_check.pieces[middle] != NO_INDEX && p_pieces[p_check.pieces[middle]].race_index == rule.middle_race_index) {
			return true;
		}
	}
	return false;
}

void add_match(int p_formation, const Placement &p_cells, const SlotCheck &p_check, std::vector<bool> *r_used, std::vector<Match> *r_matches) {
	Match match;
	match.formation = p_formation;
	match.pieces = p_check.pieces;
	match.cells = p_cells;
	match.missing_slot = p_check.unsatisfied == 0 ? NO_INDEX : p_check.last_unsatisfied;
	for (int piece : p_check.pieces) {
		if (piece != NO_INDEX) {
			(*r_used)[piece] = true;
		}
	}
	r_matches->push_back(match);
}

void add_near_miss(int p_formation, const PatternDef &p_pattern, const Placement &p_cells, const SlotCheck &p_check, const Grid &p_grid, std::vector<NearMiss> *r_near) {
	const int missing = p_check.last_unsatisfied;
	const int needed = p_pattern.slots[missing].class_index;
	const int members = static_cast<int>(p_cells.size()) - 1;
	// The class must be nameable: a distinct-class slot open to any class is not.
	if (p_check.unsatisfied != 1 || !p_check.has_distinct_classes || members < MIN_NEAR_MISS_MEMBERS || p_grid.at(p_cells[missing]) != NO_INDEX || (needed == ANY && p_pattern.needs_distinct_classes)) {
		return;
	}
	for (const NearMiss &other : *r_near) {
		if (other.formation == p_formation && other.cells[other.missing_slot] == p_cells[missing]) {
			return;
		}
	}
	NearMiss near;
	near.formation = p_formation;
	near.pieces = p_check.pieces;
	near.cells = p_cells;
	near.missing_slot = missing;
	near.needed_class = needed;
	r_near->push_back(near);
}

void match_one(int p_formation, const PatternDef &p_pattern, const std::vector<Piece> &p_pieces, const Grid &p_grid, const MatchOptions &p_options, std::vector<Match> *r_matches, std::vector<NearMiss> *r_near) {
	std::vector<Placement> placements;
	p_pattern.handler->collect_placements(p_pattern, &placements);
	std::vector<bool> used(p_pieces.size(), false);
	for (const Placement &cells : placements) {
		const SlotCheck check = check_placement(p_pattern, cells, p_pieces, p_grid, used);
		if (check.unsatisfied == 0 && check.has_distinct_classes) {
			add_match(p_formation, cells, check, &used, r_matches);
		}
	}
	for (const Placement &cells : placements) {
		const SlotCheck check = check_placement(p_pattern, cells, p_pieces, p_grid, used);
		if (check.unsatisfied == 1 && check.has_distinct_classes && allows_missing(p_pattern, p_options, check, p_pieces)) {
			add_match(p_formation, cells, check, &used, r_matches);
		}
	}
	if (r_near == nullptr) {
		return;
	}
	for (const Placement &cells : placements) {
		add_near_miss(p_formation, p_pattern, cells, check_placement(p_pattern, cells, p_pieces, p_grid, used), p_grid, r_near);
	}
}

} // namespace

void match_formations(const std::vector<PatternDef> &p_patterns, const std::vector<Piece> &p_pieces, const MatchOptions &p_options, std::vector<Match> *r_matches, std::vector<NearMiss> *r_near) {
	const Grid grid(p_pieces);
	for (int index = 0; index < static_cast<int>(p_patterns.size()); index++) {
		if (p_patterns[index].handler != nullptr) {
			match_one(index, p_patterns[index], p_pieces, grid, p_options, r_matches, r_near);
		}
	}
}

} // namespace formation
