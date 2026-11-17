#pragma once

#include "tactics_unit_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <string>

namespace godot {

// A wave of side B leaders (each with its own squad) arriving at the start
// of side B's phase of `round`, near the entry cells in turn (hold the
// city).
class TacticsWaveData : public Resource {
	GDCLASS(TacticsWaveData, Resource)

	int round = 1;
	TypedArray<TacticsLeaderData> leaders;
	TypedArray<Vector2i> entry_cells;

protected:
	static void _bind_methods();

public:
	bool to_wave_def(tactics::WaveDef *r_def, std::string *r_error) const;

	void set_round(int64_t p_value) { round = clamp_to_int(p_value); }
	int get_round() const { return round; }
	void set_leaders(const TypedArray<TacticsLeaderData> & p_value) { leaders = p_value; }
	TypedArray<TacticsLeaderData> get_leaders() const { return leaders; }
	void set_entry_cells(const TypedArray<Vector2i> & p_value) { entry_cells = p_value; }
	TypedArray<Vector2i> get_entry_cells() const { return entry_cells; }
};

// A secondary goal: `kind` names its handler (`goal.villages_safe`,
// `goal.no_losses`, `goal.by_round` with value the round,
// `goal.camps_taken`); met when side A wins, worth `supplies`.
class TacticsGoalData : public Resource {
	GDCLASS(TacticsGoalData, Resource)

	StringName kind;
	int value = 0;
	int supplies = 0;

protected:
	static void _bind_methods();

public:
	bool to_goal_def(tactics::GoalDef *r_def, std::string *r_error) const;

	void set_kind(const StringName & p_value) { kind = p_value; }
	StringName get_kind() const { return kind; }
	void set_value(int64_t p_value) { value = clamp_to_int(p_value); }
	int get_value() const { return value; }
	void set_supplies(int64_t p_value) { supplies = clamp_to_int(p_value); }
	int get_supplies() const { return supplies; }
};

// What a scenario is won by (Docs/systems/tactics_objectives.md): `kind`
// names the handler (`objective_kind.take_pass`, `.hold_city`, `.escort`,
// `.break_siege`, `.slay_general`); the fields it does not read stay unset.
class TacticsObjectiveData : public Resource {
	GDCLASS(TacticsObjectiveData, Resource)

	StringName id;
	StringName kind;
	int site = -1;
	int rounds = 0;
	int count = 0;
	int required_leader = -1;
	TypedArray<Vector2i> exit_cells;
	TypedArray<Vector2i> road_cells;
	Ref<TacticsTroopData> convoy;
	int general = -1;
	int flee_hp_pct = 0;
	int general_hold_cells = 0;
	TypedArray<TacticsWaveData> waves;
	TypedArray<TacticsGoalData> goals;

protected:
	static void _bind_methods();

public:
	bool to_objective_def(tactics::ObjectiveDef *r_def, std::string *r_error) const;

	void set_id(const StringName & p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_kind(const StringName & p_value) { kind = p_value; }
	StringName get_kind() const { return kind; }
	void set_site(int64_t p_value) { site = clamp_to_int(p_value); }
	int get_site() const { return site; }
	void set_rounds(int64_t p_value) { rounds = clamp_to_int(p_value); }
	int get_rounds() const { return rounds; }
	void set_count(int64_t p_value) { count = clamp_to_int(p_value); }
	int get_count() const { return count; }
	void set_required_leader(int64_t p_value) { required_leader = clamp_to_int(p_value); }
	int get_required_leader() const { return required_leader; }
	void set_exit_cells(const TypedArray<Vector2i> & p_value) { exit_cells = p_value; }
	TypedArray<Vector2i> get_exit_cells() const { return exit_cells; }
	void set_road_cells(const TypedArray<Vector2i> & p_value) { road_cells = p_value; }
	TypedArray<Vector2i> get_road_cells() const { return road_cells; }
	void set_convoy(const Ref<TacticsTroopData> & p_value) { convoy = p_value; }
	Ref<TacticsTroopData> get_convoy() const { return convoy; }
	void set_general(int64_t p_value) { general = clamp_to_int(p_value); }
	int get_general() const { return general; }
	void set_flee_hp_pct(int64_t p_value) { flee_hp_pct = clamp_to_int(p_value); }
	int get_flee_hp_pct() const { return flee_hp_pct; }
	void set_general_hold_cells(int64_t p_value) { general_hold_cells = clamp_to_int(p_value); }
	int get_general_hold_cells() const { return general_hold_cells; }
	void set_waves(const TypedArray<TacticsWaveData> & p_value) { waves = p_value; }
	TypedArray<TacticsWaveData> get_waves() const { return waves; }
	void set_goals(const TypedArray<TacticsGoalData> & p_value) { goals = p_value; }
	TypedArray<TacticsGoalData> get_goals() const { return goals; }
};

} // namespace godot
