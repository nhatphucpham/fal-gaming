#include "tactics_catalog.h"

#include "tactics_orders.h"
#include "tactics_passives.h"
#include "tactics_sim.h"
#include "tactics_validation.h"

#include <godot_cpp/variant/dictionary.hpp>

using namespace godot;

namespace {

constexpr int MIN_LEADER_PASSIVES = 1;

template <typename T>
Ref<T> find_by_id(const TypedArray<T> &p_entries, const StringName &p_id) {
	for (int64_t index = 0; index < p_entries.size(); index++) {
		const Ref<T> entry = p_entries[index];
		if (entry.is_valid() && entry->get_id() == p_id) {
			return entry;
		}
	}
	return Ref<T>();
}

bool contains(const Array &p_entries, const Variant &p_entry) {
	return p_entries.has(p_entry);
}

String where(const Ref<Resource> &p_resource) {
	return p_resource->get_path().is_empty() ? String(p_resource->get("id")) : p_resource->get_path();
}

} // namespace

void TacticsCatalog::validate_ids(const Array &p_entries, const String &p_prefix, bool p_needs_description, PackedStringArray &r_problems) const {
	Dictionary seen;
	for (int64_t index = 0; index < p_entries.size(); index++) {
		const Ref<Resource> entry = p_entries[index];
		if (entry.is_null()) {
			r_problems.push_back(vformat("TacticsCatalog: an empty %s entry at %d", p_prefix, index));
			continue;
		}
		const String id = entry->get("id");
		if (!id.begins_with(p_prefix) || seen.has(id)) {
			r_problems.push_back(vformat("TacticsCatalog: %s has a bad or duplicate id '%s', expected %s<name>", where(entry), id, p_prefix));
		}
		seen[id] = true;
		if (String(entry->get("name_key")).is_empty() || (p_needs_description && String(entry->get("description_key")).is_empty())) {
			r_problems.push_back(vformat("TacticsCatalog: %s needs name_key%s", where(entry), p_needs_description ? " and description_key" : ""));
		}
	}
}

void TacticsCatalog::validate_units(PackedStringArray &r_problems) const {
	for (int64_t index = 0; index < troops.size(); index++) {
		const Ref<TacticsTroopData> troop = troops[index];
		tactics::UnitDef def;
		std::string error;
		if (troop.is_valid() && (!troop->to_unit_def(&def, &error) || !tactics::validate_unit_def(def, &error))) {
			r_problems.push_back("TacticsCatalog: " + to_godot_string(error));
		}
	}
	for (int64_t index = 0; index < leaders.size(); index++) {
		const Ref<TacticsLeaderData> leader = leaders[index];
		if (leader.is_null()) {
			continue;
		}
		tactics::UnitDef def;
		std::string error;
		if (!leader->to_unit_def(&def, &error) || !tactics::validate_unit_def(def, &error)) {
			r_problems.push_back("TacticsCatalog: " + to_godot_string(error));
			continue;
		}
		if (def.passives.size() < static_cast<size_t>(MIN_LEADER_PASSIVES) || !def.has_skill) {
			r_problems.push_back(vformat("TacticsCatalog: %s needs 1..3 passives and a skill", where(leader)));
		}
		const TypedArray<TacticsPassiveData> leader_passives = leader->get_passives();
		for (int64_t passive = 0; passive < leader_passives.size(); passive++) {
			if (!contains(passives, leader_passives[passive])) {
				r_problems.push_back(vformat("TacticsCatalog: %s uses a passive not listed in passives", where(leader)));
			}
		}
		if (leader->get_skill().is_valid() && !contains(skills, leader->get_skill())) {
			r_problems.push_back(vformat("TacticsCatalog: %s uses a skill not listed in skills", where(leader)));
		}
		const TypedArray<TacticsTroopData> squad = leader->get_squad();
		for (int64_t soldier = 0; soldier < squad.size(); soldier++) {
			if (!contains(troops, squad[soldier])) {
				r_problems.push_back(vformat("TacticsCatalog: %s has a squad troop not listed in troops", where(leader)));
			}
		}
		// The same capacity TacticsSim::get_squad_capacity() gives the leader.
		int capacity = def.lead_capacity;
		for (const tactics::PassiveDef &passive : def.passives) {
			capacity += passive.handler->get_extra_capacity != nullptr ? passive.handler->get_extra_capacity(passive) : 0;
		}
		capacity = capacity < tactics::MAX_SQUAD_SIZE ? capacity : tactics::MAX_SQUAD_SIZE;
		if (squad.size() > capacity) {
			r_problems.push_back(vformat("TacticsCatalog: %s has %d soldiers for a capacity of %d", where(leader), squad.size(), capacity));
		}
	}
}

void TacticsCatalog::validate_references(PackedStringArray &r_problems) const {
	Array units;
	units.append_array(troops);
	units.append_array(leaders);
	for (int64_t index = 0; index < units.size(); index++) {
		const Ref<TacticsUnitData> unit = units[index];
		if (unit.is_null()) {
			continue;
		}
		const TypedArray<TacticsKeywordData> unit_keywords = unit->get_keywords();
		for (int64_t keyword = 0; keyword < unit_keywords.size(); keyword++) {
			if (!contains(keywords, unit_keywords[keyword])) {
				r_problems.push_back(vformat("TacticsCatalog: %s uses a keyword not listed in keywords", where(unit)));
			}
		}
	}
	validate_terrain_ids(r_problems);
	for (int64_t index = 0; index < passives.size(); index++) {
		const Ref<TacticsPassiveData> passive = passives[index];
		const bool is_unlisted = passive.is_valid() && ((passive->get_keyword().is_valid() && !contains(keywords, passive->get_keyword())) || (passive->get_zone().is_valid() && !contains(zones, passive->get_zone())));
		if (is_unlisted) {
			r_problems.push_back(vformat("TacticsCatalog: %s uses a keyword or zone not listed in the catalog", where(passive)));
		}
	}
	for (int64_t index = 0; index < skills.size(); index++) {
		const Ref<TacticsSkillData> skill = skills[index];
		const TypedArray<TacticsSkillEffectData> effects = skill.is_valid() ? skill->get_effects() : TypedArray<TacticsSkillEffectData>();
		for (int64_t effect = 0; effect < effects.size(); effect++) {
			const Ref<TacticsSkillEffectData> data = effects[effect];
			if (data.is_valid() && data->get_zone().is_valid() && !contains(zones, data->get_zone())) {
				r_problems.push_back(vformat("TacticsCatalog: %s uses a zone not listed in zones", where(skill)));
			}
		}
	}
}

// Terrain ids named by keywords (heavy) and passives (a terrain condition)
// exist, so a typo does not silently switch the effect off.
void TacticsCatalog::validate_terrain_ids(PackedStringArray &r_problems) const {
	Dictionary known;
	for (int64_t index = 0; index < terrains.size(); index++) {
		const Ref<TacticsTerrainData> terrain = terrains[index];
		if (terrain.is_valid()) {
			known[terrain->get_id()] = true;
		}
	}
	for (int64_t index = 0; index < keywords.size(); index++) {
		const Ref<TacticsKeywordData> keyword = keywords[index];
		const Array terrain_ids = keyword.is_valid() ? keyword->get_terrain_ids() : Array();
		for (int64_t terrain = 0; terrain < terrain_ids.size(); terrain++) {
			if (!known.has(StringName(terrain_ids[terrain]))) {
				r_problems.push_back(vformat("TacticsCatalog: %s names unknown terrain %s", where(keyword), terrain_ids[terrain]));
			}
		}
	}
	for (int64_t index = 0; index < passives.size(); index++) {
		const Ref<TacticsPassiveData> passive = passives[index];
		if (passive.is_valid() && !String(passive->get_condition_terrain_id()).is_empty() && !known.has(passive->get_condition_terrain_id())) {
			r_problems.push_back(vformat("TacticsCatalog: %s names unknown terrain %s", where(passive), passive->get_condition_terrain_id()));
		}
	}
}

void TacticsCatalog::validate_maps(PackedStringArray &r_problems) const {
	for (int64_t index = 0; index < maps.size(); index++) {
		const Ref<TacticsMapData> map = maps[index];
		if (map.is_null()) {
			continue;
		}
		tactics::MapDef def;
		std::string error;
		if (!map->to_map_def(&def, &error) || !tactics::validate_map(def, &error)) {
			r_problems.push_back("TacticsCatalog: " + to_godot_string(error));
			continue;
		}
		const TypedArray<TacticsTerrainData> legend = map->get_legend_terrains();
		for (int64_t terrain = 0; terrain < legend.size(); terrain++) {
			if (!contains(terrains, legend[terrain])) {
				r_problems.push_back(vformat("TacticsCatalog: %s uses a terrain not listed in terrains", where(map)));
			}
		}
		Dictionary used;
		for (int side = 0; side < tactics::SIDE_COUNT; side++) {
			const TypedArray<Vector2i> spawns = map->get_spawn_cells(side);
			for (int64_t spawn = 0; spawn < spawns.size(); spawn++) {
				const Vector2i cell = spawns[spawn];
				if (cell.x < 0 || cell.x >= def.width || cell.y < 0 || cell.y >= def.height) {
					r_problems.push_back(vformat("TacticsCatalog: %s has spawn cell %s off the map", where(map), cell));
					continue;
				}
				// A leader cannot be placed there: add_leader() would refuse it.
				const tactics::TerrainDef &terrain = def.terrains[def.cell_terrain[cell.y * def.width + cell.x]];
				if (used.has(cell) || terrain.is_impassable) {
					r_problems.push_back(vformat("TacticsCatalog: %s has spawn cell %s twice or on impassable terrain", where(map), cell));
				}
				used[cell] = true;
			}
		}
	}
}

void TacticsCatalog::validate_scenarios(PackedStringArray &r_problems) const {
	for (int64_t index = 0; index < scenarios.size(); index++) {
		const Ref<TacticsScenarioData> scenario = scenarios[index];
		if (scenario.is_null()) {
			continue;
		}
		if (scenario->get_rules().is_null() || scenario->get_map().is_null() || !contains(maps, scenario->get_map())) {
			r_problems.push_back(vformat("TacticsCatalog: %s needs rules and a map listed in maps", where(scenario)));
			continue;
		}
		for (int side = 0; side < tactics::SIDE_COUNT; side++) {
			const TypedArray<TacticsLeaderData> side_leaders = scenario->get_leaders(side);
			if (side_leaders.is_empty() || side_leaders.size() > scenario->get_map()->get_spawn_cells(side).size() || side_leaders.size() > scenario->get_rules()->get_max_leaders_per_side()) {
				r_problems.push_back(vformat("TacticsCatalog: %s side %d has %d leaders for %d spawn cells", where(scenario), side, side_leaders.size(), scenario->get_map()->get_spawn_cells(side).size()));
			}
			for (int64_t leader = 0; leader < side_leaders.size(); leader++) {
				if (!contains(leaders, side_leaders[leader])) {
					r_problems.push_back(vformat("TacticsCatalog: %s uses a leader not listed in leaders", where(scenario)));
				}
			}
		}
		std::string error;
		if (!try_load_scenario(scenario, &error)) {
			r_problems.push_back(vformat("TacticsCatalog: %s does not load: %s", where(scenario), to_godot_string(error)));
		}
	}
}

// Places the scenario's leaders as TacticsBattle.load_scenario() does, so a
// spawn cell that a soldier placed before takes is caught here.
bool TacticsCatalog::try_load_scenario(const Ref<TacticsScenarioData> &p_scenario, std::string *r_error) const {
	tactics::MapDef map;
	tactics::TacticsSim sim;
	if (!p_scenario->get_map()->to_map_def(&map, r_error) || !sim.setup(p_scenario->get_rules()->to_rules(), map, r_error)) {
		return false;
	}
	for (int side = 0; side < tactics::SIDE_COUNT; side++) {
		const TypedArray<TacticsLeaderData> side_leaders = p_scenario->get_leaders(side);
		const TypedArray<Vector2i> spawns = p_scenario->get_map()->get_spawn_cells(side);
		for (int64_t index = 0; index < side_leaders.size() && index < spawns.size(); index++) {
			const Ref<TacticsLeaderData> leader = side_leaders[index];
			tactics::UnitDef def;
			std::vector<tactics::UnitDef> squad;
			if (leader.is_null()) {
				*r_error = "side " + std::to_string(side) + " leader " + std::to_string(index) + " is empty";
				return false;
			}
			const Vector2i cell = spawns[index];
			if (!leader->to_unit_def(&def, r_error) || !tactics_squad_to_unit_defs(def.id, leader->get_squad(), &squad, r_error) ||
					sim.add_leader(side, def, { cell.x, cell.y }, squad, r_error) == tactics::NO_UNIT) {
				return false;
			}
		}
	}
	return true;
}

PackedStringArray TacticsCatalog::validate() const {
	PackedStringArray problems;
	if (rules.is_null()) {
		problems.push_back("TacticsCatalog: rules is not set");
	} else {
		std::string error;
		if (!tactics::validate_rules(rules->to_rules(), &error)) {
			problems.push_back("TacticsCatalog: " + to_godot_string(error));
		}
	}
	validate_ids(terrains, "terrain.", false, problems);
	validate_ids(keywords, "keyword.", true, problems);
	validate_ids(zones, "zone.", false, problems);
	validate_ids(passives, "tactics_passive.", true, problems);
	validate_ids(skills, "tactics_skill.", true, problems);
	validate_ids(troops, "troop.", false, problems);
	validate_ids(leaders, "leader.", false, problems);
	validate_ids(maps, "map.", false, problems);
	validate_ids(scenarios, "scenario.", false, problems);
	validate_units(problems);
	validate_references(problems);
	validate_maps(problems);
	validate_scenarios(problems);
	return problems;
}

Ref<TacticsTerrainData> TacticsCatalog::get_terrain(const StringName &p_id) const { return find_by_id(terrains, p_id); }
Ref<TacticsKeywordData> TacticsCatalog::get_keyword(const StringName &p_id) const { return find_by_id(keywords, p_id); }
Ref<TacticsZoneData> TacticsCatalog::get_zone(const StringName &p_id) const { return find_by_id(zones, p_id); }
Ref<TacticsPassiveData> TacticsCatalog::get_passive(const StringName &p_id) const { return find_by_id(passives, p_id); }
Ref<TacticsSkillData> TacticsCatalog::get_skill(const StringName &p_id) const { return find_by_id(skills, p_id); }
Ref<TacticsTroopData> TacticsCatalog::get_troop(const StringName &p_id) const { return find_by_id(troops, p_id); }
Ref<TacticsLeaderData> TacticsCatalog::get_leader(const StringName &p_id) const { return find_by_id(leaders, p_id); }
Ref<TacticsMapData> TacticsCatalog::get_map(const StringName &p_id) const { return find_by_id(maps, p_id); }
Ref<TacticsScenarioData> TacticsCatalog::get_scenario(const StringName &p_id) const { return find_by_id(scenarios, p_id); }

void TacticsCatalog::_bind_methods() {
	ClassDB::bind_method(D_METHOD("validate"), &TacticsCatalog::validate);
	ClassDB::bind_method(D_METHOD("get_terrain", "id"), &TacticsCatalog::get_terrain);
	ClassDB::bind_method(D_METHOD("get_keyword", "id"), &TacticsCatalog::get_keyword);
	ClassDB::bind_method(D_METHOD("get_zone", "id"), &TacticsCatalog::get_zone);
	ClassDB::bind_method(D_METHOD("get_passive", "id"), &TacticsCatalog::get_passive);
	ClassDB::bind_method(D_METHOD("get_skill", "id"), &TacticsCatalog::get_skill);
	ClassDB::bind_method(D_METHOD("get_troop", "id"), &TacticsCatalog::get_troop);
	ClassDB::bind_method(D_METHOD("get_leader", "id"), &TacticsCatalog::get_leader);
	ClassDB::bind_method(D_METHOD("get_map", "id"), &TacticsCatalog::get_map);
	ClassDB::bind_method(D_METHOD("get_scenario", "id"), &TacticsCatalog::get_scenario);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, rules);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, terrains);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, keywords);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, zones);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, passives);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, skills);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, troops);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, leaders);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, maps);
	BATTLE_BIND_ACCESSORS(TacticsCatalog, scenarios);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "rules", PROPERTY_HINT_RESOURCE_TYPE, "TacticsRulesData"), "set_rules", "get_rules");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "terrains", PROPERTY_HINT_ARRAY_TYPE, "TacticsTerrainData"), "set_terrains", "get_terrains");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "keywords", PROPERTY_HINT_ARRAY_TYPE, "TacticsKeywordData"), "set_keywords", "get_keywords");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "zones", PROPERTY_HINT_ARRAY_TYPE, "TacticsZoneData"), "set_zones", "get_zones");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "passives", PROPERTY_HINT_ARRAY_TYPE, "TacticsPassiveData"), "set_passives", "get_passives");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "skills", PROPERTY_HINT_ARRAY_TYPE, "TacticsSkillData"), "set_skills", "get_skills");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "troops", PROPERTY_HINT_ARRAY_TYPE, "TacticsTroopData"), "set_troops", "get_troops");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "leaders", PROPERTY_HINT_ARRAY_TYPE, "TacticsLeaderData"), "set_leaders", "get_leaders");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "maps", PROPERTY_HINT_ARRAY_TYPE, "TacticsMapData"), "set_maps", "get_maps");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "scenarios", PROPERTY_HINT_ARRAY_TYPE, "TacticsScenarioData"), "set_scenarios", "get_scenarios");
}
