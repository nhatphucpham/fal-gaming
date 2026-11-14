#include "synergy.h"

#include "battle/battle_shapes.h"
#include "battle/unit_data.h"

#include "rules/synergy_eval.h"
#include "rules/synergy_validation.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace {

const Vector2i NO_CELL(-1, -1);

Vector2i to_vector(const formation::LocalCell &p_cell) {
	return Vector2i(p_cell.col, p_cell.rank);
}

// Shape ids live in the battle; the rules layer cannot check them.
bool check_shape_params(const rules::SynergyConfig &p_config, std::string *r_error) {
	const auto check = [&](const std::string &p_owner, const rules::ModifierDef &p_modifier) {
		if (p_modifier.handler != nullptr && p_modifier.handler->kind == rules::ModifierKind::ATTACK_SHAPE && battle::find_shape_handler(p_modifier.param) == nullptr) {
			*r_error = p_owner + " has unknown shape '" + p_modifier.param + "'";
			return false;
		}
		return true;
	};
	for (const rules::MilestoneDef &milestone : p_config.milestones) {
		for (const rules::TierDef &tier : milestone.tiers) {
			for (const rules::ModifierDef &modifier : tier.modifiers) {
				if (!check(milestone.id, modifier)) {
					return false;
				}
			}
		}
	}
	for (const rules::FormationDef &entry : p_config.formations) {
		for (const rules::ModifierDef &modifier : entry.modifiers) {
			if (!check(entry.id, modifier)) {
				return false;
			}
		}
	}
	return true;
}

bool read_piece(const rules::SynergyConfig &p_config, const Variant &p_value, formation::Piece *r_piece) {
	ERR_FAIL_COND_V_MSG(p_value.get_type() != Variant::DICTIONARY, false, "Synergy: evaluate() needs Dictionaries, got " + Variant::get_type_name(p_value.get_type()));
	const Dictionary entry = p_value;
	const Ref<UnitData> unit = entry.get("unit", Variant());
	String class_id;
	String race_id;
	if (unit.is_valid()) {
		r_piece->unit_id = to_std_string(unit->get_id());
		class_id = unit->get_class_id();
		race_id = unit->get_race_id();
		r_piece->cost = unit->get_cost();
	} else {
		r_piece->unit_id = to_std_string(String(entry.get("unit_id", "")));
		class_id = entry.get("class_id", "");
		race_id = entry.get("race_id", "");
		r_piece->cost = entry.get("cost", 1);
	}
	r_piece->col = entry.get("col", 0);
	r_piece->rank = entry.get("rank", 0);
	r_piece->class_index = rules::find_class_index(p_config, to_std_string(class_id));
	r_piece->race_index = rules::find_race_index(p_config, to_std_string(race_id));
	return true;
}

Array milestones_to_array(const rules::SynergyConfig &p_config, const rules::SynergyResult &p_result, rules::CountedKind p_kind) {
	Array list;
	for (const rules::MilestoneState &state : p_result.milestones) {
		const rules::MilestoneDef &milestone = p_config.milestones[state.milestone];
		if (milestone.kind != p_kind) {
			continue;
		}
		PackedInt32Array thresholds;
		for (const rules::TierDef &tier : milestone.tiers) {
			thresholds.push_back(tier.at);
		}
		Dictionary entry;
		entry["id"] = StringName(to_godot_string(milestone.id));
		entry["counted_id"] = StringName(to_godot_string(milestone.counted_id));
		entry["count"] = state.count;
		entry["thresholds"] = thresholds;
		entry["reached"] = state.reached;
		list.push_back(entry);
	}
	return list;
}

Dictionary match_to_dictionary(const rules::SynergyConfig &p_config, const rules::FormationState &p_state) {
	const formation::Match &match = p_state.match;
	Array cells;
	Array slot_cells;
	Array pieces;
	for (size_t slot = 0; slot < match.cells.size(); slot++) {
		slot_cells.push_back(to_vector(match.cells[slot]));
		if (match.pieces[slot] != formation::NO_INDEX) {
			cells.push_back(to_vector(match.cells[slot]));
			pieces.push_back(match.pieces[slot]);
		}
	}
	Dictionary entry;
	entry["id"] = StringName(to_godot_string(p_config.formations[match.formation].id));
	entry["level"] = p_state.level;
	entry["cells"] = cells;
	entry["slot_cells"] = slot_cells;
	entry["pieces"] = pieces;
	entry["missing_cell"] = match.missing_slot == formation::NO_INDEX ? NO_CELL : to_vector(match.cells[match.missing_slot]);
	return entry;
}

Dictionary near_to_dictionary(const rules::SynergyConfig &p_config, const formation::NearMiss &p_near) {
	Array cells;
	Array pieces;
	for (size_t slot = 0; slot < p_near.cells.size(); slot++) {
		if (p_near.pieces[slot] != formation::NO_INDEX) {
			cells.push_back(to_vector(p_near.cells[slot]));
			pieces.push_back(p_near.pieces[slot]);
		}
	}
	Dictionary entry;
	entry["id"] = StringName(to_godot_string(p_config.formations[p_near.formation].id));
	entry["cells"] = cells;
	entry["pieces"] = pieces;
	entry["missing_cell"] = to_vector(p_near.cells[p_near.missing_slot]);
	entry["needed_class"] = p_near.needed_class == formation::ANY ? StringName() : StringName(to_godot_string(p_config.class_ids[p_near.needed_class]));
	return entry;
}

} // namespace

PackedStringArray Synergy::setup(const Array &p_formations, const Array &p_milestones, const Ref<HopLucData> &p_hop_luc) {
	PackedStringArray problems;
	is_configured = false;
	rules::SynergyConfig next;
	std::string error;
	for (int64_t index = 0; index < p_formations.size(); index++) {
		const Ref<FormationData> data = p_formations[index];
		rules::FormationDef def;
		if (data.is_null() || !data->to_formation_def(&def, &error)) {
			problems.push_back(vformat("Synergy: formations[%d] is empty or bad: %s", index, to_godot_string(error)));
			continue;
		}
		next.formations.push_back(def);
	}
	for (int64_t index = 0; index < p_milestones.size(); index++) {
		const Ref<MilestoneData> data = p_milestones[index];
		rules::MilestoneDef def;
		if (data.is_null() || !data->to_milestone_def(&def, &error)) {
			problems.push_back(vformat("Synergy: milestones[%d] is empty or bad: %s", index, to_godot_string(error)));
			continue;
		}
		next.milestones.push_back(def);
	}
	if (p_hop_luc.is_null()) {
		problems.push_back("Synergy: hop_luc is not set");
	} else if (!p_hop_luc->to_hop_luc_def(&next.hop_luc, &error)) {
		problems.push_back("Synergy: " + to_godot_string(error));
	}
	if (problems.is_empty() && (!rules::resolve_config(&next, &error) || !check_shape_params(next, &error))) {
		problems.push_back("Synergy: " + to_godot_string(error));
	}
	if (problems.is_empty()) {
		config = next;
		is_configured = true;
	}
	return problems;
}

Dictionary Synergy::evaluate(const Array &p_pieces) const {
	Dictionary result;
	ERR_FAIL_COND_V_MSG(!is_configured, result, "Synergy: evaluate() called before a successful setup()");
	std::vector<formation::Piece> pieces;
	for (int64_t index = 0; index < p_pieces.size(); index++) {
		formation::Piece piece;
		if (!read_piece(config, p_pieces[index], &piece)) {
			return result;
		}
		pieces.push_back(piece);
	}
	const rules::SynergyResult evaluation = rules::evaluate(config, pieces);
	result["class_milestones"] = milestones_to_array(config, evaluation, rules::CountedKind::CLASS);
	result["race_milestones"] = milestones_to_array(config, evaluation, rules::CountedKind::RACE);
	Array formations;
	for (const rules::FormationState &state : evaluation.formations) {
		formations.push_back(match_to_dictionary(config, state));
	}
	Array near;
	for (const formation::NearMiss &miss : evaluation.near_misses) {
		near.push_back(near_to_dictionary(config, miss));
	}
	result["formations"] = formations;
	result["near_formations"] = near;
	result["hop_luc"] = evaluation.points;
	result["hop_luc_tier"] = evaluation.tier == rules::NO_INDEX ? 0 : config.hop_luc.tiers[evaluation.tier].at;
	result["next_tier"] = evaluation.next_tier_at;
	return result;
}

void Synergy::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "formations", "milestones", "hop_luc"), &Synergy::setup);
	ClassDB::bind_method(D_METHOD("is_ready"), &Synergy::is_ready);
	ClassDB::bind_method(D_METHOD("evaluate", "pieces"), &Synergy::evaluate);
}
