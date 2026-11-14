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

// One damage event through the pipeline (basic attacks, skills, passives).
struct DamageSpec {
	int source = NO_UNIT;
	int victim = NO_UNIT;
	int coefficient_pct = 100;
	DamageKind kind = DamageKind::PHYSICAL;
	int increase_pct = 0;
	bool is_crit = false;
	// Empty for basic attacks; the skill or passive id otherwise.
	std::string skill_id;
	int blocked_by = NO_UNIT;
	int cause = 0;
	// A melee basic attack: counts for passives that react to melee hits.
	bool is_melee_attack = false;
};

class BattleSim {
	struct RegisteredClass {
		ClassDef def;
		const TargetingHandler *targeting = nullptr;
		const ShapeHandler *shape = nullptr;
		const OpeningHandler *opening = nullptr;
	};

	Rules rules;
	bool has_rules = false;
	struct UnitLoadout {
		SkillDef skill;
		PassiveDef passive;
	};

	std::vector<RegisteredClass> classes;
	std::vector<UnitState> units;
	// Parallel to units: the skill and passive each unit uses.
	std::vector<UnitLoadout> loadouts;
	std::vector<ScheduledStep> scheduled_steps;
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
	void apply_hit(int p_attacker, int p_victim, int p_blocked_by, int p_attack_event, bool p_is_crit, int p_increase_pct);
	void react_to_damage(const DamageSpec &p_spec, int p_damage_event);
	void kill(int p_victim, int p_killer, int p_damage_event);
	void hash_skill_state(uint64_t *r_hash, const UnitState &p_unit) const;
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
	// FNV-1a 64 over the tick, the result and, in index order, every unit
	// field that changes during the battle (see Docs/systems/battle.md).
	uint64_t get_state_hash() const;
	const std::vector<UnitState> &get_units() const { return units; }
	const ClassDef &get_class_def(const UnitState &p_unit) const;

	// Handler API.
	const Board &get_board() const { return board; }
	// A move started at tick t with duration d ends at tick t + d, when the
	// unit can act again: one cell takes exactly d ticks.
	bool is_moving(const UnitState &p_unit) const;
	int get_move_ticks_left(const UnitState &p_unit) const;
	bool is_in_range(const UnitState &p_unit, const UnitState &p_target) const;
	bool has_enemy_in_range(const UnitState &p_unit) const;
	bool is_targeted_by_enemy(int p_unit) const;
	void deactivate_opening(int p_unit);
	// Keeps a target in range. Otherwise picks again among enemies in range
	// if there are any; else keeps the target unless it died or was lost for
	// longer than target_lost_ticks.
	void update_target(int p_unit);
	// True when the target is in range; then attacks if the charge is full
	// and spends it.
	bool attack_if_ready(int p_unit);
	// Attacks without using the attack charge; returns the attack event id.
	// p_increase_pct adds to the damage increase group (charge momentum).
	int perform_attack(int p_unit, int p_target, int p_cause, int p_increase_pct = 0);
	// Starts a move into a free neighbour cell; returns the move event id.
	int start_move(int p_unit, const Cell &p_to, int p_duration_ticks, MoveKind p_kind, int p_cause);
	int emit_event(BattleEvent p_event);

	// Skill API, used by Native/src/skill/.
	// The unit's skill state (Khí, cast, statuses, passive counters, charge).
	// Hp and cells change only through deal_damage() and start_move().
	UnitSkillState &edit_skill_state(int p_unit) { return units[p_unit].skills; }
	const SkillDef &get_skill(int p_unit) const { return loadouts[p_unit].skill; }
	const PassiveDef &get_passive(int p_unit) const { return loadouts[p_unit].passive; }
	// Applies one damage event: Khí for the victim, its passives, death.
	// Returns the damage event id, or 0 when the victim was already dead.
	int deal_damage(const DamageSpec &p_spec);
	// Pushes the unit into p_to when it is alive, can be pushed and the cell
	// is free; returns whether it moved.
	bool knock_back(int p_unit, const Cell &p_to, int p_cause);
	void schedule_step(const ScheduledStep &p_step) { scheduled_steps.push_back(p_step); }
	// Removes and returns the steps due at the current tick, in order.
	std::vector<ScheduledStep> take_due_steps();
};

} // namespace battle
