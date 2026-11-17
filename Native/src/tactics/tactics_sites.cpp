#include "tactics_sites.h"

#include "tactics_incidents.h"
#include "tactics_sim.h"
#include "tactics_skills.h"

// The site handlers: village (heal, recruit, loot), shrine (charge, calm,
// bless), camp (capture, rest) and stronghold (capture by standing on it,
// armor, sight, reinforcements). Docs/systems/tactics_sites.md.

namespace tactics {

namespace {

constexpr int PERCENT = 100;
constexpr int MAX_CELLS = 64;
constexpr int MAX_PHASES = 20;
constexpr int MAX_SUPPLIES = 100;
constexpr int MAX_KARMA = 10;

bool fail(std::string *r_error, const std::string &p_message) {
	*r_error = p_message;
	return false;
}

const SitePlacement &placed(const TacticsSim &p_sim, int p_site) {
	return p_sim.get_map().sites[p_site];
}

int get_living_soldiers(const TacticsSim &p_sim, int p_leader) {
	int count = 0;
	for (int soldier : p_sim.get_units()[p_leader].soldiers) {
		count += p_sim.get_units()[soldier].is_alive ? 1 : 0;
	}
	return count;
}

// The leader and its living soldiers.
std::vector<int> get_squad_units(const TacticsSim &p_sim, int p_leader) {
	std::vector<int> squad = { p_leader };
	for (int soldier : p_sim.get_units()[p_leader].soldiers) {
		if (p_sim.get_units()[soldier].is_alive) {
			squad.push_back(soldier);
		}
	}
	return squad;
}

bool is_hurt(const UnitState &p_unit) {
	return p_unit.is_alive && p_unit.hp < p_unit.def.max_hp;
}

int get_heal_amount(const UnitState &p_unit, int p_pct) {
	const int amount = p_unit.def.max_hp * p_pct / PERCENT;
	return amount < 1 ? 1 : amount;
}

void add_village_karma(TacticsSim &p_sim, int p_points, KarmaKind p_kind, int p_cause) {
	for (int point = 0; point < p_points; point++) {
		p_sim.add_karma(SIDE_A, p_kind, p_cause);
	}
}

// --- Village ------------------------------------------------------------

bool check_village(const TacticsSim &p_sim, int p_site, int p_leader, const std::string &p_choice, int p_option, std::string *r_error) {
	const SiteDef &def = placed(p_sim, p_site).def;
	if (p_sim.get_site_states()[p_site].status != SiteStatus::READY) {
		return fail(r_error, def.id + " was already visited or burned");
	}
	if (p_choice == "heal") {
		bool has_hurt = false;
		for (int unit : get_squad_units(p_sim, p_leader)) {
			has_hurt = has_hurt || is_hurt(p_sim.get_units()[unit]);
		}
		return has_hurt || fail(r_error, "nobody in the squad of leader " + std::to_string(p_leader) + " is hurt");
	}
	if (p_choice == "recruit") {
		if (p_option < 0 || p_option >= static_cast<int>(def.recruits.size())) {
			return fail(r_error, def.id + " has no recruit " + std::to_string(p_option));
		}
		return get_living_soldiers(p_sim, p_leader) < p_sim.get_squad_capacity(p_leader) || fail(r_error, "the squad of leader " + std::to_string(p_leader) + " is full");
	}
	return true;
}

void apply_village(TacticsSim &p_sim, int p_site, int p_leader, const std::string &p_choice, int p_option, int p_cause) {
	const SiteDef &def = placed(p_sim, p_site).def;
	SiteState &state = p_sim.edit_site(p_site);
	const int side = p_sim.get_units()[p_leader].side;
	state.uses++;
	if (p_choice == "loot") {
		state.status = SiteStatus::BURNED;
		state.burned_by = side;
		p_sim.change_site(p_site, side, "looted", p_cause);
		p_sim.add_supplies(side, def.supplies, def.id, p_cause);
		// Our own looting weighs more than a village the enemy reached.
		add_village_karma(p_sim, side == SIDE_A ? def.karma_looted : def.karma_burned, KarmaKind::BAIT, p_cause);
		return;
	}
	state.status = SiteStatus::USED;
	p_sim.change_site(p_site, side, "used", p_cause);
	if (p_choice == "heal") {
		for (int unit : get_squad_units(p_sim, p_leader)) {
			p_sim.heal_unit(unit, get_heal_amount(p_sim.get_units()[unit], def.heal_pct), def.id, p_cause);
		}
		return;
	}
	p_sim.spawn_soldier(p_leader, def.recruits[p_option], "recruit", p_cause);
}

bool validate_village(const SiteDef &p_def, std::string *r_error) {
	const bool is_valid = p_def.heal_pct >= 0 && p_def.heal_pct <= PERCENT && p_def.supplies >= 0 && p_def.supplies <= MAX_SUPPLIES &&
			p_def.karma_kept >= 0 && p_def.karma_kept <= MAX_KARMA && p_def.karma_burned >= 0 && p_def.karma_burned <= MAX_KARMA &&
			p_def.karma_looted >= 0 && p_def.karma_looted <= MAX_KARMA && !p_def.recruits.empty();
	return is_valid || fail(r_error, p_def.id + " needs heal_pct 0..100, supplies 0..100, karma 0..10 and at least one recruit");
}

// --- Shrine -------------------------------------------------------------

std::vector<int> find_wavering_near(const TacticsSim &p_sim, int p_leader, int p_radius) {
	std::vector<int> found;
	const UnitState &leader = p_sim.get_units()[p_leader];
	for (const UnitState &unit : p_sim.get_units()) {
		if (unit.is_alive && unit.side == leader.side && unit.stage == IncidentStage::WAVERING && get_manhattan(unit.cell, leader.cell) <= p_radius) {
			found.push_back(unit.index);
		}
	}
	return found;
}

bool check_shrine(const TacticsSim &p_sim, int p_site, int p_leader, const std::string &p_choice, int, std::string *r_error) {
	const SiteDef &def = placed(p_sim, p_site).def;
	const UnitState &leader = p_sim.get_units()[p_leader];
	if (p_sim.get_site_states()[p_site].status != SiteStatus::READY) {
		return fail(r_error, def.id + " was already prayed at");
	}
	if (p_choice == "charge") {
		return (leader.def.has_skill && leader.skill_charge < leader.def.skill.charge_threshold) || fail(r_error, "leader " + std::to_string(p_leader) + " has its skill charged");
	}
	if (p_choice == "calm") {
		return !find_wavering_near(p_sim, p_leader, def.calm_radius_cells).empty() || fail(r_error, "no wavering soldier near leader " + std::to_string(p_leader));
	}
	return true;
}

void apply_shrine(TacticsSim &p_sim, int p_site, int p_leader, const std::string &p_choice, int, int p_cause) {
	const SiteDef &def = placed(p_sim, p_site).def;
	SiteState &state = p_sim.edit_site(p_site);
	state.uses++;
	state.status = state.uses >= def.uses ? SiteStatus::USED : SiteStatus::READY;
	p_sim.change_site(p_site, p_sim.get_units()[p_leader].side, "used", p_cause);
	if (p_choice == "charge") {
		const UnitState &leader = p_sim.get_units()[p_leader];
		p_sim.change_skill_charge(p_leader, leader.def.skill.charge_threshold - leader.skill_charge, false, p_cause);
		return;
	}
	if (p_choice == "calm") {
		for (int soldier : find_wavering_near(p_sim, p_leader, def.calm_radius_cells)) {
			calm_wavering_soldier(p_sim, soldier, "shrine", p_cause);
		}
		return;
	}
	// The blessing lasts the rest of the battle.
	for (int unit : get_squad_units(p_sim, p_leader)) {
		BuffState buff;
		buff.unit = unit;
		buff.stat = def.bless_stat;
		buff.amount = def.bless_amount;
		buff.source_id = def.id;
		p_sim.add_buff(buff, p_sim.get_rules().max_rounds, p_cause);
	}
}

bool validate_shrine(const SiteDef &p_def, std::string *r_error) {
	const bool is_valid = p_def.calm_radius_cells >= 0 && p_def.calm_radius_cells <= MAX_CELLS && p_def.bless_stat != StatKind::NONE &&
			p_def.bless_amount >= -PERCENT && p_def.bless_amount <= PERCENT && p_def.uses >= 1;
	return is_valid || fail(r_error, p_def.id + " needs calm_radius_cells 0..64, a bless_stat, bless_amount -100..100 and uses >= 1");
}

// --- Camp ---------------------------------------------------------------

bool check_camp(const TacticsSim &p_sim, int p_site, int p_leader, const std::string &, int, std::string *r_error) {
	const UnitState &leader = p_sim.get_units()[p_leader];
	if (p_sim.get_site_states()[p_site].owner == leader.side) {
		return fail(r_error, "the camp is already held by side " + std::to_string(leader.side));
	}
	return !p_sim.has_enemy_next_to(leader.side, leader.cell) || fail(r_error, "an enemy stands next to leader " + std::to_string(p_leader));
}

void apply_camp(TacticsSim &p_sim, int p_site, int p_leader, const std::string &, int, int p_cause) {
	const int side = p_sim.get_units()[p_leader].side;
	SiteState &state = p_sim.edit_site(p_site);
	state.owner = side;
	state.owned_round = p_sim.get_round();
	state.uses++;
	p_sim.change_site(p_site, side, "captured", p_cause);
	p_sim.add_supplies(side, placed(p_sim, p_site).def.supplies, placed(p_sim, p_site).def.id, p_cause);
}

// Units of the owner within the camp's radius rest at the end of its phase.
void rest_at_camp(TacticsSim &p_sim, int p_site, int p_side, int p_cause) {
	const SitePlacement &site = placed(p_sim, p_site);
	if (p_sim.get_site_states()[p_site].owner != p_side) {
		return;
	}
	const int count = static_cast<int>(p_sim.get_units().size());
	for (int index = 0; index < count; index++) {
		const UnitState &unit = p_sim.get_units()[index];
		if (unit.side == p_side && is_hurt(unit) && !unit.def.is_noncombatant && get_manhattan(unit.cell, site.cell) <= site.def.radius_cells) {
			p_sim.heal_unit(index, get_heal_amount(unit, site.def.heal_pct), site.def.id, p_cause);
		}
	}
}

bool validate_camp(const SiteDef &p_def, std::string *r_error) {
	const bool is_valid = p_def.heal_pct >= 0 && p_def.heal_pct <= PERCENT && p_def.radius_cells >= 0 && p_def.radius_cells <= MAX_CELLS && p_def.supplies >= 0 && p_def.supplies <= MAX_SUPPLIES;
	return is_valid || fail(r_error, p_def.id + " needs heal_pct 0..100, radius_cells 0..64 and supplies 0..100");
}

// --- Stronghold ---------------------------------------------------------

int find_leader_on(const TacticsSim &p_sim, int p_side, const Cell &p_cell) {
	const int occupant = p_sim.get_occupant(p_cell);
	if (occupant == NO_UNIT || p_sim.get_units()[occupant].side != p_side || !p_sim.is_leader(occupant)) {
		return NO_UNIT;
	}
	return occupant;
}

void emit_capture(TacticsSim &p_sim, int p_site, int p_side, const char *p_kind, int p_cause) {
	Event event;
	event.type = EventType::CAPTURE_PROGRESSED;
	event.value = p_sim.get_site_states()[p_site].capture_progress;
	event.threshold = placed(p_sim, p_site).def.capture_phases;
	event.side = p_side;
	event.target = p_site;
	event.to = placed(p_sim, p_site).cell;
	event.kind = p_kind;
	event.amount = p_sim.get_seen_mask(event.to);
	event.cause = p_cause;
	p_sim.emit(event);
}

// End of p_side's phase: a leader of the side on it with no enemy next to
// it takes one more phase of the capture; contested, the count waits; with
// none of the side's leaders on it, the side's count is lost.
void capture_stronghold(TacticsSim &p_sim, int p_site, int p_side, int p_cause) {
	const SitePlacement &site = placed(p_sim, p_site);
	SiteState &state = p_sim.edit_site(p_site);
	const int holder = find_leader_on(p_sim, p_side, site.cell);
	if (holder == NO_UNIT) {
		if (state.capture_side == p_side && state.capture_progress > 0) {
			state.capture_progress = 0;
			emit_capture(p_sim, p_site, p_side, "lost", p_cause);
		}
		return;
	}
	if (state.owner == p_side) {
		return;
	}
	if (p_sim.has_enemy_next_to(p_side, site.cell)) {
		emit_capture(p_sim, p_site, p_side, "contested", p_cause);
		return;
	}
	if (state.capture_side != p_side) {
		state.capture_side = p_side;
		state.capture_progress = 0;
	}
	state.capture_progress++;
	emit_capture(p_sim, p_site, p_side, "advanced", p_cause);
	if (state.capture_progress >= site.def.capture_phases) {
		state.owner = p_side;
		state.owned_round = p_sim.get_round();
		state.capture_progress = 0;
		state.capture_side = NO_INDEX;
		p_sim.change_site(p_site, p_side, "captured", p_cause);
	}
}

// From its round, the owner's reinforcements arrive next to it, once.
void reinforce_stronghold(TacticsSim &p_sim, int p_site, int p_side, int p_cause) {
	const SiteDef &def = placed(p_sim, p_site).def;
	SiteState &state = p_sim.edit_site(p_site);
	if (!def.has_reinforcement || state.has_reinforced || state.owner != p_side || p_sim.get_round() < def.reinforce_round) {
		return;
	}
	state.has_reinforced = true;
	p_sim.spawn_leader(p_side, def.reinforce_leader, def.reinforce_squad, placed(p_sim, p_site).cell, "reinforce", p_cause);
}

bool check_none(const TacticsSim &, int, int, const std::string &, int, std::string *r_error) {
	return fail(r_error, "this site has no choice to take");
}

void apply_none(TacticsSim &, int, int, const std::string &, int, int) {
}

bool validate_stronghold(const SiteDef &p_def, std::string *r_error) {
	const bool is_valid = p_def.capture_phases >= 1 && p_def.capture_phases <= MAX_PHASES && p_def.vision_cells >= 0 && p_def.vision_cells <= MAX_CELLS &&
			p_def.armor_bonus >= 0 && p_def.armor_bonus <= 1000 && p_def.reinforce_round >= 0 && p_def.reinforce_round <= 1000 &&
			(!p_def.has_reinforcement || p_def.reinforce_round > 0);
	return is_valid || fail(r_error, p_def.id + " needs capture_phases 1..20, vision_cells 0..64, armor_bonus 0..1000 and a reinforce_round with its leader");
}

const SiteHandler SITE_HANDLERS[] = {
	{ "site_kind.village", { "heal", "recruit", "loot" }, check_village, apply_village, nullptr, nullptr, validate_village },
	{ "site_kind.shrine", { "charge", "calm", "bless" }, check_shrine, apply_shrine, nullptr, nullptr, validate_shrine },
	{ "site_kind.camp", { "capture" }, check_camp, apply_camp, rest_at_camp, nullptr, validate_camp },
	{ "site_kind.stronghold", {}, check_none, apply_none, capture_stronghold, reinforce_stronghold, validate_stronghold },
};

} // namespace

const SiteHandler *find_site_handler(const std::string &p_id) {
	for (const SiteHandler &handler : SITE_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

int get_site_option_count(const SiteDef &p_def, const std::string &p_choice) {
	if (p_choice == "recruit") {
		return static_cast<int>(p_def.recruits.size());
	}
	return 1;
}

bool validate_site(const SitePlacement &p_site, int p_width, int p_height, std::string *r_error) {
	const SiteDef &def = p_site.def;
	if (def.handler == nullptr) {
		return fail(r_error, def.id + " has no known kind");
	}
	const bool is_on_map = p_site.cell.col >= 0 && p_site.cell.col < p_width && p_site.cell.row >= 0 && p_site.cell.row < p_height;
	if (!is_on_map || p_site.owner < NO_INDEX || p_site.owner > SIDE_B) {
		return fail(r_error, def.id + " needs a cell on the map and an owner of -1, 0 or 1");
	}
	if (def.reach_cells < 0 || def.reach_cells > MAX_CELLS || def.uses < 1 || def.uses > MAX_PHASES) {
		return fail(r_error, def.id + " needs reach_cells 0..64 and uses 1..20");
	}
	return def.handler->validate(def, r_error);
}

int get_site_armor_bonus(const TacticsSim &p_sim, int p_unit, const Cell &p_cell) {
	const int site = find_site_at(p_sim, p_cell);
	if (site == NO_INDEX || !is_stronghold(placed(p_sim, site).def)) {
		return 0;
	}
	return p_sim.get_site_states()[site].owner == p_sim.get_units()[p_unit].side ? placed(p_sim, site).def.armor_bonus : 0;
}

int find_site_at(const TacticsSim &p_sim, const Cell &p_cell) {
	const std::vector<SitePlacement> &sites = p_sim.get_map().sites;
	for (size_t index = 0; index < sites.size(); index++) {
		if (sites[index].cell == p_cell) {
			return static_cast<int>(index);
		}
	}
	return NO_INDEX;
}

void run_sites_phase_start(TacticsSim &p_sim, int p_side, int p_cause) {
	const int count = static_cast<int>(p_sim.get_map().sites.size());
	for (int site = 0; site < count && !p_sim.is_finished(); site++) {
		if (placed(p_sim, site).def.handler->on_phase_start != nullptr) {
			placed(p_sim, site).def.handler->on_phase_start(p_sim, site, p_side, p_cause);
		}
	}
}

void run_sites_phase_end(TacticsSim &p_sim, int p_side, int p_cause) {
	const int count = static_cast<int>(p_sim.get_map().sites.size());
	for (int site = 0; site < count && !p_sim.is_finished(); site++) {
		if (placed(p_sim, site).def.handler->on_phase_end != nullptr) {
			placed(p_sim, site).def.handler->on_phase_end(p_sim, site, p_side, p_cause);
		}
	}
}

void settle_sites(TacticsSim &p_sim, int p_cause) {
	const int count = static_cast<int>(p_sim.get_map().sites.size());
	for (int site = 0; site < count; site++) {
		const SiteDef &def = placed(p_sim, site).def;
		if (is_village(def) && p_sim.get_site_states()[site].status != SiteStatus::BURNED) {
			add_village_karma(p_sim, def.karma_kept, KarmaKind::RESCUE, p_cause);
		}
	}
}

bool is_village(const SiteDef &p_def) {
	return p_def.handler == &SITE_HANDLERS[0];
}

bool is_stronghold(const SiteDef &p_def) {
	return p_def.handler == &SITE_HANDLERS[3];
}

bool is_camp(const SiteDef &p_def) {
	return p_def.handler == &SITE_HANDLERS[2];
}

} // namespace tactics
