// BattleSim: milestones, formations and Hợp Lực. start() evaluates both
// sides with the rules layer and installs one ActiveModifier per grant;
// the hooks below act on them during the battle. See
// Docs/systems/synergy.md.

#include "battle_sim.h"

#include "battle_shapes.h"

#include "rules/synergy_eval.h"
#include "rules/synergy_validation.h"
#include "skill/skill_areas.h"
#include "skill/skill_cast.h"
#include "skill/skill_selectors.h"
#include "skill/skill_statuses.h"

#include <algorithm>

namespace battle {

namespace {

using rules::ModifierKind;

constexpr int PERCENT = 100;
const char *const VOLLEY_SELECTOR_ID = "select.densest_area";
const char *const VOLLEY_AREA_ID = "area.row3";

const char *const SOURCE_KIND_NAMES[] = { "class", "race", "formation", "hop_luc" };

bool fail(const std::string &p_message, std::string *r_error) {
	if (r_error != nullptr) {
		*r_error = p_message;
	}
	return false;
}

} // namespace

const char *get_source_kind_name(rules::SourceKind p_kind) {
	return SOURCE_KIND_NAMES[static_cast<int>(p_kind)];
}

bool BattleSim::set_synergy(const rules::SynergyConfig &p_config, std::string *r_error) {
	if (!units.empty()) {
		return fail("the synergy configuration cannot change after units were added", r_error);
	}
	rules::SynergyConfig config = p_config;
	if (!rules::resolve_config(&config, r_error)) {
		return false;
	}
	synergy = config;
	has_synergy = true;
	return true;
}

void BattleSim::clear_synergy() {
	synergy = rules::SynergyConfig();
	has_synergy = false;
}

void BattleSim::install_synergy() {
	sources.clear();
	modifiers.clear();
	for (UnitState &unit : units) {
		unit.modifiers.clear();
	}
	if (!has_synergy) {
		return;
	}
	install_side(SIDE_A);
	install_side(SIDE_B);
	apply_start_stats();
}

void BattleSim::install_side(int p_side) {
	std::vector<int> unit_of_piece;
	std::vector<formation::Piece> pieces;
	for (const UnitState &unit : units) {
		if (unit.side != p_side) {
			continue;
		}
		const Cell local = global_to_local(p_side, unit.cell);
		formation::Piece piece;
		piece.col = local.col;
		piece.rank = local.row;
		piece.class_index = rules::find_class_index(synergy, get_class_def(unit).id);
		piece.race_index = rules::find_race_index(synergy, unit.race_id);
		piece.unit_id = unit.unit_id;
		piece.cost = unit.cost;
		pieces.push_back(piece);
		unit_of_piece.push_back(unit.index);
	}
	const rules::SynergyResult result = rules::evaluate(synergy, pieces);
	std::vector<rules::Source> found;
	std::vector<rules::Grant> grants;
	rules::collect_grants(synergy, result, pieces, &found, &grants);
	const int first_source = static_cast<int>(sources.size());
	for (const rules::Source &entry : found) {
		SynergySource source;
		source.side = p_side;
		source.kind = entry.kind;
		source.id = entry.id;
		source.level = entry.level;
		source.threshold = entry.threshold;
		for (int piece : entry.pieces) {
			source.units.push_back(unit_of_piece[piece]);
		}
		for (const formation::LocalCell &cell : entry.cells) {
			source.cells.push_back(local_to_global(p_side, cell.col, cell.rank));
		}
		sources.push_back(source);
	}
	for (const rules::Grant &grant : grants) {
		ActiveModifier modifier;
		modifier.unit = unit_of_piece[grant.piece];
		modifier.kind = grant.def->handler->kind;
		modifier.handler_id = grant.def->handler_id;
		modifier.value = grant.value;
		modifier.count = grant.def->count;
		modifier.ticks = grant.def->ticks;
		modifier.stat = grant.def->stat;
		modifier.param = grant.def->param;
		modifier.source = first_source + grant.source;
		modifier.origin_id = grant.origin_id;
		units[modifier.unit].modifiers.push_back(static_cast<int>(modifiers.size()));
		modifiers.push_back(modifier);
	}
}

// Stats fixed for the whole battle: max hp, range from the front rank, the
// attack shape.
void BattleSim::apply_start_stats() {
	for (UnitState &unit : units) {
		const int hp_pct = sum_modifiers(unit.index, ModifierKind::MAX_HP_PCT);
		if (hp_pct > 0) {
			unit.max_hp = static_cast<int>(static_cast<int64_t>(unit.max_hp) * (PERCENT + hp_pct) / PERCENT);
			unit.hp = unit.max_hp;
		}
		if (global_to_local(unit.side, unit.cell).row == 1) {
			unit.range_bonus += sum_modifiers(unit.index, ModifierKind::RANGE_ADD_IF_FRONT);
		}
		const ActiveModifier *shape = find_modifier(unit.index, ModifierKind::ATTACK_SHAPE);
		if (shape != nullptr) {
			unit.shape_override = find_shape_handler(shape->param);
		}
	}
}

// On tick 1, right after battle_started: one event per active thing, then
// the starting Khí.
void BattleSim::emit_synergy_events() {
	for (const SynergySource &source : sources) {
		BattleEvent event;
		event.type = EventType::SYNERGY_ACTIVATED;
		event.side = source.side;
		event.synergy_kind = get_source_kind_name(source.kind);
		event.synergy_id = source.id;
		event.level = source.level;
		event.threshold = source.threshold;
		event.units = source.units;
		event.cells = source.cells;
		emit_event(event);
	}
	for (const UnitState &unit : units) {
		add_qi(*this, unit.index, sum_modifiers(unit.index, ModifierKind::START_QI), 0);
	}
}

void BattleSim::run_volleys() {
	for (size_t index = 0; index < modifiers.size(); index++) {
		const ActiveModifier modifier = modifiers[index];
		if (modifier.kind != ModifierKind::VOLLEY || tick % modifier.ticks != 0 || !units[modifier.unit].is_alive || !sources[modifier.source].is_active) {
			continue;
		}
		if (!has_status(units[modifier.unit], StatusKind::STUN)) {
			fire_volley(modifier);
		}
	}
}

// Physical damage to every enemy in the row of three around the enemy cell
// whose row holds the most enemies. Not a basic attack: no Khí for the shooter.
void BattleSim::fire_volley(const ActiveModifier &p_modifier) {
	const UnitState &shooter = units[p_modifier.unit];
	const AreaHandler *area = find_area_handler(VOLLEY_AREA_ID);
	const SelectorHandler *selector = find_selector_handler(VOLLEY_SELECTOR_ID);
	SkillStepDef step;
	Cell anchor;
	if (!selector->select(*this, shooter, step, area, 0, &anchor)) {
		return;
	}
	std::vector<Cell> cells;
	area->collect(anchor, shooter.side, 0, &cells);
	const std::vector<int> enemies = get_enemies_in_cells(*this, shooter.side, cells);
	if (enemies.empty()) {
		return;
	}
	const int cause = emit_modifier_triggered(p_modifier.unit, p_modifier, 0, cells);
	for (int enemy : enemies) {
		if (!units[p_modifier.unit].is_alive) {
			return;
		}
		DamageSpec spec;
		spec.source = p_modifier.unit;
		spec.victim = enemy;
		spec.coefficient_pct = p_modifier.value;
		spec.skill_id = p_modifier.origin_id;
		spec.cause = cause;
		deal_damage(spec);
	}
}

void BattleSim::break_formations(int p_victim, int p_cause) {
	for (SynergySource &source : sources) {
		if (source.kind != rules::SourceKind::FORMATION || !source.is_active || std::find(source.units.begin(), source.units.end(), p_victim) == source.units.end()) {
			continue;
		}
		source.is_active = false;
		BattleEvent event;
		event.type = EventType::FORMATION_BROKEN;
		event.cause = p_cause;
		event.side = source.side;
		event.synergy_kind = get_source_kind_name(source.kind);
		event.synergy_id = source.id;
		event.level = source.level;
		event.units = source.units;
		event.cells = source.cells;
		emit_event(event);
	}
}

// mod.qi_on_ally_kill: the killer and every ally sharing that modifier's
// source gain its value.
void BattleSim::reward_ally_kill(int p_killer, int p_cause) {
	const ActiveModifier *found = find_modifier(p_killer, ModifierKind::QI_ON_ALLY_KILL);
	if (found == nullptr) {
		return;
	}
	const ActiveModifier modifier = *found;
	const int cause = emit_modifier_triggered(p_killer, modifier, p_cause);
	for (const ActiveModifier &other : modifiers) {
		if (other.kind == ModifierKind::QI_ON_ALLY_KILL && other.source == modifier.source && units[other.unit].is_alive) {
			add_qi(*this, other.unit, other.value, cause);
		}
	}
}

void BattleSim::fill_damage_request(const DamageSpec &p_spec, DamageRequest *r_request) const {
	const UnitState &source = units[p_spec.source];
	const UnitState &victim = units[p_spec.victim];
	const ClassDef &source_class = get_class_def(source);
	const ClassDef &victim_class = get_class_def(victim);
	r_request->attack = source.attack;
	r_request->coefficient_pct = p_spec.coefficient_pct;
	r_request->kind = p_spec.kind;
	r_request->is_counter = std::find(source_class.counter_ids.begin(), source_class.counter_ids.end(), victim_class.id) != source_class.counter_ids.end();
	r_request->counter_bonus_pct = rules.counter_bonus_pct;
	r_request->is_crit = p_spec.is_crit;
	r_request->crit_multiplier_pct = rules.crit_multiplier_pct;
	const bool is_own_skill = !p_spec.skill_id.empty() && source.skills.has_skill && p_spec.skill_id == get_skill(p_spec.source).id;
	r_request->increase_pct = p_spec.increase_pct + sum_modifiers(p_spec.source, ModifierKind::DAMAGE_DEALT_PCT) + (is_own_skill ? sum_modifiers(p_spec.source, ModifierKind::SKILL_DAMAGE_PCT) : 0);
	const bool is_ranged_physical = p_spec.kind == DamageKind::PHYSICAL && source_class.is_ranged;
	r_request->decrease_pct = get_status_amount(victim, StatusKind::GUARD) + sum_modifiers(p_spec.victim, ModifierKind::DAMAGE_TAKEN_PCT)
			+ (is_ranged_physical ? sum_modifiers(p_spec.victim, ModifierKind::RANGED_PHYSICAL_TAKEN_PCT) : 0);
	int stats[2] = { 0, 0 };
	if (victim.is_alive) {
		for (int index : victim.modifiers) {
			const ActiveModifier &modifier = modifiers[index];
			if (modifier.kind == ModifierKind::STAT_ADD && sources[modifier.source].is_active) {
				stats[modifier.stat] += modifier.value;
			}
		}
	}
	r_request->armor = victim_class.armor + stats[static_cast<int>(rules::StatId::ARMOR)];
	r_request->magic_resist = victim_class.magic_resist + stats[static_cast<int>(rules::StatId::MAGIC_RESIST)];
	r_request->armor_break_pct = get_status_amount(victim, StatusKind::ARMOR_BREAK);
}

// A hit from an enemy: a block takes it whole, else a split leaves the
// victim its share (the others get theirs from share_split()).
int BattleSim::adjust_hit_amount(const DamageSpec &p_spec, int p_amount, bool *r_is_blocked, int *r_split_modifier, int *r_share) {
	if (units[p_spec.source].side == units[p_spec.victim].side) {
		return p_amount;
	}
	for (int index : units[p_spec.victim].modifiers) {
		ActiveModifier &modifier = modifiers[index];
		if (modifier.kind == ModifierKind::BLOCK_FIRST_HIT && sources[modifier.source].is_active && modifier.uses < modifier.count) {
			modifier.uses++;
			*r_is_blocked = true;
			emit_modifier_triggered(p_spec.victim, modifier, p_spec.cause);
			return 0;
		}
	}
	for (int index : units[p_spec.victim].modifiers) {
		const ActiveModifier &modifier = modifiers[index];
		SynergySource &source = sources[modifier.source];
		if (modifier.kind != ModifierKind::SPLIT_FIRST_HIT || !source.is_active || source.is_split_used) {
			continue;
		}
		source.is_split_used = true;
		const int living = static_cast<int>(std::count_if(source.units.begin(), source.units.end(), [&](int p_unit) { return units[p_unit].is_alive; }));
		*r_split_modifier = index;
		*r_share = p_amount / living;
		emit_modifier_triggered(p_spec.victim, modifier, p_spec.cause, source.cells);
		return p_amount - *r_share * (living - 1);
	}
	return p_amount;
}

void BattleSim::share_split(const DamageSpec &p_spec, int p_split_modifier, int p_share, int p_cause) {
	if (p_share <= 0) {
		return;
	}
	const ActiveModifier modifier = modifiers[p_split_modifier];
	const std::vector<int> members = sources[modifier.source].units;
	for (int member : members) {
		if (member == p_spec.victim || !units[member].is_alive) {
			continue;
		}
		DamageSpec share;
		share.source = p_spec.source;
		share.victim = member;
		share.kind = p_spec.kind;
		share.fixed_amount = p_share;
		share.skill_id = modifier.origin_id;
		share.cause = p_cause;
		deal_damage(share);
	}
}

void BattleSim::reflect_melee(const DamageSpec &p_spec, int p_amount, int p_cause) {
	if (!p_spec.is_melee_attack || p_spec.fixed_amount >= 0 || !units[p_spec.source].is_alive) {
		return;
	}
	const ActiveModifier *modifier = find_modifier(p_spec.victim, ModifierKind::REFLECT_MELEE_PCT);
	const int reflected = static_cast<int>(static_cast<int64_t>(p_amount) * sum_modifiers(p_spec.victim, ModifierKind::REFLECT_MELEE_PCT) / PERCENT);
	if (modifier == nullptr || reflected <= 0) {
		return;
	}
	DamageSpec reflect;
	reflect.source = p_spec.victim;
	reflect.victim = p_spec.source;
	reflect.fixed_amount = reflected;
	reflect.skill_id = modifier->origin_id;
	reflect.cause = emit_modifier_triggered(p_spec.victim, *modifier, p_cause);
	deal_damage(reflect);
}

int BattleSim::sum_modifiers(int p_unit, ModifierKind p_kind) const {
	const UnitState &unit = units[p_unit];
	int sum = 0;
	if (!unit.is_alive) {
		return sum;
	}
	for (int index : unit.modifiers) {
		const ActiveModifier &modifier = modifiers[index];
		if (modifier.kind == p_kind && sources[modifier.source].is_active) {
			sum += modifier.value;
		}
	}
	return sum;
}

const ActiveModifier *BattleSim::find_modifier(int p_unit, ModifierKind p_kind) const {
	const UnitState &unit = units[p_unit];
	if (!unit.is_alive) {
		return nullptr;
	}
	for (int index : unit.modifiers) {
		const ActiveModifier &modifier = modifiers[index];
		if (modifier.kind == p_kind && sources[modifier.source].is_active) {
			return &modifier;
		}
	}
	return nullptr;
}

ActiveModifier *BattleSim::find_modifier(int p_unit, ModifierKind p_kind) {
	return const_cast<ActiveModifier *>(static_cast<const BattleSim *>(this)->find_modifier(p_unit, p_kind));
}

int BattleSim::emit_modifier_triggered(int p_unit, const ActiveModifier &p_modifier, int p_cause, const std::vector<Cell> &p_cells) {
	BattleEvent event;
	event.type = EventType::MODIFIER_TRIGGERED;
	event.cause = p_cause;
	event.unit = p_unit;
	event.side = units[p_unit].side;
	event.modifier_id = p_modifier.handler_id;
	event.synergy_id = p_modifier.origin_id;
	event.cells = p_cells;
	return emit_event(event);
}

} // namespace battle
