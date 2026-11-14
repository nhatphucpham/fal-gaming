#pragma once

// Plain C++ types of the skill system: skill and passive definitions as the
// simulation sees them, and the per-unit state they need (Khí, cast,
// statuses, passive counters, charge). No Godot headers. Handler pointers are
// filled by resolve_skill() / resolve_passive() (skill_validation.h).
// See Docs/systems/skill.md.

#include "battle/battle_basic_types.h"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace battle {

struct SelectorHandler;
struct AreaHandler;
struct EffectHandler;
struct ConditionHandler;

constexpr int MAX_SKILL_EFFECTS = 3;
// A star-3 override or an after-skill field left at this keeps the base value.
constexpr int SAME_AS_BASE = -1;

// Who an effect acts on.
enum class EffectTarget {
	// Living enemies standing in the skill's cells when it resolves.
	AREA = 0,
	SELF = 1,
	// The other unit of a passive's trigger (the attacker, the charger).
	SOURCE = 2,
};

// One effect block (`effect.damage`, ...). The meaning of value, duration
// and count depends on the effect; see Docs/systems/skill.md.
struct EffectDef {
	std::string id;
	EffectTarget target = EffectTarget::AREA;
	int value = 0;
	int duration_ticks = 0;
	int count = 0;
	// Count at 3 stars, or SAME_AS_BASE.
	int star3_count = SAME_AS_BASE;
	DamageKind damage_kind = DamageKind::PHYSICAL;
	const EffectHandler *handler = nullptr;
};

// One resolution of a skill: who it aims at, which cells, what it does.
struct SkillStepDef {
	std::string selector_id;
	int selector_range = 0;
	std::string area_id;
	int area_size = 0;
	std::vector<EffectDef> effects;
	const SelectorHandler *selector = nullptr;
	const AreaHandler *area = nullptr;
};

struct SkillDef {
	std::string id;
	int qi_cost = 100;
	SkillStepDef main;
	// Area at 3 stars; empty id or SAME_AS_BASE keeps the main one.
	std::string star3_area_id;
	int star3_area_size = SAME_AS_BASE;
	const AreaHandler *star3_area = nullptr;
	// The Hậu chiêu, only at 3 stars: resolves after_delay_ticks after the
	// main step. An empty after.selector_id reuses the main cells; no
	// after.effects repeats the main effects.
	bool has_after_skill = false;
	int after_delay_ticks = 0;
	SkillStepDef after;
};

enum class PassiveTrigger {
	BASIC_ATTACK_LANDED,
	DAMAGED,
	ARROW_BLOCKED,
	MELEE_HIT_TAKEN,
	CHARGE_IMPACT_INCOMING,
	CHARGE_IMPACT,
	ELEMENT_REACTION,
	// A unit of the other side resolved a skill (main step, not the Hậu chiêu).
	ENEMY_SKILL_RESOLVED,
};

struct PassiveDef {
	std::string id;
	std::string trigger_id;
	// Empty means no condition.
	std::string condition_id;
	int condition_radius = 0;
	// Fires on every Nth matching trigger (1: every one).
	int every_nth = 1;
	// 0: unlimited.
	int limit_per_battle = 0;
	// Fires at most once per source unit per battle.
	bool once_per_source = false;
	// When above 0: fires when every_nth triggers fall within this many
	// ticks (a sliding window), then the window empties.
	int window_ticks = 0;
	EffectDef effect;
	PassiveTrigger trigger = PassiveTrigger::BASIC_ATTACK_LANDED;
	const ConditionHandler *condition = nullptr;
};

enum class StatusKind {
	TAUNTED = 0,
	GUARD = 1,
	ARMOR_BREAK = 2,
	STUN = 3,
	// Turned to stone: takes no damage and does nothing (boss rule Hóa Đá).
	PETRIFIED = 4,
};
constexpr int STATUS_COUNT = 5;

// A status is active while the tick is below end_tick.
struct StatusSlot {
	bool is_active = false;
	int end_tick = 0;
	int amount = 0;
	int source = NO_UNIT;
};

struct CastState {
	bool is_casting = false;
	// The tick on which the effects resolve (the last cast tick).
	int end_tick = 0;
	int event_id = 0;
	Cell anchor;
	std::vector<Cell> cells;
};

// A charge in progress: the cavalry opening or a skill charge.
struct ChargeState {
	bool is_active = false;
	bool is_skill = false;
	int coefficient_pct = 0;
	int cells_run = 0;
	// Columns still to charge after this one (skill charge at 3 stars).
	int columns_left = 0;
	int reposition_ticks = 0;
	int cause = 0;
	// The enemy the charge runs at (its lane target); NO_UNIT: none yet.
	int target = NO_UNIT;
};

struct PassiveCounters {
	int trigger_count = 0;
	int fire_count = 0;
	// Bit i set: already fired against unit i (once_per_source).
	uint64_t used_sources = 0;
	// Ticks of the triggers inside the window (window_ticks), oldest first.
	std::vector<int> window_hits;
};

// The skill side of one unit in a battle.
struct UnitSkillState {
	bool has_skill = false;
	bool has_passive = false;
	int qi = 0;
	int qi_max = 0;
	CastState cast;
	ChargeState charge;
	PassiveCounters passive;
	std::array<StatusSlot, STATUS_COUNT> statuses;
};

// A Hậu chiêu waiting for its tick.
struct ScheduledStep {
	int tick = 0;
	int caster = NO_UNIT;
	int cause = 0;
	std::vector<Cell> cells;
};

} // namespace battle
