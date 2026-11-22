#include "tactics_battle.h"

#include <godot_cpp/core/error_macros.hpp>

// TacticsBattle's bonds (Duyên): set before the battle, read on the map.

using namespace godot;

namespace {

int read_int(const Dictionary &p_entry, const char *p_key, int p_default) {
	return p_entry.has(p_key) ? clamp_to_int(static_cast<int64_t>(p_entry[p_key])) : p_default;
}

} // namespace

bool TacticsBattle::set_bonds(const Array &p_bonds, const Dictionary &p_rules) {
	tactics::BondRules rules;
	rules.radius_cells = read_int(p_rules, "radius_cells", rules.radius_cells);
	rules.attack_pct_per_level = read_int(p_rules, "attack_pct_per_level", rules.attack_pct_per_level);
	rules.max_level = read_int(p_rules, "max_level", rules.max_level);
	std::vector<tactics::BondDef> bonds;
	for (int64_t index = 0; index < p_bonds.size(); index++) {
		const Variant item = p_bonds[index];
		ERR_FAIL_COND_V_MSG(item.get_type() != Variant::DICTIONARY, false, vformat("Tactics: set_bonds() entry %d is not a Dictionary", index));
		const Dictionary entry = item;
		bonds.push_back({ read_int(entry, "a", tactics::NO_UNIT), read_int(entry, "b", tactics::NO_UNIT), read_int(entry, "level", 0) });
	}
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.set_bonds(rules, bonds, &error), false, "Tactics: set_bonds() refused: " + to_godot_string(error));
	return true;
}

Array TacticsBattle::get_bonds() const {
	Array result;
	const std::vector<tactics::UnitState> &units = sim.get_units();
	for (const tactics::BondDef &bond : sim.get_bonds()) {
		Dictionary entry;
		entry["a"] = bond.unit_a;
		entry["b"] = bond.unit_b;
		entry["level"] = bond.level;
		entry["is_active"] = tactics::is_bond_active(sim, bond, bond.unit_a, units[bond.unit_a].cell);
		entry["attack_pct"] = bond.level * sim.get_bond_rules().attack_pct_per_level;
		result.push_back(entry);
	}
	return result;
}
