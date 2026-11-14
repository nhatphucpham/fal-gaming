#include "modifier_handlers.h"

namespace rules {

namespace {

const ModifierHandler MODIFIER_HANDLERS[] = {
	{ "mod.stat_add", ModifierKind::STAT_ADD, true },
	{ "mod.block_first_hit", ModifierKind::BLOCK_FIRST_HIT, false },
	{ "mod.damage_dealt_pct", ModifierKind::DAMAGE_DEALT_PCT, false },
	{ "mod.qi_on_attack", ModifierKind::QI_ON_ATTACK, false },
	{ "mod.reflect_melee_pct", ModifierKind::REFLECT_MELEE_PCT, false },
	{ "mod.range_add_if_front", ModifierKind::RANGE_ADD_IF_FRONT, false, true },
	{ "mod.pierce_behind", ModifierKind::PIERCE_BEHIND, false },
	{ "mod.charge_impact_pct", ModifierKind::CHARGE_IMPACT_PCT, false },
	{ "mod.knockback_cells", ModifierKind::KNOCKBACK_CELLS, false },
	{ "mod.attack_speed_pct", ModifierKind::ATTACK_SPEED_PCT, false },
	{ "mod.first_attack_crit", ModifierKind::FIRST_ATTACK_CRIT, false },
	{ "mod.attack_shape", ModifierKind::ATTACK_SHAPE, true, true },
	{ "mod.skill_damage_pct", ModifierKind::SKILL_DAMAGE_PCT, false },
	{ "mod.ranged_physical_taken_pct", ModifierKind::RANGED_PHYSICAL_TAKEN_PCT, false },
	{ "mod.volley", ModifierKind::VOLLEY, false },
	{ "mod.charge_speed_until_attack", ModifierKind::CHARGE_SPEED_UNTIL_ATTACK, false },
	{ "mod.nth_attack_bonus_pct", ModifierKind::NTH_ATTACK_BONUS_PCT, false },
	{ "mod.charge_immunity", ModifierKind::CHARGE_IMMUNITY, false },
	{ "mod.damage_taken_pct", ModifierKind::DAMAGE_TAKEN_PCT, false },
	{ "mod.split_first_hit", ModifierKind::SPLIT_FIRST_HIT, false },
	{ "mod.start_qi", ModifierKind::START_QI, false },
	{ "mod.max_hp_pct", ModifierKind::MAX_HP_PCT, false, true },
	{ "mod.qi_on_ally_kill", ModifierKind::QI_ON_ALLY_KILL, false },
};

const RuleHandler RULE_HANDLERS[] = {
	{ "rule.formation_level", RuleKind::FORMATION_LEVEL },
	{ "rule.formation_missing_middle", RuleKind::FORMATION_MISSING_MIDDLE },
	{ "rule.formation_missing_any", RuleKind::FORMATION_MISSING_ANY },
};

struct StatEntry {
	const char *name;
	StatId stat;
};

const StatEntry STATS[] = {
	{ "armor", StatId::ARMOR },
	{ "magic_resist", StatId::MAGIC_RESIST },
};

} // namespace

const ModifierHandler *find_modifier_handler(const std::string &p_id) {
	for (const ModifierHandler &handler : MODIFIER_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

const RuleHandler *find_rule_handler(const std::string &p_id) {
	for (const RuleHandler &handler : RULE_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

bool find_stat_id(const std::string &p_name, StatId *r_stat) {
	for (const StatEntry &entry : STATS) {
		if (p_name == entry.name) {
			*r_stat = entry.stat;
			return true;
		}
	}
	return false;
}

} // namespace rules
