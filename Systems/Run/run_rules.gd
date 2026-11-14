class_name RunRules
extends Resource
## Every economy number of a run (gold, supply, levels, shop odds, stage
## income, battle results, rewards), so tuning never touches RunState.
## Lives in Data/Rules/run_rules.tres. Levels run from start_level to
## max_level; arrays indexed by level start at start_level.
## [codeblock]
## var rules := catalog.run_rules
## var odds := rules.get_shop_odds(5)   # percent by cost 1..5
## [/codeblock]

@export_group("Start")
@export var start_morale: int = 60
@export var max_morale: int = 60
@export var start_gold: int = 10
@export var start_supply: int = 0
@export var start_level: int = 3
@export var max_level: int = 9

@export_group("Board and bench")
@export var bench_slots: int = 6
## Board capacity is the level, but never above this.
@export var max_board_units: int = 8
@export var max_star: int = 3
@export var copies_to_merge: int = 3

@export_group("Legends (cost 5)")
@export var legend_cost: int = 5
@export var legend_copies_to_merge: int = 2
@export var legend_max_star: int = 2
@export var legend_board_limit: int = 2

@export_group("Shop")
@export var shop_slots: int = 5
@export var refresh_gold: int = 2
@export var supply_pack_gold: int = 4
@export var supply_pack_amount: int = 4
## Supply needed to go from each level to the next, from start_level up to
## max_level - 1.
@export var supply_to_next: PackedInt32Array = PackedInt32Array([2, 4, 6, 10, 14, 20])
## Percent chance of cost 1..5 per shop slot, one row per level from
## start_level to max_level; each row sums to 100.
@export var shop_odds: Array[PackedInt32Array] = []

@export_group("Stages")
@export var stage_count: int = 12
## Gold at the start of each stage's preparation, by stage 1..stage_count.
@export var stage_income: PackedInt32Array = PackedInt32Array([4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 10])
@export var stage_supply: int = 2
## From this stage on, preparation brings winter_supply instead.
@export var winter_from_stage: int = 9
@export var winter_supply: int = 1
## Enemy units per stage, checked against Data/Stages/ by Catalog.validate().
@export var enemy_counts: PackedInt32Array = PackedInt32Array([3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8])

@export_group("Battle results")
@export var win_gold: int = 1
@export var win_supply: int = 2
## Win streak bonus: from the streak_gold_wins[i]-th win in a row, a win
## pays streak_gold_bonus[i] more gold (the highest step reached counts).
@export var streak_gold_wins: PackedInt32Array = PackedInt32Array([2, 4])
@export var streak_gold_bonus: PackedInt32Array = PackedInt32Array([1, 2])
@export var loss_morale_base: int = 6
@export var loss_morale_per_enemy: int = 2

@export_group("Rewards")
@export var rest_morale: int = 15
@export var hunt_supply: int = 6
@export var black_market_levels: int = 1
@export var black_market_free_refreshes: int = 1
## "Kho báu": gold paid by the loot reward.
@export var loot_gold: int = 5
## Reward cards offered after a won battle and after a lost one, drawn
## from all the rewards.
@export var rewards_after_win: int = 3
@export var rewards_after_loss: int = 2

@export_group("Road encounters")
## After the reward of these stages one road encounter plays.
@export var encounter_stages: PackedInt32Array = PackedInt32Array([2, 4, 6, 8, 10])

@export_group("Boss")
## The stage whose line-up holds the boss (exactly one is_boss unit there,
## none elsewhere).
@export var boss_stage: int = 12
## From this stage on, the prep top bar shows the boss badge.
@export var boss_reveal_stage: int = 6

@export_group("Kỳ Ngộ")
## Each family's hidden threshold is rolled in this range at run start.
@export var ngo_threshold_min: int = 4
@export var ngo_threshold_max: int = 7
## Ngộ per battle for each family with a tier reached.
@export var ngo_per_active: int = 1
## More Ngộ for every active family after a lost battle.
@export var ngo_loss_bonus: int = 1
## More Ngộ for the active, unmutated family that dealt the most damage.
@export var ngo_top_damage_bonus: int = 2
## A meter never goes above this (it also bounds saved values).
@export var ngo_meter_max: int = 99
@export var epiphanies_per_run: int = 4


## Supply to reach the next level, or -1 at max_level.
func get_supply_to_next(level: int) -> int:
	var index := level - start_level
	if level >= max_level or index < 0 or index >= supply_to_next.size():
		return -1
	return supply_to_next[index]


## Percent by cost 1..5 for a shop slot at `level` (clamped to the table).
func get_shop_odds(level: int) -> PackedInt32Array:
	var index := clampi(level - start_level, 0, shop_odds.size() - 1)
	return shop_odds[index]


## Gold income at the start of `stage` (1-based).
func get_stage_income(stage: int) -> int:
	return stage_income[clampi(stage, 1, stage_income.size()) - 1]


## Supply income at the start of `stage`: less in winter.
func get_stage_supply(stage: int) -> int:
	return winter_supply if stage >= winter_from_stage else stage_supply


func get_enemy_count(stage: int) -> int:
	return enemy_counts[clampi(stage, 1, enemy_counts.size()) - 1]


## Extra gold a win pays as the `streak`-th win in a row (0 below the
## first step).
func get_streak_bonus(streak: int) -> int:
	var bonus := 0
	for index: int in mini(streak_gold_wins.size(), streak_gold_bonus.size()):
		if streak >= streak_gold_wins[index]:
			bonus = streak_gold_bonus[index]
	return bonus


## Most units on the board at `level`.
func get_capacity(level: int) -> int:
	return mini(level, max_board_units)


## Problems in the numbers, one message per problem; empty when valid.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var levels := max_level - start_level + 1
	if levels < 1:
		problems.append("Run: %s has max_level %d below start_level %d" % [resource_path, max_level, start_level])
		return problems
	if shop_odds.size() != levels:
		problems.append("Run: %s has %d shop_odds rows, expected %d" % [resource_path, shop_odds.size(), levels])
	for index: int in shop_odds.size():
		var row := shop_odds[index]
		var total := 0
		for percent: int in row:
			total += percent
		if row.size() != Catalog.MAX_COST or total != 100:
			problems.append("Run: %s shop_odds[%d] must have 5 values summing to 100, got %s" % [resource_path, index, row])
	if supply_to_next.size() != levels - 1:
		problems.append("Run: %s has %d supply_to_next values, expected %d" % [resource_path, supply_to_next.size(), levels - 1])
	for pair: Array in [["stage_income", stage_income], ["enemy_counts", enemy_counts]]:
		var values: PackedInt32Array = pair[1]
		if values.size() != stage_count:
			problems.append("Run: %s has %d %s values, expected %d" % [resource_path, values.size(), pair[0], stage_count])
	if start_morale < 1 or start_morale > max_morale or bench_slots < 1 or shop_slots < 1:
		problems.append("Run: %s has a bad start_morale, bench_slots or shop_slots" % resource_path)
	if boss_stage < 1 or boss_stage > stage_count or boss_reveal_stage < 1 or boss_reveal_stage > boss_stage:
		problems.append("Run: %s has boss_stage %d and boss_reveal_stage %d, expected 1 <= reveal <= boss <= %d" % [resource_path, boss_stage, boss_reveal_stage, stage_count])
	if ngo_threshold_min < 1 or ngo_threshold_max < ngo_threshold_min or ngo_meter_max < ngo_threshold_max or epiphanies_per_run < 0:
		problems.append("Run: %s has bad Kỳ Ngộ numbers (thresholds %d..%d, meter max %d, per run %d)" % [resource_path, ngo_threshold_min, ngo_threshold_max, ngo_meter_max, epiphanies_per_run])
	for count: int in [rewards_after_win, rewards_after_loss]:
		if count < 1 or count > RunState.REWARD_IDS.size():
			problems.append("Run: %s has rewards_after_win %d and rewards_after_loss %d, expected 1..%d" % [resource_path, rewards_after_win, rewards_after_loss, RunState.REWARD_IDS.size()])
			break
	if streak_gold_wins.size() != streak_gold_bonus.size() or loot_gold < 1:
		problems.append("Run: %s needs one streak_gold_bonus per streak_gold_wins and loot_gold above 0" % resource_path)
	for stage: int in encounter_stages:
		if stage < 1 or stage >= stage_count:
			problems.append("Run: %s has encounter stage %d, expected 1..%d" % [resource_path, stage, stage_count - 1])
	return problems
