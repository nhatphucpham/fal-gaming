#include "tactics_keywords.h"

#include "tactics_sim.h"

namespace tactics {

namespace {

constexpr int PERCENT = 100;

// keyword.long_weapon: when attacked in melee, the counter comes first.
bool long_weapon_strikes_first(const KeywordDef &p_keyword, AttackKind p_incoming) {
	(void)p_keyword;
	return p_incoming == AttackKind::MELEE;
}

// keyword.charge: `amount` percent more damage on the attacker's own hits
// after a run of at least `min_cells` steps in one direction this phase.
void charge_outgoing(const KeywordDef &p_keyword, const HitContext &p_context, HitModifiers &r_mods) {
	if (p_context.is_counter || p_context.kind == AttackKind::SKILL) {
		return;
	}
	if (p_context.sim->get_units()[p_context.attacker].straight_cells >= p_keyword.min_cells) {
		r_mods.increase_pct += p_keyword.amount;
	}
}

// keyword.armor_pierce: ignores `amount` percent of the target's armor.
void armor_pierce_outgoing(const KeywordDef &p_keyword, const HitContext &p_context, HitModifiers &r_mods) {
	(void)p_context;
	if (p_keyword.amount > r_mods.armor_break_pct) {
		r_mods.armor_break_pct = p_keyword.amount > PERCENT ? PERCENT : p_keyword.amount;
	}
}

// keyword.cover: allies orthogonally next to this unit take `amount`
// percent less ranged damage; several covers do not add up.
void cover_incoming_as_ally(const KeywordDef &p_keyword, const HitContext &p_context, HitModifiers &r_mods) {
	if (p_context.kind == AttackKind::RANGED && p_keyword.amount > r_mods.cover_pct) {
		r_mods.cover_pct = p_keyword.amount;
	}
}

// keyword.flying: every cell costs 1; impassable terrain and zones of
// control do not stop it (enemy cells still do).
void flying_movement(const KeywordDef &p_keyword, const MapDef &p_map, MoveProfile &r_profile) {
	(void)p_keyword;
	(void)p_map;
	r_profile.ignores_terrain_cost = true;
	r_profile.ignores_impassable = true;
	r_profile.ignores_zone_of_control = true;
}

// keyword.heavy: `amount` extra move cost on each terrain in terrain_ids.
void heavy_movement(const KeywordDef &p_keyword, const MapDef &p_map, MoveProfile &r_profile) {
	for (size_t index = 0; index < p_map.terrains.size(); index++) {
		for (const std::string &terrain_id : p_keyword.terrain_ids) {
			if (terrain_id == p_map.terrains[index].id) {
				r_profile.extra_cost_by_terrain[index] += p_keyword.amount;
			}
		}
	}
}

const KeywordHandler KEYWORD_HANDLERS[] = {
	{ "keyword.long_weapon", nullptr, nullptr, nullptr, long_weapon_strikes_first },
	{ "keyword.charge", nullptr, charge_outgoing, nullptr, nullptr },
	{ "keyword.armor_pierce", nullptr, armor_pierce_outgoing, nullptr, nullptr },
	{ "keyword.cover", nullptr, nullptr, cover_incoming_as_ally, nullptr },
	{ "keyword.flying", flying_movement, nullptr, nullptr, nullptr },
	{ "keyword.heavy", heavy_movement, nullptr, nullptr, nullptr },
	{ "keyword.scout", nullptr, nullptr, nullptr, nullptr, true },
};

} // namespace

const KeywordHandler *find_keyword_handler(const std::string &p_id) {
	for (const KeywordHandler &handler : KEYWORD_HANDLERS) {
		if (p_id == handler.id) {
			return &handler;
		}
	}
	return nullptr;
}

MoveProfile build_move_profile(const TacticsSim &p_sim, int p_unit) {
	MoveProfile profile;
	profile.extra_cost_by_terrain.assign(p_sim.get_map().terrains.size(), 0);
	for (const KeywordDef *keyword : p_sim.collect_keywords(p_unit)) {
		if (keyword->handler->modify_movement != nullptr) {
			keyword->handler->modify_movement(*keyword, p_sim.get_map(), profile);
		}
	}
	return profile;
}

void note_hit_source(std::vector<std::string> *r_sources, const HitModifiers &p_before, const HitModifiers &p_after, const std::string &p_id) {
	if (r_sources == nullptr || p_before == p_after) {
		return;
	}
	for (const std::string &source : *r_sources) {
		if (source == p_id) {
			return;
		}
	}
	r_sources->push_back(p_id);
}

} // namespace tactics
