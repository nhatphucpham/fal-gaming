#pragma once

// Plain C++ types of formation matching: shapes on one side's line-up in
// local coordinates (col 1..7, rank 1..4, rank 1 = front). No Godot headers,
// no floats, so the prep screen and the battle get the same answer on every
// device. See Docs/systems/formation.md.

#include <string>
#include <vector>

namespace formation {

constexpr int COLS = 7;
constexpr int RANKS = 4;
constexpr int NO_INDEX = -1;
// A slot whose class is ANY accepts every class.
constexpr int ANY = -1;
constexpr int MAX_SLOTS = 6;

struct PatternHandler;

struct LocalCell {
	int col = 0;
	int rank = 0;
};

inline bool operator==(const LocalCell &p_a, const LocalCell &p_b) {
	return p_a.col == p_b.col && p_a.rank == p_b.rank;
}

// One unit of the line-up. Class and race are indexes into the id tables of
// the synergy configuration (NO_INDEX for an id nothing refers to).
struct Piece {
	int col = 1;
	int rank = 1;
	int class_index = NO_INDEX;
	int race_index = NO_INDEX;
	std::string unit_id;
	int cost = 1;
};

// One member position of a pattern, relative to the anchor (slot 0 sits at
// the anchor). drank grows toward the back.
struct Slot {
	int dcol = 0;
	int drank = 0;
	int class_index = ANY;
};

// A shape and its parameters. The handler turns it into candidate
// placements; the matcher (formation_match.h) fills them with pieces.
struct PatternDef {
	std::string handler_id;
	std::vector<Slot> slots;
	// 0: any column / rank; otherwise the anchor must stand there.
	int anchor_col = 0;
	int anchor_rank = 0;
	// Also try the shape flipped left to right.
	bool is_mirrored = false;
	// Every member must have a different class.
	bool needs_distinct_classes = false;
	// The slot a wolf-folk unit must hold to complete a 3-unit formation
	// with one member missing; NO_INDEX when the pattern has none.
	int middle_slot = NO_INDEX;
	const PatternHandler *handler = nullptr;
};

// A formation may match with one slot empty when one of these holds.
struct MissingRule {
	// Applies to patterns with exactly this many slots.
	int slot_count = 0;
	// NO_INDEX: any slot may be missing. Otherwise the pattern's middle slot
	// must hold a unit of this race (and may not be the missing one).
	int middle_race_index = NO_INDEX;
};

struct MatchOptions {
	std::vector<MissingRule> missing_rules;
};

// One formation instance found on the line-up.
struct Match {
	int formation = 0;
	// Per slot: the piece index, or NO_INDEX for the missing slot.
	std::vector<int> pieces;
	// Per slot: the cell (the missing slot's cell too).
	std::vector<LocalCell> cells;
	int missing_slot = NO_INDEX;
};

// A formation that one more unit on a free cell would complete.
struct NearMiss {
	int formation = 0;
	std::vector<int> pieces;
	std::vector<LocalCell> cells;
	int missing_slot = NO_INDEX;
	// The class the free cell needs, or ANY.
	int needed_class = ANY;
};

} // namespace formation
