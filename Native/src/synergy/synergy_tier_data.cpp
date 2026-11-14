#include "synergy_tier_data.h"

using namespace godot;

bool SynergyTierData::to_tier_def(rules::TierDef *r_def) const {
	r_def->at = at;
	return copy_modifier_defs(modifiers, &r_def->modifiers);
}

bool godot::copy_tier_defs(const String &p_owner, const TypedArray<SynergyTierData> &p_tiers, std::vector<rules::TierDef> *r_defs, std::string *r_error) {
	r_defs->clear();
	for (int64_t index = 0; index < p_tiers.size(); index++) {
		const Ref<SynergyTierData> tier = p_tiers[index];
		rules::TierDef def;
		if (tier.is_null() || !tier->to_tier_def(&def)) {
			*r_error = to_std_string(p_owner) + " tier " + std::to_string(index) + " is empty or has an empty modifier";
			return false;
		}
		r_defs->push_back(def);
	}
	return true;
}

void SynergyTierData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(SynergyTierData, at);
	BATTLE_BIND_ACCESSORS(SynergyTierData, description_key);
	BATTLE_BIND_ACCESSORS(SynergyTierData, modifiers);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "at", PROPERTY_HINT_RANGE, "1,100,1"), "set_at", "get_at");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "modifiers", PROPERTY_HINT_ARRAY_TYPE, "ModifierData"), "set_modifiers", "get_modifiers");
}
