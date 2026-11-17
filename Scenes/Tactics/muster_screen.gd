class_name MusterScreen
extends Control
## "Điểm binh", before a tactics battle: the objective, the weather, the
## time of day and our scouts (Docs/systems/tactics_vision.md), a legend of
## the map's terrains, our leaders with their squads (scouts marked with an
## eye) and the enemy's leaders.
## Tapping a soldier and then another leader moves it there when that
## leader has room (capacities come from a TacticsBattle loaded with the
## scenario, so the rules stay in C++). With a TacticsCampaign every
## soldier is a roster person (face, marks), soldiers named for their marks
## lead squads of their own, a returning traitor stands with the enemy,
## and "Sổ quân" opens the roster. "Xuất quân" hands the squads on.
## [codeblock]
## var muster := MusterScreen.new()
## muster.scenario = scenario
## muster.battle_requested.connect(func(squads: Array) -> void: ...)
## [/codeblock]

## `squads`: one Array of TacticsTroopData per leader of side 0, in order.
signal battle_requested(squads: Array)
signal back_requested()

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"
const CHIP_PX := Vector2(100, 90)
const SWATCH_PX: float = 44.0
## How far a press on a leader card may slide and still be a tap.
const TAP_SLOP_PX: float = 24.0

var scenario: TacticsScenarioData
var catalog: TacticsCatalog
## The roster around this muster; it sets the scenario and squads.
var campaign: TacticsCampaign

var _text: TacticsText
var _squads: Array[Array] = []
## Person ids, in the same places as `_squads` (-1 without a campaign).
var _people: Array[Array] = []
var _capacities: Array[int] = []
var _picked := Vector2i(-1, -1)
var _press_position := Vector2.ZERO
var _forces: VBoxContainer
var _hint: Label
## The scenario as a loaded battle shows it: objective, sites and units.
var _objective: Dictionary = {}
var _sites: Array = []
var _units: Array = []
var _supplies_label: Label
var _reserve_button: PressButton


func _ready() -> void:
	theme = GameTheme.create()
	if catalog == null:
		catalog = load(CATALOG_PATH) as TacticsCatalog
	_text = TacticsText.new(catalog)
	if campaign != null:
		scenario = campaign.scenario
		campaign.fill_text(_text)
	_read_capacities()
	for slot: int in scenario.leaders_a.size():
		var squad: Array = []
		var ids: Array = []
		if campaign != null:
			squad.assign(campaign.squads[slot])
			ids.assign(campaign.people[slot])
		else:
			squad.assign(scenario.get_squad(0, slot))
			ids.resize(squad.size())
			ids.fill(-1)
		_squads.append(squad)
		_people.append(ids)
	_build()
	_refresh()


## The soldiers the leader at `leader_slot` (in the scenario's order) has now.
func get_squad(leader_slot: int) -> Array:
	return _squads[leader_slot]


## Person ids per leader, in the order of the squads (for the campaign).
func get_people() -> Array:
	var people: Array = []
	for ids: Array in _people:
		var typed: Array[int] = []
		typed.assign(ids)
		people.append(typed)
	return people


func get_capacity(leader_slot: int) -> int:
	return _capacities[leader_slot]


## Picks the soldier at `soldier_slot` of that leader to move; picking it
## again puts it back.
func select_soldier(leader_slot: int, soldier_slot: int) -> void:
	var slot := Vector2i(leader_slot, soldier_slot)
	_picked = Vector2i(-1, -1) if _picked == slot else slot
	if _picked.x >= 0:
		var troop: TacticsTroopData = _squads[leader_slot][soldier_slot]
		_hint.text = tr("MUSTER_PICKED_FORMAT") % tr(troop.name_key)
	else:
		_hint.text = tr("MUSTER_HINT")
	_refresh()


func get_picked() -> Vector2i:
	return _picked


## Moves the picked soldier to that leader; false (and a hint) when the
## leader is full or nothing is picked.
func move_selected_to(leader_slot: int) -> bool:
	if _picked.x < 0 or _picked.x == leader_slot:
		return false
	if _squads[leader_slot].size() >= _capacities[leader_slot]:
		Sound.play(&"block")
		_hint.text = tr("MUSTER_FULL_FORMAT") % tr(scenario.leaders_a[leader_slot].name_key)
		return false
	var troop: TacticsTroopData = _squads[_picked.x][_picked.y]
	var person: int = _people[_picked.x][_picked.y]
	_squads[_picked.x].remove_at(_picked.y)
	_people[_picked.x].remove_at(_picked.y)
	_squads[leader_slot].append(troop)
	_people[leader_slot].append(person)
	_picked = Vector2i(-1, -1)
	Sound.play(&"merge")
	_hint.text = tr("MUSTER_HINT")
	_refresh()
	return true


func start_battle() -> void:
	var squads: Array = []
	for squad: Array in _squads:
		var typed: Array[TacticsTroopData] = []
		typed.assign(squad)
		squads.append(typed)
	battle_requested.emit(squads)


# The squad capacity of each of our leaders, from the rules in C++.
func _read_capacities() -> void:
	var scratch := TacticsBattle.new()
	if not scratch.load_scenario(scenario):
		push_error("MusterScreen: the scenario %s did not load" % scenario.id)
	_units = scratch.get_units()
	for state: Dictionary in _units:
		if state["role"] == &"leader" and state["side"] == 0:
			_capacities.append(int(state["capacity"]))
	_objective = scratch.get_objective_state()
	_sites = scratch.get_sites(0)
	scratch.free()


func _build() -> void:
	var background := Backdrop.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 16
	page.offset_right = -16
	page.offset_top = 16
	page.offset_bottom = -16
	page.add_theme_constant_override(&"separation", 8)
	add_child(page)
	var title := _label("MUSTER_TITLE", 44, Palette.GOLD)
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 8)
	scroll.add_child(body)
	body.add_child(_objective_panel())
	body.add_child(_terrain_panel())
	_forces = VBoxContainer.new()
	_forces.add_theme_constant_override(&"separation", 10)
	body.add_child(_forces)
	# Under the forces, so the squads stay on the first screen.
	body.add_child(_environment_panel())
	body.add_child(_enemy_panel())
	_hint = _label("MUSTER_HINT", 22, Palette.CREAM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	page.add_child(buttons)
	buttons.add_child(_button("BUTTON_BACK", back_requested.emit, false))
	if campaign != null:
		buttons.add_child(_button("BUTTON_ROSTER", open_roster, false))
	buttons.add_child(_button("BUTTON_START_BATTLE", start_battle, true))


## Opens the roster (Sổ quân) over the muster.
func open_roster() -> TacticsRosterView:
	var view := TacticsRosterView.new()
	view.campaign = campaign
	add_child(view)
	return view


func _objective_panel() -> Control:
	var box := _panel()
	box.name = "ObjectivePanel"
	var rows := VBoxContainer.new()
	box.add_child(rows)
	rows.add_child(_label(tr(scenario.name_key), 34, Palette.GOLD))
	var kind: StringName = _objective.get("kind", &"")
	if kind != &"" and kind != &"objective_kind.cell":
		rows.add_child(_label(tr(TacticsText.id_to_key(kind)), 26, Palette.JADE_LIGHT))
	rows.add_child(_wrapped(objective_text(), Palette.TEXT))
	var goals: PackedStringArray = []
	for goal: Dictionary in _objective.get("goals", []):
		goals.append(tr("MUSTER_GOAL_ITEM_FORMAT") % [_goal_name(goal), goal["supplies"]])
	if not goals.is_empty():
		rows.add_child(_wrapped(tr("MUSTER_GOALS_FORMAT") % "; ".join(goals), Palette.GOLD))
	var kinds: PackedStringArray = []
	for site: Dictionary in _sites:
		var data := catalog.get_site(site["id"])
		var site_name := tr(data.name_key) if data != null else String(site["id"])
		if not kinds.has(site_name):
			kinds.append(site_name)
	if not kinds.is_empty():
		rows.add_child(_wrapped(tr("MUSTER_SITES_FORMAT") % ", ".join(kinds), Palette.TEXT_DIM))
	if campaign != null:
		rows.add_child(_supplies_row())
	return box


## The objective in full: what wins, what loses and by when.
func objective_text() -> String:
	var max_rounds := scenario.rules.max_rounds
	var site_name := ""
	var site := int(_objective.get("site", -1))
	if site >= 0 and site < _sites.size():
		var data := catalog.get_site(_sites[site]["id"])
		site_name = tr(data.name_key) if data != null else ""
	match _objective.get("kind", &""):
		&"objective_kind.take_pass":
			return tr("OBJECTIVE_DESC_TAKE_PASS_FORMAT") % [site_name, max_rounds]
		&"objective_kind.hold_city":
			var rounds: PackedStringArray = []
			for wave: Dictionary in _objective["waves"]:
				rounds.append(str(wave["round"]))
			return tr("OBJECTIVE_DESC_HOLD_CITY_FORMAT") % [site_name, _objective["rounds"], ", ".join(rounds)]
		&"objective_kind.escort":
			return tr("OBJECTIVE_DESC_ESCORT_FORMAT") % max_rounds
		&"objective_kind.break_siege":
			return tr("OBJECTIVE_DESC_BREAK_SIEGE_FORMAT") % [_objective["count"], _required_leader_name(), max_rounds]
		&"objective_kind.slay_general":
			var general := int(_objective["general"])
			var general_name := _text.unit_name(_units[general]) if general >= 0 else ""
			return tr("OBJECTIVE_DESC_SLAY_GENERAL_FORMAT") % [general_name, _objective["flee_hp_pct"], max_rounds]
	var map := scenario.map
	var cell := map.objective_cell
	var objective_terrain := map.legend_terrains[map.legend_symbols.find(map.rows[cell.y][cell.x])]
	return tr("MUSTER_OBJECTIVE_FORMAT") % [tr(objective_terrain.name_key), max_rounds]


# The leader that must break out (by scenario order among our leaders).
func _required_leader_name() -> String:
	var wanted := int(_objective.get("required_leader", -1))
	if wanted >= 0 and wanted < scenario.leaders_a.size():
		return tr(scenario.leaders_a[wanted].name_key)
	return ""


func _goal_name(goal: Dictionary) -> String:
	if goal["kind"] == &"goal.by_round":
		return tr("GOAL_BY_ROUND_FORMAT") % goal["value"]
	return tr("GOAL_" + String(goal["kind"]).trim_prefix("goal.").to_upper())


# The supplies in store and the reserve soldier they buy.
func _supplies_row() -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	_supplies_label = _label("", 24, Palette.GOLD)
	row.add_child(_supplies_label)
	if scenario.reserve_troop != null:
		_reserve_button = PressButton.new()
		_reserve_button.name = "ReserveButton"
		_reserve_button.focus_mode = Control.FOCUS_NONE
		_reserve_button.custom_minimum_size = Vector2(0, 96)
		_reserve_button.text = tr("MUSTER_RESERVE_FORMAT") % [tr(scenario.reserve_troop.name_key), scenario.reserve_cost]
		_reserve_button.pressed.connect(hire_reserve)
		row.add_child(_reserve_button)
	return row


## Spends supplies on the scenario's reserve soldier, who joins the first
## leader with room; false (and a hint) without room or supplies.
func hire_reserve() -> bool:
	if campaign == null or scenario.reserve_troop == null:
		return false
	var slot := -1
	for index: int in _squads.size():
		if _squads[index].size() < _capacities[index]:
			slot = index
			break
	if slot < 0:
		Sound.play(&"block")
		_hint.text = tr("MUSTER_RESERVE_NO_ROOM")
		return false
	if not campaign.can_hire_reserve():
		Sound.play(&"block")
		_hint.text = tr("MUSTER_RESERVE_NO_SUPPLIES")
		return false
	var person := campaign.hire_reserve(scenario.leaders_a[slot].id)
	_squads[slot].append(scenario.reserve_troop)
	_people[slot].append(person)
	campaign.fill_text(_text)
	Sound.play(&"merge")
	_hint.text = tr("MUSTER_RESERVE_HIRED_FORMAT") % [tr(scenario.reserve_troop.name_key), tr(scenario.leaders_a[slot].name_key)]
	_refresh()
	return true


# The weather (and the one it turns into), the time of day, fog of war and
# which of our troops scout.
func _environment_panel() -> Control:
	var box := _panel()
	box.name = "EnvironmentPanel"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	box.add_child(rows)
	rows.add_child(_label("MUSTER_ENVIRONMENT", 28, Palette.GOLD))
	var weather := scenario.weather if scenario.weather != null else catalog.get_weather(&"weather.clear")
	if weather != null:
		rows.add_child(_icon_row(weather.icon, TacticsText.describe_environment(weather)))
	if scenario.weather_change_round > 0 and scenario.weather_after != null:
		rows.add_child(_wrapped(tr("MUSTER_WEATHER_CHANGE_FORMAT") % [scenario.weather_change_round, tr(scenario.weather_after.name_key)], Palette.TEXT))
	var daytimes := scenario.daytimes
	var first: TacticsDaytimeData = daytimes[clampi(scenario.daytime_start_index, 0, daytimes.size() - 1)] if not daytimes.is_empty() else catalog.get_daytime(&"daytime.day")
	if first != null:
		rows.add_child(_icon_row(first.icon, TacticsText.describe_environment(first)))
	if daytimes.size() > 1:
		rows.add_child(_wrapped(tr("MUSTER_DAYTIME_CYCLE_FORMAT") % [tr(first.name_key), scenario.daytime_step_rounds], Palette.TEXT))
	if scenario.fog_of_war:
		rows.add_child(_wrapped(tr("MUSTER_FOG"), Palette.TEXT))
		var scouts := _scout_names()
		rows.add_child(_wrapped(tr("MUSTER_SCOUTS_FORMAT") % ", ".join(scouts) if not scouts.is_empty() else tr("MUSTER_NO_SCOUTS"), Palette.JADE_LIGHT))
	return box


func _icon_row(icon: Texture2D, line: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var image := TextureRect.new()
	image.texture = icon
	image.custom_minimum_size = Vector2(48, 48)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(image)
	var label := _wrapped(line, Palette.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _wrapped(line: String, color: Color) -> Label:
	var label := _label(line, 22, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# Our leaders and troops with the scout keyword, each name once with a count.
func _scout_names() -> PackedStringArray:
	var counts: Dictionary[String, int] = {}
	for slot: int in scenario.leaders_a.size():
		var units: Array = [scenario.leaders_a[slot]]
		units.append_array(_squads[slot])
		for unit: TacticsUnitData in units:
			if _is_scout(unit):
				var name := tr(unit.name_key)
				counts[name] = counts.get(name, 0) + 1
	var names: PackedStringArray = []
	for name: String in counts:
		names.append(name if counts[name] == 1 else "%s ×%d" % [name, counts[name]])
	return names


func _is_scout(unit: TacticsUnitData) -> bool:
	return _keyword_ids(unit).has(&"keyword.scout")


# One swatch per terrain the map uses, drawn like the map draws it.
func _terrain_panel() -> Control:
	var box := _panel()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	box.add_child(rows)
	rows.add_child(_label("MUSTER_TERRAIN", 28, Palette.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 6)
	rows.add_child(grid)
	var map := scenario.map
	for index: int in map.legend_terrains.size():
		if not "".join(map.rows).contains(map.legend_symbols[index]):
			continue
		var terrain := map.legend_terrains[index]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override(&"separation", 8)
		grid.add_child(row)
		var swatch := _Swatch.new()
		swatch.terrain_id = terrain.id
		swatch.custom_minimum_size = Vector2(SWATCH_PX, SWATCH_PX)
		row.add_child(swatch)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override(&"separation", -4)
		row.add_child(texts)
		texts.add_child(_label(tr(terrain.name_key), 21, Palette.CREAM))
		var effects := _label(_text.terrain_effects(terrain.id), GameTheme.SMALL_FONT_SIZE, Palette.TEXT_DIM)
		effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(effects)
	return box


func _enemy_panel() -> Control:
	var box := _panel()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	var names: PackedStringArray = []
	for slot: int in scenario.leaders_b.size():
		if campaign == null or campaign.enemy_people[slot] < 0:
			var leader: TacticsLeaderData = scenario.leaders_b[slot]
			names.append(tr("MUSTER_ENEMY_LEADER_FORMAT") % [tr(leader.name_key), leader.squad.size()])
	var label := _label(tr("MUSTER_ENEMY_FORMAT") % ", ".join(names), 22, TacticsPainter.ENEMY_FILL.lightened(0.4))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(label)
	if campaign == null:
		return box
	for slot: int in scenario.leaders_b.size():
		if campaign.enemy_people[slot] >= 0:
			rows.add_child(_returning_row(campaign.get_person(campaign.enemy_people[slot]), scenario.leaders_b[slot]))
	return box


# A deserter or traitor of ours back as an enemy leader.
func _returning_row(person: Dictionary, leader: TacticsLeaderData) -> Control:
	var row := HBoxContainer.new()
	row.name = "Returning%d" % person["id"]
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	var face := TacticsFace.FaceView.new()
	face.look = person["look"]
	face.ring = Palette.VERMILION
	face.custom_minimum_size = Vector2(56, 56)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(face)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override(&"separation", -2)
	row.add_child(texts)
	var key := "MUSTER_RETURNING_TRAITOR_FORMAT" if person["status"] == "traitor" else "MUSTER_RETURNING_DESERTER_FORMAT"
	texts.add_child(_label(tr(key) % tr(leader.name_key), 23, Palette.VERMILION.lightened(0.3)))
	var detail := _label(tr("MUSTER_RETURNING_DETAIL_FORMAT") % [leader.squad.size(), _text.unit_name(person["troop"]), (person["marks"] as Array).size()], 19, Palette.TEXT_DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(detail)
	return row


# Rebuilds the leader cards (a menu screen; nothing here runs per frame).
func _refresh() -> void:
	for child: Node in _forces.get_children():
		_forces.remove_child(child)
		child.queue_free()
	_forces.add_child(_label("MUSTER_FORCES", 28, Palette.GOLD))
	for slot: int in scenario.leaders_a.size():
		_forces.add_child(_leader_card(slot))
	if _supplies_label != null:
		_supplies_label.text = tr("MUSTER_SUPPLIES_FORMAT") % campaign.roster.supplies
	if _reserve_button != null:
		_reserve_button.disabled = not campaign.can_hire_reserve()


func _leader_card(slot: int) -> Control:
	var leader: TacticsLeaderData = scenario.leaders_a[slot]
	var box := _panel()
	box.name = "LeaderCard%d" % slot
	# PASS: a drag that starts on a card still scrolls the page; only a
	# press and release close together count as a tap on the leader.
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.gui_input.connect(_on_card_input.bind(slot))
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 2)
	box.add_child(rows)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 10)
	rows.add_child(head)
	var person := _leader_person(slot)
	var token := _Token.new()
	token.is_leader = true
	token.glyph = TacticsPainter.glyph_for(leader.base_class.id, _keyword_ids(leader))
	token.look = person.get("look", -1)
	token.is_scout = _is_scout(leader) and scenario.fog_of_war
	token.custom_minimum_size = Vector2(52, 52)
	head.add_child(token)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override(&"separation", -2)
	head.add_child(texts)
	texts.add_child(_label(tr(leader.name_key), 27, Palette.GOLD if not person.is_empty() else Palette.CREAM))
	if not person.is_empty():
		texts.add_child(_label(tr("MUSTER_NAMED_LEADER_FORMAT") % _text.unit_name(person["troop"]), 19, Palette.JADE_LIGHT))
	var skill := leader.skill
	if skill != null:
		texts.add_child(_label(tr("MUSTER_SKILL_FORMAT") % [tr(skill.name_key), _text.charge_name(skill.charge), skill.charge_threshold], 20, Palette.TEXT_DIM))
	var is_full := _squads[slot].size() >= _capacities[slot]
	head.add_child(_label(tr("MUSTER_CAPACITY_FORMAT") % [_squads[slot].size(), _capacities[slot]], 24, Palette.GOLD if is_full else Palette.TEXT))
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override(&"separation", 8)
	rows.add_child(chips)
	for soldier_slot: int in _squads[slot].size():
		chips.add_child(_chip(slot, soldier_slot))
	return box


func _on_card_input(event: InputEvent, slot: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_position = button.global_position
	elif button.global_position.distance_to(_press_position) <= TAP_SLOP_PX:
		move_selected_to(slot)


func _chip(leader_slot: int, soldier_slot: int) -> PressButton:
	var troop: TacticsTroopData = _squads[leader_slot][soldier_slot]
	var person := campaign.get_person(_people[leader_slot][soldier_slot]) if campaign != null else {}
	var chip := PressButton.new()
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.custom_minimum_size = CHIP_PX
	if _picked == Vector2i(leader_slot, soldier_slot):
		chip.theme_type_variation = &"PrimaryButton"
	var face := _Token.new()
	face.glyph = TacticsPainter.glyph_for(troop.base_class.id, _keyword_ids(troop))
	# The chip is narrow: the troop's short name ("Giáo", "Cung").
	face.caption = tr(troop.name_key + "_SHORT")
	face.look = person.get("look", -1)
	face.marks = (person["marks"] as Array).size() if not person.is_empty() else 0
	face.is_scout = _is_scout(troop) and scenario.fog_of_war
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(face)
	chip.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		select_soldier(leader_slot, soldier_slot))
	return chip


func _leader_person(slot: int) -> Dictionary:
	if campaign == null or slot >= campaign.leader_people.size() or campaign.leader_people[slot] < 0:
		return {}
	return campaign.get_person(campaign.leader_people[slot])


func _keyword_ids(unit: TacticsUnitData) -> Array:
	var ids: Array = []
	for keyword: TacticsKeywordData in unit.keywords:
		ids.append(keyword.id)
	return ids


func _panel() -> PanelContainer:
	var box := PanelContainer.new()
	var style := GameTheme.make_panel(Palette.PANEL, 16, 4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	box.add_theme_stylebox_override(&"panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


# No text is drawn under GameTheme.SMALL_FONT_SIZE.
func _label(text: String, font_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", maxi(font_px, GameTheme.SMALL_FONT_SIZE))
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text_key: String, action: Callable, is_primary: bool) -> PressButton:
	var button := PressButton.new()
	button.text = text_key
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 96)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_primary:
		button.theme_type_variation = &"PrimaryButton"
	button.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		action.call())
	return button


## A terrain swatch for the legend.
class _Swatch extends Control:
	var terrain_id: StringName

	func _draw() -> void:
		TacticsPainter.draw_terrain(self, terrain_id, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2.ZERO, size), Palette.INK, false, 2.0)


## A token as the map draws it (or a roster person's face), with an
## optional caption under it and the person's marks over it.
class _Token extends Control:
	const CAPTION_PAD_PX: float = 3.0

	var glyph: StringName = &"class.sword"
	var is_leader: bool = false
	var caption: String = ""
	## A face seed; -1 draws the token.
	var look: int = -1
	var marks: int = 0
	## An eye at the top right: it scouts.
	var is_scout: bool = false

	func _draw() -> void:
		var shape := get_shape()
		var c: Vector2 = shape["center"]
		var r: float = shape["radius"]
		if look >= 0:
			TacticsFace.draw_face(self, c, r, look, Palette.GOLD if is_leader else TacticsPainter.PLAYER_FILL)
			if not is_leader:
				TacticsPainter.draw_glyph_badge(self, c + Vector2(r * 0.8, r * 0.7), 9.0, glyph)
		else:
			TacticsPainter.draw_token(self, c, 0, is_leader, glyph, false)
		for index: int in mini(marks, 3):
			var p := Vector2(8.0, 9.0 + index * 11.0)
			var diamond := PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)])
			draw_colored_polygon(diamond, Palette.GOLD)
			diamond.append(diamond[0])
			draw_polyline(diamond, Palette.INK, 1.5)
		if is_scout:
			TacticsPainter.draw_scout_badge(self, c + Vector2(r * 0.78, -r * 0.7), 10.0)
		if caption.is_empty():
			return
		var font := get_theme_default_font()
		var font_px := GameTheme.SMALL_FONT_SIZE
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		draw_string(font, Vector2((size.x - width) / 2.0, shape["baseline"]), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Palette.CREAM)

	## Where the face (center, radius) and the caption (baseline, top: its
	## letters' highest point) are drawn, in layout px.
	func get_shape() -> Dictionary:
		var font := get_theme_default_font()
		var font_px := GameTheme.SMALL_FONT_SIZE
		if caption.is_empty():
			return {"center": size / 2.0, "radius": minf(size.y, size.x) / 2.0, "baseline": size.y, "top": size.y}
		# The face fills what the caption's line leaves above it.
		var baseline := size.y - CAPTION_PAD_PX - font.get_descent(font_px)
		var top := baseline - font.get_ascent(font_px)
		var r := minf((top - 2.0 * CAPTION_PAD_PX) / 2.0, size.x / 2.0)
		return {"center": Vector2(size.x / 2.0, CAPTION_PAD_PX + r), "radius": r, "baseline": baseline, "top": top}
