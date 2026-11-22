class_name TacticsRegionCard
extends Control
## The card a tap on a world-map region opens, from the bottom: who holds
## it, its battle and the enemy's pressure there, whether the enemy
## declared it strikes it next and, when it can be fought, the items to
## use and the two ways in side by side: "Thủ công" (the tactics battle)
## and "Auto" (the auto battle), each with what it costs and pays written
## under it, so the trade-off is read before the tap. A region of ours with
## a market has a button into it. A tap on the shade closes it.
## [codeblock]
## var card := TacticsRegionCard.new()
## card.roster = roster
## card.region_id = &"region.ferry"
## card.manual_requested.connect(func(id: StringName, items: Array) -> void: ...)
## [/codeblock]

signal manual_requested(region_id: StringName, items: Array)
signal auto_requested(region_id: StringName, items: Array)
signal market_requested(region_id: StringName)
signal closed()

const MODE_BUTTON_PX: float = 104.0

var roster: TacticsRoster
var region_id: StringName = &""
## Tests and stills: no slide.
var is_instant: bool = false

var _panel: PanelContainer
var _chosen_items: Array[TacticsItemData] = []
var _item_buttons: Dictionary[StringName, PressButton] = {}
var _is_sent: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(Palette.INK, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(_on_shade_input)
	add_child(shade)
	_panel = TacticsViews.panel(Palette.INDIGO_DARK)
	_panel.name = "Card"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 12.0
	_panel.offset_right = -12.0
	_panel.offset_bottom = -12.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	_panel.add_child(rows)
	_fill(rows)
	if is_instant:
		Sound.play(&"card_flip")
	else:
		TacticsViews.slide_in(self)


## The items chosen for this battle.
func get_chosen_items() -> Array[TacticsItemData]:
	return _chosen_items


## Turns one item on or off for this battle.
func toggle_item(id: StringName) -> void:
	var item := roster.world.data.get_item(id)
	if item == null or roster.get_item_count(id) <= 0:
		return
	if _chosen_items.has(item):
		_chosen_items.erase(item)
	else:
		_chosen_items.append(item)
	var button: PressButton = _item_buttons.get(id)
	if button != null:
		button.theme_type_variation = &"PrimaryButton" if _chosen_items.has(item) else &""
		button.bounce()
	Sound.play(&"ui_tap")


func close() -> void:
	if _is_sent:
		return
	_is_sent = true
	Sound.play(&"ui_tap")
	closed.emit()


func _fill(rows: VBoxContainer) -> void:
	var world := roster.world
	var region := world.data.get_region(region_id)
	var state := world.get_state(region_id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	rows.add_child(head)
	var title := TacticsViews.label(tr(region.name_key), 38, Palette.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(TacticsViews.label("REGION_STATE_" + String(state).to_upper(), 24, TacticsWorldMap.STATE_FILLS[state].lightened(0.35)))
	if region.is_home():
		rows.add_child(TacticsViews.wrapped(tr("REGION_HOME_HINT"), 22, Palette.TEXT))
	else:
		var kind := region.scenario.objective.kind if region.scenario.objective != null else &""
		rows.add_child(TacticsViews.wrapped(tr("REGION_BATTLE_FORMAT") % [tr(region.scenario.name_key), tr(TacticsText.id_to_key(kind))], 22, Palette.CREAM))
		rows.add_child(TacticsViews.wrapped(TacticsWorldText.pressure_line(world, region_id), 22, Palette.VERMILION.lightened(0.35) if world.get_pressure(region_id) > 0 else Palette.TEXT_DIM))
	if world.get_threat() == region_id:
		rows.add_child(TacticsViews.wrapped(tr("REGION_THREATENED"), 24, Palette.VERMILION.lightened(0.3)))
	if state == TacticsWorld.STATE_LOCKED:
		rows.add_child(TacticsViews.wrapped(tr("REGION_LOCKED_HINT"), 22, Palette.TEXT_DIM))
	elif state == TacticsWorld.STATE_OURS:
		rows.add_child(TacticsViews.wrapped(tr("REGION_DEFEND_HINT" if world.get_threat() == region_id else "REGION_HELD_HINT"), 22, Palette.JADE_LIGHT))
	if world.can_fight(region_id):
		_add_items(rows)
		rows.add_child(_mode_row(region))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	rows.add_child(buttons)
	buttons.add_child(TacticsViews.button("BUTTON_CLOSE", close, false))
	if world.can_shop(region_id):
		var market := TacticsViews.button(tr("BUTTON_MARKET_FORMAT") % tr(region.market_name_key), func() -> void: _send(market_requested, []), true)
		market.name = "MarketButton"
		buttons.add_child(market)


func _add_items(rows: VBoxContainer) -> void:
	var held: Array[TacticsItemData] = []
	for item: TacticsItemData in roster.world.data.items:
		if roster.get_item_count(item.id) > 0:
			held.append(item)
	if held.is_empty():
		return
	rows.add_child(TacticsViews.label("REGION_ITEMS", 22, Palette.GOLD))
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	rows.add_child(line)
	for item: TacticsItemData in held:
		var button := PressButton.new()
		button.name = "Item_" + String(item.id).trim_prefix("item.")
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 88)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 22)
		button.text = tr("ITEM_TOGGLE_FORMAT") % [tr(item.name_key), roster.get_item_count(item.id)]
		button.tooltip_text = tr(item.desc_key)
		button.pressed.connect(toggle_item.bind(item.id))
		_item_buttons[item.id] = button
		line.add_child(button)


# Thủ công and Auto side by side, each with its trade-off under it.
func _mode_row(region: TacticsRegionData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var modes := [
		["ManualButton", "BUTTON_MANUAL", tr("MODE_MANUAL_DESC"), manual_requested, true],
		["AutoButton", "BUTTON_AUTO", tr("MODE_AUTO_DESC_FORMAT") % region.auto_supplies, auto_requested, false],
	]
	for mode: Array in modes:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0
		column.add_theme_constant_override(&"separation", 4)
		row.add_child(column)
		var signal_to: Signal = mode[3]
		var button := TacticsViews.button(mode[1], func() -> void: _send(signal_to, _chosen_items.duplicate()), mode[4])
		button.name = mode[0]
		button.custom_minimum_size.y = MODE_BUTTON_PX
		button.add_theme_font_size_override(&"font_size", 32)
		column.add_child(button)
		column.add_child(TacticsViews.wrapped(mode[2], 22, Palette.TEXT))
	return row


# One request per card: a second tap while the screen changes does nothing.
func _send(target: Signal, items: Array) -> void:
	if _is_sent:
		return
	_is_sent = true
	if target == market_requested:
		target.emit(region_id)
	else:
		target.emit(region_id, items)


func _on_shade_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		close()
