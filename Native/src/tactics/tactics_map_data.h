#pragma once

#include "tactics_site_data.h"
#include "tactics_terrain_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <string>

namespace godot {

// A tactics map: one row of terrain symbols per map row, a legend from
// symbol to terrain, leader spawn cells per side and an optional objective
// cell. One file per map in Data/Tactics/Maps/, id `map.<name>`.
//   rows = PackedStringArray("..f..", ...); legend_symbols = ".f"
//   legend_terrains = [plain.tres, forest.tres]
class TacticsMapData : public Resource {
	GDCLASS(TacticsMapData, Resource)

	StringName id;
	String name_key;
	int width = 12;
	int height = 16;
	PackedStringArray rows;
	String legend_symbols;
	TypedArray<TacticsTerrainData> legend_terrains;
	TypedArray<Vector2i> spawn_cells_a;
	TypedArray<Vector2i> spawn_cells_b;
	Vector2i objective_cell = Vector2i(-1, -1);
	int objective_side = 0;
	Vector2i facing_a = Vector2i(0, -1);
	Vector2i facing_b = Vector2i(0, 1);
	TypedArray<Vector2i> guard_cells;
	// Sites placed on the map (Docs/systems/tactics_sites.md): sites[i] on
	// site_cells[i], held at the start by site_owners[i] (-1 nobody; an
	// empty array: nobody holds any).
	TypedArray<TacticsSiteData> sites;
	TypedArray<Vector2i> site_cells;
	PackedInt32Array site_owners;

protected:
	static void _bind_methods();

public:
	// False and r_error when a row has the wrong length or an unknown symbol.
	bool to_map_def(tactics::MapDef *r_def, std::string *r_error) const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_width(int64_t p_value) { width = clamp_to_int(p_value); }
	int get_width() const { return width; }
	void set_height(int64_t p_value) { height = clamp_to_int(p_value); }
	int get_height() const { return height; }
	void set_rows(const PackedStringArray &p_value) { rows = p_value; }
	PackedStringArray get_rows() const { return rows; }
	void set_legend_symbols(const String &p_value) { legend_symbols = p_value; }
	String get_legend_symbols() const { return legend_symbols; }
	void set_legend_terrains(const TypedArray<TacticsTerrainData> &p_value) { legend_terrains = p_value; }
	TypedArray<TacticsTerrainData> get_legend_terrains() const { return legend_terrains; }
	void set_spawn_cells_a(const TypedArray<Vector2i> &p_value) { spawn_cells_a = p_value; }
	TypedArray<Vector2i> get_spawn_cells_a() const { return spawn_cells_a; }
	void set_spawn_cells_b(const TypedArray<Vector2i> &p_value) { spawn_cells_b = p_value; }
	TypedArray<Vector2i> get_spawn_cells_b() const { return spawn_cells_b; }
	void set_objective_cell(const Vector2i &p_value) { objective_cell = p_value; }
	Vector2i get_objective_cell() const { return objective_cell; }
	void set_objective_side(int64_t p_value) { objective_side = clamp_to_int(p_value); }
	int get_objective_side() const { return objective_side; }
	void set_facing_a(const Vector2i &p_value) { facing_a = p_value; }
	Vector2i get_facing_a() const { return facing_a; }
	void set_facing_b(const Vector2i &p_value) { facing_b = p_value; }
	Vector2i get_facing_b() const { return facing_b; }
	void set_guard_cells(const TypedArray<Vector2i> &p_value) { guard_cells = p_value; }
	TypedArray<Vector2i> get_guard_cells() const { return guard_cells; }
	void set_sites(const TypedArray<TacticsSiteData> &p_value) { sites = p_value; }
	TypedArray<TacticsSiteData> get_sites() const { return sites; }
	void set_site_cells(const TypedArray<Vector2i> &p_value) { site_cells = p_value; }
	TypedArray<Vector2i> get_site_cells() const { return site_cells; }
	void set_site_owners(const PackedInt32Array &p_value) { site_owners = p_value; }
	PackedInt32Array get_site_owners() const { return site_owners; }
	// The spawn cells of a side (0 or 1); empty with an error for another side.
	TypedArray<Vector2i> get_spawn_cells(int64_t p_side) const {
		ERR_FAIL_COND_V_MSG(p_side != tactics::SIDE_A && p_side != tactics::SIDE_B, TypedArray<Vector2i>(), vformat("Tactics: get_spawn_cells() got side %d, expected 0 or 1", p_side));
		return p_side == tactics::SIDE_A ? spawn_cells_a : spawn_cells_b;
	}
};

} // namespace godot
