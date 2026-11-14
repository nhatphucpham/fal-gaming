#pragma once

#include "battle_rules_data.h"
#include "battle_sim.h"
#include "class_data.h"
#include "unit_data.h"

#include "synergy/synergy.h"

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
	Ref<Synergy> synergy;
	bool log_enabled = false;
	// True while signals for a tick are emitted; commands that change the
	// battle are refused then, so a handler cannot re-enter step().
	bool is_emitting = false;

	void log_event(const battle::BattleEvent &p_event) const;

protected:
	static void _bind_methods();

public:
	// Must be called before add_unit(); clears nothing else.
	void set_rules(const Ref<BattleRulesData> &p_rules);
	Ref<BattleRulesData> get_rules() const { return rules; }
	// Milestones, formations and Hợp Lực for both sides, evaluated at
	// start(); null turns them off. Refused once units exist.
	void set_synergy(const Ref<Synergy> &p_synergy);
	Ref<Synergy> get_synergy() const { return synergy; }
	// Kỳ Ngộ overrides for one side (synergy_overrides.h), applied on top of
	// set_synergy()'s data until set_synergy() is called again. Refused once
	// units exist; an empty array removes them.
	void set_synergy_overrides(int64_t p_side, const Array &p_overrides);
	// Validates the class's handler ids and stats; false with an error on bad data.
	bool register_class(const Ref<ClassData> &p_class);
	// Returns the unit's index, or -1 with an error.
	int add_unit(int64_t p_side, const Ref<UnitData> &p_unit, int64_t p_star, int64_t p_local_col, int64_t p_local_rank);
	// Back to an empty battle that has not started; classes and rules stay.
	void clear();
	// Freezes the setup; the first step() emits battle_started.
	void start();
	// Advances one tick; returns that tick's events as read-only dictionaries
	// and emits them as signals. Commands are refused while the signals run.
	Array step();
	// Steps until the battle ends or max_ticks steps were taken, starting it
	// if needed; returns the final state hash (empty if a handler freed it).
	String run_to_end(int64_t p_max_ticks);

	bool is_started() const { return sim.is_started(); }
	bool is_finished() const { return sim.is_finished(); }
	// -1 while the battle runs.
	int get_winner() const { return sim.get_winner(); }
	int get_tick() const { return sim.get_tick(); }
	// 16 hex digits.
	String get_state_hash() const;
	int get_unit_count() const { return static_cast<int>(sim.get_units().size()); }
	Dictionary get_unit_state(int64_t p_index) const;
	Array get_units() const;

	void set_log_enabled(bool p_enabled) { log_enabled = p_enabled; }
	bool is_log_enabled() const { return log_enabled; }

	static bool is_valid_side(int64_t p_side);
	static bool is_valid_local_cell(int64_t p_local_col, int64_t p_local_rank);
	// (-1, -1) with an error for a bad side or cell.
	static Vector2i local_to_global(int64_t p_side, int64_t p_local_col, int64_t p_local_rank);
	// Returns (local col, rank); the rank is outside 1..4 in the enemy half.
	// (-1, -1) with an error for a bad side or a cell off the board.
	static Vector2i global_to_local(int64_t p_side, int64_t p_col, int64_t p_row);
};

} // namespace godot

VARIANT_ENUM_CAST(Battle::Side);
