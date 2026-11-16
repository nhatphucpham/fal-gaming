#pragma once

#include "tactics_incidents.h"
#include "tactics_state.h"

#include <cstdint>
#include <memory>
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

// Which side of a hit a stat source is listed for (collect_stat_sources).
enum class StatUse {
	ATTACK = 0,
	DEFENCE = 1,
};

// What a skill cast at a cell would do, from preview_skill().
struct SkillPreview {
	std::vector<Cell> cells;
	std::vector<int> targets;
	// Damage taken per target, summed over the skill's hits.
	std::vector<SkillTargetResult> results;
	// Units that would get a buff.
	std::vector<int> buffed;
	// Cells of the zones the cast would make.
	std::vector<Cell> zone_cells;
};

// One turn-based tactics battle on a square grid (Docs/systems/tactics.md).
// Commands change the state and append events; queries never do. Once
// battle_ended is emitted nothing changes and no event follows. The whole
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
	// Incidents (tactics_sim_incidents.cpp): all of these are setup and
	// refused once started. Rules with `enabled` false turn incidents off.
	bool set_incident_rules(const IncidentRules &p_rules, uint64_t p_seed, std::string *r_error);
	// Karma carried in from earlier battles; it shifts the seeds' odds.
	void set_carried_karma(int p_side, int p_bait, int p_rescue);
	// The roster person behind a soldier and its marks from earlier battles.
	bool set_unit_record(int p_unit, int p_record_id, int p_good_marks, int p_bad_marks, std::string *r_error);
	// Forces a seed (tests, scripted battles): when any is set, no seed is
	// drawn at random.
	bool set_forced_seed(int p_unit, int p_incident, std::string *r_error);
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
	// Takes back p_unit's last move in a human phase, one step at a time,
	// while its moves since its last other command only moved the leader
	// and its squad (and changed its charge): the battle returns to the
	// state before that move, same hash. Any other command, or a move that
	// caused anything else (a zone, karma, the objective), ends the steps
	// that can be taken back (Docs/systems/tactics.md, Undo).
	bool can_undo_move(int p_unit) const;
	bool undo_move(int p_unit, std::string *r_error);

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
	const IncidentRules &get_incident_rules() const { return incident_rules; }
	// The incident index for an id, or NO_INDEX.
	int find_incident(const std::string &p_id) const;
	const std::vector<std::pair<int, int>> &get_forced_seeds() const { return forced_seeds; }
	int get_carried_karma(int p_side, KarmaKind p_kind) const { return carried_karma[p_side][static_cast<int>(p_kind)]; }
	// Karma this battle has added so far.
	int get_battle_karma(int p_side, KarmaKind p_kind) const { return battle_karma[p_side][static_cast<int>(p_kind)]; }
	// Incident effects that change how a soldier moves.
	bool is_holding_ground(int p_unit) const { return turn < units[p_unit].hold_end_turn; }
	bool is_acting_free(int p_unit) const { return turn < units[p_unit].free_end_turn; }
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
	// The cell p_unit would strike p_target from this phase: where it stands
	// when it can no longer move, else the safest cell its points left reach
	// in range (tactics_brain.h, pick_safest_strike_cell), never a move that
	// takes the objective (that move alone wins); NO_CELL when none.
	Cell get_strike_cell(int p_unit, int p_target) const;
	// Enemies p_unit could attack this phase, moving first with the points
	// left if it still may (the same cells as get_strike_cell).
	std::vector<int> get_strike_targets(int p_unit) const;
	// A copy of the battle after p_unit moved to p_cell (its squad steps and
	// strikes as move_leader() makes it), or its own cell unchanged. False
	// with r_error when the move would be refused.
	bool simulate_move(int p_unit, const Cell &p_cell, TacticsSim *r_copy, std::string *r_error) const;
	// A leader's turn (Docs/systems/tactics.md, A leader's turn). Its turn
	// is open while it is alive, on the active side and has not waited:
	// it may then wait or change its order. It may move while open with
	// move points that reach a cell, attack once and cast once.
	bool can_leader_act(int p_unit) const;
	bool can_leader_move(int p_unit) const;
	bool can_leader_attack(int p_unit) const;
	bool can_leader_cast(int p_unit) const;
	// Nothing left to do this phase: not open, or no cell to move to, no
	// strike (moving first if it may) and no skill cell. True for units
	// that are not a leader of the active side.
	bool is_leader_closed(int p_unit) const;
	// Move points p_unit may still spend now: what is left this phase for
	// a unit of the active side (0 while held by a zone of control), its
	// full move points otherwise (its next phase, for reach and intents).
	int get_move_budget(int p_unit) const;
	// Units attack() would accept for p_unit now, by index.
	std::vector<int> get_attack_targets(int p_unit) const;
	// Cells use_skill() would accept for p_unit now, row-major.
	std::vector<Cell> get_skill_cells(int p_unit) const;
	// The outcome of use_skill(p_unit, p_cell) run on a copy. False with
	// r_error when use_skill() would refuse it.
	bool preview_skill(int p_unit, const Cell &p_cell, SkillPreview *r_preview, std::string *r_error) const;
	// Appends the ids of passives, buffs and (for DEFENCE) terrain that
	// change the unit's attack, or its armor and magic resist, each once.
	void collect_stat_sources(int p_unit, StatUse p_use, std::vector<std::string> &r_sources) const;

	// Used by the handlers and rules modules.
	UnitState &edit_unit(int p_unit) { return units[p_unit]; }
	int emit(Event &r_event);
	// Lowers hp, emits damage_dealt and, at 0, unit_died; returns the damage
	// event id. Nothing happens to a unit that is already dead. A soldier
	// guarding the target (incident.rescue) takes the hit instead.
	int deal_damage(int p_source, int p_target, int p_amount, const std::string &p_content_id, bool p_is_counter, int p_cause);
	// Moves a unit and emits unit_moved; p_path includes both ends. Returns
	// the event id, 0 when nothing moved. Never takes the objective: only a
	// leader's own move does (move_leader).
	int relocate_unit(int p_unit, const std::vector<Cell> &p_path, const std::string &p_kind, int p_cause);
	// Both last p_duration_rounds rounds: until the start of the active
	// side's phase that many rounds later (end_round and end_turn are set here).
	void add_zone(ZoneState p_zone, int p_duration_rounds, int p_cause);
	void add_buff(BuffState p_buff, int p_duration_rounds, int p_cause);
	// Removes zones[p_index] and emits zone_expired.
	void remove_zone(int p_index, int p_cause);
	void change_skill_charge(int p_leader, int p_delta, bool p_resets, int p_cause);
	void emit_passive_triggered(int p_unit, const std::string &p_passive_id, int p_cause);
	// Puts a unit on a free cell with no event and no other effect, for the
	// what-if checks of tactics_brain.cpp; only ever on a copy.
	void place_for_query(int p_unit, const Cell &p_cell, int p_straight_cells);
	// Runs the soldiers' moves only (orders.h): after each leader move, and
	// in the preview.
	void run_squad_moves(int p_leader, int p_cause);
	// Moves p_unit along p_path (a leader's move or a soldier's squad walk)
	// and spends its move points, p_cost: its straight run goes on across
	// walks, and it is held when it stops in an enemy's zone of control.
	int walk_unit(int p_unit, const std::vector<Cell> &p_path, int p_cost, const std::string &p_kind, int p_cause);
	// Incident helpers (tactics_incidents.cpp).
	IncidentRandom &edit_random() { return random; }
	void add_karma(int p_side, KarmaKind p_kind, int p_cause);
	// The soldier leaves the battle by p_edge: unit_fled, off the map.
	void remove_fled_unit(int p_unit, const Cell &p_edge, int p_cause);
	// The soldier joins p_new_leader's squad on the other side; false (and
	// no change) when that squad has no room.
	bool defect_unit(int p_unit, int p_new_leader, int p_cause);

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
	IncidentRules incident_rules;
	uint64_t incident_seed = 0;
	IncidentRandom random;
	std::vector<std::pair<int, int>> forced_seeds;
	int carried_karma[SIDE_COUNT][2] = { { 0, 0 }, { 0, 0 } };
	// The battle before each move that can still be taken back, the last
	// on top, and whose moves they were. Each copy holds the stack below it.
	std::vector<std::shared_ptr<const TacticsSim>> undo_states;
	int undo_leader = NO_UNIT;
	int battle_karma[SIDE_COUNT][2] = { { 0, 0 }, { 0, 0 } };

	bool check_new_leader(int p_side, const UnitDef &p_leader, const std::vector<UnitDef> &p_squad, std::string *r_error) const;
	bool check_command(int p_unit, std::string *r_error) const;
	bool check_leader_can_act(int p_unit, std::string *r_error) const;
	bool check_leader_can_attack(int p_unit, std::string *r_error) const;
	bool check_leader_can_cast(int p_unit, std::string *r_error) const;
	bool check_leader_move(int p_unit, const Cell &p_cell, std::string *r_error) const;
	bool takes_objective(int p_unit, const Cell &p_cell) const;
	void place_soldiers(int p_leader);
	// Returns the leader's unit_moved event id.
	int apply_leader_move(int p_unit, const Cell &p_cell, int p_cause);
	void update_heading(int p_unit);
	// The squad steps and, if it has not yet this phase, strikes.
	void run_squad_strike(int p_leader, int p_cause);
	void begin_phase(int p_side);
	void clear_undo();
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
	void hash_setup(uint64_t *r_hash) const;
	void hash_unit(uint64_t *r_hash, const UnitState &p_unit) const;
	void hash_incidents(uint64_t *r_hash) const;
};

} // namespace tactics
