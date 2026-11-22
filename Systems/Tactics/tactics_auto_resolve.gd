class_name TacticsAutoResolve
extends RefCounted
## "Auto": resolves a region with the auto battle (`Battle`, the auto chess
## simulation, through its public API only) instead of the tactics map.
## Our leaders and squads as mustered by a TacticsCampaign (the same
## roster people) and the region's enemy become auto-battle units: each
## keeps its own UnitData and ClassData, with the class's hp and attack
## scaled by the tactics unit's percents (a scaled copy of the class,
## registered on this one battle; counters still point at the copies of
## the classes they counter). A side with more than the board holds puts
## its leaders first, then soldiers by turn of leader, and the units left
## off lend their hp to the ones on it. The auto battle sees no objective,
## waves or terrain, so the region's `auto_enemy_pct` scales the enemy's hp
## and attack to stand in for them. Placement (melee to the front,
## ranged to the back, columns shuffled) comes from the battle seed. The
## result is applied by TacticsCampaign.apply_auto(): no one dies, the
## fallen are wounded. See Docs/systems/tactics_world.md.
## resolve() plays it at once; start() and advance() play it a little at a
## time (the world screen, a slice a frame).
## [codeblock]
## var result := TacticsAutoResolve.resolve(campaign)
## var summary := campaign.apply_auto(result)
## [/codeblock]

const RULES_PATH: String = "res://Data/Rules/battle_rules.tres"
const LEADER_STAR: int = 2
const SOLDIER_STAR: int = 1
const MAX_TICKS: int = 20000
const COLUMNS: int = 7
const RANKS: int = 4
## The rank a unit prefers: melee soldiers in front, melee leaders behind
## them, ranged soldiers and then ranged leaders at the back.
const RANK_MELEE_SOLDIER: int = 1
const RANK_MELEE_LEADER: int = 2
const RANK_RANGED_SOLDIER: int = 3
const RANK_RANGED_LEADER: int = 4


## Ticks the battle advances in one advance() call at most; the world
## screen calls it each frame until its time budget runs out.
const TICKS_PER_CHUNK: int = 20

var _battle: Battle
var _placed: Array = []
var _counts: Array = []
var _fortune: int = 0
var _ticks_left: int = MAX_TICKS
var _result: Dictionary = {}


## Plays the region's battle to its end in one call. Returns {is_won,
## winner, ticks, hash, units: [{side, person, is_leader, troop, leader_id,
## alive, hp, max_hp}], counts: [[alive, placed, total] side A, side B],
## fortune (the enemy %, see fortune_pct())}. The same as start(), then
## advance() until it returns true, then get_result().
static func resolve(campaign: TacticsCampaign) -> Dictionary:
	var auto := TacticsAutoResolve.new()
	auto.start(campaign)
	auto.advance(MAX_TICKS)
	return auto.get_result()


## Sets the battle up (units placed, not run yet). Then advance() it, a
## little each frame, so a slow device never freezes on one frame.
func start(campaign: TacticsCampaign) -> void:
	var rules := load(RULES_PATH) as BattleRulesData
	var sides: Array = [_our_units(campaign), _enemy_units(campaign)]
	_battle = Battle.new()
	_battle.set_rules(rules)
	for side: int in 2:
		var chosen := _choose(sides[side], rules.max_units_per_side)
		_placed.append(chosen)
		_counts.append([0, chosen.size(), (sides[side] as Array).size()])
	var region := campaign.roster.world.data.get_region(campaign.region_id)
	var seed_value := campaign.get_battle_seed()
	_fortune = fortune_pct(seed_value, campaign.roster.world.data.auto_fortune_pct)
	var enemy_pct: int = (region.auto_enemy_pct if region != null else 100) * (100 + _fortune) / 100
	_register_classes(_battle, _placed, _fill_pct(sides, _placed), [100, enemy_pct])
	for side: int in 2:
		_place(_battle, side, _placed[side], seed_value + side)
	_battle.start()


## Runs up to `max_ticks` more steps (ticks); true once the battle is over (the
## result is then ready). The ticks run are the same however they are cut.
func advance(max_ticks: int) -> bool:
	if is_finished():
		return true
	# Steps, not ticks, as run_to_end() counts them: the same cap in total
	# as one run_to_end(MAX_TICKS).
	var steps := mini(maxi(max_ticks, 1), _ticks_left)
	_battle.run_to_end(steps)
	_ticks_left -= steps
	if _battle.is_finished() or _ticks_left <= 0:
		_finish()
		return true
	return false


func is_finished() -> bool:
	return not _result.is_empty()


## Units of each side still standing now: [ours, the enemy's], out of
## get_placed_counts().
func get_alive_counts() -> Array[int]:
	var alive: Array[int] = [0, 0]
	if is_finished():
		return [int(_counts[0][0]), int(_counts[1][0])]
	for side: int in 2:
		for entry: Dictionary in _placed[side]:
			alive[side] += 1 if _battle.get_unit_state(entry["index"])["alive"] else 0
	return alive


## Units each side put on the board: [ours, the enemy's].
func get_placed_counts() -> Array[int]:
	return [int(_counts[0][1]), int(_counts[1][1])]


## The fortune of war of this battle (see fortune_pct()).
func get_fortune() -> int:
	return _fortune


## The result (see resolve()); empty until advance() returned true.
func get_result() -> Dictionary:
	return _result


func _finish() -> void:
	var rows: Array[Dictionary] = []
	for side: int in 2:
		for entry: Dictionary in _placed[side]:
			var state := _battle.get_unit_state(entry["index"])
			_counts[side][0] += 1 if state["alive"] else 0
			rows.append({
				"side": side, "person": entry["person"], "is_leader": entry["is_leader"], "unit_id": entry["unit"].id,
				"leader_id": entry["leader_id"], "alive": state["alive"], "hp": state["hp"], "max_hp": state["max_hp"],
			})
	var winner := _battle.get_winner()
	_result = {
		"is_won": winner == Battle.SIDE_A, "winner": winner, "ticks": _battle.get_tick(), "hash": _battle.get_state_hash(), "units": rows,
		"counts": _counts, "fortune": _fortune,
	}
	_battle.free()
	_battle = null


## The fortune of war of a battle seed: the enemy's hp and attack move by
## this % (-limit..+limit, the same for the same seed).
static func fortune_pct(seed_value: int, limit: int) -> int:
	if limit <= 0:
		return 0
	return absi(hash("%d:auto:fortune" % seed_value)) % (2 * limit + 1) - limit


# Our side: [{unit (TacticsUnitData), is_leader, person, leader_id, slot}],
# leaders in muster order, each followed by its squad.
static func _our_units(campaign: TacticsCampaign) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	var scenario := campaign.scenario
	for slot: int in scenario.leaders_a.size():
		var leader: TacticsLeaderData = scenario.leaders_a[slot]
		var leader_person: int = campaign.leader_people[slot] if slot < campaign.leader_people.size() else -1
		units.append({"unit": leader, "is_leader": true, "person": leader_person, "leader_id": leader.id, "slot": slot})
		var squad: Array = campaign.squads[slot]
		var ids: Array = campaign.people[slot]
		for index: int in squad.size():
			if (squad[index] as TacticsTroopData).is_noncombatant:
				continue
			units.append({"unit": squad[index], "is_leader": false, "person": ids[index] if index < ids.size() else -1, "leader_id": leader.id, "slot": slot})
	return units


static func _enemy_units(campaign: TacticsCampaign) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	var scenario := campaign.scenario
	for slot: int in scenario.leaders_b.size():
		var leader: TacticsLeaderData = scenario.leaders_b[slot]
		units.append({"unit": leader, "is_leader": true, "person": -1, "leader_id": leader.id, "slot": slot})
		for troop: TacticsTroopData in scenario.get_squad(Battle.SIDE_B, slot):
			if not troop.is_noncombatant:
				units.append({"unit": troop, "is_leader": false, "person": -1, "leader_id": leader.id, "slot": slot})
	return units


# Leaders first, then one soldier of each leader in turn, up to `limit`.
static func _choose(units: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	for entry: Dictionary in units:
		if entry["is_leader"] and chosen.size() < limit:
			chosen.append(entry)
	var by_slot: Dictionary[int, Array] = {}
	for entry: Dictionary in units:
		if not entry["is_leader"]:
			if not by_slot.has(entry["slot"]):
				by_slot[entry["slot"]] = []
			by_slot[entry["slot"]].append(entry)
	var slots := by_slot.keys()
	slots.sort()
	var round_index := 0
	while chosen.size() < limit:
		var added := false
		for slot: int in slots:
			var squad: Array = by_slot[slot]
			if round_index < squad.size() and chosen.size() < limit:
				chosen.append(squad[round_index])
				added = true
		if not added:
			break
		round_index += 1
	return chosen


# Per side, the % the placed units' hp is raised by so they carry the hp of
# the units left off the board.
static func _fill_pct(sides: Array, placed: Array) -> Array[int]:
	var result: Array[int] = []
	for side: int in 2:
		var total := 0
		var on_board := 0
		for entry: Dictionary in sides[side]:
			total += _base_hp(entry["unit"])
		for entry: Dictionary in placed[side]:
			on_board += _base_hp(entry["unit"])
		result.append(100 * total / maxi(on_board, 1))
	return result


static func _base_hp(unit: TacticsUnitData) -> int:
	return unit.base_class.max_hp * unit.hp_pct / 100


# One scaled copy of each class a unit needs (by class, hp % and attack %),
# registered before any unit; counters name the copies of the countered
# classes, so a class still counters what it countered.
static func _register_classes(battle: Battle, placed: Array, fill_pct: Array[int], side_pct: Array) -> void:
	var copies: Dictionary = {}
	var by_base: Dictionary = {}
	for side: int in 2:
		for entry: Dictionary in placed[side]:
			var unit: TacticsUnitData = entry["unit"]
			var hp_pct: int = unit.hp_pct * fill_pct[side] / 100 * side_pct[side] / 100
			var attack_pct: int = unit.attack_pct * side_pct[side] / 100
			var key := "%s__%d_%d" % [unit.base_class.id, hp_pct, attack_pct]
			if not copies.has(key):
				var copy := unit.base_class.duplicate() as ClassData
				copy.id = StringName(key)
				copy.max_hp = maxi(unit.base_class.max_hp * hp_pct / 100, 1)
				copy.attack = unit.base_class.attack * attack_pct / 100
				copies[key] = copy
				if not by_base.has(unit.base_class.id):
					by_base[unit.base_class.id] = []
				by_base[unit.base_class.id].append(StringName(key))
			var unit_copy := unit.base_unit.duplicate() as UnitData
			unit_copy.class_id = StringName(key)
			entry["auto_unit"] = unit_copy
	for key: String in copies:
		var copy: ClassData = copies[key]
		var counters: Array[StringName] = []
		for countered: StringName in copy.counters:
			for countered_copy: StringName in by_base.get(countered, []):
				counters.append(countered_copy)
		copy.counters = counters
		battle.register_class(copy)


# Each unit on the free cell of its rank nearest the front of the column
# order (from the seed), or of the nearest rank with room.
static func _place(battle: Battle, side: int, entries: Array, seed_value: int) -> void:
	var columns: Array[int] = []
	for column: int in COLUMNS:
		columns.append(column + 1)
	for index: int in range(COLUMNS - 1, 0, -1):
		var other := absi(hash("%d:auto:%d" % [seed_value, index])) % (index + 1)
		var kept := columns[index]
		columns[index] = columns[other]
		columns[other] = kept
	var taken: Dictionary = {}
	for entry: Dictionary in entries:
		var cell := _free_cell(_rank_for(entry), columns, taken)
		taken[cell] = true
		entry["index"] = battle.add_unit(side, entry["auto_unit"], LEADER_STAR if entry["is_leader"] else SOLDIER_STAR, cell.x, cell.y)


static func _rank_for(entry: Dictionary) -> int:
	var is_ranged: bool = (entry["unit"] as TacticsUnitData).base_class.is_ranged
	if entry["is_leader"]:
		return RANK_RANGED_LEADER if is_ranged else RANK_MELEE_LEADER
	return RANK_RANGED_SOLDIER if is_ranged else RANK_MELEE_SOLDIER


static func _free_cell(rank: int, columns: Array[int], taken: Dictionary) -> Vector2i:
	for distance: int in RANKS:
		for wanted: int in [rank - distance, rank + distance]:
			if wanted < 1 or wanted > RANKS:
				continue
			for column: int in columns:
				if not taken.has(Vector2i(column, wanted)):
					return Vector2i(column, wanted)
	push_error("TacticsAutoResolve: no free cell for rank %d" % rank)
	return Vector2i(1, 1)
