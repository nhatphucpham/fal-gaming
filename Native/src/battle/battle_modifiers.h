#pragma once

// Battle modifiers: what class and race milestones, formations and Hợp Lực
// give a unit for one battle. The rules layer (Native/src/rules/) decides
// who gets what at start(); the battle keeps one ActiveModifier per grant
// and asks for them by kind at fixed hook points (Docs/systems/synergy.md).
// A modifier works while its source is active and its unit lives; a
// formation's source ends when one of its members dies.

#include "battle_basic_types.h"

#include "rules/synergy_types.h"

#include <string>
#include <vector>

namespace battle {

struct ActiveModifier {
	int unit = NO_UNIT;
	rules::ModifierKind kind = rules::ModifierKind::DAMAGE_DEALT_PCT;
	std::string handler_id;
	int value = 0;
	int count = 0;
	int ticks = 0;
	int stat = 0;
	std::string param;
	// Index into BattleSim's synergy sources.
	int source = 0;
	// The milestone, formation or `hop_luc` id.
	std::string origin_id;
	// Times it acted (blocks used).
	int uses = 0;
};

struct SynergySource {
	int side = SIDE_A;
	rules::SourceKind kind = rules::SourceKind::CLASS;
	std::string id;
	int level = 0;
	int threshold = 0;
	std::vector<int> units;
	// Global cells of the members at battle start (formations).
	std::vector<Cell> cells;
	bool is_active = true;
	// mod.split_first_hit: the split happened.
	bool is_split_used = false;
};

// `class`, `race`, `formation` or `hop_luc`.
const char *get_source_kind_name(rules::SourceKind p_kind);

} // namespace battle
