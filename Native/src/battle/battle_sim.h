#pragma once

// BattleSim runs one battle tick by tick with integer math only, so the same
// setup gives the same events and state hash on every device.
//   BattleSim sim;
//   sim.set_rules(rules, &error);
//   sim.register_class(shield, &error);
//   sim.add_unit(SIDE_A, spec, 4, 1, &error);
//   sim.start(&error);
//   while (!sim.is_finished()) { sim.step(); }
// The handler section is the API that targeting, shape and opening handlers
// use; presentation code goes through the Battle node instead.

#include "battle_board.h"
#include "battle_rules.h"
#include "battle_types.h"

#include <cstdint>
#include <string>
#include <vector>

namespace battle {

struct TargetingHandler;
struct ShapeHandler;
struct OpeningHandler;

class BattleSim {
	struct RegisteredClass {
		ClassDef def;
		const TargetingHandler *targeting = nullptr;
		const ShapeHandler *shape = nullptr;
		const OpeningHandler *opening = nullptr;
	};

	Rules rules;
	bool has_rules = false;
	std::vector<RegisteredClass> classes;
	std::vector<UnitState> units;
	Board board;
	std::vector<BattleEvent> events;
	int tick = 0;
	int next_event_id = 1;
	bool started = false;
	bool finished = false;
	int winner = NO_WINNER;

	int find_class_index(const std::string &p_class_id) const;
	bool check_new_unit(int p_side, const UnitSpec &p_spec, int p_local_col, int p_local_rank, std::string *r_error) const;
	bool resolve_handlers(const ClassDef &p_def, RegisteredClass *r_class, std::string *r_error) const;
	std::vector<int> get_action_order() const;
	bool acts_before(const UnitState &p_a, const UnitState &p_b, int p_first_side) const;
	void act(int p_unit);
	void act_normally(int p_unit);
	void set_target(int p_unit, int p_target);
	void move_toward_target(int p_unit);
	int pick_nearest_reachable_enemy(int p_unit) const;
	bool find_step_toward(int p_unit, int p_target, Cell *r_step) const;
	void apply_hit(int p_attacker, int p_victim, int p_blocked_by, int p_attack_event);
	void kill(int p_victim, int p_killer, int p_damage_event);
	void check_end();
	void end_battle(int p_winner, EndReason p_reason);
	int get_time_limit_winner() const;

public:
	// Rules can change only while no unit has been added.
	bool set_rules(const Rules &p_rules, std::string *r_error);
	const Rules &get_rules() const { return rules; }
	// Adds or replaces a class by id. Fails on unknown handler ids or bad stats.
	bool register_class(const ClassDef &p_def, std::string *r_error);
	// Returns the new unit's index, or NO_UNIT and sets r_error.
	int add_unit(int p_side, const UnitSpec &p_spec, int p_local_col, int p_local_rank, std::string *r_error);
	// Removes all units and resets the clock; classes and rules stay.
	void clear();
	bool start(std::string *r_error);
	// Advances one tick and returns that tick's events (valid until the next
	// call). Does nothing before start or after the end.
	const std::vector<BattleEvent> &step();

	bool is_started() const { return started; }
	bool is_finished() const { return finished; }
	int get_winner() const { return winner; }
	int get_tick() const { return tick; }
	// FNV-1a 64 over the tick and each unit's alive, hp, cell, charge, move
	// timer and target, in index order.
	uint64_t get_state_hash() const;
	const std::vector<UnitState> &get_units() const { return units; }
	const ClassDef &get_class_def(const UnitState &p_unit) const;

	// Handler API.
	const Board &get_board() const { return board; }
	bool is_in_range(const UnitState &p_unit, const UnitState &p_target) const;
	bool has_enemy_in_range(const UnitState &p_unit) const;
	bool is_targeted_by_enemy(int p_unit) const;
	void deactivate_opening(int p_unit);
	// Keeps the current target or picks a new one (dead, or lost for longer
	// than target_lost_ticks).
	void update_target(int p_unit);
	// True when the target is in range; then attacks if the charge is full
	// and spends it.
	bool attack_if_ready(int p_unit);
	// Attacks without using the attack charge; returns the attack event id.
	int perform_attack(int p_unit, int p_target, int p_cause);
	// Starts a move into a free neighbour cell; returns the move event id.
	int start_move(int p_unit, const Cell &p_to, int p_duration_ticks, MoveKind p_kind, int p_cause);
	int emit_event(BattleEvent p_event);
};

} // namespace battle
