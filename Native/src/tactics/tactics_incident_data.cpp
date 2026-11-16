#include "tactics_incident_data.h"

#include "tactics_incidents.h"

using namespace godot;

bool TacticsIncidentData::to_incident_def(tactics::IncidentDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->handler = tactics::find_incident_handler(r_def->id);
	if (r_def->handler == nullptr) {
		*r_error = "incident " + r_def->id + " has no handler";
		return false;
	}
	r_def->base_weight = base_weight;
	r_def->seeds_ai_side = seeds_ai_side;
	r_def->threshold_pct = threshold_pct;
	r_def->threshold_count = threshold_count;
	r_def->radius_cells = radius_cells;
	r_def->calm_radius_cells = calm_radius_cells;
	r_def->unseen_waver_pct = unseen_waver_pct;
	r_def->amount = amount;
	r_def->secondary_amount = secondary_amount;
	r_def->duration_rounds = duration_rounds;
	return true;
}

bool TacticsIncidentData::is_good() const {
	const tactics::IncidentHandler *handler = tactics::find_incident_handler(to_std_string(id));
	return handler != nullptr && handler->is_good;
}

void TacticsIncidentData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_good"), &TacticsIncidentData::is_good);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, id);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, base_weight);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, seeds_ai_side);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, threshold_pct);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, threshold_count);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, calm_radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, unseen_waver_pct);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, amount);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, secondary_amount);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, duration_rounds);
	BATTLE_BIND_ACCESSORS(TacticsIncidentData, mark_passive);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "base_weight", PROPERTY_HINT_RANGE, "0,1000,1"), "set_base_weight", "get_base_weight");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "seeds_ai_side"), "set_seeds_ai_side", "get_seeds_ai_side");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "threshold_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_threshold_pct", "get_threshold_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "threshold_count", PROPERTY_HINT_RANGE, "0,8,1"), "set_threshold_count", "get_threshold_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "radius_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_radius_cells", "get_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "calm_radius_cells", PROPERTY_HINT_RANGE, "0,64,1"), "set_calm_radius_cells", "get_calm_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "unseen_waver_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_unseen_waver_pct", "get_unseen_waver_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "amount"), "set_amount", "get_amount");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "secondary_amount"), "set_secondary_amount", "get_secondary_amount");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "duration_rounds", PROPERTY_HINT_RANGE, "0,100,1"), "set_duration_rounds", "get_duration_rounds");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "mark_passive", PROPERTY_HINT_RESOURCE_TYPE, "TacticsPassiveData"), "set_mark_passive", "get_mark_passive");
}

bool TacticsIncidentRulesData::to_incident_rules(tactics::IncidentRules *r_rules, std::string *r_error) const {
	*r_rules = rules;
	r_rules->enabled = true;
	r_rules->incidents.clear();
	for (int64_t index = 0; index < incidents.size(); index++) {
		const Ref<TacticsIncidentData> incident = incidents[index];
		tactics::IncidentDef def;
		if (incident.is_null()) {
			*r_error = "incident rules have an empty incident at " + std::to_string(index);
			return false;
		}
		if (!incident->to_incident_def(&def, r_error)) {
			return false;
		}
		r_rules->incidents.push_back(def);
	}
	return true;
}

Ref<TacticsIncidentData> TacticsIncidentRulesData::get_incident(const StringName &p_id) const {
	for (int64_t index = 0; index < incidents.size(); index++) {
		const Ref<TacticsIncidentData> incident = incidents[index];
		if (incident.is_valid() && incident->get_id() == p_id) {
			return incident;
		}
	}
	return Ref<TacticsIncidentData>();
}

void TacticsIncidentRulesData::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_incident", "id"), &TacticsIncidentRulesData::get_incident);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, min_seeds);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, max_seeds);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, ai_min_seeds);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, ai_max_seeds);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, marked_soldier_weight);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, mark_polarity_weight);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, karma_weight_per_point);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, karma_weight_cap);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, bait_distance_cells);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, rescue_hp_pct);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, incidents);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, marks_to_name);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, traitor_marks_to_return);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, karma_keep_pct);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, named_lead_capacity);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, named_hp_pct);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, named_attack_pct);
	BATTLE_BIND_ACCESSORS(TacticsIncidentRulesData, named_skill);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "min_seeds", PROPERTY_HINT_RANGE, "0,8,1"), "set_min_seeds", "get_min_seeds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_seeds", PROPERTY_HINT_RANGE, "0,8,1"), "set_max_seeds", "get_max_seeds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ai_min_seeds", PROPERTY_HINT_RANGE, "0,8,1"), "set_ai_min_seeds", "get_ai_min_seeds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ai_max_seeds", PROPERTY_HINT_RANGE, "0,8,1"), "set_ai_max_seeds", "get_ai_max_seeds");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "marked_soldier_weight", PROPERTY_HINT_RANGE, "0,1000,1"), "set_marked_soldier_weight", "get_marked_soldier_weight");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mark_polarity_weight", PROPERTY_HINT_RANGE, "0,1000,1"), "set_mark_polarity_weight", "get_mark_polarity_weight");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "karma_weight_per_point", PROPERTY_HINT_RANGE, "0,1000,1"), "set_karma_weight_per_point", "get_karma_weight_per_point");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "karma_weight_cap", PROPERTY_HINT_RANGE, "0,1000,1"), "set_karma_weight_cap", "get_karma_weight_cap");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bait_distance_cells", PROPERTY_HINT_RANGE, "1,64,1"), "set_bait_distance_cells", "get_bait_distance_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "rescue_hp_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_rescue_hp_pct", "get_rescue_hp_pct");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "incidents", PROPERTY_HINT_ARRAY_TYPE, "TacticsIncidentData"), "set_incidents", "get_incidents");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "marks_to_name", PROPERTY_HINT_RANGE, "1,20,1"), "set_marks_to_name", "get_marks_to_name");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "traitor_marks_to_return", PROPERTY_HINT_RANGE, "1,20,1"), "set_traitor_marks_to_return", "get_traitor_marks_to_return");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "karma_keep_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_karma_keep_pct", "get_karma_keep_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "named_lead_capacity", PROPERTY_HINT_RANGE, "0,8,1"), "set_named_lead_capacity", "get_named_lead_capacity");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "named_hp_pct", PROPERTY_HINT_RANGE, "1,1000,1"), "set_named_hp_pct", "get_named_hp_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "named_attack_pct", PROPERTY_HINT_RANGE, "0,1000,1"), "set_named_attack_pct", "get_named_attack_pct");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "named_skill", PROPERTY_HINT_RESOURCE_TYPE, "TacticsSkillData"), "set_named_skill", "get_named_skill");
}

tactics::TraitDef TacticsTraitData::to_trait_def() const {
	tactics::TraitDef def;
	def.id = to_std_string(id);
	for (int64_t index = 0; index < incident_ids.size(); index++) {
		def.incident_ids.push_back(to_std_string(StringName(incident_ids[index])));
	}
	for (int64_t index = 0; index < weight_pcts.size(); index++) {
		def.weight_pcts.push_back(weight_pcts[index]);
	}
	return def;
}

void TacticsTraitData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsTraitData, id);
	BATTLE_BIND_ACCESSORS(TacticsTraitData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsTraitData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsTraitData, incident_ids);
	BATTLE_BIND_ACCESSORS(TacticsTraitData, weight_pcts);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "incident_ids", PROPERTY_HINT_ARRAY_TYPE, "StringName"), "set_incident_ids", "get_incident_ids");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "weight_pcts"), "set_weight_pcts", "get_weight_pcts");
}
