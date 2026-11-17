#pragma once

#include "tactics_unit_data.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <string>

namespace godot {

// A site kind's numbers (Docs/systems/tactics_sites.md): one file per site
// in Data/Tactics/Sites/, id `site.<name>`, `kind` naming its handler
// (`site_kind.village`, `site_kind.shrine`, `site_kind.camp`,
// `site_kind.stronghold`). Maps place sites on cells.
class TacticsSiteData : public Resource {
	GDCLASS(TacticsSiteData, Resource)

	StringName id;
	StringName kind;
	String name_key;
	String description_key;
	int reach_cells = 1;
	int uses = 1;
	int heal_pct = 0;
	TypedArray<TacticsTroopData> recruits;
	int supplies = 0;
	int karma_kept = 0;
	int karma_burned = 0;
	int karma_looted = 0;
	int calm_radius_cells = 0;
	StringName bless_stat;
	int bless_amount = 0;
	int radius_cells = 0;
	int capture_phases = 1;
	int vision_cells = 0;
	int armor_bonus = 0;
	int reinforce_round = 0;
	Ref<TacticsLeaderData> reinforce_leader;
	TypedArray<TacticsTroopData> reinforce_squad;
	bool ends_turn = false;

protected:
	static void _bind_methods();

public:
	// False with r_error on an unknown kind, stat or a bad troop.
	bool to_site_def(tactics::SiteDef *r_def, std::string *r_error) const;

	void set_id(const StringName & p_value) { id = p_value; }
	StringName get_id() const { return id; }
	void set_kind(const StringName & p_value) { kind = p_value; }
	StringName get_kind() const { return kind; }
	void set_name_key(const String & p_value) { name_key = p_value; }
	String get_name_key() const { return name_key; }
	void set_description_key(const String & p_value) { description_key = p_value; }
	String get_description_key() const { return description_key; }
	void set_reach_cells(int64_t p_value) { reach_cells = clamp_to_int(p_value); }
	int get_reach_cells() const { return reach_cells; }
	void set_uses(int64_t p_value) { uses = clamp_to_int(p_value); }
	int get_uses() const { return uses; }
	void set_heal_pct(int64_t p_value) { heal_pct = clamp_to_int(p_value); }
	int get_heal_pct() const { return heal_pct; }
	void set_recruits(const TypedArray<TacticsTroopData> & p_value) { recruits = p_value; }
	TypedArray<TacticsTroopData> get_recruits() const { return recruits; }
	void set_supplies(int64_t p_value) { supplies = clamp_to_int(p_value); }
	int get_supplies() const { return supplies; }
	void set_karma_kept(int64_t p_value) { karma_kept = clamp_to_int(p_value); }
	int get_karma_kept() const { return karma_kept; }
	void set_karma_burned(int64_t p_value) { karma_burned = clamp_to_int(p_value); }
	int get_karma_burned() const { return karma_burned; }
	void set_karma_looted(int64_t p_value) { karma_looted = clamp_to_int(p_value); }
	int get_karma_looted() const { return karma_looted; }
	void set_calm_radius_cells(int64_t p_value) { calm_radius_cells = clamp_to_int(p_value); }
	int get_calm_radius_cells() const { return calm_radius_cells; }
	void set_bless_stat(const StringName & p_value) { bless_stat = p_value; }
	StringName get_bless_stat() const { return bless_stat; }
	void set_bless_amount(int64_t p_value) { bless_amount = clamp_to_int(p_value); }
	int get_bless_amount() const { return bless_amount; }
	void set_radius_cells(int64_t p_value) { radius_cells = clamp_to_int(p_value); }
	int get_radius_cells() const { return radius_cells; }
	void set_capture_phases(int64_t p_value) { capture_phases = clamp_to_int(p_value); }
	int get_capture_phases() const { return capture_phases; }
	void set_vision_cells(int64_t p_value) { vision_cells = clamp_to_int(p_value); }
	int get_vision_cells() const { return vision_cells; }
	void set_armor_bonus(int64_t p_value) { armor_bonus = clamp_to_int(p_value); }
	int get_armor_bonus() const { return armor_bonus; }
	void set_reinforce_round(int64_t p_value) { reinforce_round = clamp_to_int(p_value); }
	int get_reinforce_round() const { return reinforce_round; }
	void set_reinforce_leader(const Ref<TacticsLeaderData> & p_value) { reinforce_leader = p_value; }
	Ref<TacticsLeaderData> get_reinforce_leader() const { return reinforce_leader; }
	void set_reinforce_squad(const TypedArray<TacticsTroopData> & p_value) { reinforce_squad = p_value; }
	TypedArray<TacticsTroopData> get_reinforce_squad() const { return reinforce_squad; }
	void set_ends_turn(bool p_value) { ends_turn = p_value; }
	bool get_ends_turn() const { return ends_turn; }
};

} // namespace godot
