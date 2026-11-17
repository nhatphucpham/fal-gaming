#include "tactics_incidents.h"

#include "tactics_passives.h"
#include "tactics_paths.h"
#include "tactics_sim.h"

namespace tactics {

namespace {

constexpr int PERCENT = 100;

int get_hp_pct(const UnitState &p_unit) {
	return p_unit.hp * PERCENT / (p_unit.def.max_hp > 0 ? p_unit.def.max_hp : 1);
}

// The soldier's leader when it lives, else nullptr.
const UnitState *find_living_leader(const TacticsSim &p_sim, int p_soldier) {
	const int leader = p_sim.get_units()[p_soldier].leader;
	if (leader == NO_UNIT || !p_sim.get_units()[leader].is_alive) {
		return nullptr;
	}
	return &p_sim.get_units()[leader];
}

// Living units other than p_unit within p_cells (Manhattan), enemies or allies.
int count_near(const TacticsSim &p_sim, int p_unit, int p_cells, bool p_enemies) {
	const UnitState &self = p_sim.get_units()[p_unit];
	int count = 0;
	for (const UnitState &other : p_sim.get_units()) {
		const bool is_enemy = other.side != self.side;
		if (other.index != p_unit && other.is_alive && is_enemy == p_enemies && get_manhattan(other.cell, self.cell) <= p_cells) {
			count++;
		}
	}
	return count;
}

// The end turn of an effect that lasts duration_rounds full rounds after the
// end of the soldier's phase: it covers the coming enemy phase and the
// soldier's next p_rounds own phases.
int get_effect_end_turn(const TacticsSim &p_sim, int p_rounds) {
	return p_sim.get_turn() + SIDE_COUNT * (p_rounds + 1);
}

// The free cell next to p_leader the soldier would dash to: nearest to the
// soldier, then the lowest cell index; NO_CELL when none.
Cell find_cell_beside(const TacticsSim &p_sim, int p_soldier, int p_leader) {
	const Cell from = p_sim.get_units()[p_soldier].cell;
	const Cell center = p_sim.get_units()[p_leader].cell;
	Cell best = NO_CELL;
	for (const Cell &direction : DIRECTIONS) {
		const Cell cell = center + direction;
		if (!can_stop_at(p_sim, p_soldier, cell)) {
			continue;
		}
		const bool is_better = best == NO_CELL || get_manhattan(cell, from) < get_manhattan(best, from) ||
				(get_manhattan(cell, from) == get_manhattan(best, from) && p_sim.get_cell_index(cell) < p_sim.get_cell_index(best));
		best = is_better ? cell : best;
	}
	return best;
}

// incident.rescue (good): its leader is down to threshold_pct of its hp and
// within radius_cells. It dashes next to the leader and takes every hit
// aimed at it while it stands there, for duration_rounds (0: the coming
// enemy phase).
bool rescue_triggered(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	const UnitState *leader = find_living_leader(p_sim, p_unit);
	if (leader == nullptr || get_hp_pct(*leader) > p_def.threshold_pct) {
		return false;
	}
	const int distance = get_manhattan(leader->cell, p_sim.get_units()[p_unit].cell);
	return distance <= p_def.radius_cells && (distance == 1 || find_cell_beside(p_sim, p_unit, leader->index) != NO_CELL);
}

void rescue_fire(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause) {
	const int leader = p_sim.get_units()[p_unit].leader;
	const Cell from = p_sim.get_units()[p_unit].cell;
	if (get_manhattan(from, p_sim.get_units()[leader].cell) > 1) {
		p_sim.relocate_unit(p_unit, { from, find_cell_beside(p_sim, p_unit, leader) }, "dash", p_cause);
	}
	UnitState &unit = p_sim.edit_unit(p_unit);
	unit.guard_leader = leader;
	unit.guard_end_turn = get_effect_end_turn(p_sim, p_def.duration_rounds);
}

// incident.stand (good): at least threshold_count enemies next to it and no
// ally next to it. Armor +amount, and it cannot be moved (squad steps,
// pulls) for duration_rounds.
bool stand_triggered(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	return count_near(p_sim, p_unit, 1, true) >= p_def.threshold_count && count_near(p_sim, p_unit, 1, false) == 0;
}

void stand_fire(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause) {
	BuffState buff;
	buff.unit = p_unit;
	buff.stat = StatKind::ARMOR;
	buff.amount = p_def.amount;
	buff.source_id = p_def.id;
	p_sim.add_buff(buff, p_def.duration_rounds + 1, p_cause);
	p_sim.edit_unit(p_unit).hold_end_turn = get_effect_end_turn(p_sim, p_def.duration_rounds);
}

// incident.surge (good): an ally died next to it since the start of its
// previous own phase. Attack +amount% and armor +secondary_amount for
// duration_rounds (100: the rest of any battle in the data).
bool surge_triggered(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	const int fell = p_sim.get_units()[p_unit].ally_fell_turn;
	(void)p_def;
	return fell > 0 && fell >= p_sim.get_turn() - SIDE_COUNT;
}

void surge_fire(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause) {
	BuffState buff;
	buff.unit = p_unit;
	buff.source_id = p_def.id;
	buff.stat = StatKind::ATTACK_PCT;
	buff.amount = p_def.amount;
	p_sim.add_buff(buff, p_def.duration_rounds + 1, p_cause);
	if (p_def.secondary_amount != 0 && p_sim.get_units()[p_unit].is_alive) {
		buff.stat = StatKind::ARMOR;
		buff.amount = p_def.secondary_amount;
		p_sim.add_buff(buff, p_def.duration_rounds + 1, p_cause);
	}
}

// incident.discontent (bad): it was used as bait (hit while its leader stood
// far) in threshold_count phases. For its next duration_rounds own phases
// it ignores the order and acts as `free`.
bool discontent_triggered(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	return p_sim.get_units()[p_unit].bait_count >= p_def.threshold_count;
}

void discontent_fire(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause) {
	(void)p_cause;
	UnitState &unit = p_sim.edit_unit(p_unit);
	unit.free_end_turn = get_effect_end_turn(p_sim, p_def.duration_rounds);
	unit.bait_count = 0;
}

// incident.riot (bad): its leader is dead or its squad lost threshold_pct of
// its soldiers. Allied soldiers within radius_cells are shoved one cell away
// from it (when that cell is free) and take amount damage.
bool riot_triggered(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	const UnitState *leader = find_living_leader(p_sim, p_unit);
	if (leader == nullptr) {
		return true;
	}
	int lost = 0;
	for (int soldier : leader->soldiers) {
		lost += p_sim.get_units()[soldier].is_alive ? 0 : 1;
	}
	return !leader->soldiers.empty() && lost * PERCENT >= p_def.threshold_pct * static_cast<int>(leader->soldiers.size());
}

void riot_fire(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause) {
	const UnitState &self = p_sim.get_units()[p_unit];
	const Cell center = self.cell;
	const int side = self.side;
	const int count = static_cast<int>(p_sim.get_units().size());
	for (int index = 0; index < count && !p_sim.is_finished(); index++) {
		const UnitState &ally = p_sim.get_units()[index];
		const int distance = get_manhattan(ally.cell, center);
		if (index == p_unit || !ally.is_alive || ally.side != side || p_sim.is_leader(index) || ally.def.is_noncombatant || distance > p_def.radius_cells) {
			continue;
		}
		const int delta_col = ally.cell.col - center.col;
		const int delta_row = ally.cell.row - center.row;
		const Cell step = abs_int(delta_col) > abs_int(delta_row) ? Cell{ delta_col > 0 ? 1 : -1, 0 } : Cell{ 0, delta_row > 0 ? 1 : -1 };
		const Cell to = ally.cell + step;
		if (!p_sim.is_holding_ground(index) && can_stop_at(p_sim, index, to)) {
			p_sim.relocate_unit(index, { ally.cell, to }, "shove", p_cause);
		}
		if (p_def.amount > 0) {
			p_sim.deal_damage(p_unit, index, p_def.amount, p_def.id, false, p_cause);
		}
	}
}

// incident.flee (bad): its leader is dead or at least radius_cells away, and
// threshold_count enemies are within secondary_amount cells. It runs to the
// nearest edge cell away from the enemy and leaves the battle.
bool flee_triggered(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	const UnitState *leader = find_living_leader(p_sim, p_unit);
	const bool is_alone = leader == nullptr || get_manhattan(leader->cell, p_sim.get_units()[p_unit].cell) >= p_def.radius_cells;
	return is_alone && count_near(p_sim, p_unit, p_def.secondary_amount, true) >= p_def.threshold_count;
}

// Distance from p_cell to the nearest living enemy of p_side; -1 when none.
int get_enemy_distance(const TacticsSim &p_sim, int p_side, const Cell &p_cell) {
	int best = -1;
	for (const UnitState &other : p_sim.get_units()) {
		if (other.is_alive && other.side != p_side && (best < 0 || get_manhattan(other.cell, p_cell) < best)) {
			best = get_manhattan(other.cell, p_cell);
		}
	}
	return best;
}

// The nearest edge cell the soldier is nearer to than any enemy (it runs
// away, not through them); the nearest edge cell when there is none.
Cell find_escape_edge(const TacticsSim &p_sim, int p_unit) {
	const MapDef &map = p_sim.get_map();
	const UnitState &self = p_sim.get_units()[p_unit];
	Cell best = self.cell;
	int best_score = -1;
	for (int index = 0; index < map.width * map.height; index++) {
		const Cell cell = p_sim.get_cell_at(index);
		if (cell.col != 0 && cell.row != 0 && cell.col != map.width - 1 && cell.row != map.height - 1) {
			continue;
		}
		const int distance = get_manhattan(cell, self.cell);
		const int enemy_distance = get_enemy_distance(p_sim, self.side, cell);
		const bool is_away = enemy_distance < 0 || distance < enemy_distance;
		const int score = distance + (is_away ? 0 : map.width * map.height);
		if (best_score < 0 || score < best_score) {
			best = cell;
			best_score = score;
		}
	}
	return best;
}

void flee_fire(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause) {
	(void)p_def;
	p_sim.remove_fled_unit(p_unit, find_escape_edge(p_sim, p_unit), p_cause);
}

// The nearest enemy leader within radius_cells with at least
// secondary_amount% of its hp, then the lower index; NO_UNIT when none.
int find_strong_enemy_leader(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	const UnitState &self = p_sim.get_units()[p_unit];
	int best = NO_UNIT;
	for (const UnitState &other : p_sim.get_units()) {
		const int distance = get_manhattan(other.cell, self.cell);
		if (!other.is_alive || other.side == self.side || !p_sim.is_leader(other.index) || distance > p_def.radius_cells || get_hp_pct(other) < p_def.secondary_amount) {
			continue;
		}
		if (best == NO_UNIT || distance < get_manhattan(p_sim.get_units()[best].cell, self.cell)) {
			best = other.index;
		}
	}
	return best;
}

// incident.betray (bad): its leader is dead or down to threshold_pct of its
// hp, and an enemy leader with at least secondary_amount% hp stands within
// radius_cells. It joins that leader's squad (no room: it flees instead).
bool betray_triggered(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	const UnitState *leader = find_living_leader(p_sim, p_unit);
	const bool is_weak = leader == nullptr || get_hp_pct(*leader) <= p_def.threshold_pct;
	return is_weak && find_strong_enemy_leader(p_sim, p_unit, p_def) != NO_UNIT;
}

void betray_fire(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause) {
	const int new_leader = find_strong_enemy_leader(p_sim, p_unit, p_def);
	if (!p_sim.defect_unit(p_unit, new_leader, p_cause)) {
		flee_fire(p_sim, p_unit, p_def, p_cause);
	}
}

// Fog of war: a soldier out of its leader's sight may waver though its own
// trigger does not hold, at unseen_waver_pct % plus the night's and the
// weather's waver_pct (Docs/systems/tactics_vision.md, Incidents).
bool rolls_unseen_waver(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def) {
	if (p_def.unseen_waver_pct <= 0 || !p_sim.is_out_of_leader_sight(p_unit)) {
		return false;
	}
	const int pct = p_def.unseen_waver_pct + p_sim.get_daytime().waver_pct + p_sim.get_weather().waver_pct;
	return pct > 0 && p_sim.edit_random().next(PERCENT) < pct;
}

const IncidentHandler INCIDENT_HANDLERS[] = {
	{ "incident.rescue", true, rescue_triggered, rescue_fire },
	{ "incident.stand", true, stand_triggered, stand_fire },
	{ "incident.surge", true, surge_triggered, surge_fire },
	{ "incident.discontent", false, discontent_triggered, discontent_fire },
	{ "incident.riot", false, riot_triggered, riot_fire },
	{ "incident.flee", false, flee_triggered, flee_fire },
	{ "incident.betray", false, betray_triggered, betray_fire },
};

const char *const KARMA_KIND_IDS[] = { "bait", "rescue" };

// Picks an index by weight; p_total must be > 0.
int pick_weighted(IncidentRandom &r_random, const std::vector<int> &p_weights, int p_total) {
	int roll = r_random.next(p_total);
	for (size_t index = 0; index < p_weights.size(); index++) {
		if (roll < p_weights[index]) {
			return static_cast<int>(index);
		}
		roll -= p_weights[index];
	}
	return static_cast<int>(p_weights.size()) - 1;
}

void plant_side_seeds(TacticsSim &p_sim, int p_side) {
	const IncidentRules &rules = p_sim.get_incident_rules();
	const bool is_ai = p_sim.is_side_ai(p_side);
	std::vector<int> soldiers;
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.side == p_side && unit.is_alive && !p_sim.is_leader(unit.index)) {
			soldiers.push_back(unit.index);
		}
	}
	const int low = is_ai ? rules.ai_min_seeds : rules.min_seeds;
	const int high = is_ai ? rules.ai_max_seeds : rules.max_seeds;
	IncidentRandom &random = p_sim.edit_random();
	int count = low + random.next(high - low + 1);
	count = count < static_cast<int>(soldiers.size()) ? count : static_cast<int>(soldiers.size());
	for (int planted = 0; planted < count; planted++) {
		// Soldiers with marks from earlier battles are likelier to carry one.
		std::vector<int> soldier_weights;
		int soldier_total = 0;
		for (int soldier : soldiers) {
			const UnitState &unit = p_sim.get_units()[soldier];
			soldier_weights.push_back(1 + (unit.good_marks + unit.bad_marks) * rules.marked_soldier_weight);
			soldier_total += soldier_weights.back();
		}
		const int pick = pick_weighted(random, soldier_weights, soldier_total);
		const int soldier = soldiers[pick];
		soldiers.erase(soldiers.begin() + pick);
		std::vector<int> weights;
		int total = 0;
		for (size_t incident = 0; incident < rules.incidents.size(); incident++) {
			const bool is_allowed = !is_ai || rules.incidents[incident].seeds_ai_side;
			weights.push_back(is_allowed ? get_incident_weight(p_sim, soldier, static_cast<int>(incident)) : 0);
			total += weights.back();
		}
		if (total > 0) {
			UnitState &unit = p_sim.edit_unit(soldier);
			unit.seed = pick_weighted(random, weights, total);
			unit.stage = IncidentStage::DORMANT;
		}
	}
}

void calm_incident(TacticsSim &p_sim, int p_unit, const char *p_reason, int p_cause = 0) {
	UnitState &unit = p_sim.edit_unit(p_unit);
	unit.stage = IncidentStage::DORMANT;
	unit.is_unseen_waver = false;
	Event event;
	event.type = EventType::INCIDENT_CALMED;
	event.unit = p_unit;
	event.content_id = p_sim.get_incident_rules().incidents[unit.seed].id;
	event.kind = p_reason;
	event.cause = p_cause;
	p_sim.emit(event);
}

void fire_incident(TacticsSim &p_sim, int p_unit) {
	const IncidentDef &def = p_sim.get_incident_rules().incidents[p_sim.get_units()[p_unit].seed];
	const UnitState &unit = p_sim.get_units()[p_unit];
	MarkState mark;
	mark.incident = unit.seed;
	mark.leader_id = unit.leader != NO_UNIT ? p_sim.get_units()[unit.leader].def.id : std::string();
	mark.terrain_id = p_sim.get_terrain(unit.cell).id;
	mark.cell = unit.cell;
	mark.round = p_sim.get_round();
	Event fired;
	fired.type = EventType::INCIDENT_FIRED;
	fired.unit = p_unit;
	fired.target = unit.leader;
	fired.side = unit.side;
	fired.to = unit.cell;
	fired.content_id = def.id;
	fired.is_first_strike = def.handler->is_good;
	p_sim.edit_unit(p_unit).stage = IncidentStage::FIRED;
	const int fired_id = p_sim.emit(fired);
	def.handler->fire(p_sim, p_unit, def, fired_id);
	if (p_sim.is_finished()) {
		return;
	}
	p_sim.edit_unit(p_unit).marks.push_back(mark);
	Event earned;
	earned.type = EventType::MARK_EARNED;
	earned.unit = p_unit;
	earned.content_id = def.id;
	earned.kind = mark.leader_id;
	earned.detail_id = mark.terrain_id;
	earned.to = mark.cell;
	earned.value = static_cast<int>(p_sim.get_units()[p_unit].marks.size());
	earned.cause = fired_id;
	p_sim.emit(earned);
}

void add_bait(TacticsSim &p_sim, int p_soldier, int p_cause) {
	const UnitState &soldier = p_sim.get_units()[p_soldier];
	const UnitState *leader = find_living_leader(p_sim, p_soldier);
	if (leader == nullptr || soldier.last_baited_turn == p_sim.get_turn() || get_manhattan(leader->cell, soldier.cell) < p_sim.get_incident_rules().bait_distance_cells) {
		return;
	}
	UnitState &unit = p_sim.edit_unit(p_soldier);
	unit.bait_count++;
	unit.last_baited_turn = p_sim.get_turn();
	p_sim.add_karma(unit.side, KarmaKind::BAIT, p_cause);
}

} // namespace

const IncidentHandler *find_incident_handler(const std::string &p_id) {
	for (const IncidentHandler &handler : INCIDENT_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

const char *get_karma_kind_id(KarmaKind p_kind) {
	return KARMA_KIND_IDS[static_cast<int>(p_kind)];
}

void IncidentRandom::seed(uint64_t p_seed) {
	// splitmix64, so nearby seeds start far apart; never 0 for xorshift.
	uint64_t mixed = p_seed + 0x9E3779B97F4A7C15ULL;
	mixed = (mixed ^ (mixed >> 30)) * 0xBF58476D1CE4E5B9ULL;
	mixed = (mixed ^ (mixed >> 27)) * 0x94D049BB133111EBULL;
	mixed ^= mixed >> 31;
	state = mixed != 0 ? mixed : 1;
}

int IncidentRandom::next(int p_bound) {
	state ^= state >> 12;
	state ^= state << 25;
	state ^= state >> 27;
	const uint64_t value = state * 2685821657736338717ULL;
	return static_cast<int>((value >> 33) % static_cast<uint64_t>(p_bound));
}

int get_incident_weight(const TacticsSim &p_sim, int p_soldier, int p_incident) {
	const IncidentRules &rules = p_sim.get_incident_rules();
	const IncidentDef &def = rules.incidents[p_incident];
	const UnitState &soldier = p_sim.get_units()[p_soldier];
	const bool is_good = def.handler->is_good;
	const int karma = p_sim.get_carried_karma(soldier.side, is_good ? KarmaKind::RESCUE : KarmaKind::BAIT);
	const int karma_weight = karma * rules.karma_weight_per_point;
	int weight = def.base_weight + (karma_weight < rules.karma_weight_cap ? karma_weight : rules.karma_weight_cap);
	weight += (is_good ? soldier.good_marks : soldier.bad_marks) * rules.mark_polarity_weight;
	int pct = PERCENT;
	if (soldier.leader != NO_UNIT) {
		for (const TraitDef &trait : p_sim.get_units()[soldier.leader].def.traits) {
			for (size_t index = 0; index < trait.incident_ids.size(); index++) {
				pct += trait.incident_ids[index] == def.id ? trait.weight_pcts[index] : 0;
			}
		}
	}
	return weight * (pct > 0 ? pct : 0) / PERCENT;
}

bool calm_wavering_soldier(TacticsSim &p_sim, int p_unit, const char *p_reason, int p_cause) {
	if (!p_sim.get_units()[p_unit].is_alive || p_sim.get_units()[p_unit].stage != IncidentStage::WAVERING) {
		return false;
	}
	calm_incident(p_sim, p_unit, p_reason, p_cause);
	return true;
}

void plant_incident_seeds(TacticsSim &p_sim) {
	if (!p_sim.get_forced_seeds().empty()) {
		for (const std::pair<int, int> &forced : p_sim.get_forced_seeds()) {
			UnitState &unit = p_sim.edit_unit(forced.first);
			unit.seed = forced.second;
			unit.stage = IncidentStage::DORMANT;
		}
		return;
	}
	for (int side = 0; side < SIDE_COUNT; side++) {
		plant_side_seeds(p_sim, side);
	}
}

void begin_incident_phase(TacticsSim &p_sim, int p_side, int p_cause) {
	const IncidentRules &rules = p_sim.get_incident_rules();
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.side != p_side || !unit.is_alive || unit.stage != IncidentStage::DORMANT) {
			continue;
		}
		const IncidentDef &def = rules.incidents[unit.seed];
		bool is_unseen = false;
		if (!def.handler->is_triggered(p_sim, unit.index, def)) {
			if (!rolls_unseen_waver(p_sim, unit.index, def)) {
				continue;
			}
			is_unseen = true;
		}
		p_sim.edit_unit(unit.index).stage = IncidentStage::WAVERING;
		p_sim.edit_unit(unit.index).is_unseen_waver = is_unseen;
		Event event;
		event.type = EventType::SOLDIER_WAVERED;
		event.unit = unit.index;
		event.content_id = def.id;
		event.is_first_strike = def.handler->is_good;
		event.cause = p_cause;
		p_sim.emit(event);
	}
}

void resolve_incident_phase(TacticsSim &p_sim, int p_side) {
	const int count = static_cast<int>(p_sim.get_units().size());
	for (int index = 0; index < count && !p_sim.is_finished(); index++) {
		const UnitState &unit = p_sim.get_units()[index];
		if (unit.side != p_side || !unit.is_alive || unit.stage != IncidentStage::WAVERING) {
			continue;
		}
		const IncidentDef &def = p_sim.get_incident_rules().incidents[unit.seed];
		const UnitState *leader = find_living_leader(p_sim, index);
		// Out of its leader's sight nobody can calm it (Docs/systems/tactics_vision.md).
		const bool is_out_of_sight = p_sim.is_out_of_leader_sight(index);
		const bool is_unseen = unit.is_unseen_waver;
		p_sim.edit_unit(index).is_unseen_waver = false;
		if (!def.handler->is_triggered(p_sim, index, def) && !(is_unseen && is_out_of_sight)) {
			calm_incident(p_sim, index, is_unseen ? "leader" : "faded");
		} else if (def.calm_radius_cells > 0 && leader != nullptr && !is_out_of_sight && get_manhattan(leader->cell, unit.cell) <= def.calm_radius_cells) {
			p_sim.edit_unit(index).bait_count = 0;
			calm_incident(p_sim, index, "leader");
		} else {
			fire_incident(p_sim, index);
		}
	}
}

int find_hit_guard(const TacticsSim &p_sim, int p_leader) {
	if (!p_sim.get_incident_rules().enabled || !p_sim.is_leader(p_leader)) {
		return p_leader;
	}
	const UnitState &leader = p_sim.get_units()[p_leader];
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.is_alive && unit.guard_leader == p_leader && unit.side == leader.side && p_sim.get_turn() < unit.guard_end_turn && get_manhattan(unit.cell, leader.cell) == 1) {
			return unit.index;
		}
	}
	return p_leader;
}

void note_soldier_hit(TacticsSim &p_sim, int p_soldier, int p_cause) {
	if (p_sim.get_incident_rules().enabled && p_sim.get_units()[p_soldier].is_alive && !p_sim.is_leader(p_soldier)) {
		add_bait(p_sim, p_soldier, p_cause);
	}
}

void note_unit_died(TacticsSim &p_sim, int p_unit, int p_cause) {
	if (!p_sim.get_incident_rules().enabled) {
		return;
	}
	const UnitState &dead = p_sim.get_units()[p_unit];
	if (!p_sim.is_leader(p_unit)) {
		add_bait(p_sim, p_unit, p_cause);
	}
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.is_alive && unit.side == dead.side && !p_sim.is_leader(unit.index) && get_manhattan(unit.cell, dead.cell) == 1) {
			p_sim.edit_unit(unit.index).ally_fell_turn = p_sim.get_turn();
		}
	}
}

// Only the leader's first rescue in a phase counts, so moving back and
// forth next to a hurt soldier earns nothing more.
void note_leader_moved(TacticsSim &p_sim, int p_leader, int p_cause) {
	if (!p_sim.get_incident_rules().enabled || p_sim.get_units()[p_leader].has_rescued) {
		return;
	}
	const UnitState &leader = p_sim.get_units()[p_leader];
	for (const UnitState &unit : p_sim.get_units()) {
		const bool is_hurt_ally = unit.is_alive && unit.side == leader.side && !p_sim.is_leader(unit.index) && get_hp_pct(unit) <= p_sim.get_incident_rules().rescue_hp_pct;
		if (is_hurt_ally && get_manhattan(unit.cell, leader.cell) == 1 && count_near(p_sim, unit.index, 1, true) > 0) {
			p_sim.edit_unit(p_leader).has_rescued = true;
			p_sim.add_karma(leader.side, KarmaKind::RESCUE, p_cause);
			return;
		}
	}
}

} // namespace tactics
