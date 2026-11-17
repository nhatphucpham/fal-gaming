#pragma once

#include "tactics_passive_data.h"
#include "tactics_skill_data.h"
#include "tactics_types.h"

#include "battle/bridge_strings.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <string>

namespace godot {

// One incident (Biến cố): `id` is its handler (tactics_incidents.cpp,
// `incident.rescue`, ...), the rest tunes it; fields a handler does not read
// stay 0. One file per incident in Data/Tactics/Incidents/. `mark_passive`
// is the passive a soldier named for its marks gets when this incident is
// its most common mark. Schema in Docs/systems/tactics.md, Incidents.
class TacticsIncidentData : public Resource {
	GDCLASS(TacticsIncidentData, Resource)

	StringName id;
	String name_key;
	String description_key;
	int base_weight = 0;
	bool seeds_ai_side = false;
	int threshold_pct = 0;
	int threshold_count = 0;
	int radius_cells = 0;
	int calm_radius_cells = 0;
	int unseen_waver_pct = 0;
	int amount = 0;
	int secondary_amount = 0;
	int duration_rounds = 0;
	Ref<TacticsPassiveData> mark_passive;

protected:
	static void _bind_methods();

public:
	// False and r_error for an unknown handler id.
	bool to_incident_def(tactics::IncidentDef *r_def, std::string *r_error) const;
	// True for the good incidents (rescue, stand, surge), from the handler.
	bool is_good() const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_base_weight(int64_t p_value) { base_weight = clamp_to_int(p_value); }
	int get_base_weight() const { return base_weight; }
	void set_seeds_ai_side(bool p_value) { seeds_ai_side = p_value; }
	bool get_seeds_ai_side() const { return seeds_ai_side; }
	void set_threshold_pct(int64_t p_value) { threshold_pct = clamp_to_int(p_value); }
	int get_threshold_pct() const { return threshold_pct; }
	void set_threshold_count(int64_t p_value) { threshold_count = clamp_to_int(p_value); }
	int get_threshold_count() const { return threshold_count; }
	void set_radius_cells(int64_t p_value) { radius_cells = clamp_to_int(p_value); }
	int get_radius_cells() const { return radius_cells; }
	void set_calm_radius_cells(int64_t p_value) { calm_radius_cells = clamp_to_int(p_value); }
	int get_calm_radius_cells() const { return calm_radius_cells; }
	void set_unseen_waver_pct(int64_t p_value) { unseen_waver_pct = clamp_to_int(p_value); }
	int get_unseen_waver_pct() const { return unseen_waver_pct; }
	void set_amount(int64_t p_value) { amount = clamp_to_int(p_value); }
	int get_amount() const { return amount; }
	void set_secondary_amount(int64_t p_value) { secondary_amount = clamp_to_int(p_value); }
	int get_secondary_amount() const { return secondary_amount; }
	void set_duration_rounds(int64_t p_value) { duration_rounds = clamp_to_int(p_value); }
	int get_duration_rounds() const { return duration_rounds; }
	void set_mark_passive(const Ref<TacticsPassiveData> &p_value) { mark_passive = p_value; }
	Ref<TacticsPassiveData> get_mark_passive() const { return mark_passive; }
};

// Seeds, odds, karma and the roster numbers of the incidents, with the
// incidents themselves. The project uses
// Data/Tactics/Incidents/incident_rules.tres; TacticsBattle reads it in
// set_incident_rules(). The roster fields (marks_to_name and below) are
// read by the GDScript roster (Systems/Tactics/), not by the simulation.
class TacticsIncidentRulesData : public Resource {
	GDCLASS(TacticsIncidentRulesData, Resource)

	tactics::IncidentRules rules;
	TypedArray<TacticsIncidentData> incidents;
	int marks_to_name = 3;
	int traitor_marks_to_return = 2;
	int karma_keep_pct = 50;
	int named_lead_capacity = 2;
	int named_hp_pct = 130;
	int named_attack_pct = 110;
	Ref<TacticsSkillData> named_skill;

protected:
	static void _bind_methods();

public:
	// The simulation's rules with every incident; false and r_error when an
	// incident entry is empty or unknown.
	bool to_incident_rules(tactics::IncidentRules *r_rules, std::string *r_error) const;
	Ref<TacticsIncidentData> get_incident(const StringName &p_id) const;

	void set_min_seeds(int64_t p_value) { rules.min_seeds = clamp_to_int(p_value); }
	int get_min_seeds() const { return rules.min_seeds; }
	void set_max_seeds(int64_t p_value) { rules.max_seeds = clamp_to_int(p_value); }
	int get_max_seeds() const { return rules.max_seeds; }
	void set_ai_min_seeds(int64_t p_value) { rules.ai_min_seeds = clamp_to_int(p_value); }
	int get_ai_min_seeds() const { return rules.ai_min_seeds; }
	void set_ai_max_seeds(int64_t p_value) { rules.ai_max_seeds = clamp_to_int(p_value); }
	int get_ai_max_seeds() const { return rules.ai_max_seeds; }
	void set_marked_soldier_weight(int64_t p_value) { rules.marked_soldier_weight = clamp_to_int(p_value); }
	int get_marked_soldier_weight() const { return rules.marked_soldier_weight; }
	void set_mark_polarity_weight(int64_t p_value) { rules.mark_polarity_weight = clamp_to_int(p_value); }
	int get_mark_polarity_weight() const { return rules.mark_polarity_weight; }
	void set_karma_weight_per_point(int64_t p_value) { rules.karma_weight_per_point = clamp_to_int(p_value); }
	int get_karma_weight_per_point() const { return rules.karma_weight_per_point; }
	void set_karma_weight_cap(int64_t p_value) { rules.karma_weight_cap = clamp_to_int(p_value); }
	int get_karma_weight_cap() const { return rules.karma_weight_cap; }
	void set_bait_distance_cells(int64_t p_value) { rules.bait_distance_cells = clamp_to_int(p_value); }
	int get_bait_distance_cells() const { return rules.bait_distance_cells; }
	void set_rescue_hp_pct(int64_t p_value) { rules.rescue_hp_pct = clamp_to_int(p_value); }
	int get_rescue_hp_pct() const { return rules.rescue_hp_pct; }
	void set_incidents(const TypedArray<TacticsIncidentData> &p_value) { incidents = p_value; }
	TypedArray<TacticsIncidentData> get_incidents() const { return incidents; }
	void set_marks_to_name(int64_t p_value) { marks_to_name = clamp_to_int(p_value); }
	int get_marks_to_name() const { return marks_to_name; }
	void set_traitor_marks_to_return(int64_t p_value) { traitor_marks_to_return = clamp_to_int(p_value); }
	int get_traitor_marks_to_return() const { return traitor_marks_to_return; }
	void set_karma_keep_pct(int64_t p_value) { karma_keep_pct = clamp_to_int(p_value); }
	int get_karma_keep_pct() const { return karma_keep_pct; }
	void set_named_lead_capacity(int64_t p_value) { named_lead_capacity = clamp_to_int(p_value); }
	int get_named_lead_capacity() const { return named_lead_capacity; }
	void set_named_hp_pct(int64_t p_value) { named_hp_pct = clamp_to_int(p_value); }
	int get_named_hp_pct() const { return named_hp_pct; }
	void set_named_attack_pct(int64_t p_value) { named_attack_pct = clamp_to_int(p_value); }
	int get_named_attack_pct() const { return named_attack_pct; }
	void set_named_skill(const Ref<TacticsSkillData> &p_value) { named_skill = p_value; }
	Ref<TacticsSkillData> get_named_skill() const { return named_skill; }
};

// A leader trait (nết tướng), such as `trait.strict`: percent changes to the
// weight of incidents seeded in that leader's soldiers, one per entry of
// `incident_ids` (the same index in `weight_pcts`, -100..1000). One file per
// trait in Data/Tactics/Traits/.
class TacticsTraitData : public Resource {
	GDCLASS(TacticsTraitData, Resource)

	StringName id;
	String name_key;
	String description_key;
	TypedArray<StringName> incident_ids;
	PackedInt32Array weight_pcts;

protected:
	static void _bind_methods();

public:
	tactics::TraitDef to_trait_def() const;

	void set_id(const StringName &p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String &p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_incident_ids(const TypedArray<StringName> &p_value) { incident_ids = p_value; }
	TypedArray<StringName> get_incident_ids() const { return incident_ids; }
	void set_weight_pcts(const PackedInt32Array &p_value) { weight_pcts = p_value; }
	PackedInt32Array get_weight_pcts() const { return weight_pcts; }
};

} // namespace godot
