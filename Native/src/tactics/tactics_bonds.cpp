#include "tactics_bonds.h"

#include "tactics_sim.h"

namespace tactics {

namespace {

bool is_close(const TacticsSim &p_sim, int p_unit, const Cell &p_cell, int p_partner) {
	const std::vector<UnitState> &units = p_sim.get_units();
	const UnitState &partner = units[p_partner];
	return units[p_unit].is_alive && partner.is_alive && units[p_unit].side == partner.side &&
			get_manhattan(p_cell, partner.cell) <= p_sim.get_bond_rules().radius_cells;
}

} // namespace

bool TacticsSim::set_bonds(const BondRules &p_rules, const std::vector<BondDef> &p_bonds, std::string *r_error) {
	if (!is_ready || started) {
		*r_error = "set_bonds() needs the leaders and a battle that has not started";
		return false;
	}
	if (!check_bonds(*this, p_rules, p_bonds, r_error)) {
		return false;
	}
	bonds_enabled = true;
	bond_rules = p_rules;
	bonds = p_bonds;
	return true;
}

bool check_bonds(const TacticsSim &p_sim, const BondRules &p_rules, const std::vector<BondDef> &p_bonds, std::string *r_error) {
	if (p_rules.radius_cells < 0 || p_rules.radius_cells > MAX_BOND_RADIUS_CELLS) {
		*r_error = "bond radius_cells " + std::to_string(p_rules.radius_cells) + " is outside 0.." + std::to_string(MAX_BOND_RADIUS_CELLS);
		return false;
	}
	if (p_rules.attack_pct_per_level < 0 || p_rules.attack_pct_per_level > MAX_BOND_ATTACK_PCT) {
		*r_error = "bond attack_pct_per_level " + std::to_string(p_rules.attack_pct_per_level) + " is outside 0.." + std::to_string(MAX_BOND_ATTACK_PCT);
		return false;
	}
	if (p_rules.max_level < 1 || p_rules.max_level > MAX_BOND_LEVEL) {
		*r_error = "bond max_level " + std::to_string(p_rules.max_level) + " is outside 1.." + std::to_string(MAX_BOND_LEVEL);
		return false;
	}
	const int count = static_cast<int>(p_sim.get_units().size());
	for (const BondDef &bond : p_bonds) {
		const bool are_units = bond.unit_a >= 0 && bond.unit_a < count && bond.unit_b >= 0 && bond.unit_b < count && bond.unit_a != bond.unit_b;
		if (!are_units || !p_sim.is_leader(bond.unit_a) || !p_sim.is_leader(bond.unit_b)) {
			*r_error = "a bond needs two different leaders, got units " + std::to_string(bond.unit_a) + " and " + std::to_string(bond.unit_b);
			return false;
		}
		if (p_sim.get_units()[bond.unit_a].start_side != p_sim.get_units()[bond.unit_b].start_side) {
			*r_error = "bonded leaders " + std::to_string(bond.unit_a) + " and " + std::to_string(bond.unit_b) + " are on different sides";
			return false;
		}
		if (bond.level < 1 || bond.level > p_rules.max_level) {
			*r_error = "bond level " + std::to_string(bond.level) + " is outside 1.." + std::to_string(p_rules.max_level);
			return false;
		}
	}
	return true;
}

std::vector<BondTally> make_bond_tallies(const TacticsSim &p_sim) {
	std::vector<BondTally> tallies;
	const std::vector<UnitState> &units = p_sim.get_units();
	for (const UnitState &first : units) {
		if (!p_sim.is_leader(first.index)) {
			continue;
		}
		for (const UnitState &second : units) {
			if (second.index > first.index && p_sim.is_leader(second.index) && second.start_side == first.start_side) {
				tallies.push_back({ first.index, second.index, 0 });
			}
		}
	}
	return tallies;
}

bool is_bond_active(const TacticsSim &p_sim, const BondDef &p_bond, int p_unit, const Cell &p_cell) {
	if (p_unit == p_bond.unit_a) {
		return is_close(p_sim, p_unit, p_cell, p_bond.unit_b);
	}
	if (p_unit == p_bond.unit_b) {
		return is_close(p_sim, p_unit, p_cell, p_bond.unit_a);
	}
	return false;
}

int get_bond_attack_pct(const TacticsSim &p_sim, int p_unit, const Cell &p_cell) {
	int pct = 0;
	for (const BondDef &bond : p_sim.get_bonds()) {
		if (is_bond_active(p_sim, bond, p_unit, p_cell)) {
			pct += bond.level * p_sim.get_bond_rules().attack_pct_per_level;
		}
	}
	return pct;
}

void tally_bonds(TacticsSim &p_sim, int p_side) {
	const std::vector<UnitState> &units = p_sim.get_units();
	for (BondTally &tally : p_sim.edit_bond_tallies()) {
		if (units[tally.unit_a].side == p_side && is_close(p_sim, tally.unit_a, units[tally.unit_a].cell, tally.unit_b)) {
			tally.phases++;
		}
	}
}

} // namespace tactics
