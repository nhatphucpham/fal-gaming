#pragma once

#include "tactics_incident_data.h"
#include "tactics_map_data.h"
#include "tactics_rules_data.h"
#include "tactics_scenario_data.h"
#include "tactics_sim.h"
#include "tactics_unit_data.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// Godot face of one turn-based tactics battle (Docs/systems/tactics.md).
// Presentation sends commands (each returns its events and emits them as
// signals) and reads queries; it never edits the battle.
//   battle.load_scenario(catalog.get_scenario(&"scenario.river_crossing"))
//   battle.start()
//   battle.move_leader(0, Vector2i(2, 11))
//   battle.attack(0, enemy_index)
//   battle.end_phase()  # the AI side plays its phase before this returns
class TacticsBattle : public Node {
	GDCLASS(TacticsBattle, Node)

public:
	enum Side {
		SIDE_A = tactics::SIDE_A,
		SIDE_B = tactics::SIDE_B,
	};

private:
	tactics::TacticsSim sim;
	bool log_enabled = false;
	// True while a command's signals are emitted; commands are refused then.
	bool is_emitting = false;

	// Turns the simulation's new events into read-only dictionaries,
	// logs them and emits them; returns them.
	Array flush_events();
	bool check_not_emitting(const char *p_method) const;
	void log_event(const tactics::Event &p_event) const;
	bool check_unit(int64_t p_unit, const char *p_method) const;
	void clear_setup();

protected:
	static void _bind_methods();

public:
	// Setup; refused once started.
	bool setup(const Ref<TacticsRulesData> &p_rules, const Ref<TacticsMapData> &p_map);
	// setup() with the scenario's rules and map, then its leaders on the
	// map's spawn cells in order, each with its own squad. On failure the
	// battle is left with no setup, so start() is refused.
	bool load_scenario(const Ref<TacticsScenarioData> &p_scenario);
	// load_scenario() with other squads for one side: p_squads holds one
	// Array of TacticsTroopData per leader of that side, in order (each up
	// to the leader's capacity). The other side keeps its own squads.
	bool load_scenario_with_squads(const Ref<TacticsScenarioData> &p_scenario, int64_t p_side, const Array &p_squads);
	void set_side_ai(int64_t p_side, bool p_is_ai);
	bool is_side_ai(int64_t p_side) const;
	// The leader's unit index, or -1 with an error. Uses the leader's squad.
	int add_leader(int64_t p_side, const Ref<TacticsLeaderData> &p_leader, const Vector2i &p_cell);
	// Same with an explicit squad (an Array of TacticsTroopData, may be empty).
	int add_leader_with_squad(int64_t p_side, const Ref<TacticsLeaderData> &p_leader, const Vector2i &p_cell, const Array &p_squad);
	// Incidents (tactics_battle_incidents.cpp): after load_scenario() or
	// setup() and the leaders, before start(). Without them a battle has no
	// incidents.
	bool set_incident_rules(const Ref<TacticsIncidentRulesData> &p_rules, int64_t p_seed);
	void set_karma(int64_t p_side, int64_t p_bait, int64_t p_rescue);
	bool set_unit_record(int64_t p_unit, int64_t p_record_id, int64_t p_good_marks, int64_t p_bad_marks);
	bool set_incident_seed(int64_t p_unit, const StringName &p_incident);
	Array start();

	// Commands of the active side: each returns its events (empty with an
	// error when refused).
	Array move_leader(int64_t p_unit, const Vector2i &p_cell);
	Array attack(int64_t p_unit, int64_t p_target);
	Array use_skill(int64_t p_unit, const Vector2i &p_cell);
	Array wait(int64_t p_unit);
	Array set_order(int64_t p_unit, const StringName &p_order);
	Array end_phase();

	// Queries (tactics_battle_queries.cpp); none changes the battle.
	bool is_started() const { return sim.is_started(); }
	bool is_finished() const { return sim.is_finished(); }
	int get_winner() const { return sim.get_winner(); }
	StringName get_end_reason() const;
	int get_round() const { return sim.get_round(); }
	int get_turn() const { return sim.get_turn(); }
	int get_active_side() const { return sim.get_active_side(); }
	int get_map_width() const { return sim.get_map().width; }
	int get_map_height() const { return sim.get_map().height; }
	StringName get_terrain_id(const Vector2i &p_cell) const;
	String get_state_hash() const;
	int get_unit_count() const { return static_cast<int>(sim.get_units().size()); }
	Dictionary get_unit_state(int64_t p_unit) const;
	Array get_units() const;
	Array get_zones() const;
	Array get_reachable_cells(int64_t p_unit) const;
	Array get_path_to(int64_t p_unit, const Vector2i &p_cell) const;
	Array get_formation_slots(int64_t p_leader) const;
	Dictionary forecast_engagement(int64_t p_attacker, int64_t p_defender) const;
	Array preview_squad(int64_t p_leader, const Vector2i &p_cell) const;
	Dictionary get_skill_charge(int64_t p_leader) const;
	Array get_enemy_intents() const;
	bool can_move(int64_t p_unit) const;
	bool can_act(int64_t p_unit) const;
	Array get_attack_targets(int64_t p_unit) const;
	Array get_skill_cells(int64_t p_unit) const;
	Dictionary preview_skill(int64_t p_unit, const Vector2i &p_cell) const;
	// Tests and tools only: the hidden seeds; the screen never shows them.
	Array get_incident_seeds() const;
	Dictionary get_karma(int64_t p_side) const;
	// Survivors, deaths, flights, defections and marks so far, for the
	// roster after the battle.
	Dictionary get_battle_report() const;

	void set_log_enabled(bool p_enabled) { log_enabled = p_enabled; }
	bool is_log_enabled() const { return log_enabled; }
};

} // namespace godot

VARIANT_ENUM_CAST(TacticsBattle::Side);
