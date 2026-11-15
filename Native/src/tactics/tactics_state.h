#pragma once

// Mutable state of a tactics battle: units, zones, buffs, declared AI
// intents and the events that report every change.

#include "tactics_types.h"

namespace tactics {

struct UnitState {
	int index = 0;
	int side = SIDE_A;
	UnitDef def;
	// Soldiers: their leader. Leaders: NO_UNIT.
	int leader = NO_UNIT;
	// Leaders: their soldiers in squad order (dead ones stay listed).
	std::vector<int> soldiers;
	bool is_alive = true;
	int hp = 1;
	Cell cell;
	// Reset at the start of the unit's side phase.
	bool has_moved = false;
	bool has_acted = false;
	bool has_squad_acted = false;
	// Steps of the same direction at the end of the last move this phase.
	int straight_cells = 0;
	// Leaders.
	int order = 0;
	Cell heading = { 0, -1 };
	// Consecutive moves with the same heading (0 before any move).
	int heading_streak = 0;
	int skill_charge = 0;
	int skill_area_bonus = 0;
	// Soldiers: attacked since the soldier last took its squad step.
	bool was_attacked_since_move = false;
	int last_attacker = NO_UNIT;
};

struct ZoneState {
	ZoneDef def;
	int side = SIDE_A;
	int source = NO_UNIT;
	std::vector<Cell> cells;
	// The zone is removed at the start of the first phase of this round.
	int end_round = 0;
};

struct BuffState {
	int unit = NO_UNIT;
	StatKind stat = StatKind::ATTACK_PCT;
	int amount = 0;
	int end_round = 0;
	std::string source_id;
};

enum class IntentAction {
	WAIT = 0,
	ATTACK = 1,
	SKILL = 2,
};

// What an AI leader will do in its next phase, declared at the start of the
// opponent's phase.
struct Intent {
	int leader = NO_UNIT;
	Cell destination;
	IntentAction action = IntentAction::WAIT;
	int target = NO_UNIT;
	Cell target_cell;
};

enum class EventType {
	BATTLE_STARTED = 0,
	PHASE_STARTED,
	PHASE_ENDED,
	UNIT_MOVED,
	ORDER_CHANGED,
	LEADER_WAITED,
	ENGAGEMENT_STARTED,
	ENGAGEMENT_ENDED,
	DAMAGE_DEALT,
	UNIT_DIED,
	SKILL_USED,
	SKILL_RESOLVED,
	SKILL_CHARGE_CHANGED,
	SKILL_GREW,
	BUFF_APPLIED,
	BUFF_ENDED,
	ZONE_CREATED,
	ZONE_EXPIRED,
	PASSIVE_TRIGGERED,
	INTENT_DECLARED,
	BATTLE_ENDED,
};

struct SkillTargetResult {
	int unit = NO_UNIT;
	int amount = 0;
	int hp_after = 0;
	bool is_dead = false;
};

// One state change. Fields that a type does not use keep their defaults;
// Docs/systems/tactics.md lists each type's payload.
struct Event {
	int id = 0;
	int turn = 0;
	int cause = 0;
	EventType type = EventType::BATTLE_STARTED;
	int unit = NO_UNIT;
	int target = NO_UNIT;
	int side = NO_INDEX;
	int round = 0;
	int amount = 0;
	int hp_after = 0;
	int value = 0;
	int threshold = 0;
	int end_round = 0;
	int winner = NO_WINNER;
	bool is_counter = false;
	bool is_first_strike = false;
	Cell from;
	Cell to;
	std::vector<Cell> cells;
	std::vector<int> units;
	// A content or handler id: skill, passive, zone, order or buff stat.
	std::string content_id;
	// A small name: move kind, attack kind, intent action, end reason.
	std::string kind;
	std::vector<SkillTargetResult> results;
};

// The outcome of one engagement, as resolved or forecast.
struct EngagementResult {
	bool is_valid = false;
	int attacker = NO_UNIT;
	int defender = NO_UNIT;
	AttackKind kind = AttackKind::MELEE;
	bool is_first_strike = false;
	bool can_counter = false;
	int attacker_damage_per_hit = 0;
	int defender_damage_per_hit = 0;
	int attacker_hits = 0;
	int defender_hits = 0;
	int attacker_hp_after = 0;
	int defender_hp_after = 0;
	bool is_attacker_dead = false;
	bool is_defender_dead = false;
};

} // namespace tactics
