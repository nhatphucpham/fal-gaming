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
@export var loss_morale_base: int = 6
@export var loss_morale_per_enemy: int = 2

@export_group("Rewards")
@export var rest_morale: int = 15
@export var hunt_supply: int = 6
@export var black_market_levels: int = 1
@export var black_market_free_refreshes: int = 1
## Rewards offered after a lost battle (all are offered after a win).
@export var rewards_after_loss: int = 2


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
	if rewards_after_loss < 1 or rewards_after_loss > RunState.REWARD_IDS.size():
		problems.append("Run: %s has rewards_after_loss %d, expected 1..%d" % [resource_path, rewards_after_loss, RunState.REWARD_IDS.size()])
	return problems
