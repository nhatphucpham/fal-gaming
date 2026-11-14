#pragma once

#include "bridge_strings.h"

#include "skill/skill_types.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

// One effect block of a skill or passive (`effect.damage`, ...), written as
// a sub-resource inside a SkillData or PassiveData file. What value,
// duration_ticks and count mean depends on the effect (Docs/systems/skill.md).
class SkillEffectData : public Resource {
	GDCLASS(SkillEffectData, Resource)

public:
	enum Target {
		TARGET_AREA = 0,
		TARGET_SELF = 1,
		TARGET_SOURCE = 2,
	};

private:
	StringName id;
	// Stored as ints so unknown values survive for the battle to reject.
	int target = TARGET_AREA;
	int value = 0;
	int duration_ticks = 0;
	int count = 0;
	int star3_count = battle::SAME_AS_BASE;
	int damage_kind = 0;

protected:
	static void _bind_methods();

public:
	battle::EffectDef to_effect_def() const;

	void set_id(const StringName &p_id) { id = p_id; }
	StringName get_id() const { return id; }
	void set_target(int64_t p_target) { target = clamp_to_int(p_target); }
	int64_t get_target() const { return target; }
	void set_value(int64_t p_value) { value = clamp_to_int(p_value); }
	int get_value() const { return value; }
	void set_duration_ticks(int64_t p_value) { duration_ticks = clamp_to_int(p_value); }
	int get_duration_ticks() const { return duration_ticks; }
	void set_count(int64_t p_value) { count = clamp_to_int(p_value); }
	int get_count() const { return count; }
	void set_star3_count(int64_t p_value) { star3_count = clamp_to_int(p_value); }
	int get_star3_count() const { return star3_count; }
	void set_damage_kind(int64_t p_value) { damage_kind = clamp_to_int(p_value); }
	int64_t get_damage_kind() const { return damage_kind; }
};

} // namespace godot

VARIANT_ENUM_CAST(SkillEffectData::Target);
