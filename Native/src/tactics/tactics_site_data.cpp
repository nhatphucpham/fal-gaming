#include "tactics_site_data.h"

#include "tactics_passives.h"
#include "tactics_sites.h"

using namespace godot;

bool TacticsSiteData::to_site_def(tactics::SiteDef *r_def, std::string *r_error) const {
	r_def->id = to_std_string(id);
	r_def->handler = tactics::find_site_handler(to_std_string(kind));
	if (r_def->handler == nullptr) {
		*r_error = r_def->id + " has unknown kind " + to_std_string(kind);
		return false;
	}
	r_def->reach_cells = reach_cells;
	r_def->uses = uses;
	r_def->heal_pct = heal_pct;
	r_def->supplies = supplies;
	r_def->karma_kept = karma_kept;
	r_def->karma_burned = karma_burned;
	r_def->karma_looted = karma_looted;
	r_def->calm_radius_cells = calm_radius_cells;
	r_def->bless_stat = bless_stat.is_empty() ? tactics::StatKind::NONE : tactics::find_stat_kind(to_std_string(bless_stat));
	if (!bless_stat.is_empty() && r_def->bless_stat == tactics::StatKind::NONE) {
		*r_error = r_def->id + " has unknown bless_stat " + to_std_string(bless_stat);
		return false;
	}
	r_def->bless_amount = bless_amount;
	r_def->radius_cells = radius_cells;
	r_def->capture_phases = capture_phases;
	r_def->vision_cells = vision_cells;
	r_def->armor_bonus = armor_bonus;
	r_def->reinforce_round = reinforce_round;
	r_def->ends_turn = ends_turn;
	r_def->recruits.clear();
	if (!tactics_squad_to_unit_defs(r_def->id, recruits, &r_def->recruits, r_error)) {
		return false;
	}
	r_def->has_reinforcement = reinforce_leader.is_valid();
	r_def->reinforce_squad.clear();
	if (r_def->has_reinforcement) {
		if (!reinforce_leader->to_unit_def(&r_def->reinforce_leader, r_error)) {
			return false;
		}
		if (!tactics_squad_to_unit_defs(r_def->id, reinforce_squad, &r_def->reinforce_squad, r_error)) {
			return false;
		}
	}
	return true;
}

void TacticsSiteData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(TacticsSiteData, id);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, kind);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, name_key);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, description_key);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, reach_cells);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, uses);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, heal_pct);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, recruits);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, supplies);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, karma_kept);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, karma_burned);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, karma_looted);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, calm_radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, bless_stat);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, bless_amount);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, radius_cells);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, capture_phases);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, vision_cells);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, armor_bonus);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, reinforce_round);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, reinforce_leader);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, reinforce_squad);
	BATTLE_BIND_ACCESSORS(TacticsSiteData, ends_turn);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "kind"), "set_kind", "get_kind");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "description_key"), "set_description_key", "get_description_key");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "reach_cells", PROPERTY_HINT_RANGE, "0,8,1"), "set_reach_cells", "get_reach_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "uses", PROPERTY_HINT_RANGE, "1,20,1"), "set_uses", "get_uses");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "heal_pct", PROPERTY_HINT_RANGE, "0,100,1"), "set_heal_pct", "get_heal_pct");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "recruits", PROPERTY_HINT_ARRAY_TYPE, "TacticsTroopData"), "set_recruits", "get_recruits");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "supplies", PROPERTY_HINT_RANGE, "0,100,1"), "set_supplies", "get_supplies");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "karma_kept", PROPERTY_HINT_RANGE, "0,10,1"), "set_karma_kept", "get_karma_kept");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "karma_burned", PROPERTY_HINT_RANGE, "0,10,1"), "set_karma_burned", "get_karma_burned");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "karma_looted", PROPERTY_HINT_RANGE, "0,10,1"), "set_karma_looted", "get_karma_looted");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "calm_radius_cells", PROPERTY_HINT_RANGE, "0,16,1"), "set_calm_radius_cells", "get_calm_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "bless_stat"), "set_bless_stat", "get_bless_stat");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bless_amount", PROPERTY_HINT_RANGE, "-100,100,1"), "set_bless_amount", "get_bless_amount");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "radius_cells", PROPERTY_HINT_RANGE, "0,16,1"), "set_radius_cells", "get_radius_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "capture_phases", PROPERTY_HINT_RANGE, "1,20,1"), "set_capture_phases", "get_capture_phases");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "vision_cells", PROPERTY_HINT_RANGE, "0,16,1"), "set_vision_cells", "get_vision_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "armor_bonus", PROPERTY_HINT_RANGE, "0,1000,1"), "set_armor_bonus", "get_armor_bonus");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "reinforce_round", PROPERTY_HINT_RANGE, "0,99,1"), "set_reinforce_round", "get_reinforce_round");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "reinforce_leader", PROPERTY_HINT_RESOURCE_TYPE, "TacticsLeaderData"), "set_reinforce_leader", "get_reinforce_leader");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "reinforce_squad", PROPERTY_HINT_ARRAY_TYPE, "TacticsTroopData"), "set_reinforce_squad", "get_reinforce_squad");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "ends_turn"), "set_ends_turn", "get_ends_turn");
}
