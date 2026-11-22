class_name TacticsWorld
extends RefCounted
## The Chiến Dịch world map's state, saved inside the roster (`world`): the
## regions we control (khống chế), the enemy pressure on each, the region
## the enemy declared it presses next (địch báo trước ý đồ), the world turn,
## the campaign cycle and what each market sold this turn. Every region
## fought is one turn: the enemy's declared push then lands unless we
## fought there. Rules and numbers come from TacticsWorldData; see
## Docs/systems/tactics_world.md.
## [codeblock]
## var world := roster.world
## if world.is_open(&"region.ferry"): ...
## var change := world.finish_region(&"region.ferry", true)
## [/codeblock]

## Region states, as the world map colours them.
const STATE_HOME: StringName = &"home"
const STATE_OURS: StringName = &"ours"
const STATE_OPEN: StringName = &"open"
const STATE_LOCKED: StringName = &"locked"
## What the declared push does when we fight elsewhere.
const THREAT_HARDEN: StringName = &"threat.harden"
const THREAT_TAKE: StringName = &"threat.take"

## The world's data; loaded from TacticsWorldData.PATH when not set.
var data: TacticsWorldData:
	get:
		if data == null:
			data = load(TacticsWorldData.PATH) as TacticsWorldData
		return data
## Regions we hold, besides the home region, in the order taken.
var cleared: Array[StringName] = []
## Region id -> pressure level (0..max_pressure); missing is 0.
var pressure: Dictionary = {}
## The region the enemy presses next; empty when every region is ours.
var threat: StringName = &""
## Regions fought in this campaign (Auto or Thủ công, won or lost).
var turn: int = 0
## Campaigns finished; each new one starts with more pressure.
var cycle: int = 0
## "<region id>/<offer index>" -> how many that offer sold this turn.
var sold: Dictionary = {}
## The roster's seed: the enemy's pushes follow it.
var seed_value: int = 1
## Whether the player heard the war horn for the declared push (the world
## screen sounds it once per push); a new push sets it back to false.
var is_threat_heard: bool = false
## Whether a threat was ever picked (a fresh world picks one on first use).
var _has_threat: bool = false


## The state as the roster saves it.
func to_save_data() -> Dictionary:
	var saved_pressure := {}
	for id: StringName in pressure:
		saved_pressure[String(id)] = pressure[id]
	return {
		"cleared": cleared.map(func(id: StringName) -> String: return String(id)), "pressure": saved_pressure,
		"threat": String(threat), "turn": turn, "cycle": cycle, "sold": sold.duplicate(), "has_threat": _has_threat,
		"threat_heard": is_threat_heard,
	}


## Reads a saved state; false when it is malformed (the roster then sets
## the save aside). An empty Dictionary is a fresh world.
func read(saved: Dictionary) -> bool:
	if saved.is_empty():
		return true
	var reader := SaveReader.new(saved)
	turn = reader.get_int("turn")
	cycle = reader.get_int("cycle")
	threat = StringName(reader.get_string("threat"))
	_has_threat = reader.get_bool("has_threat")
	# Optional: older saves have none: the horn sounds once more.
	var heard: Variant = saved.get("threat_heard", false)
	if not heard is bool:
		return false
	is_threat_heard = heard
	cleared.clear()
	for id: Variant in reader.get_array("cleared"):
		if not id is String:
			return false
		cleared.append(StringName(id))
	for key: String in ["pressure", "sold"]:
		var map: Variant = saved.get(key)
		if not map is Dictionary:
			return false
		for id: Variant in map:
			var value: Variant = map[id]
			if not id is String or not (value is int or value is float) or int(value) < 0:
				return false
			if key == "pressure":
				pressure[StringName(id)] = int(value)
			else:
				sold[id] = int(value)
	_drop_unknown()
	return reader.is_valid and turn >= 0 and cycle >= 0


# A save naming a region the data no longer has (or pressure past the cap,
# or the home as ours) keeps the rest: those entries go, with one warning,
# and a push on an unknown region is declared again.
func _drop_unknown() -> void:
	var dropped: PackedStringArray = []
	for id: StringName in cleared.duplicate():
		if data.get_region(id) == null or id == data.home_region or cleared.count(id) > 1:
			cleared.erase(id)
			dropped.append(String(id))
	for id: StringName in pressure.keys():
		if data.get_region(id) == null:
			pressure.erase(id)
			dropped.append(String(id))
		else:
			pressure[id] = mini(int(pressure[id]), data.max_pressure)
	if threat != &"" and data.get_region(threat) == null:
		dropped.append(String(threat))
		_declare(pick_threat())
	if not dropped.is_empty():
		push_warning("TacticsWorld: the save names unknown regions %s; left out" % ", ".join(dropped))


## home, ours, open (reachable, the enemy's) or locked (not reachable yet).
func get_state(id: StringName) -> StringName:
	if id == data.home_region:
		return STATE_HOME
	if cleared.has(id):
		return STATE_OURS
	return STATE_OPEN if _touches_ours(id) else STATE_LOCKED


func is_open(id: StringName) -> bool:
	return get_state(id) == STATE_OPEN


## Whether the player can fight in this region now: an open region, or one
## of ours the enemy declared it will take.
func can_fight(id: StringName) -> bool:
	var state := get_state(id)
	return state == STATE_OPEN or (state == STATE_OURS and get_threat() == id)


## The market of a region we hold (or the home), else false.
func can_shop(id: StringName) -> bool:
	var region := data.get_region(id)
	var state := get_state(id)
	return region != null and region.has_market() and (state == STATE_OURS or state == STATE_HOME)


func get_pressure(id: StringName) -> int:
	return int(pressure.get(id, 0))


## Enemy hp and attack in a region, as a percent of the scenario's.
func get_enemy_power_pct(id: StringName) -> int:
	return 100 + data.pressure_step_pct * get_pressure(id)


## The region the enemy presses next (picked on first ask).
func get_threat() -> StringName:
	if not _has_threat:
		_declare(pick_threat())
	return threat


## threat.harden (an open region gets harder) or threat.take (a region of
## ours falls back to the enemy); empty without a threat.
func get_threat_kind() -> StringName:
	var id := get_threat()
	if id == &"":
		return &""
	return THREAT_TAKE if get_state(id) == STATE_OURS else THREAT_HARDEN


## Regions the enemy may press: open ones, and ours with a market that
## touch an open one. In the world's region order.
func get_threat_candidates() -> Array[StringName]:
	var candidates: Array[StringName] = []
	for region: TacticsRegionData in data.regions:
		var state := get_state(region.id)
		if state == STATE_OPEN or (state == STATE_OURS and region.has_market() and _touches_open(region.id)):
			candidates.append(region.id)
	return candidates


## The enemy's next push for this world turn, from the roster seed.
func pick_threat() -> StringName:
	var candidates := get_threat_candidates()
	if candidates.is_empty():
		return &""
	return candidates[absi(hash("%d:world:%d:%d" % [seed_value, cycle, turn])) % candidates.size()]


## Every region but the home is ours.
func is_complete() -> bool:
	for region: TacticsRegionData in data.regions:
		if not region.is_home() and not cleared.has(region.id):
			return false
	return true


## One region fought: a win makes it ours, a lost defence gives it up, and
## the declared push lands if it was elsewhere. Moves the turn on, empties
## the markets' sales and declares the next push. Returns {region, won,
## taken (bool), lost ([ids]), hardened (id or empty), pressure (its new
## level), is_complete, threat (the next)}.
func finish_region(id: StringName, is_won: bool) -> Dictionary:
	var declared := get_threat()
	var change := {"region": id, "won": is_won, "taken": false, "lost": [], "hardened": &"", "pressure": 0}
	if is_won and not cleared.has(id):
		cleared.append(id)
		change["taken"] = true
	if is_won:
		pressure.erase(id)
	elif cleared.has(id):
		_lose(id, change)
	if declared != &"" and declared != id:
		if cleared.has(declared):
			_lose(declared, change)
		else:
			pressure[declared] = mini(get_pressure(declared) + 1, data.max_pressure)
			change["hardened"] = declared
			change["pressure"] = pressure[declared]
	turn += 1
	sold.clear()
	_declare(pick_threat())
	change["is_complete"] = is_complete()
	change["threat"] = threat
	return change


## After every region is ours: the next campaign, every region the enemy's
## again with cycle_pressure more levels of pressure. The roster stays.
func start_new_cycle() -> void:
	cycle += 1
	cleared.clear()
	sold.clear()
	pressure.clear()
	var level := mini(cycle * data.cycle_pressure, data.max_pressure)
	for region: TacticsRegionData in data.regions:
		if not region.is_home() and level > 0:
			pressure[region.id] = level
	_declare(pick_threat())


func get_sold(region_id: StringName, offer_index: int) -> int:
	return int(sold.get("%s/%d" % [region_id, offer_index], 0))


func note_sold(region_id: StringName, offer_index: int) -> void:
	var key := "%s/%d" % [region_id, offer_index]
	sold[key] = int(sold.get(key, 0)) + 1


## Region ids next to `id`, both ways, in the world's region order.
func get_neighbours(id: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	var region := data.get_region(id)
	for other: TacticsRegionData in data.regions:
		if other.id != id and (other.neighbours.has(id) or (region != null and region.neighbours.has(other.id))):
			found.append(other.id)
	return found


# A new push: not heard yet.
func _declare(id: StringName) -> void:
	threat = id
	_has_threat = true
	is_threat_heard = false


func _lose(id: StringName, change: Dictionary) -> void:
	cleared.erase(id)
	pressure[id] = maxi(get_pressure(id), 1)
	(change["lost"] as Array).append(id)


func _touches_ours(id: StringName) -> bool:
	for neighbour: StringName in get_neighbours(id):
		if neighbour == data.home_region or cleared.has(neighbour):
			return true
	return false


func _touches_open(id: StringName) -> bool:
	for neighbour: StringName in get_neighbours(id):
		if get_state(neighbour) == STATE_OPEN:
			return true
	return false
