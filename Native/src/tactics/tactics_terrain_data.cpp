#include "tactics_terrain_data.h"

using namespace godot;

tactics::TerrainDef TacticsTerrainData::to_terrain_def() const {
	tactics::TerrainDef def;
	def.id = to_std_string(id);
	def.move_cost = move_cost;
	def.is_impassable = is_impassable;
	def.armor_bonus = armor_bonus;
	def.damage_taken_pct = damage_taken_pct;
	def.ranged_damage_taken_pct = ranged_damage_taken_pct;
	def.ranged_range_bonus = ranged_range_bonus;
	return def;
}

void TacticsTerrainData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, id);
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, move_cost);
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, is_impassable);
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, armor_bonus);
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, damage_taken_pct);
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, ranged_damage_taken_pct);
	BATTLE_BIND_ACCESSORS(TacticsTerrainData, ranged_range_bonus);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "move_cost", PROPERTY_HINT_RANGE, "1,20,1"), "set_move_cost", "get_move_cost");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_impassable"), "set_is_impassable", "get_is_impassable");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "armor_bonus"), "set_armor_bonus", "get_armor_bonus");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "damage_taken_pct", PROPERTY_HINT_RANGE, "-100,100,1"), "set_damage_taken_pct", "get_damage_taken_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ranged_damage_taken_pct", PROPERTY_HINT_RANGE, "-100,100,1"), "set_ranged_damage_taken_pct", "get_ranged_damage_taken_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ranged_range_bonus", PROPERTY_HINT_RANGE, "0,12,1"), "set_ranged_range_bonus", "get_ranged_range_bonus");
}
