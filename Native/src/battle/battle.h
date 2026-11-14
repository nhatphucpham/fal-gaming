#pragma once

#include "battle_rules_data.h"
#include "battle_sim.h"
#include "class_data.h"
#include "unit_data.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// Godot face of one battle. It does not tick by itself: connect a SimClock's
// `ticked` signal to a function that calls step(), or call step() in a loop.
//   battle.set_rules(catalog.battle_rules)
//   for c in catalog.classes: battle.register_class(c)
//   battle.add_unit(Battle.SIDE_A, catalog.get_unit(&"unit.archer"), 1, 4, 4)
//   battle.start()
//   clock.ticked.connect(func(_tick: int) -> void: battle.step())
// Every state change comes out as an event (see Docs/systems/battle.md).
class Battle : public Node {
	GDCLASS(Battle, Node)

public:
	enum Side {
		SIDE_A = battle::SIDE_A,
		SIDE_B = battle::SIDE_B,
	};

private:
	battle::BattleSim sim;
	Ref<BattleRulesData> rules;
	bool log_enabled = false;

	void log_event(const battle::BattleEvent &p_event) const;

protected:
	static void _bind_methods();

public:
	// Must be called before add_unit(); clears nothing else.
	void set_rules(const Ref<BattleRulesData> &p_rules);
	Ref<BattleRulesData> get_rules() const { return rules; }
	// Validates the class's handler ids and stats; false with an error on bad data.
	bool register_class(const Ref<ClassData> &p_class);
	// Returns the unit's index, or -1 with an error.
	int add_unit(int p_side, const Ref<UnitData> &p_unit, int p_star, int p_local_col, int p_local_rank);
	// Back to an empty battle that has not started; classes and rules stay.
	void clear();
	// Freezes the setup; the first step() emits battle_started.
	void start();
	// Advances one tick; returns that tick's events as dictionaries and emits
	// them as signals.
	Array step();
	// Steps until the battle ends or max_ticks steps were taken, starting it
	// if needed; returns the final state hash.
	String run_to_end(int p_max_ticks);

	bool is_started() const { return sim.is_started(); }
	bool is_finished() const { return sim.is_finished(); }
	// -1 while the battle runs.
	int get_winner() const { return sim.get_winner(); }
	int get_tick() const { return sim.get_tick(); }
	// 16 hex digits.
	String get_state_hash() const;
	int get_unit_count() const { return static_cast<int>(sim.get_units().size()); }
	Dictionary get_unit_state(int p_index) const;
	Array get_units() const;

	void set_log_enabled(bool p_enabled) { log_enabled = p_enabled; }
	bool is_log_enabled() const { return log_enabled; }

	static Vector2i local_to_global(int p_side, int p_local_col, int p_local_rank);
	// Returns (local col, rank); the rank is outside 1..4 in the enemy half.
	static Vector2i global_to_local(int p_side, int p_col, int p_row);
};

} // namespace godot

VARIANT_ENUM_CAST(Battle::Side);
