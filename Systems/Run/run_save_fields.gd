class_name RunSaveFields
extends RefCounted
## Reads and checks the top-level fields of a run save (everything but the
## piece rows, which RunRoster checks against the placement rules). Every key
## the game writes is required; see "Save format" in Docs/systems/run.md.
## [codeblock]
## var fields := RunSaveFields.read(data, catalog)
## if fields.is_empty(): return false
## [/codeblock]

## The phases a save can hold, by their name in the file.
const PHASES: Dictionary[String, int] = {"prep": RunState.Phase.PREP, "reward": RunState.Phase.REWARD}


## The saved values, typed, under the same keys as the file ("phase" as a
## RunState.Phase, "rewards" as RunState.Reward values, "shop" as ids), or
## an empty dictionary when a key is missing, a type is wrong or a value is
## out of range.
static func read(data: Dictionary, catalog: Catalog) -> Dictionary:
	var rules := catalog.run_rules
	var reader := SaveReader.new(data)
	var fields := {
		"stage": reader.get_int("stage"), "stages_cleared": reader.get_int("stages_cleared"),
		"morale": reader.get_int("morale"), "gold": reader.get_int("gold"),
		"supply": reader.get_int("supply"), "level": reader.get_int("level"),
		"seed": reader.get_int_string("seed"), "rng_state": reader.get_int_string("rng_state"),
		"next_piece_id": reader.get_int("next_piece_id"), "pieces": reader.get_array("pieces"),
		"black_market": reader.get_bool("black_market"), "free_refreshes": reader.get_int("free_refreshes"),
	}
	var phase_name := reader.get_string("phase")
	var shop := reader.get_array("shop")
	var rewards := reader.get_array("rewards")
	if not reader.is_valid or not PHASES.has(phase_name):
		return {}
	fields["phase"] = PHASES[phase_name]
	fields["shop"] = _read_offers(shop, catalog)
	fields["rewards"] = _read_rewards(rewards, fields, rules)
	if fields["shop"] == null or fields["rewards"] == null or not _is_in_range(fields, rules):
		return {}
	return fields


## The phase's name in the file.
static func get_phase_name(phase: RunState.Phase) -> String:
	return PHASES.find_key(phase)


# Shop offers as ids ("" an empty slot), or null with more offers than
# slots, a wrong type or an unknown unit.
static func _read_offers(saved: Array, catalog: Catalog) -> Variant:
	var offers: Array[StringName] = []
	for offer: Variant in saved:
		var unit: UnitData = catalog.get_unit(StringName(offer)) if offer is String and offer != "" else null
		if not offer is String or (offer != "" and (unit == null or unit.is_boss)):
			return null
		offers.append(StringName(offer))
	return offers if offers.size() <= catalog.run_rules.shop_slots else null


# The offered rewards, or null when they could not have been offered: none
# outside the reward phase; in it all of them (after a win) or
# `rewards_after_loss` (after a loss; at most what is left without the rest
# at the final stage), each known and once, and no rest at the final stage,
# which is only repeated after a loss.
static func _read_rewards(saved: Array, fields: Dictionary, rules: RunRules) -> Variant:
	var rewards: Array[RunState.Reward] = []
	for id: Variant in saved:
		var index := RunState.REWARD_IDS.find(StringName(id)) if id is String else -1
		if index < 0 or rewards.has(index):
			return null
		rewards.append(index as RunState.Reward)
	if fields["phase"] != RunState.Phase.REWARD:
		return rewards if rewards.is_empty() else null
	var is_final: bool = fields["stage"] >= rules.stage_count
	var after_loss := mini(rules.rewards_after_loss, RunState.REWARD_IDS.size() - (1 if is_final else 0))
	if rewards.size() != RunState.REWARD_IDS.size() and rewards.size() != after_loss:
		return null
	if is_final and rewards.has(RunState.Reward.REST):
		return null
	return rewards


# In the reward phase the stage just won counts as cleared already (the
# final stage only reaches it after a loss).
static func _is_in_range(fields: Dictionary, rules: RunRules) -> bool:
	var stage: int = fields["stage"]
	var cleared: int = fields["stages_cleared"]
	var is_after_win_possible: bool = fields["phase"] == RunState.Phase.REWARD and stage < rules.stage_count
	var cleared_max := stage if is_after_win_possible else stage - 1
	return stage >= 1 and stage <= rules.stage_count \
		and fields["morale"] >= 1 and fields["morale"] <= rules.max_morale \
		and fields["gold"] >= 0 and fields["supply"] >= 0 \
		and fields["level"] >= rules.start_level and fields["level"] <= rules.max_level \
		and cleared >= 0 and cleared <= cleared_max
