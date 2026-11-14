#include "synergy_validation.h"

#include "formation/formation_patterns.h"

namespace rules {

namespace {

constexpr int MIN_PATTERN_DRANK = 0;
constexpr int MAX_PATTERN_DRANK = formation::RANKS - 1;
constexpr int MAX_PATTERN_DCOL = formation::COLS - 1;
constexpr int MAX_RULE_LEVELS = 3;
constexpr int MAX_DOUBLE_FROM_COST = 5;

// Which scopes an owner may use.
enum class Owner {
	MILESTONE,
	FORMATION,
	HOP_LUC,
};

struct ScopeEntry {
	const char *id;
	ModifierScope scope;
};

const ScopeEntry SCOPES[] = {
	{ "scope.counted", ModifierScope::COUNTED },
	{ "scope.side", ModifierScope::SIDE },
	{ "scope.members", ModifierScope::MEMBERS },
	{ "scope.slots", ModifierScope::SLOTS },
	{ "scope.behind_members", ModifierScope::BEHIND_MEMBERS },
};

bool fail(const std::string &p_message, std::string *r_error) {
	if (r_error != nullptr) {
		*r_error = p_message;
	}
	return false;
}

bool check_range(const std::string &p_owner, const char *p_field, int p_value, int p_min, int p_max, std::string *r_error) {
	if (p_value >= p_min && p_value <= p_max) {
		return true;
	}
	return fail(p_owner + " " + p_field + " must be " + std::to_string(p_min) + ".." + std::to_string(p_max) + ", got " + std::to_string(p_value), r_error);
}

int intern(std::vector<std::string> *r_ids, const std::string &p_id) {
	for (int index = 0; index < static_cast<int>(r_ids->size()); index++) {
		if ((*r_ids)[index] == p_id) {
			return index;
		}
	}
	r_ids->push_back(p_id);
	return static_cast<int>(r_ids->size()) - 1;
}

bool is_scope_allowed(ModifierScope p_scope, Owner p_owner) {
	switch (p_owner) {
		case Owner::MILESTONE:
			return p_scope == ModifierScope::COUNTED || p_scope == ModifierScope::SIDE;
		case Owner::FORMATION:
			return p_scope != ModifierScope::COUNTED;
		case Owner::HOP_LUC:
			return p_scope == ModifierScope::SIDE;
	}
	return false;
}

bool resolve_scope(const std::string &p_owner, ModifierDef *r_modifier, Owner p_owner_kind, int p_slot_count, std::string *r_error) {
	bool found = false;
	for (const ScopeEntry &entry : SCOPES) {
		if (r_modifier->scope_id == entry.id) {
			r_modifier->scope = entry.scope;
			found = true;
		}
	}
	if (!found || !is_scope_allowed(r_modifier->scope, p_owner_kind)) {
		return fail(p_owner + " has unknown or misplaced scope '" + r_modifier->scope_id + "'", r_error);
	}
	if (r_modifier->scope == ModifierScope::SLOTS && r_modifier->slots.empty()) {
		return fail(p_owner + " scope.slots lists no slot", r_error);
	}
	for (int slot : r_modifier->slots) {
		if (!check_range(p_owner, "slot", slot, 0, p_slot_count - 1, r_error)) {
			return false;
		}
	}
	if (r_modifier->is_per_formation && (p_owner_kind != Owner::MILESTONE || r_modifier->scope != ModifierScope::SIDE)) {
		return fail(p_owner + " per_formation needs a milestone modifier with scope.side", r_error);
	}
	return true;
}

bool resolve_mod(const std::string &p_owner, ModifierDef *r_modifier, std::string *r_error) {
	const ModifierHandler *handler = r_modifier->handler;
	if (handler->needs_param && r_modifier->param.empty()) {
		return fail(p_owner + " needs a param", r_error);
	}
	if (handler->kind == ModifierKind::STAT_ADD) {
		StatId stat;
		if (!find_stat_id(r_modifier->param, &stat)) {
			return fail(p_owner + " has unknown stat '" + r_modifier->param + "'", r_error);
		}
		r_modifier->stat = static_cast<int>(stat);
	}
	const bool needs_count = handler->kind == ModifierKind::BLOCK_FIRST_HIT || handler->kind == ModifierKind::NTH_ATTACK_BONUS_PCT;
	if (needs_count && r_modifier->count < 1) {
		return fail(p_owner + " count must be at least 1", r_error);
	}
	if (handler->kind == ModifierKind::VOLLEY && r_modifier->ticks < 1) {
		return fail(p_owner + " ticks must be at least 1", r_error);
	}
	return true;
}

bool resolve_rule(const std::string &p_owner, ModifierDef *r_modifier, std::string *r_error) {
	if (r_modifier->rule->kind == RuleKind::FORMATION_LEVEL) {
		return check_range(p_owner, "value", r_modifier->value, 1, MAX_RULE_LEVELS, r_error) && check_range(p_owner, "count", r_modifier->count, 1, formation::MAX_SLOTS, r_error);
	}
	return check_range(p_owner, "count", r_modifier->count, 2, formation::MAX_SLOTS, r_error);
}

bool resolve_modifier(const std::string &p_owner, ModifierDef *r_modifier, Owner p_owner_kind, int p_slot_count, std::string *r_error) {
	const std::string owner = p_owner + " " + r_modifier->handler_id;
	if (!check_range(owner, "value", r_modifier->value, 0, MAX_MODIFIER_VALUE, r_error) || !check_range(owner, "count", r_modifier->count, 0, MAX_MODIFIER_COUNT, r_error)
			|| !check_range(owner, "ticks", r_modifier->ticks, 0, MAX_MODIFIER_TICKS, r_error)) {
		return false;
	}
	r_modifier->handler = find_modifier_handler(r_modifier->handler_id);
	r_modifier->rule = find_rule_handler(r_modifier->handler_id);
	if (r_modifier->rule != nullptr) {
		// Rules bend matching; only race milestones may carry them.
		return p_owner_kind == Owner::MILESTONE ? resolve_rule(owner, r_modifier, r_error) : fail(owner + ": rules belong to milestones", r_error);
	}
	if (r_modifier->handler == nullptr) {
		return fail(p_owner + " has unknown modifier '" + r_modifier->handler_id + "'", r_error);
	}
	return resolve_scope(owner, r_modifier, p_owner_kind, p_slot_count, r_error) && resolve_mod(owner, r_modifier, r_error);
}

bool resolve_tiers(const std::string &p_owner, std::vector<TierDef> *r_tiers, Owner p_owner_kind, std::string *r_error) {
	if (!check_range(p_owner, "tier count", static_cast<int>(r_tiers->size()), 1, MAX_TIERS, r_error)) {
		return false;
	}
	int previous = 0;
	for (size_t index = 0; index < r_tiers->size(); index++) {
		TierDef &tier = (*r_tiers)[index];
		const std::string owner = p_owner + " tier " + std::to_string(index);
		if (tier.at <= previous) {
			return fail(owner + " at must be above the previous tier's " + std::to_string(previous) + ", got " + std::to_string(tier.at), r_error);
		}
		previous = tier.at;
		for (ModifierDef &modifier : tier.modifiers) {
			if (!resolve_modifier(owner, &modifier, p_owner_kind, 0, r_error)) {
				return false;
			}
		}
	}
	return true;
}

bool resolve_milestone(SynergyConfig *r_config, MilestoneDef *r_milestone, std::string *r_error) {
	if (r_milestone->id.empty() || r_milestone->counted_id.empty()) {
		return fail("a milestone has an empty id or counted_id", r_error);
	}
	if (!check_range(r_milestone->id, "double_from_cost", r_milestone->double_from_cost, 0, MAX_DOUBLE_FROM_COST, r_error)) {
		return false;
	}
	const bool is_class = r_milestone->kind == CountedKind::CLASS;
	r_milestone->counted_index = intern(is_class ? &r_config->class_ids : &r_config->race_ids, r_milestone->counted_id);
	return resolve_tiers(r_milestone->id, &r_milestone->tiers, Owner::MILESTONE, r_error);
}

bool resolve_pattern(SynergyConfig *r_config, FormationDef *r_formation, std::string *r_error) {
	formation::PatternDef &pattern = r_formation->pattern;
	const std::string &owner = r_formation->id;
	pattern.handler = formation::find_pattern_handler(pattern.handler_id);
	if (pattern.handler == nullptr) {
		return fail(owner + " has unknown pattern '" + pattern.handler_id + "'", r_error);
	}
	const int slot_count = static_cast<int>(pattern.slots.size());
	if (!check_range(owner, "slot count", slot_count, 1, formation::MAX_SLOTS, r_error) || !check_range(owner, "slot class count", static_cast<int>(r_formation->slot_class_ids.size()), slot_count, slot_count, r_error)
			|| !check_range(owner, "anchor_col", pattern.anchor_col, 0, formation::COLS, r_error) || !check_range(owner, "anchor_rank", pattern.anchor_rank, 0, formation::RANKS, r_error)
			|| !check_range(owner, "middle_slot", pattern.middle_slot, formation::NO_INDEX, slot_count - 1, r_error)) {
		return false;
	}
	for (int slot = 0; slot < slot_count; slot++) {
		formation::Slot &entry = pattern.slots[slot];
		if (!check_range(owner, "slot dcol", entry.dcol, -MAX_PATTERN_DCOL, MAX_PATTERN_DCOL, r_error) || !check_range(owner, "slot drank", entry.drank, MIN_PATTERN_DRANK, MAX_PATTERN_DRANK, r_error)) {
			return false;
		}
		const std::string &class_id = r_formation->slot_class_ids[slot];
		entry.class_index = class_id.empty() ? formation::ANY : intern(&r_config->class_ids, class_id);
	}
	return true;
}

bool resolve_formation(SynergyConfig *r_config, FormationDef *r_formation, std::string *r_error) {
	if (r_formation->id.empty()) {
		return fail("a formation has an empty id", r_error);
	}
	if (!resolve_pattern(r_config, r_formation, r_error)) {
		return false;
	}
	for (ModifierDef &modifier : r_formation->modifiers) {
		if (!resolve_modifier(r_formation->id, &modifier, Owner::FORMATION, static_cast<int>(r_formation->pattern.slots.size()), r_error)) {
			return false;
		}
	}
	return true;
}

} // namespace

bool resolve_config(SynergyConfig *r_config, std::string *r_error) {
	r_config->is_resolved = false;
	r_config->class_ids.clear();
	r_config->race_ids.clear();
	for (MilestoneDef &milestone : r_config->milestones) {
		if (!resolve_milestone(r_config, &milestone, r_error)) {
			return false;
		}
		// Rules act on the milestone's race.
		for (const TierDef &tier : milestone.tiers) {
			for (const ModifierDef &modifier : tier.modifiers) {
				if (modifier.rule != nullptr && modifier.rule->kind != RuleKind::FORMATION_MISSING_ANY && milestone.kind != CountedKind::RACE) {
					return fail(milestone.id + " " + modifier.handler_id + " needs a race milestone", r_error);
				}
			}
		}
	}
	for (FormationDef &entry : r_config->formations) {
		if (!resolve_formation(r_config, &entry, r_error)) {
			return false;
		}
	}
	HopLucDef &hop_luc = r_config->hop_luc;
	if (!check_range("hop_luc", "level_step_pct", hop_luc.level_step_pct, 0, MAX_LEVEL_STEP_PCT, r_error) || !check_range("hop_luc", "max_formation_level", hop_luc.max_level, 1, MAX_FORMATION_LEVEL, r_error)
			|| !resolve_tiers("hop_luc", &hop_luc.tiers, Owner::HOP_LUC, r_error)) {
		return false;
	}
	r_config->is_resolved = true;
	return true;
}

int find_class_index(const SynergyConfig &p_config, const std::string &p_class_id) {
	for (int index = 0; index < static_cast<int>(p_config.class_ids.size()); index++) {
		if (p_config.class_ids[index] == p_class_id) {
			return index;
		}
	}
	return NO_INDEX;
}

int find_race_index(const SynergyConfig &p_config, const std::string &p_race_id) {
	for (int index = 0; index < static_cast<int>(p_config.race_ids.size()); index++) {
		if (p_config.race_ids[index] == p_race_id) {
			return index;
		}
	}
	return NO_INDEX;
}

} // namespace rules
