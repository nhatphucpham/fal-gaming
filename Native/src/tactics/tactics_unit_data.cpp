#include "tactics_unit_data.h"

#include "tactics_orders.h"

using namespace godot;

namespace {

constexpr int64_t PERCENT = 100;

} // namespace

bool TacticsUnitData::fill_unit_def(tactics::UnitDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	if (base_unit.is_null() || base_class.is_null() || base_unit->get_class_id() != base_class->get_id()) {
		*r_error = r_def->id + " needs base_unit and base_class, with base_unit.class_id equal to base_class.id";
		return false;
	}
	if (!base_class->has_valid_damage_kind()) {
		*r_error = r_def->id + " has a base_class with an unknown damage_kind";
		return false;
	}
	r_def->base_unit_id = to_std_string(base_unit->get_id());
	// Products in 64 bits, then saturated: validation rejects out-of-range values.
	r_def->max_hp = clamp_to_int(static_cast<int64_t>(base_class->get_max_hp()) * hp_pct / PERCENT);
	r_def->attack = clamp_to_int(static_cast<int64_t>(base_class->get_attack()) * attack_pct / PERCENT);
	r_def->armor = base_class->get_armor();
	r_def->magic_resist = base_class->get_magic_resist();
	r_def->damage_kind = static_cast<tactics::DamageKind>(base_class->get_damage_kind());
	r_def->is_ranged = base_class->get_is_ranged();
	r_def->min_range_cells = min_range_cells;
	r_def->max_range_cells = max_range_cells;
	r_def->move_points = move_points;
	r_def->vision_cells = vision_cells;
	r_def->keywords.clear();
	for (int64_t index = 0; index < keywords.size(); index++) {
		const Ref<TacticsKeywordData> keyword = keywords[index];
		tactics::KeywordDef def;
		if (keyword.is_null() || !keyword->to_keyword_def(&def, r_error)) {
			*r_error = r_def->id + ": " + (keyword.is_null() ? std::string("empty keyword entry") : *r_error);
			return false;
		}
		r_def->keywords.push_back(def);
	}
	return true;
}

bool TacticsTroopData::to_unit_def(tactics::UnitDef *r_def, std::string *r_error) const {
	r_def->role = tactics::UnitRole::SOLDIER;
	return fill_unit_def(r_def, r_error);
}

bool TacticsLeaderData::to_unit_def(tactics::UnitDef *r_def, std::string *r_error) const {
	r_def->role = tactics::UnitRole::LEADER;
	if (!fill_unit_def(r_def, r_error)) {
		return false;
	}
	r_def->lead_capacity = lead_capacity;
	r_def->default_order = tactics::find_order_index(to_std_string(default_order));
	if (r_def->default_order == tactics::NO_INDEX) {
		*r_error = r_def->id + " has unknown default_order " + to_std_string(default_order);
		return false;
	}
	r_def->passives.clear();
	for (int64_t index = 0; index < passives.size(); index++) {
		const Ref<TacticsPassiveData> passive = passives[index];
		tactics::PassiveDef def;
		if (passive.is_null() || !passive->to_passive_def(&def, r_error)) {
			*r_error = r_def->id + ": " + (passive.is_null() ? std::string("empty passive entry") : *r_error);
			return false;
		}
		r_def->passives.push_back(def);
	}
	r_def->traits.clear();
	for (int64_t index = 0; index < traits.size(); index++) {
		const Ref<TacticsTraitData> trait = traits[index];
		if (trait.is_null()) {
			*r_error = r_def->id + ": empty trait entry";
			return false;
		}
		r_def->traits.push_back(trait->to_trait_def());
	}
	r_def->has_skill = skill.is_valid();
	if (r_def->has_skill && !skill->to_skill_def(&r_def->skill, r_error)) {
		*r_error = r_def->id + ": " + *r_error;
		return false;
	}
	return true;
}

bool godot::tactics_squad_to_unit_defs(const std::string &p_leader_id, const Array &p_squad, std::vector<tactics::UnitDef> *r_defs, std::string *r_error) {
	r_defs->clear();
	for (int64_t index = 0; index < p_squad.size(); index++) {
		const Ref<TacticsTroopData> troop = p_squad[index];
		tactics::UnitDef soldier;
		if (troop.is_null()) {
			*r_error = p_leader_id + " squad entry " + std::to_string(index) + " is not a TacticsTroopData";
			return false;
		}
		if (!troop->to_unit_def(&soldier, r_error)) {
			return false;
		}
		r_defs->push_back(soldier);
	}
	return true;
}

void TacticsUnitData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsUnitData, id);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, base_unit);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, base_class);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, hp_pct);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, attack_pct);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, min_range_cells);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, max_range_cells);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, move_points);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, vision_cells);
	BATTLE_BIND_ACCESSORS(TacticsUnitData, keywords);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "base_unit", PROPERTY_HINT_RESOURCE_TYPE, "UnitData"), "set_base_unit", "get_base_unit");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "base_class", PROPERTY_HINT_RESOURCE_TYPE, "ClassData"), "set_base_class", "get_base_class");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "hp_pct", PROPERTY_HINT_RANGE, "1,1000,1"), "set_hp_pct", "get_hp_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "attack_pct", PROPERTY_HINT_RANGE, "0,1000,1"), "set_attack_pct", "get_attack_pct");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "min_range_cells", PROPERTY_HINT_RANGE, "1,12,1"), "set_min_range_cells", "get_min_range_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_range_cells", PROPERTY_HINT_RANGE, "1,12,1"), "set_max_range_cells", "get_max_range_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "move_points", PROPERTY_HINT_RANGE, "0,20,1"), "set_move_points", "get_move_points");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "vision_cells", PROPERTY_HINT_RANGE, "1,16,1"), "set_vision_cells", "get_vision_cells");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "keywords", PROPERTY_HINT_ARRAY_TYPE, "TacticsKeywordData"), "set_keywords", "get_keywords");
}

void TacticsLeaderData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsLeaderData, lead_capacity);
	BATTLE_BIND_ACCESSORS(TacticsLeaderData, passives);
	BATTLE_BIND_ACCESSORS(TacticsLeaderData, skill);
	BATTLE_BIND_ACCESSORS(TacticsLeaderData, default_order);
	BATTLE_BIND_ACCESSORS(TacticsLeaderData, squad);
	BATTLE_BIND_ACCESSORS(TacticsLeaderData, traits);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "lead_capacity", PROPERTY_HINT_RANGE, "0,8,1"), "set_lead_capacity", "get_lead_capacity");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "passives", PROPERTY_HINT_ARRAY_TYPE, "TacticsPassiveData"), "set_passives", "get_passives");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "skill", PROPERTY_HINT_RESOURCE_TYPE, "TacticsSkillData"), "set_skill", "get_skill");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "default_order"), "set_default_order", "get_default_order");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "squad", PROPERTY_HINT_ARRAY_TYPE, "TacticsTroopData"), "set_squad", "get_squad");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "traits", PROPERTY_HINT_ARRAY_TYPE, "TacticsTraitData"), "set_traits", "get_traits");
}
