#pragma once

#include "tactics_scenario_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// Every tactics data file, listed explicitly so nothing scans directories
// at runtime (that breaks in exported and web builds). The project uses
// Data/Tactics/tactics_catalog.tres; the auto battle's Catalog does not
// know about it.
//   var catalog := load("res://Data/Tactics/tactics_catalog.tres") as TacticsCatalog
//   assert(catalog.validate().is_empty())
//   battle.load_scenario(catalog.get_scenario(&"scenario.river_crossing"))
class TacticsCatalog : public Resource {
	GDCLASS(TacticsCatalog, Resource)

	Ref<TacticsRulesData> rules;
	TypedArray<TacticsTerrainData> terrains;
	TypedArray<TacticsKeywordData> keywords;
	TypedArray<TacticsZoneData> zones;
	TypedArray<TacticsPassiveData> passives;
	TypedArray<TacticsSkillData> skills;
	TypedArray<TacticsTroopData> troops;
	TypedArray<TacticsLeaderData> leaders;
	TypedArray<TacticsMapData> maps;
	TypedArray<TacticsScenarioData> scenarios;

	void validate_ids(const Array &p_entries, const String &p_prefix, bool p_needs_description, PackedStringArray &r_problems) const;
	void validate_units(PackedStringArray &r_problems) const;
	// Keywords and zones used by units, passives and skills are listed.
	void validate_references(PackedStringArray &r_problems) const;
	void validate_maps(PackedStringArray &r_problems) const;
	void validate_scenarios(PackedStringArray &r_problems) const;

protected:
	static void _bind_methods();

public:
	// Problems in the data, one message per problem; empty when valid.
	PackedStringArray validate() const;
	Ref<TacticsTerrainData> get_terrain(const StringName &p_id) const;
	Ref<TacticsKeywordData> get_keyword(const StringName &p_id) const;
	Ref<TacticsZoneData> get_zone(const StringName &p_id) const;
	Ref<TacticsPassiveData> get_passive(const StringName &p_id) const;
	Ref<TacticsSkillData> get_skill(const StringName &p_id) const;
	Ref<TacticsTroopData> get_troop(const StringName &p_id) const;
	Ref<TacticsLeaderData> get_leader(const StringName &p_id) const;
	Ref<TacticsMapData> get_map(const StringName &p_id) const;
	Ref<TacticsScenarioData> get_scenario(const StringName &p_id) const;

	void set_rules(const Ref<TacticsRulesData> &p_value) { rules = p_value; }
	Ref<TacticsRulesData> get_rules() const { return rules; }
	void set_terrains(const TypedArray<TacticsTerrainData> &p_value) { terrains = p_value; }
	TypedArray<TacticsTerrainData> get_terrains() const { return terrains; }
	void set_keywords(const TypedArray<TacticsKeywordData> &p_value) { keywords = p_value; }
	TypedArray<TacticsKeywordData> get_keywords() const { return keywords; }
	void set_zones(const TypedArray<TacticsZoneData> &p_value) { zones = p_value; }
	TypedArray<TacticsZoneData> get_zones() const { return zones; }
	void set_passives(const TypedArray<TacticsPassiveData> &p_value) { passives = p_value; }
	TypedArray<TacticsPassiveData> get_passives() const { return passives; }
	void set_skills(const TypedArray<TacticsSkillData> &p_value) { skills = p_value; }
	TypedArray<TacticsSkillData> get_skills() const { return skills; }
	void set_troops(const TypedArray<TacticsTroopData> &p_value) { troops = p_value; }
	TypedArray<TacticsTroopData> get_troops() const { return troops; }
	void set_leaders(const TypedArray<TacticsLeaderData> &p_value) { leaders = p_value; }
	TypedArray<TacticsLeaderData> get_leaders() const { return leaders; }
	void set_maps(const TypedArray<TacticsMapData> &p_value) { maps = p_value; }
	TypedArray<TacticsMapData> get_maps() const { return maps; }
	void set_scenarios(const TypedArray<TacticsScenarioData> &p_value) { scenarios = p_value; }
	TypedArray<TacticsScenarioData> get_scenarios() const { return scenarios; }
};

} // namespace godot
