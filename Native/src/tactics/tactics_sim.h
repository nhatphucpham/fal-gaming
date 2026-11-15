#pragma once

#include "tactics_state.h"

#include <cstdint>
#include <string>
#include <vector>

namespace tactics {

// Effective stats of a unit on a cell: base, terrain, passives and buffs.
struct Stats {
	int attack = 0;
	int armor = 0;
	int magic_resist = 0;
	int move_points = 0;
	int min_range_cells = 1;
	int max_range_cells = 1;
};

// One turn-based tactics battle on a square grid (Docs/systems/tactics.md).
// Commands change the state and append events; queries never do. The whole
// object is a value: copying it gives an independent battle, which is how
// forecasts and previews run the real rules without touching this one.
//   sim.setup(rules, map, &error);
//   const int leader = sim.add_leader(SIDE_A, def, { 2, 12 }, squad, &error);
//   sim.start(&error);
//   sim.move_leader(leader, { 2, 9 }, &error);
class TacticsSim {
public:
	// Setup. setup() clears everything; add_leader() places the leader and
	// its squad around it. Both refuse once started.
	bool setup(const Rules &p_rules, const MapDef &p_map, std::string *r_error);
	int add_leader(int p_side, const UnitDef &p_leader, const Cell &p_cell, const std::vector<UnitDef> &p_squad, std::string *r_error);
	void set_side_ai(int p_side, bool p_is_ai) { side_is_ai[p_side] = p_is_ai; }
	bool is_side_ai(int p_side) const { return side_is_ai[p_side]; }
	// Begins round 1 with side A's phase (AI phases run on their own).
	bool start(std::string *r_error);

	// Commands for the active side. False with r_error when refused.
	bool move_leader(int p_unit, const Cell &p_cell, std::string *r_error);
	bool attack(int p_unit, int p_target, std::string *r_error);
	bool use_skill(int p_unit, const Cell &p_cell, std::string *r_error);
	bool wait(int p_unit, std::string *r_error);
	bool set_order(int p_unit, int p_order, std::string *r_error);
	// Ends the phase; AI phases that follow run before it returns.
	bool end_phase(std::string *r_error);

	// Events appended since the last take_events().
	std::vector<Event> take_events();

	// Queries.
	bool is_started() const { return started; }
	bool is_finished() const { return finished; }
	int get_winner() const { return winner; }
	const std::string &get_end_reason() const { return end_reason; }
	int get_round() const { return round; }
	int get_turn() const { return turn; }
	int get_active_side() const { return active_side; }
	const Rules &get_rules() const { return rules; }
	const MapDef &get_map() const { return map; }
	const std::vector<UnitState> &get_units() const { return units; }
	const std::vector<ZoneState> &get_zones() const { return zones; }
	const std::vector<BuffState> &get_buffs() const { return buffs; }
	const std::vector<Intent> &get_intents() const { return intents; }
	bool is_on_map(const Cell &p_cell) const;
	int get_cell_index(const Cell &p_cell) const { return p_cell.row * map.width + p_cell.col; }
	Cell get_cell_at(int p_index) const { return { p_index % map.width, p_index / map.width }; }
	const TerrainDef &get_terrain(const Cell &p_cell) const;
	int get_occupant(const Cell &p_cell) const;
	Stats get_stats(int p_unit) const { return get_stats_at(p_unit, units[p_unit].cell); }
	Stats get_stats_at(int p_unit, const Cell &p_cell) const;
	// Own keywords plus those granted by the leader's squad passives.
	std::vector<const KeywordDef *> collect_keywords(int p_unit) const;
	bool is_leader(int p_unit) const { return units[p_unit].def.role == UnitRole::LEADER; }
	int get_squad_capacity(int p_leader) const;
	// The exact outcome of p_attacker engaging p_defender now; no change here.
	EngagementResult forecast_engagement(int p_attacker, int p_defender) const;
	// Where each soldier would stand after p_leader moved to p_cell:
	// pairs of (soldier, cell). Empty with r_error when the move is refused.
	std::vector<std::pair<int, Cell>> preview_squad(int p_leader, const Cell &p_cell, std::string *r_error) const;
	uint64_t get_state_hash() const;

	// Used by the handlers and rules modules.
	UnitState &edit_unit(int p_unit) { return units[p_unit]; }
	int emit(Event &r_event);
	// Lowers hp, emits damage_dealt and, at 0, unit_died; returns the damage
	// event id. Nothing happens to a unit that is already dead.
	int deal_damage(int p_source, int p_target, int p_amount, const std::string &p_content_id, bool p_is_counter, int p_cause);
	// Moves a unit and emits unit_moved; p_path includes both ends. Returns
	// the event id, 0 when nothing moved. Never takes the objective: only a
	// leader's own move does (move_leader).
	int relocate_unit(int p_unit, const std::vector<Cell> &p_path, const std::string &p_kind, int p_cause);
	// Both last p_duration_rounds rounds: until the start of the active
	// side's phase that many rounds later (end_round and end_turn are set here).
	void add_zone(ZoneState p_zone, int p_duration_rounds, int p_cause);
	void add_buff(BuffState p_buff, int p_duration_rounds, int p_cause);
	void change_skill_charge(int p_leader, int p_delta, bool p_resets, int p_cause);
	void emit_passive_triggered(int p_unit, const std::string &p_passive_id, int p_cause);
	// Runs the soldiers' moves only (orders.h); the preview uses it alone.
	void run_squad_moves(int p_leader, int p_cause);

private:
	Rules rules;
	MapDef map;
	std::vector<UnitState> units;
	std::vector<int> occupants;
	std::vector<ZoneState> zones;
	std::vector<BuffState> buffs;
	std::vector<Intent> intents;
	std::vector<Event> events;
	bool side_is_ai[SIDE_COUNT] = { false, true };
	bool is_ready = false;
	bool started = false;
	bool finished = false;
	int winner = NO_WINNER;
	std::string end_reason;
	int round = 0;
	// Phases begun so far; the log's t= value.
	int turn = 0;
	int active_side = SIDE_A;
	int next_event_id = 1;

	bool check_command(int p_unit, std::string *r_error) const;
	bool check_leader_can_act(int p_unit, std::string *r_error) const;
	bool check_leader_move(int p_unit, const Cell &p_cell, std::string *r_error) const;
	void place_soldiers(int p_leader);
	// Returns the leader's unit_moved event id.
	int apply_leader_move(int p_unit, const Cell &p_cell, int p_cause);
	void update_heading(int p_unit, const Cell &p_from, const Cell &p_to);
	void finish_leader_action(int p_unit, int p_cause);
	void run_squad_step(int p_leader, int p_cause);
	void begin_phase(int p_side);
	void close_phase();
	void run_ai_phase();
	// Runs AI phases until a player phase begins or the battle ends.
	void run_ai_phases();
	void begin_next_phase();
	void apply_phase_start_effects(int p_cause);
	void expire_timed_effects(int p_cause);
	void handle_death(int p_unit, int p_killer, int p_cause);
	// Ends the battle when a side has no living leader.
	void check_rout(int p_cause);
	// Ends the battle when p_leader's own move ended on its side's objective.
	void check_objective_taken(int p_leader, int p_cause);
	void end_battle(int p_winner, const std::string &p_reason, int p_cause);
	void declare_intents(int p_cause);
	void hash_unit(uint64_t *r_hash, const UnitState &p_unit) const;
};

} // namespace tactics
