class_name TacticsWorldScreen
extends Control
## "Thế trận", the Chiến Dịch world map: the regions and who holds them,
## the enemy's declared next push and what ignoring it costs, the
## supplies. A tap on a region opens its card (TacticsRegionCard): fight it
## by hand ("Thủ công": the muster, then the tactics battle; Main does
## that) or "Auto" (resolved here with the auto battle, its result shown
## over the map), or visit its market. When every region is ours, "Chiến
## dịch mới" starts the next campaign. An idle screen draws nothing: the
## map redraws only when something changes. See
## Docs/systems/tactics_world.md.
## [codeblock]
## var screen := TacticsWorldScreen.new()
## screen.roster = TacticsRoster.load_roster()
## screen.manual_requested.connect(func(id: StringName, items: Array) -> void: ...)
## [/codeblock]

## Thủ công: Main opens the muster of that region with those items.
signal manual_requested(region_id: StringName, items: Array)
signal back_requested()

const CATALOG_PATH: String = "res://Data/Tactics/tactics_catalog.tres"

var roster: TacticsRoster
var catalog: TacticsCatalog
## A region whose change just landed (the region fought): it rings once.
var changed_region: StringName = &""
## Tests and stills: no slides, no saves.
var is_instant: bool = false

var _map: TacticsWorldMap
var _supplies: Label
var _held: Label
var _threat_title: Label
var _threat_cost: Label
var _intent_panel: PanelContainer
var _hint: Label
var _new_button: PressButton
var _card: TacticsRegionCard
var _overlay: Control
var _is_busy: bool = false


func _ready() -> void:
	theme = GameTheme.create()
	if catalog == null:
		catalog = load(CATALOG_PATH) as TacticsCatalog
	for problem: String in roster.world.data.validate():
		push_error(problem)
	_build()
	refresh()
	if changed_region != &"":
		_map.pulse(changed_region)
	if roster.world.get_threat() != &"" and not is_instant:
		Sound.play(&"war_horn")


func get_map() -> TacticsWorldMap:
	return _map


## The region card open now, or null.
func get_card() -> TacticsRegionCard:
	return _card if is_instance_valid(_card) else null


## The overlay open now (market, Auto result, roster), or null.
func get_overlay() -> Control:
	return _overlay if is_instance_valid(_overlay) else null


func get_threat_text() -> String:
	return "%s %s" % [_threat_title.text, _threat_cost.text]


## Labels, supplies and the map as the world is now.
func refresh() -> void:
	var world := roster.world
	_supplies.text = tr("WORLD_SUPPLIES_FORMAT") % roster.supplies
	var regions := 0
	for region: TacticsRegionData in world.data.regions:
		regions += 0 if region.is_home() else 1
	_held.text = tr("WORLD_HELD_FORMAT") % [world.cleared.size(), regions]
	var lines := TacticsWorldText.threat_lines(world)
	_threat_title.text = lines[0]
	_threat_cost.text = lines[1] if lines.size() > 1 else ""
	_threat_cost.visible = lines.size() > 1
	_new_button.visible = world.is_complete()
	if world.is_complete():
		_threat_title.text = tr("WORLD_COMPLETE")
		_threat_cost.text = tr("WORLD_NEW_CAMPAIGN_HINT")
		_threat_cost.visible = true
	_map.queue_redraw()


## Opens the card of a region (the map's tap).
func open_region(id: StringName) -> TacticsRegionCard:
	if _is_busy or get_overlay() != null:
		return null
	if get_card() != null:
		_card.queue_free()
	_map.selected = id
	_card = TacticsRegionCard.new()
	_card.roster = roster
	_card.region_id = id
	_card.is_instant = is_instant
	_card.closed.connect(_close_card)
	_card.manual_requested.connect(_on_manual)
	_card.auto_requested.connect(resolve_auto)
	_card.market_requested.connect(open_market)
	add_child(_card)
	return _card


## Auto: the region resolved with the auto battle; its result shows over
## the map. Saves the roster (unless instant).
func resolve_auto(id: StringName, items: Array = []) -> TacticsAutoResultView:
	if _is_busy or not roster.world.can_fight(id):
		return null
	_is_busy = true
	_close_card()
	Sound.play(&"battle_drum")
	var region := roster.world.data.get_region(id)
	var campaign := TacticsCampaign.new(roster, catalog, region.scenario, _plan(id, items))
	var summary := campaign.apply_auto(TacticsAutoResolve.resolve(campaign), not is_instant)
	var view := TacticsAutoResultView.new()
	view.campaign = campaign
	view.summary = summary
	view.is_instant = is_instant
	view.continue_requested.connect(func() -> void:
		view.queue_free()
		_overlay = null
		_is_busy = false
		changed_region = id
		refresh()
		_map.pulse(id)
		if roster.world.get_threat() != &"":
			Sound.play(&"war_horn"))
	_show_overlay(view)
	return view


## The market of a region of ours.
func open_market(id: StringName) -> TacticsMarketView:
	if not roster.world.can_shop(id):
		return null
	_close_card()
	var view := TacticsMarketView.new()
	view.campaign = TacticsCampaign.new(roster, catalog, null)
	view.region_id = id
	view.is_instant = is_instant
	view.bought.connect(func(_result: Dictionary) -> void: refresh())
	view.closed.connect(func() -> void:
		_overlay = null
		refresh())
	_show_overlay(view)
	return view


func open_roster() -> TacticsRosterView:
	var view := TacticsRosterView.new()
	view.campaign = TacticsCampaign.new(roster, catalog, null)
	view.closed.connect(func() -> void: _overlay = null)
	_show_overlay(view)
	return view


## After the last region: every region the enemy's again, harder.
func start_new_campaign() -> void:
	if not roster.world.is_complete():
		return
	roster.world.start_new_cycle()
	if not is_instant:
		roster.save()
	Sound.play(&"war_horn")
	refresh()
	_map.pulse(roster.world.data.home_region)


func _plan(id: StringName, items: Array) -> Dictionary:
	return {"region": id, "enemy_power_pct": roster.world.get_enemy_power_pct(id), "items": items}


func _on_manual(id: StringName, items: Array) -> void:
	if _is_busy:
		return
	_is_busy = true
	manual_requested.emit(id, items)


func _close_card() -> void:
	if get_card() != null:
		_card.queue_free()
	_card = null
	_map.selected = &""


func _show_overlay(view: Control) -> void:
	_overlay = view
	add_child(view)


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
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	page.add_child(head)
	var title := TacticsViews.label("WORLD_TITLE", 44, Palette.GOLD)
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var counters := VBoxContainer.new()
	counters.add_theme_constant_override(&"separation", -4)
	head.add_child(counters)
	_supplies = TacticsViews.label("", 28, Palette.GOLD)
	_supplies.name = "Supplies"
	_supplies.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counters.add_child(_supplies)
	_held = TacticsViews.label("", 22, Palette.JADE_LIGHT)
	_held.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counters.add_child(_held)
	_map = TacticsWorldMap.new()
	_map.name = "WorldMap"
	_map.world = roster.world
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.region_tapped.connect(func(id: StringName) -> void: open_region(id))
	page.add_child(_map)
	page.add_child(_legend())
	_intent_panel = TacticsViews.panel(Color(Palette.VERMILION_DARK, 0.55))
	_intent_panel.name = "IntentPanel"
	var intent_rows := VBoxContainer.new()
	intent_rows.add_theme_constant_override(&"separation", 2)
	_intent_panel.add_child(intent_rows)
	_threat_title = TacticsViews.wrapped("", 24, Palette.CREAM)
	intent_rows.add_child(_threat_title)
	_threat_cost = TacticsViews.wrapped("", 22, Palette.GOLD)
	intent_rows.add_child(_threat_cost)
	page.add_child(_intent_panel)
	_hint = TacticsViews.label("WORLD_HINT", 22, Palette.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	page.add_child(buttons)
	buttons.add_child(TacticsViews.button("BUTTON_BACK", back_requested.emit, false))
	buttons.add_child(TacticsViews.button("BUTTON_ROSTER", open_roster, false))
	_new_button = TacticsViews.button("BUTTON_NEW_CAMPAIGN", start_new_campaign, true)
	_new_button.name = "NewCampaignButton"
	buttons.add_child(_new_button)


# Three swatches: ours, the enemy's, out of reach.
func _legend() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	var entries := [
		[TacticsWorld.STATE_OURS, "LEGEND_OURS"], [TacticsWorld.STATE_OPEN, "LEGEND_ENEMY"], [TacticsWorld.STATE_LOCKED, "LEGEND_LOCKED"],
	]
	for entry: Array in entries:
		var swatch := ColorRect.new()
		swatch.color = TacticsWorldMap.STATE_FILLS[entry[0]]
		swatch.custom_minimum_size = Vector2(26, 26)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		row.add_child(TacticsViews.label(entry[1], 22, Palette.TEXT))
	return row
