#include "synergy_overrides.h"

#include "modifier_data.h"

#include "rules/synergy_validation.h"

#include <godot_cpp/variant/dictionary.hpp>

using namespace godot;

namespace {

bool fail(const std::string &p_message, std::string *r_error) {
	*r_error = p_message;
	return false;
}

rules::MilestoneDef *find_milestone(rules::SynergyConfig *r_config, const std::string &p_id) {
	for (rules::MilestoneDef &milestone : r_config->milestones) {
		if (milestone.id == p_id) {
			return &milestone;
		}
	}
	return nullptr;
}

bool apply_one(const Variant &p_value, int64_t p_index, rules::SynergyConfig *r_config, std::string *r_error) {
	const std::string where = "override " + std::to_string(p_index);
	if (p_value.get_type() != Variant::DICTIONARY) {
		return fail(where + " is not a Dictionary", r_error);
	}
	const Dictionary entry = p_value;
	const std::string id = to_std_string(String(entry.get("milestone", "")));
	rules::MilestoneDef *milestone = find_milestone(r_config, id);
	if (milestone == nullptr) {
		return fail(where + " names unknown milestone '" + id + "'", r_error);
	}
	const int64_t tier = entry.get("tier", -1);
	if (tier < 0 || tier >= static_cast<int64_t>(milestone->tiers.size())) {
		return fail(where + " (" + id + ") has no tier " + std::to_string(tier), r_error);
	}
	rules::TierDef &target = milestone->tiers[tier];
	if (entry.has("at")) {
		target.at = clamp_to_int(entry["at"]);
	}
	if (entry.has("modifiers")) {
		const Variant list = entry["modifiers"];
		if (list.get_type() != Variant::ARRAY) {
			return fail(where + " (" + id + ") modifiers is not an Array", r_error);
		}
		const Array modifiers = list;
		target.modifiers.clear();
		for (int64_t modifier = 0; modifier < modifiers.size(); modifier++) {
			const Ref<ModifierData> data = modifiers[modifier];
			if (data.is_null()) {
				return fail(where + " (" + id + ") has an empty modifier", r_error);
			}
			target.modifiers.push_back(data->to_modifier_def());
		}
	}
	return true;
}

} // namespace

bool godot::apply_synergy_overrides(const rules::SynergyConfig &p_base, const Array &p_overrides, rules::SynergyConfig *r_config, std::string *r_error) {
	rules::SynergyConfig config = p_base;
	for (int64_t index = 0; index < p_overrides.size(); index++) {
		if (!apply_one(p_overrides[index], index, &config, r_error)) {
			return false;
		}
	}
	if (!rules::resolve_config(&config, r_error)) {
		return false;
	}
	*r_config = config;
	return true;
}
