#pragma once

// Duyên (bonds): two leaders of one side who fought shoulder to shoulder in
// earlier battles have a bond level (the roster keeps it). While both stand
// within BondRules::radius_cells of each other, each gets
// attack_pct_per_level % attack per level. The battle also counts, for
// every pair of leaders that started on one side, that side's phases that
// ended with both alive and within the radius; the roster builds bonds
// from that count. See Docs/systems/tactics_world.md.

#include "tactics_types.h"

#include <string>
#include <vector>

namespace tactics {

class TacticsSim;

struct BondRules {
	int radius_cells = 2;
	int attack_pct_per_level = 5;
	int max_level = 3;
};

struct BondDef {
	int unit_a = NO_UNIT;
	int unit_b = NO_UNIT;
	int level = 0;
};

// Phases of their side that ended with both leaders alive and close.
struct BondTally {
	int unit_a = NO_UNIT;
	int unit_b = NO_UNIT;
	int phases = 0;
};

// The source id a forecast names for a bond's attack bonus.
constexpr const char *BOND_SOURCE_ID = "bond";
constexpr int MAX_BOND_RADIUS_CELLS = 8;
constexpr int MAX_BOND_ATTACK_PCT = 100;
constexpr int MAX_BOND_LEVEL = 5;

// Checks the rules and every bond against the battle's leaders.
bool check_bonds(const TacticsSim &p_sim, const BondRules &p_rules, const std::vector<BondDef> &p_bonds, std::string *r_error);
// One tally per pair of leaders that share a start side, in unit order.
std::vector<BondTally> make_bond_tallies(const TacticsSim &p_sim);
// Whether the bond's two leaders are alive, on one side and close, with
// p_unit standing at p_cell (a forecast may ask about another cell).
bool is_bond_active(const TacticsSim &p_sim, const BondDef &p_bond, int p_unit, const Cell &p_cell);
// The attack percent p_unit's bonds give it at p_cell.
int get_bond_attack_pct(const TacticsSim &p_sim, int p_unit, const Cell &p_cell);
// Counts the phase that p_side just closed.
void tally_bonds(TacticsSim &p_sim, int p_side);

} // namespace tactics
