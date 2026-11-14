#pragma once

#include "battle_types.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// A unit class (Khiên, Kiếm, ...): base stats for a cost-1, one-star unit and
// the handler ids that decide how it fights. One file per class in
// Data/Classes/; the Battle node reads it through register_class().
class ClassData : public Resource {
	GDCLASS(ClassData, Resource)

public:
	enum DamageKind {
		DAMAGE_PHYSICAL = 0,
		DAMAGE_MAGIC = 1,
	};

private:
	StringName id;
	String name_key;
	int max_hp = 1;
	int attack = 0;
	int attacks_per_100s = 60;
	int range_cells = 1;
	int armor = 0;
	int magic_resist = 0;
	DamageKind damage_kind = DAMAGE_PHYSICAL;
	StringName targeting = "target.nearest";
	StringName opening;
	StringName attack_shape = "shape.single";
	TypedArray<StringName> counters;
	bool is_ranged = false;
	bool blocks_arrows = false;
	bool immune_to_knockback = false;
	bool stops_charge = false;

protected:
	static void _bind_methods();

public:
	// Copies the fields into the simulation's plain struct.
	battle::ClassDef to_class_def() const;

	void set_id(const StringName &p_id) { id = p_id; }
	StringName get_id() const { return id; }
	void set_name_key(const String &p_name_key) { name_key = p_name_key; }
	String get_name_key() const { return name_key; }
	void set_max_hp(int p_max_hp) { max_hp = p_max_hp; }
	int get_max_hp() const { return max_hp; }
	void set_attack(int p_attack) { attack = p_attack; }
	int get_attack() const { return attack; }
	void set_attacks_per_100s(int p_attacks_per_100s) { attacks_per_100s = p_attacks_per_100s; }
	int get_attacks_per_100s() const { return attacks_per_100s; }
	void set_range_cells(int p_range_cells) { range_cells = p_range_cells; }
	int get_range_cells() const { return range_cells; }
	void set_armor(int p_armor) { armor = p_armor; }
	int get_armor() const { return armor; }
	void set_magic_resist(int p_magic_resist) { magic_resist = p_magic_resist; }
	int get_magic_resist() const { return magic_resist; }
	void set_damage_kind(DamageKind p_damage_kind) { damage_kind = p_damage_kind; }
	DamageKind get_damage_kind() const { return damage_kind; }
	void set_targeting(const StringName &p_targeting) { targeting = p_targeting; }
	StringName get_targeting() const { return targeting; }
	void set_opening(const StringName &p_opening) { opening = p_opening; }
	StringName get_opening() const { return opening; }
	void set_attack_shape(const StringName &p_attack_shape) { attack_shape = p_attack_shape; }
	StringName get_attack_shape() const { return attack_shape; }
	void set_counters(const TypedArray<StringName> &p_counters) { counters = p_counters; }
	TypedArray<StringName> get_counters() const { return counters; }
	void set_is_ranged(bool p_is_ranged) { is_ranged = p_is_ranged; }
	bool get_is_ranged() const { return is_ranged; }
	void set_blocks_arrows(bool p_blocks_arrows) { blocks_arrows = p_blocks_arrows; }
	bool get_blocks_arrows() const { return blocks_arrows; }
	void set_immune_to_knockback(bool p_immune_to_knockback) { immune_to_knockback = p_immune_to_knockback; }
	bool get_immune_to_knockback() const { return immune_to_knockback; }
	void set_stops_charge(bool p_stops_charge) { stops_charge = p_stops_charge; }
	bool get_stops_charge() const { return stops_charge; }
};

} // namespace godot

VARIANT_ENUM_CAST(ClassData::DamageKind);
