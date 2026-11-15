#pragma once

// Squad orders (`order.follow`, `order.vanguard`, `order.flank`,
// `order.hold`, `order.free`), looked up by id, and the soldiers' automatic
// step: every soldier moves (in squad order), then every soldier attacks.
// Add a formation order by adding its slot table and a registry line.

#include "tactics_types.h"

#include <string>
#include <vector>

namespace tactics {

class TacticsSim;

// A squad may hold at most this many soldiers (the slot tables' length).
constexpr int MAX_SQUAD_SIZE = 8;

enum class SquadMode {
	// Soldiers take the order's slots around the leader.
	FORMATION = 0,
	// Soldiers stay where they are.
	HOLD,
	// Soldiers ignore the leader and seek enemies on their own.
	FREE,
};

// A slot relative to the leader: cells forward along its heading and to
// its right.
struct SlotOffset {
	int forward;
	int right;
};

struct OrderHandler {
	const char *id;
	SquadMode mode;
	// MAX_SQUAD_SIZE entries for FORMATION, nullptr otherwise.
	const SlotOffset *slots;
};

// The order's index, or NO_INDEX when the id is not registered.
int find_order_index(const std::string &p_id);
const OrderHandler &get_order_handler(int p_index);
// The squad's slot cells for the leader's current cell, heading and order,
// shifted along the heading when the leader kept it two moves in a row.
std::vector<Cell> get_formation_slots(const TacticsSim &p_sim, int p_leader);
void move_squad(TacticsSim &p_sim, int p_leader, int p_cause);
void attack_with_squad(TacticsSim &p_sim, int p_leader, int p_cause);
// The enemy the soldier attacks now, or NO_UNIT: one that can hit its own
// leader first, then the lowest hp, then the lowest index.
int pick_soldier_target(const TacticsSim &p_sim, int p_soldier);

} // namespace tactics
