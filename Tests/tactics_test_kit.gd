extends RefCounted
## Shared set-up for the tactics tests (tactics_test.gd, tactics_squad_test.gd):
## the tactics catalog, maps written as rows of terrain symbols, battles that
## are freed at the end, stripped copies of the sample leaders and event
## filters. Cells are (col, row) with row 0 at the top.

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
## Map symbols, in the order of TERRAIN_IDS.
const SYMBOLS: String = ".fhrdbtv"
const TERRAIN_IDS: Array[StringName] = [
	&"terrain.plain", &"terrain.forest", &"terrain.hill", &"terrain.river",
	&"terrain.ford", &"terrain.bridge", &"terrain.fort", &"terrain.village",
]
const EMPTY_ROW: String = "............"

var catalog: TacticsCatalog
var _battles: Array[TacticsBattle] = []


func load_catalog() -> bool:
	if not ClassDB.class_exists("TacticsBattle"):
		push_error("TacticsBattle is missing: build the GDExtension (scons) before importing")
		return false
	catalog = load(CATALOG_PATH) as TacticsCatalog
	if catalog == null:
		push_error("Tactics catalog did not load from %s" % CATALOG_PATH)
		return false
	var problems := catalog.validate()
	if not problems.is_empty():
		push_error("Tactics catalog is invalid: %s" % ", ".join(problems))
		return false
	return true


func free_battles() -> void:
	for battle: TacticsBattle in _battles:
		if is_instance_valid(battle):
			battle.free()
	_battles.clear()


## A map from rows of symbols (see SYMBOLS); width is the first row's length.
func make_map(rows: PackedStringArray, objective: Vector2i = Vector2i(-1, -1)) -> TacticsMapData:
	var map := TacticsMapData.new()
	map.id = &"map.test"
	map.name_key = "MAP_TEST"
	map.width = rows[0].length()
	map.height = rows.size()
	map.rows = rows
	map.legend_symbols = SYMBOLS
	var terrains: Array[TacticsTerrainData] = []
	for id: StringName in TERRAIN_IDS:
		terrains.append(catalog.get_terrain(id))
	map.legend_terrains = terrains
	map.objective_cell = objective
	return map


## An empty plain map of 12 x height.
func plain_rows(height: int = 12) -> PackedStringArray:
	var rows := PackedStringArray()
	for row: int in height:
		rows.append(EMPTY_ROW)
	return rows


## A battle on the given rows; side B is played by hand unless `ai_b`.
func new_battle(rows: PackedStringArray, ai_b: bool = false, rules: TacticsRulesData = null, objective: Vector2i = Vector2i(-1, -1)) -> TacticsBattle:
	var battle := TacticsBattle.new()
	_battles.append(battle)
	battle.set_side_ai(TacticsBattle.SIDE_B, ai_b)
	var ok := battle.setup(rules if rules != null else catalog.rules, make_map(rows, objective))
	assert(ok, "Tactics test: setup failed")
	return battle


## A copy of a sample leader with no passives and no squad unless given;
## `changes` sets other fields (move_points, keywords, ...).
func leader(id: StringName, passives: Array[TacticsPassiveData] = [], changes: Dictionary = {}) -> TacticsLeaderData:
	var data := catalog.get_leader(id).duplicate() as TacticsLeaderData
	data.passives = passives
	var squad: Array[TacticsTroopData] = []
	data.squad = squad
	for key: String in changes:
		data.set(key, changes[key])
	return data


## A copy of a sample troop with `changes` applied.
func troop(id: StringName, changes: Dictionary = {}) -> TacticsTroopData:
	var data := catalog.get_troop(id).duplicate() as TacticsTroopData
	for key: String in changes:
		data.set(key, changes[key])
	return data


func keywords(ids: Array[StringName]) -> Array[TacticsKeywordData]:
	var list: Array[TacticsKeywordData] = []
	for id: StringName in ids:
		list.append(catalog.get_keyword(id))
	return list


func add(battle: TacticsBattle, side: int, data: TacticsLeaderData, cell: Vector2i, squad: Array = []) -> int:
	var index := battle.add_leader_with_squad(side, data, cell, squad)
	assert(index >= 0, "Tactics test: could not add %s at %s" % [data.id, cell])
	return index


static func cell_of(battle: TacticsBattle, unit: int) -> Vector2i:
	return battle.get_unit_state(unit)["cell"]


static func hp_of(battle: TacticsBattle, unit: int) -> int:
	return battle.get_unit_state(unit)["hp"]


static func of_type(events: Array, type: StringName) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


## Logs and returns false when `actual` differs from `expected`.
static func expect(what: String, actual: Variant, expected: Variant) -> bool:
	if actual == expected:
		return true
	push_error("Tactics test: %s: got %s, expected %s" % [what, actual, expected])
	return false


static func expect_true(what: String, value: bool) -> bool:
	if value:
		return true
	push_error("Tactics test: %s" % what)
	return false
