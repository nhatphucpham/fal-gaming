#pragma once

// Plain C++ types shared by the battle simulation. No Godot headers here: the
// simulation must build and replay without the engine. See Docs/systems/battle.md.

#include <cstdint>
#include <string>
#include <vector>

namespace battle {

constexpr int BOARD_COLS = 7;
constexpr int BOARD_ROWS = 8;
constexpr int SIDE_RANKS = 4;
constexpr int CENTER_COL = 3;
constexpr int NO_UNIT = -1;
constexpr int NO_WINNER = -1;

enum Side {
	SIDE_A = 0,
	SIDE_B = 1,
};

// A global board cell: col 0..6, row 0..7. Side A owns rows 0..3.
struct Cell {
	int col = 0;
	int row = 0;
};

inline bool operator==(const Cell &p_a, const Cell &p_b) {
	return p_a.col == p_b.col && p_a.row == p_b.row;
}

inline bool operator!=(const Cell &p_a, const Cell &p_b) {
	return !(p_a == p_b);
}

enum class DamageKind {
	PHYSICAL = 0,
	MAGIC = 1,
};

// Class definition as the simulation sees it. Handler ids are resolved
// against the registries when the class is registered.
struct ClassDef {
	std::string id;
	int max_hp = 1;
	int attack = 0;
	int attacks_per_100s = 1;
	int range_cells = 1;
	int armor = 0;
	int magic_resist = 0;
	DamageKind damage_kind = DamageKind::PHYSICAL;
	std::string targeting_id;
	std::string opening_id;
	std::string attack_shape_id;
	std::vector<std::string> counter_ids;
	bool is_ranged = false;
	bool blocks_arrows = false;
	bool immune_to_knockback = false;
	bool stops_charge = false;
};

// What add_unit needs to know about a unit's content.
struct UnitSpec {
	std::string unit_id;
	std::string class_id;
	int cost = 1;
	int star = 1;
};

struct UnitState {
	int index = 0;
	int side = SIDE_A;
	int class_index = 0;
	std::string unit_id;
	int cost = 1;
	int star = 1;
	bool is_alive = true;
	int hp = 0;
	int max_hp = 0;
	int attack = 0;
	// The unit occupies this cell from the moment a move into it starts.
	Cell cell;
	int attack_charge = 0;
	// The unit is moving while the tick is below this. Stored as an end tick
	// so a move lasts its duration whatever the action order.
	int move_end_tick = 0;
	int target = NO_UNIT;
	bool has_seen_target_in_range = false;
	int target_out_of_range_ticks = 0;
	int no_path_ticks = 0;
	bool is_opening_active = false;
};

enum class EventType {
	BATTLE_STARTED,
	UNIT_MOVED,
	UNIT_ATTACKED,
	DAMAGE_DEALT,
	UNIT_DIED,
	CHARGE_ENDED,
	BATTLE_ENDED,
};

enum class MoveKind {
	WALK,
	CHARGE,
	KNOCKBACK,
};

enum class AttackKind {
	MELEE,
	RANGED,
	MAGIC,
};

enum class EndReason {
	ELIMINATION,
	TIME_LIMIT,
};

// One state change. Only the fields of its type are meaningful; the bridge
// turns it into a Dictionary with the keys listed in Docs/systems/battle.md.
struct BattleEvent {
	int id = 0;
	int tick = 0;
	EventType type = EventType::BATTLE_STARTED;
	int cause = 0;
	int unit = NO_UNIT;
	int source = NO_UNIT;
	int target = NO_UNIT;
	int killer = NO_UNIT;
	int hit = NO_UNIT;
	int blocked_by = NO_UNIT;
	Cell from;
	Cell to;
	int duration_ticks = 0;
	MoveKind move_kind = MoveKind::WALK;
	AttackKind attack_kind = AttackKind::MELEE;
	int amount = 0;
	int hp_after = 0;
	bool is_counter = false;
	bool is_crit = false;
	int winner = NO_WINNER;
	EndReason reason = EndReason::ELIMINATION;
};

} // namespace battle
