#pragma once

// Plain C++ types shared by the battle simulation. No Godot headers here: the
// simulation must build and replay without the engine. See Docs/systems/battle.md.

#include "battle/battle_basic_types.h"
#include "skill/skill_types.h"

#include <cstdint>
#include <string>
#include <vector>

namespace battle {

struct ShapeHandler;

// Class definition as the simulation sees it. Handler ids are resolved
// against the registries when the class is registered.
struct ClassDef {
	std::string id;
	int max_hp = 1;
	int attack = 0;
	int attacks_per_100s = 1;
	int range_cells = 1;
	int armor = 0;
	int magic_resist = 0;
	DamageKind damage_kind = DamageKind::PHYSICAL;
	std::string targeting_id;
	std::string opening_id;
	std::string attack_shape_id;
	std::vector<std::string> counter_ids;
	bool is_ranged = false;
	bool blocks_arrows = false;
	bool immune_to_knockback = false;
	bool stops_charge = false;
	// The class skill and passive; units may override them (UnitSpec).
	bool has_skill = false;
	SkillDef skill;
	bool has_passive = false;
	PassiveDef passive;
};

// What add_unit needs to know about a unit's content.
struct UnitSpec {
	std::string unit_id;
	std::string class_id;
	// Counted by race milestones; may be empty.
	std::string race_id;
	int cost = 1;
	int star = 1;
	// Optional per-unit replacements for the class skill and passive.
	bool has_skill_override = false;
	SkillDef skill_override;
	bool has_passive_override = false;
	PassiveDef passive_override;
};

struct UnitState {
	int index = 0;
	int side = SIDE_A;
	int class_index = 0;
	std::string unit_id;
	std::string race_id;
	int cost = 1;
	int star = 1;
	bool is_alive = true;
	int hp = 0;
	int max_hp = 0;
	int attack = 0;
	// The unit occupies this cell from the moment a move into it starts.
	Cell cell;
	int attack_charge = 0;
	// The unit is moving while the tick is below this. Stored as an end tick
	// so a move lasts its duration whatever the action order.
	int move_end_tick = 0;
	int target = NO_UNIT;
	bool has_seen_target_in_range = false;
	int target_out_of_range_ticks = 0;
	int no_path_ticks = 0;
	bool is_opening_active = false;
	UnitSkillState skills;
	// Basic attacks made so far (first-attack and every-Nth modifiers).
	int basic_attacks = 0;
	// Extra range from modifiers, fixed at battle start.
	int range_bonus = 0;
	// Damage this unit dealt so far (after mitigation); a statistic for the
	// run (Kỳ Ngộ), not part of the state hash: nothing reads it in battle.
	int64_t damage_dealt = 0;
	// An attack shape a modifier gave the unit at battle start, or nullptr.
	const ShapeHandler *shape_override = nullptr;
	// Indexes into BattleSim's modifiers that land on this unit.
	std::vector<int> modifiers;
};

enum class EventType {
	BATTLE_STARTED,
	UNIT_MOVED,
	UNIT_ATTACKED,
	DAMAGE_DEALT,
	UNIT_DIED,
	CHARGE_ENDED,
	BATTLE_ENDED,
	QI_CHANGED,
	SKILL_CAST_STARTED,
	SKILL_RESOLVED,
	PASSIVE_TRIGGERED,
	STATUS_APPLIED,
	STATUS_ENDED,
	SYNERGY_ACTIVATED,
	FORMATION_BROKEN,
	MODIFIER_TRIGGERED,
};

enum class MoveKind {
	WALK,
	CHARGE,
	KNOCKBACK,
};

enum class AttackKind {
	MELEE,
	RANGED,
	MAGIC,
};

enum class EndReason {
	ELIMINATION,
	TIME_LIMIT,
};

// One state change. Only the fields of its type are meaningful; the bridge
// turns it into a Dictionary with the keys listed in Docs/systems/battle.md.
struct BattleEvent {
	int id = 0;
	int tick = 0;
	EventType type = EventType::BATTLE_STARTED;
	int cause = 0;
	int unit = NO_UNIT;
	int source = NO_UNIT;
	int target = NO_UNIT;
	int killer = NO_UNIT;
	int hit = NO_UNIT;
	int blocked_by = NO_UNIT;
	Cell from;
	Cell to;
	int duration_ticks = 0;
	MoveKind move_kind = MoveKind::WALK;
	AttackKind attack_kind = AttackKind::MELEE;
	int amount = 0;
	int hp_after = 0;
	bool is_counter = false;
	bool is_crit = false;
	int winner = NO_WINNER;
	EndReason reason = EndReason::ELIMINATION;
	// Skill or passive id: damage from a skill or passive, casts, triggers.
	std::string skill_id;
	std::vector<Cell> cells;
	bool is_after_skill = false;
	int qi = 0;
	int qi_max = 0;
	StatusKind status = StatusKind::TAUNTED;
	int end_tick = 0;
	// Synergy events: the side, `class`/`race`/`formation`/`hop_luc`, the
	// milestone, formation or modifier id, level and the units involved.
	int side = SIDE_A;
	std::string synergy_kind;
	std::string synergy_id;
	int level = 0;
	int threshold = 0;
	std::vector<int> units;
	// modifier_triggered: the modifier handler id.
	std::string modifier_id;
	// damage_dealt: a modifier blocked the whole hit.
	bool is_blocked_by_modifier = false;
	// damage_dealt: the victim is petrified and took nothing.
	bool is_immune = false;
};

} // namespace battle
