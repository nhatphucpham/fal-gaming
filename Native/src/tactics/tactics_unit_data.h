#pragma once

#include "tactics_incident_data.h"
#include "tactics_keyword_data.h"
#include "tactics_passive_data.h"
#include "tactics_skill_data.h"

#include "battle/class_data.h"
#include "battle/unit_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <string>
#include <vector>

namespace godot {

// Fields shared by leaders and soldier types: the auto-battle unit and
// class it is drawn from (hp, attack, armor, magic resist, damage kind and
// is_ranged come from the class, scaled by hp_pct and attack_pct) and the
// tactics-only stats. The auto battle never reads these resources.
class TacticsUnitData : public Resource {
	GDCLASS(TacticsUnitData, Resource)

	StringName id;
	String name_key;
	Ref<UnitData> base_unit;
	Ref<ClassData> base_class;
	int hp_pct = 100;
	int attack_pct = 100;
	int min_range_cells = 1;
	int max_range_cells = 1;
	int move_points = 4;
	int vision_cells = 4;
	TypedArray<TacticsKeywordData> keywords;

protected:
	static void _bind_methods();
	// Fills the shared fields; false and r_error on missing or mismatched
	// base data or an unknown keyword.
	bool fill_unit_def(tactics::UnitDef *r_def, std::string *r_error) const;

public:
	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_base_unit(const Ref<UnitData> &p_value) { base_unit = p_value; }
	Ref<UnitData> get_base_unit() const { return base_unit; }
	void set_base_class(const Ref<ClassData> &p_value) { base_class = p_value; }
	Ref<ClassData> get_base_class() const { return base_class; }
	void set_hp_pct(int64_t p_value) { hp_pct = clamp_to_int(p_value); }
	int get_hp_pct() const { return hp_pct; }
	void set_attack_pct(int64_t p_value) { attack_pct = clamp_to_int(p_value); }
	int get_attack_pct() const { return attack_pct; }
	void set_min_range_cells(int64_t p_value) { min_range_cells = clamp_to_int(p_value); }
	int get_min_range_cells() const { return min_range_cells; }
	void set_max_range_cells(int64_t p_value) { max_range_cells = clamp_to_int(p_value); }
	int get_max_range_cells() const { return max_range_cells; }
	void set_move_points(int64_t p_value) { move_points = clamp_to_int(p_value); }
	int get_move_points() const { return move_points; }
	void set_vision_cells(int64_t p_value) { vision_cells = clamp_to_int(p_value); }
	int get_vision_cells() const { return vision_cells; }
	void set_keywords(const TypedArray<TacticsKeywordData> &p_value) { keywords = p_value; }
	TypedArray<TacticsKeywordData> get_keywords() const { return keywords; }
};

// A soldier type (binh): one file per type in Data/Tactics/Troops/, id
// `troop.<name>`.
class TacticsTroopData : public TacticsUnitData {
	GDCLASS(TacticsTroopData, TacticsUnitData)

protected:
	static void _bind_methods() {}

public:
	bool to_unit_def(tactics::UnitDef *r_def, std::string *r_error) const;
};

// The soldier definitions of a squad (an Array of TacticsTroopData) led by
// p_leader_id; false with r_error naming the bad entry.
bool tactics_squad_to_unit_defs(const std::string &p_leader_id, const Array &p_squad, std::vector<tactics::UnitDef> *r_defs, std::string *r_error);

// A leader (tướng): one file per leader in Data/Tactics/Leaders/, id
// `leader.<name>`, with its passives, skill, starting order, traits (which
// shift the odds of its soldiers' incidents) and the squad it brings when a
// scenario does not name one.
class TacticsLeaderData : public TacticsUnitData {
	GDCLASS(TacticsLeaderData, TacticsUnitData)

	int lead_capacity = 4;
	TypedArray<TacticsPassiveData> passives;
	Ref<TacticsSkillData> skill;
	StringName default_order = "order.follow";
	TypedArray<TacticsTroopData> squad;
	TypedArray<TacticsTraitData> traits;

protected:
	static void _bind_methods();

public:
	bool to_unit_def(tactics::UnitDef *r_def, std::string *r_error) const;

	void set_lead_capacity(int64_t p_value) { lead_capacity = clamp_to_int(p_value); }
	int get_lead_capacity() const { return lead_capacity; }
	void set_passives(const TypedArray<TacticsPassiveData> &p_value) { passives = p_value; }
	TypedArray<TacticsPassiveData> get_passives() const { return passives; }
	void set_skill(const Ref<TacticsSkillData> &p_value) { skill = p_value; }
	Ref<TacticsSkillData> get_skill() const { return skill; }
	void set_default_order(const StringName &p_value) { default_order = p_value; }
	StringName get_default_order() const { return default_order; }
	void set_squad(const TypedArray<TacticsTroopData> &p_value) { squad = p_value; }
	TypedArray<TacticsTroopData> get_squad() const { return squad; }
	void set_traits(const TypedArray<TacticsTraitData> &p_value) { traits = p_value; }
	TypedArray<TacticsTraitData> get_traits() const { return traits; }
};

} // namespace godot
