#include "tactics_map_data.h"

using namespace godot;

bool TacticsMapData::to_map_def(tactics::MapDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->width = width;
	r_def->height = height;
	r_def->terrains.clear();
	if (legend_terrains.size() != legend_symbols.length()) {
		*r_error = r_def->id + " has " + std::to_string(legend_symbols.length()) + " legend symbols for " + std::to_string(legend_terrains.size()) + " terrains";
		return false;
	}
	for (int64_t index = 0; index < legend_terrains.size(); index++) {
		// A repeated symbol would silently map every cell to its first terrain.
		if (legend_symbols.find(String::chr(legend_symbols[index])) != index) {
			*r_error = r_def->id + " has legend symbol '" + to_std_string(String::chr(legend_symbols[index])) + "' more than once";
			return false;
		}
		const Ref<TacticsTerrainData> terrain = legend_terrains[index];
		if (terrain.is_null()) {
			*r_error = r_def->id + " has an empty legend terrain at " + std::to_string(index);
			return false;
		}
		r_def->terrains.push_back(terrain->to_terrain_def());
	}
	if (rows.size() != height) {
		*r_error = r_def->id + " has " + std::to_string(rows.size()) + " rows, expected height " + std::to_string(height);
		return false;
	}
	r_def->cell_terrain.clear();
	for (int64_t row = 0; row < rows.size(); row++) {
		const String &line = rows[row];
		if (line.length() != width) {
			*r_error = r_def->id + " row " + std::to_string(row) + " has " + std::to_string(line.length()) + " cells, expected width " + std::to_string(width);
			return false;
		}
		for (int64_t col = 0; col < line.length(); col++) {
			const int64_t terrain = legend_symbols.find(String::chr(line[col]));
			if (terrain < 0) {
				*r_error = r_def->id + " row " + std::to_string(row) + " col " + std::to_string(col) + " has a symbol missing from legend_symbols";
				return false;
			}
			r_def->cell_terrain.push_back(static_cast<int>(terrain));
		}
	}
	r_def->has_objective = objective_cell != Vector2i(-1, -1);
	r_def->objective = { objective_cell.x, objective_cell.y };
	r_def->objective_side = objective_side;
	r_def->facing[tactics::SIDE_A] = { facing_a.x, facing_a.y };
	r_def->facing[tactics::SIDE_B] = { facing_b.x, facing_b.y };
	r_def->guard_cells.clear();
	for (int64_t index = 0; index < guard_cells.size(); index++) {
		const Vector2i cell = guard_cells[index];
		r_def->guard_cells.push_back({ cell.x, cell.y });
	}
	r_def->sites.clear();
	if (site_cells.size() != sites.size() || (!site_owners.is_empty() && site_owners.size() != sites.size())) {
		*r_error = r_def->id + " needs one site cell (and owner, if any) per site";
		return false;
	}
	for (int64_t index = 0; index < sites.size(); index++) {
		const Ref<TacticsSiteData> site = sites[index];
		tactics::SitePlacement placement;
		if (site.is_null() || !site->to_site_def(&placement.def, r_error)) {
			*r_error = r_def->id + ": " + (site.is_null() ? "empty site entry " + std::to_string(index) : *r_error);
			return false;
		}
		const Vector2i cell = site_cells[index];
		placement.cell = { cell.x, cell.y };
		placement.owner = site_owners.is_empty() ? tactics::NO_INDEX : site_owners[index];
		r_def->sites.push_back(placement);
	}
	return true;
}

void TacticsMapData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsMapData, id);
	BATTLE_BIND_ACCESSORS(TacticsMapData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsMapData, width);
	BATTLE_BIND_ACCESSORS(TacticsMapData, height);
	BATTLE_BIND_ACCESSORS(TacticsMapData, rows);
	BATTLE_BIND_ACCESSORS(TacticsMapData, legend_symbols);
	BATTLE_BIND_ACCESSORS(TacticsMapData, legend_terrains);
	BATTLE_BIND_ACCESSORS(TacticsMapData, spawn_cells_a);
	BATTLE_BIND_ACCESSORS(TacticsMapData, spawn_cells_b);
	BATTLE_BIND_ACCESSORS(TacticsMapData, objective_cell);
	BATTLE_BIND_ACCESSORS(TacticsMapData, objective_side);
	BATTLE_BIND_ACCESSORS(TacticsMapData, facing_a);
	BATTLE_BIND_ACCESSORS(TacticsMapData, facing_b);
	BATTLE_BIND_ACCESSORS(TacticsMapData, guard_cells);
	BATTLE_BIND_ACCESSORS(TacticsMapData, sites);
	BATTLE_BIND_ACCESSORS(TacticsMapData, site_cells);
	BATTLE_BIND_ACCESSORS(TacticsMapData, site_owners);
	ClassDB::bind_method(D_METHOD("get_spawn_cells", "side"), &TacticsMapData::get_spawn_cells);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "width", PROPERTY_HINT_RANGE, "1,32,1"), "set_width", "get_width");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "height", PROPERTY_HINT_RANGE, "1,32,1"), "set_height", "get_height");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "rows"), "set_rows", "get_rows");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "legend_symbols"), "set_legend_symbols", "get_legend_symbols");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "legend_terrains", PROPERTY_HINT_ARRAY_TYPE, "TacticsTerrainData"), "set_legend_terrains", "get_legend_terrains");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "spawn_cells_a", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_spawn_cells_a", "get_spawn_cells_a");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "spawn_cells_b", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_spawn_cells_b", "get_spawn_cells_b");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "objective_cell"), "set_objective_cell", "get_objective_cell");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "objective_side", PROPERTY_HINT_RANGE, "0,1,1"), "set_objective_side", "get_objective_side");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "facing_a"), "set_facing_a", "get_facing_a");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "facing_b"), "set_facing_b", "get_facing_b");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "guard_cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_guard_cells", "get_guard_cells");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "sites", PROPERTY_HINT_ARRAY_TYPE, "TacticsSiteData"), "set_sites", "get_sites");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "site_cells", PROPERTY_HINT_ARRAY_TYPE, "Vector2i"), "set_site_cells", "get_site_cells");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "site_owners"), "set_site_owners", "get_site_owners");
}
