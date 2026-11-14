#include "class_data.h"

#include "bridge_strings.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

battle::ClassDef ClassData::to_class_def() const {
	battle::ClassDef def;
	def.id = to_std_string(id);
	def.max_hp = max_hp;
	def.attack = attack;
	def.attacks_per_100s = attacks_per_100s;
	def.range_cells = range_cells;
	def.armor = armor;
	def.magic_resist = magic_resist;
	def.damage_kind = damage_kind == DAMAGE_MAGIC ? battle::DamageKind::MAGIC : battle::DamageKind::PHYSICAL;
	def.targeting_id = to_std_string(targeting);
	def.opening_id = to_std_string(opening);
	def.attack_shape_id = to_std_string(attack_shape);
	for (int64_t index = 0; index < counters.size(); index++) {
		def.counter_ids.push_back(to_std_string(StringName(counters[index])));
	}
	def.is_ranged = is_ranged;
	def.blocks_arrows = blocks_arrows;
	def.immune_to_knockback = immune_to_knockback;
	def.stops_charge = stops_charge;
	return def;
}

void ClassData::_bind_methods() {
	BIND_ENUM_CONSTANT(DAMAGE_PHYSICAL);
	BIND_ENUM_CONSTANT(DAMAGE_MAGIC);

	BATTLE_BIND_ACCESSORS(ClassData, id);
	BATTLE_BIND_ACCESSORS(ClassData, name_key);
	BATTLE_BIND_ACCESSORS(ClassData, max_hp);
	BATTLE_BIND_ACCESSORS(ClassData, attack);
	BATTLE_BIND_ACCESSORS(ClassData, attacks_per_100s);
	BATTLE_BIND_ACCESSORS(ClassData, range_cells);
	BATTLE_BIND_ACCESSORS(ClassData, armor);
	BATTLE_BIND_ACCESSORS(ClassData, magic_resist);
	BATTLE_BIND_ACCESSORS(ClassData, damage_kind);
	BATTLE_BIND_ACCESSORS(ClassData, targeting);
	BATTLE_BIND_ACCESSORS(ClassData, opening);
	BATTLE_BIND_ACCESSORS(ClassData, attack_shape);
	BATTLE_BIND_ACCESSORS(ClassData, counters);
	BATTLE_BIND_ACCESSORS(ClassData, is_ranged);
	BATTLE_BIND_ACCESSORS(ClassData, blocks_arrows);
	BATTLE_BIND_ACCESSORS(ClassData, immune_to_knockback);
	BATTLE_BIND_ACCESSORS(ClassData, stops_charge);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name_key"), "set_name_key", "get_name_key");
	ADD_GROUP("Stats", "");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_hp", PROPERTY_HINT_RANGE, "1,100000,1"), "set_max_hp", "get_max_hp");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "attack", PROPERTY_HINT_RANGE, "0,10000,1"), "set_attack", "get_attack");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "attacks_per_100s", PROPERTY_HINT_RANGE, "1,1000,1"), "set_attacks_per_100s", "get_attacks_per_100s");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "range_cells", PROPERTY_HINT_RANGE, "1,8,1"), "set_range_cells", "get_range_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "armor", PROPERTY_HINT_RANGE, "0,1000,1"), "set_armor", "get_armor");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "magic_resist", PROPERTY_HINT_RANGE, "0,1000,1"), "set_magic_resist", "get_magic_resist");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "damage_kind", PROPERTY_HINT_ENUM, "Physical,Magic"), "set_damage_kind", "get_damage_kind");
	ADD_GROUP("Behavior", "");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "targeting"), "set_targeting", "get_targeting");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "opening"), "set_opening", "get_opening");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "attack_shape"), "set_attack_shape", "get_attack_shape");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "counters", PROPERTY_HINT_ARRAY_TYPE, "StringName"), "set_counters", "get_counters");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_ranged"), "set_is_ranged", "get_is_ranged");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "blocks_arrows"), "set_blocks_arrows", "get_blocks_arrows");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "immune_to_knockback"), "set_immune_to_knockback", "get_immune_to_knockback");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "stops_charge"), "set_stops_charge", "get_stops_charge");
}
