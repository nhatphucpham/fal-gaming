#pragma once

// Sites (Docs/systems/tactics_sites.md): villages, shrines, camps and
// strongholds placed on a map. Each kind is a handler in the registry of
// the .cpp, tuned by a SiteDef (Data/Tactics/Sites/). A leader of the
// active side uses a site from its panel (TacticsSim::use_site) with one of
// the handler's choices; some sites also act at the start or end of a
// phase (a camp's rest, a stronghold's capture and reinforcements).

#include "tactics_types.h"

#include <string>
#include <vector>

namespace tactics {

class TacticsSim;

struct SiteHandler {
	const char *id;
	// The choices a leader picks from, in the order the panel shows them;
	// empty for a site that acts on its own.
	std::vector<std::string> choices;
	// Whether p_leader (already next to the site and free to act) may take
	// p_choice with p_option now; r_error says why not.
	bool (*check)(const TacticsSim &p_sim, int p_site, int p_leader, const std::string &p_choice, int p_option, std::string *r_error);
	void (*apply)(TacticsSim &p_sim, int p_site, int p_leader, const std::string &p_choice, int p_option, int p_cause);
	// The end and the start of p_side's phase; nullptr when it does nothing.
	void (*on_phase_end)(TacticsSim &p_sim, int p_site, int p_side, int p_cause);
	void (*on_phase_start)(TacticsSim &p_sim, int p_site, int p_side, int p_cause);
	// The numbers the handler reads are in range.
	bool (*validate)(const SiteDef &p_def, std::string *r_error);
};

// nullptr when the id is not registered.
const SiteHandler *find_site_handler(const std::string &p_id);
// How many options a choice has (a village's recruits), at least 1.
int get_site_option_count(const SiteDef &p_def, const std::string &p_choice);
// Range checks on a site placed on a map.
bool validate_site(const SitePlacement &p_site, int p_width, int p_height, std::string *r_error);
// Armor the stronghold under p_cell gives p_unit (its side holds it).
int get_site_armor_bonus(const TacticsSim &p_sim, int p_unit, const Cell &p_cell);
// The site on p_cell, NO_INDEX when none.
int find_site_at(const TacticsSim &p_sim, const Cell &p_cell);
// Phase hooks of every site, in map order.
void run_sites_phase_start(TacticsSim &p_sim, int p_side, int p_cause);
void run_sites_phase_end(TacticsSim &p_sim, int p_side, int p_cause);
// Before the battle ends: villages still standing count as good karma for
// side A (Docs/systems/tactics_sites.md, Karma).
void settle_sites(TacticsSim &p_sim, int p_cause);
// Whether the site is a village, by its handler.
bool is_village(const SiteDef &p_def);
bool is_stronghold(const SiteDef &p_def);
bool is_camp(const SiteDef &p_def);

} // namespace tactics
