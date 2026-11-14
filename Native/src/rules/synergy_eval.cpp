#include "synergy_eval.h"

#include "formation/formation_match.h"

#include <algorithm>
#include <array>

namespace rules {

namespace {

constexpr int PERCENT = 100;
constexpr int HEAVY_UNIT_WEIGHT = 2;
const char *const HOP_LUC_ID = "hop_luc";

struct LevelRule {
	int race_index = NO_INDEX;
	int min_members = 1;
	int levels = 0;
};

int count_milestone(const MilestoneDef &p_milestone, const std::vector<formation::Piece> &p_pieces) {
	std::vector<std::string> seen;
	int count = 0;
	for (const formation::Piece &piece : p_pieces) {
		const bool is_counted = p_milestone.kind == CountedKind::CLASS ? piece.class_index == p_milestone.counted_index : piece.race_index == p_milestone.counted_index;
		if (!is_counted) {
			continue;
		}
		if (p_milestone.counts_distinct_units) {
			if (std::find(seen.begin(), seen.end(), piece.unit_id) != seen.end()) {
				continue;
			}
			seen.push_back(piece.unit_id);
		}
		count += p_milestone.double_from_cost > 0 && piece.cost >= p_milestone.double_from_cost ? HEAVY_UNIT_WEIGHT : 1;
	}
	return count;
}

int count_reached(const MilestoneDef &p_milestone, int p_count) {
	int reached = 0;
	for (const TierDef &tier : p_milestone.tiers) {
		reached += p_count >= tier.at ? 1 : 0;
	}
	return reached;
}

// The race rules of every reached tier: missing-member rules for matching,
// level rules for after it.
void collect_rules(const SynergyConfig &p_config, const SynergyResult &p_result, formation::MatchOptions *r_options, std::vector<LevelRule> *r_levels) {
	for (const MilestoneState &state : p_result.milestones) {
		const MilestoneDef &milestone = p_config.milestones[state.milestone];
		for (int tier = 0; tier < state.reached; tier++) {
			for (const ModifierDef &modifier : milestone.tiers[tier].modifiers) {
				if (modifier.rule == nullptr) {
					continue;
				}
				switch (modifier.rule->kind) {
					case RuleKind::FORMATION_LEVEL:
						r_levels->push_back({ milestone.counted_index, modifier.count, modifier.value });
						break;
					case RuleKind::FORMATION_MISSING_MIDDLE:
						r_options->missing_rules.push_back({ modifier.count, milestone.counted_index });
						break;
					case RuleKind::FORMATION_MISSING_ANY:
						r_options->missing_rules.push_back({ modifier.count, NO_INDEX });
						break;
				}
			}
		}
	}
}

int get_level(const formation::Match &p_match, const std::vector<formation::Piece> &p_pieces, const std::vector<LevelRule> &p_rules, int p_max_level) {
	int bonus = 0;
	for (const LevelRule &rule : p_rules) {
		int members = 0;
		for (int piece : p_match.pieces) {
			members += piece != NO_INDEX && p_pieces[piece].race_index == rule.race_index ? 1 : 0;
		}
		if (members >= rule.min_members) {
			bonus = std::max(bonus, rule.levels);
		}
	}
	return std::min(1 + bonus, p_max_level);
}

void add_hop_luc(const HopLucDef &p_hop_luc, SynergyResult *r_result) {
	for (int index = 0; index < static_cast<int>(p_hop_luc.tiers.size()); index++) {
		const int at = p_hop_luc.tiers[index].at;
		if (r_result->points >= at) {
			r_result->tier = index;
		} else if (r_result->next_tier_at == 0) {
			r_result->next_tier_at = at;
		}
	}
}

std::vector<int> get_members(const formation::Match &p_match) {
	std::vector<int> members;
	for (int piece : p_match.pieces) {
		if (piece != NO_INDEX) {
			members.push_back(piece);
		}
	}
	return members;
}

int find_piece_at(const std::vector<formation::Piece> &p_pieces, int p_col, int p_rank) {
	for (int index = 0; index < static_cast<int>(p_pieces.size()); index++) {
		if (p_pieces[index].col == p_col && p_pieces[index].rank == p_rank) {
			return index;
		}
	}
	return NO_INDEX;
}

std::vector<int> all_pieces(const std::vector<formation::Piece> &p_pieces) {
	std::vector<int> pieces;
	for (int index = 0; index < static_cast<int>(p_pieces.size()); index++) {
		pieces.push_back(index);
	}
	return pieces;
}

std::vector<int> get_formation_targets(const ModifierDef &p_modifier, const formation::Match &p_match, const std::vector<formation::Piece> &p_pieces) {
	std::vector<int> targets;
	switch (p_modifier.scope) {
		case ModifierScope::SIDE:
			return all_pieces(p_pieces);
		case ModifierScope::SLOTS:
			for (int slot : p_modifier.slots) {
				if (p_match.pieces[slot] != NO_INDEX) {
					targets.push_back(p_match.pieces[slot]);
				}
			}
			return targets;
		case ModifierScope::BEHIND_MEMBERS:
			for (int member : get_members(p_match)) {
				const int behind = find_piece_at(p_pieces, p_pieces[member].col, p_pieces[member].rank + 1);
				if (behind != NO_INDEX) {
					targets.push_back(behind);
				}
			}
			return targets;
		default:
			return get_members(p_match);
	}
}

std::vector<int> get_counted_pieces(const MilestoneDef &p_milestone, const std::vector<formation::Piece> &p_pieces) {
	std::vector<int> pieces;
	for (int index = 0; index < static_cast<int>(p_pieces.size()); index++) {
		const formation::Piece &piece = p_pieces[index];
		if ((p_milestone.kind == CountedKind::CLASS ? piece.class_index : piece.race_index) == p_milestone.counted_index) {
			pieces.push_back(index);
		}
	}
	return pieces;
}

void grant_all(const ModifierDef &p_modifier, const std::vector<int> &p_targets, int p_value, int p_source, const std::string &p_origin, std::vector<Grant> *r_grants) {
	for (int piece : p_targets) {
		r_grants->push_back({ piece, &p_modifier, p_value, p_source, p_origin });
	}
}

} // namespace

int scale_by_level(int p_value, int p_level, int p_step_pct) {
	return p_value * (PERCENT + p_step_pct * (p_level - 1)) / PERCENT;
}

SynergyResult evaluate(const SynergyConfig &p_config, const std::vector<formation::Piece> &p_pieces) {
	SynergyResult result;
	if (!p_config.is_resolved) {
		return result;
	}
	for (int index = 0; index < static_cast<int>(p_config.milestones.size()); index++) {
		const int count = count_milestone(p_config.milestones[index], p_pieces);
		const int reached = count_reached(p_config.milestones[index], count);
		result.milestones.push_back({ index, count, reached });
		result.points += reached;
	}
	formation::MatchOptions options;
	std::vector<LevelRule> level_rules;
	collect_rules(p_config, result, &options, &level_rules);
	std::vector<formation::PatternDef> patterns;
	for (const FormationDef &entry : p_config.formations) {
		patterns.push_back(entry.pattern);
	}
	std::vector<formation::Match> matches;
	formation::match_formations(patterns, p_pieces, options, &matches, &result.near_misses);
	for (const formation::Match &match : matches) {
		result.formations.push_back({ match, get_level(match, p_pieces, level_rules, p_config.hop_luc.max_level) });
	}
	result.points += static_cast<int>(result.formations.size());
	add_hop_luc(p_config.hop_luc, &result);
	return result;
}

void collect_grants(const SynergyConfig &p_config, const SynergyResult &p_result, const std::vector<formation::Piece> &p_pieces, std::vector<Source> *r_sources, std::vector<Grant> *r_grants) {
	// Sources first: per-formation milestone modifiers hang on the
	// formation's source, so they end when it breaks.
	std::vector<int> milestone_first_source;
	for (const MilestoneState &state : p_result.milestones) {
		const MilestoneDef &milestone = p_config.milestones[state.milestone];
		milestone_first_source.push_back(static_cast<int>(r_sources->size()));
		for (int tier = 0; tier < state.reached; tier++) {
			Source source;
			source.kind = milestone.kind == CountedKind::CLASS ? SourceKind::CLASS : SourceKind::RACE;
			source.id = milestone.id;
			source.level = tier + 1;
			source.threshold = milestone.tiers[tier].at;
			source.pieces = get_counted_pieces(milestone, p_pieces);
			r_sources->push_back(source);
		}
	}
	const int first_formation_source = static_cast<int>(r_sources->size());
	for (const FormationState &state : p_result.formations) {
		Source source;
		source.kind = SourceKind::FORMATION;
		source.id = p_config.formations[state.match.formation].id;
		source.level = state.level;
		source.pieces = get_members(state.match);
		for (int slot = 0; slot < static_cast<int>(state.match.cells.size()); slot++) {
			if (state.match.pieces[slot] != NO_INDEX) {
				source.cells.push_back(state.match.cells[slot]);
			}
		}
		r_sources->push_back(source);
	}
	const int formation_count = static_cast<int>(p_result.formations.size());

	for (const MilestoneState &state : p_result.milestones) {
		const MilestoneDef &milestone = p_config.milestones[state.milestone];
		const std::vector<int> counted = get_counted_pieces(milestone, p_pieces);
		for (int tier = 0; tier < state.reached; tier++) {
			for (const ModifierDef &modifier : milestone.tiers[tier].modifiers) {
				if (modifier.handler == nullptr) {
					continue;
				}
				const std::vector<int> targets = modifier.scope == ModifierScope::COUNTED ? counted : all_pieces(p_pieces);
				if (!modifier.is_per_formation) {
					grant_all(modifier, targets, modifier.value, milestone_first_source[state.milestone] + tier, milestone.id, r_grants);
					continue;
				}
				for (int index = 0; index < formation_count; index++) {
					grant_all(modifier, targets, modifier.value, first_formation_source + index, milestone.id, r_grants);
				}
			}
		}
	}

	// (piece, formation, modifier index) already granted by an instance.
	std::vector<std::array<int, 3>> granted;
	for (int index = 0; index < formation_count; index++) {
		const FormationState &state = p_result.formations[index];
		const FormationDef &entry = p_config.formations[state.match.formation];
		for (int modifier = 0; modifier < static_cast<int>(entry.modifiers.size()); modifier++) {
			const ModifierDef &def = entry.modifiers[modifier];
			const int value = scale_by_level(def.value, state.level, p_config.hop_luc.level_step_pct);
			for (int piece : get_formation_targets(def, state.match, p_pieces)) {
				const std::array<int, 3> key = { piece, state.match.formation, modifier };
				if (std::find(granted.begin(), granted.end(), key) != granted.end()) {
					continue;
				}
				granted.push_back(key);
				r_grants->push_back({ piece, &def, value, first_formation_source + index, entry.id });
			}
		}
	}

	if (p_result.tier == NO_INDEX) {
		return;
	}
	Source hop_luc;
	hop_luc.kind = SourceKind::HOP_LUC;
	hop_luc.id = HOP_LUC_ID;
	hop_luc.level = p_result.points;
	hop_luc.pieces = all_pieces(p_pieces);
	r_sources->push_back(hop_luc);
	const int hop_luc_source = static_cast<int>(r_sources->size()) - 1;
	for (int tier = 0; tier <= p_result.tier; tier++) {
		for (const ModifierDef &modifier : p_config.hop_luc.tiers[tier].modifiers) {
			grant_all(modifier, hop_luc.pieces, modifier.value, hop_luc_source, HOP_LUC_ID, r_grants);
		}
	}
}

} // namespace rules
