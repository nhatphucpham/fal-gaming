#include "modifier_data.h"

using namespace godot;

rules::ModifierDef ModifierData::to_modifier_def() const {
	rules::ModifierDef def;
	def.handler_id = to_std_string(handler);
	def.scope_id = to_std_string(scope);
	for (int64_t index = 0; index < slots.size(); index++) {
		def.slots.push_back(slots[index]);
	}
	def.value = value;
	def.count = count;
	def.ticks = ticks;
	def.param = to_std_string(param);
	def.is_per_formation = per_formation;
	return def;
}

bool godot::copy_modifier_defs(const TypedArray<ModifierData> &p_modifiers, std::vector<rules::ModifierDef> *r_defs) {
	r_defs->clear();
	for (int64_t index = 0; index < p_modifiers.size(); index++) {
		const Ref<ModifierData> modifier = p_modifiers[index];
		if (modifier.is_null()) {
			return false;
		}
		r_defs->push_back(modifier->to_modifier_def());
	}
	return true;
}

void ModifierData::_bind_methods() {
	BATTLE_BIND_ACCESSORS(ModifierData, handler);
	BATTLE_BIND_ACCESSORS(ModifierData, scope);
	BATTLE_BIND_ACCESSORS(ModifierData, slots);
	BATTLE_BIND_ACCESSORS(ModifierData, value);
	BATTLE_BIND_ACCESSORS(ModifierData, count);
	BATTLE_BIND_ACCESSORS(ModifierData, ticks);
	BATTLE_BIND_ACCESSORS(ModifierData, param);
	BATTLE_BIND_ACCESSORS(ModifierData, per_formation);

	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "handler"), "set_handler", "get_handler");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "scope"), "set_scope", "get_scope");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "slots"), "set_slots", "get_slots");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "value", PROPERTY_HINT_RANGE, "0,1000,1"), "set_value", "get_value");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "count", PROPERTY_HINT_RANGE, "0,100,1"), "set_count", "get_count");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ticks", PROPERTY_HINT_RANGE, "0,10000,1"), "set_ticks", "get_ticks");
	ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "param"), "set_param", "get_param");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "per_formation"), "set_per_formation", "get_per_formation");
}
