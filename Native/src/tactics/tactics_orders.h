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
	// MAX_SQUAD_SIZE entries for FORMATION, nullptr otherwise. Earlier slots
	// are filled first; soldiers are matched to them by distance and role.
	const SlotOffset *slots;
	// FORMATION: the rules field with how far from its leader a soldier may
	// stand to strike or fall back; nullptr otherwise (no leash).
	int Rules::*leash_cells;
	// Its soldiers take a strike whose counter may kill them (vanguard).
	bool risks_soldiers;
};

// The order's index, or NO_INDEX when the id is not registered.
int find_order_index(const std::string &p_id);
// p_index is 0..get_order_count() - 1.
const OrderHandler &get_order_handler(int p_index);
int get_order_count();
// The squad's slot cells for the leader's current cell, heading and order,
// shifted along the heading when the leader kept it two moves in a row: the
// first slots of the order's table, one per living soldier; none for a dead
// leader or an order without formation.
std::vector<Cell> get_formation_slots(const TacticsSim &p_sim, int p_leader);
void move_squad(TacticsSim &p_sim, int p_leader, int p_cause);
void attack_with_squad(TacticsSim &p_sim, int p_leader, int p_cause);
// The enemy the soldier attacks now, or NO_UNIT (Docs/systems/tactics.md,
// Soldiers): never one whose counter kills it unless it kills the target or
// its order risks soldiers; first a kill, then one its squad can finish
// this step, then one that can reach its leader next phase, then the best
// damage trade, the lowest hp, the lowest index.
int pick_soldier_target(const TacticsSim &p_sim, int p_soldier);

} // namespace tactics
