#include "tactics_battle.h"

#include "tactics_vision.h"

#include <godot_cpp/core/error_macros.hpp>

// TacticsBattle's fog of war, weather and times of day
// (Docs/systems/tactics_vision.md): the environment of a scenario and what
// each side sees of the battle.

using namespace godot;

namespace {

constexpr uint8_t FOG_NEVER_SEEN = 0;
constexpr uint8_t FOG_SEEN = 1;
constexpr uint8_t FOG_VISIBLE = 2;

bool is_side(int64_t p_side) {
	return p_side == tactics::SIDE_A || p_side == tactics::SIDE_B;
}

} // namespace

bool TacticsBattle::set_environment(const Ref<TacticsScenarioData> &p_scenario) {
	ERR_FAIL_COND_V_MSG(p_scenario.is_null(), false, "Tactics: set_environment() got a null scenario");
	std::string error;
	ERR_FAIL_COND_V_MSG(!sim.set_environment(p_scenario->to_environment_def(), &error), false, vformat("Tactics: %s environment refused: %s", p_scenario->get_id(), to_godot_string(error)));
	return true;
}

PackedByteArray TacticsBattle::get_fog_cells(int64_t p_side) const {
	PackedByteArray cells;
	ERR_FAIL_COND_V_MSG(!is_side(p_side), cells, vformat("Tactics: get_fog_cells() got side %d, expected 0 or 1", p_side));
	const int side = static_cast<int>(p_side);
	const int count = sim.get_map().width * sim.get_map().height;
	cells.resize(count);
	for (int index = 0; index < count; index++) {
		const tactics::Cell cell = sim.get_cell_at(index);
		cells.set(index, sim.is_cell_visible(side, cell) ? FOG_VISIBLE : (sim.is_cell_seen(side, cell) ? FOG_SEEN : FOG_NEVER_SEEN));
	}
	return cells;
}

bool TacticsBattle::is_cell_visible(int64_t p_side, const Vector2i &p_cell) const {
	ERR_FAIL_COND_V_MSG(!is_side(p_side), false, vformat("Tactics: is_cell_visible() got side %d, expected 0 or 1", p_side));
	return sim.is_cell_visible(static_cast<int>(p_side), { p_cell.x, p_cell.y });
}

bool TacticsBattle::is_unit_seen(int64_t p_side, int64_t p_unit) const {
	ERR_FAIL_COND_V_MSG(!is_side(p_side), false, vformat("Tactics: is_unit_seen() got side %d, expected 0 or 1", p_side));
	return check_unit(p_unit, "is_unit_seen") && sim.is_unit_seen_by(static_cast<int>(p_side), static_cast<int>(p_unit));
}

Array TacticsBattle::get_last_seen(int64_t p_side) const {
	Array ghosts;
	ERR_FAIL_COND_V_MSG(!is_side(p_side), ghosts, vformat("Tactics: get_last_seen() got side %d, expected 0 or 1", p_side));
	const int side = static_cast<int>(p_side);
	for (const tactics::UnitState &unit : sim.get_units()) {
		const tactics::Cell cell = sim.get_last_seen(side, unit.index);
		if (cell == tactics::NO_CELL || sim.is_unit_seen_by(side, unit.index)) {
			continue;
		}
		Dictionary ghost;
		ghost["unit"] = unit.index;
		ghost["cell"] = Vector2i(cell.col, cell.row);
		ghosts.push_back(ghost);
	}
	return ghosts;
}

PackedByteArray TacticsBattle::get_lit_cells() const {
	PackedByteArray cells;
	if (sim.get_map().width * sim.get_map().height == 0) {
		return cells;
	}
	const std::vector<uint8_t> lit = tactics::compute_lit_cells(sim);
	cells.resize(static_cast<int64_t>(lit.size()));
	for (size_t index = 0; index < lit.size(); index++) {
		cells.set(static_cast<int64_t>(index), lit[index]);
	}
	return cells;
}

bool TacticsBattle::is_intent_known(int64_t p_side, int64_t p_leader) const {
	ERR_FAIL_COND_V_MSG(!is_side(p_side), false, vformat("Tactics: is_intent_known() got side %d, expected 0 or 1", p_side));
	return check_unit(p_leader, "is_intent_known") && sim.is_intent_known(static_cast<int>(p_side), static_cast<int>(p_leader));
}

StringName TacticsBattle::get_weather_id(int64_t p_round) const {
	return StringName(to_godot_string(sim.get_weather_of_round(static_cast<int>(p_round)).id));
}

StringName TacticsBattle::get_daytime_id(int64_t p_round) const {
	return StringName(to_godot_string(sim.get_daytime_of_round(static_cast<int>(p_round)).id));
}

int TacticsBattle::get_weather_change_round() const {
	const tactics::EnvironmentDef &environment = sim.get_environment();
	return environment.has_weather_change ? environment.weather_change_round : 0;
}
