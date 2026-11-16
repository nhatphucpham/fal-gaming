class_name TacticsPanel
extends PanelContainer
## The bottom panel of the tactics screen: a content area that shows a
## unit card or an engagement or skill forecast; under it, while one of our
## leaders is selected, the row of five order buttons (the current one
## outlined, its one-line description below); then one row of up to four
## buttons. Every button is at least 88 px tall (44 px on a 360-wide
## phone). No text is smaller than GameTheme.SMALL_FONT_SIZE, and no line
## is cut: a card line wraps, and lines that no longer fit are left out
## from the last one up. It emits what was pressed; the screen decides
## what that means.
## [codeblock]
## panel.show_card("Lạc Hồng", Palette.GOLD, "Máu 900/900", lines, hint)
## panel.set_buttons([{"action": &"end_turn", "text": "BUTTON_END_TURN"}])
## panel.action_pressed.connect(_on_action)
## panel.show_order_row(&"order.follow", text)
## [/codeblock]

signal action_pressed(action: StringName)
signal order_chosen(order: StringName)

const CONTENT_HEIGHT_PX: float = 150.0
const BUTTON_HEIGHT_PX: float = 92.0
const ORDER_BUTTON_HEIGHT_PX: float = 88.0
const DISABLED_ORDER_ALPHA: float = 0.45
## Lines a card shows under its title.
const CARD_LINES: int = 4

var _card: VBoxContainer
var _card_title: Label
var _card_side: Label
var _card_lines: Array[Label] = []
var _forecast: VBoxContainer
var _forecast_columns: Array[VBoxContainer] = []
var _forecast_note: Label
var _orders: VBoxContainer
var _order_buttons: Dictionary[StringName, PressButton] = {}
var _order_note: Label
var _current_order: StringName = &""
var _buttons: HBoxContainer


func _init() -> void:
	add_theme_stylebox_override(&"panel", _panel_style())
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 8)
	add_child(rows)
	var content := Control.new()
	content.custom_minimum_size = Vector2(0, CONTENT_HEIGHT_PX)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	rows.add_child(content)
	_build_card(content)
	_build_forecast(content)
	_build_orders(rows)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 10)
	_buttons.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_PX)
	rows.add_child(_buttons)


## A unit card: title (name) with a side note on its right and up to
## four lines, the last one dim (a hint).
func show_card(title: String, title_color: Color, side_note: String, lines: Array[String]) -> void:
	_show(_card)
	_card_title.text = title
	_card_title.add_theme_color_override(&"font_color", title_color)
	_card_side.text = side_note
	for index: int in _card_lines.size():
		_card_lines[index].text = lines[index] if index < lines.size() else ""
	_fit_card()


## The card lines shown whole now (a line left out for room is not).
func get_shown_card_lines() -> PackedStringArray:
	var shown := PackedStringArray()
	for line: Label in _card_lines:
		if line.visible and line.text != "":
			shown.append(line.text)
	return shown


## The forecast: two columns ([name, line, line] each, the attacker
## left) and a note under them (first strike, modifiers; up to two lines).
func show_forecast(left: Array[String], right: Array[String], note: String) -> void:
	_show(_forecast)
	for side: int in 2:
		var lines: Array[String] = left if side == 0 else right
		var labels := _forecast_columns[side].get_children()
		for index: int in labels.size():
			(labels[index] as Label).text = lines[index] if index < lines.size() else ""
	_forecast_note.text = note


## Shows the row of five order buttons under the card, `current` outlined
## gold and described under the row. Faces redraw only when they change.
func show_order_row(current: StringName, text: TacticsText, enabled: bool = true) -> void:
	_orders.visible = true
	_order_note.text = text.order_description(current)
	for order: StringName in _order_buttons:
		var button := _order_buttons[order]
		var face := button.get_child(0) as _OrderFace
		button.disabled = not enabled
		# A row that cannot change (the leader waited) reads as greyed out;
		# its current order stays clear.
		var alpha := 1.0 if enabled or order == current else DISABLED_ORDER_ALPHA
		if face.modulate.a != alpha:
			face.modulate.a = alpha
		var caption := text.order_name(order)
		if face.caption != caption or face.is_current != (order == current):
			face.caption = caption
			face.is_current = order == current
			face.queue_redraw()
	_current_order = current


func hide_order_row() -> void:
	_orders.visible = false


func is_order_row_shown() -> bool:
	return _orders.visible


## The order outlined in the row now.
func get_current_order() -> StringName:
	return _current_order


## The order row's description line as shown now.
func get_order_note() -> String:
	return _order_note.text


## Replaces the button row: each entry {action, text, enabled = true,
## primary = false}.
func set_buttons(entries: Array[Dictionary]) -> void:
	for child: Node in _buttons.get_children():
		child.queue_free()
		_buttons.remove_child(child)
	for entry: Dictionary in entries:
		var button := PressButton.new()
		button.text = entry["text"]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_PX)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 26)
		button.clip_text = true
		button.disabled = not entry.get("enabled", true)
		if entry.get("primary", false):
			button.theme_type_variation = &"PrimaryButton"
			button.add_theme_font_size_override(&"font_size", 28)
		var action: StringName = entry["action"]
		button.set_meta(&"action", action)
		button.pressed.connect(func() -> void:
			Sound.play(&"ui_tap")
			action_pressed.emit(action))
		_buttons.add_child(button)


## The buttons shown now: [{action, text, enabled, button}], for tests.
func get_buttons() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for button: PressButton in _buttons.get_children():
		entries.append({"action": button.get_meta(&"action"), "text": button.text, "enabled": not button.disabled, "button": button})
	return entries


## The card as shown now: title, side note, then its lines, for tests.
func get_card_texts() -> PackedStringArray:
	var texts := PackedStringArray([_card_title.text, _card_side.text])
	for line: Label in _card_lines:
		texts.append(line.text)
	return texts


## The order buttons by order id, for tests and screenshots.
func get_order_buttons() -> Dictionary[StringName, PressButton]:
	return _order_buttons


func _show(view: Control) -> void:
	for child: Control in [_card, _forecast]:
		child.visible = child == view


func _build_card(content: Control) -> void:
	_card = VBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_theme_constant_override(&"separation", 2)
	content.resized.connect(_fit_card)
	content.add_child(_card)
	var head := HBoxContainer.new()
	_card.add_child(head)
	_card_title = _label(28, Palette.GOLD)
	_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_card_title)
	_card_side = _label(GameTheme.SMALL_FONT_SIZE + 2, Palette.CREAM)
	_card_side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Its text is short and must show whole; the title gives way instead.
	_card_side.clip_text = false
	_card_side.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	head.add_child(_card_side)
	for index: int in CARD_LINES:
		var line := _label(GameTheme.SMALL_FONT_SIZE, Palette.TEXT if index < CARD_LINES - 1 else Palette.TEXT_DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.clip_text = false
		line.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_card.add_child(line)
		_card_lines.append(line)


# Shows the card lines in order while they fit whole under the title; the
# first that would not fit and every line after it are left out, so no
# line is ever cut. Only visibility changes, so nothing redraws for nothing.
func _fit_card() -> void:
	# The card grows with its lines; the room is its clipping parent's.
	var content := _card.get_parent() as Control
	var width := content.size.x
	if width <= 0.0:
		return
	var room := content.size.y - _card_title.get_combined_minimum_size().y
	var separation := float(_card.get_theme_constant(&"separation"))
	var is_room_left := true
	for line: Label in _card_lines:
		var font := line.get_theme_font(&"font")
		var font_px := line.get_theme_font_size(&"font_size")
		var height := 0.0
		if line.text != "":
			var text_size := font.get_multiline_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_px, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
			var row_px := font.get_height(font_px)
			var rows := maxi(roundi(text_size.y / row_px), 1)
			height = rows * row_px + (rows - 1) * line.get_theme_constant(&"line_spacing") + separation
		is_room_left = is_room_left and height <= room
		var is_shown := is_room_left and line.text != ""
		if line.visible != is_shown:
			line.visible = is_shown
		room -= height if is_shown else 0.0


func _build_forecast(content: Control) -> void:
	_forecast = VBoxContainer.new()
	_forecast.set_anchors_preset(Control.PRESET_FULL_RECT)
	_forecast.add_theme_constant_override(&"separation", 2)
	content.add_child(_forecast)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 16)
	_forecast.add_child(columns)
	for side: int in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override(&"separation", 0)
		columns.add_child(column)
		for index: int in 3:
			var line := _label(24 if index == 0 else GameTheme.SMALL_FONT_SIZE, Palette.GOLD if index == 0 else Palette.TEXT)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			column.add_child(line)
		_forecast_columns.append(column)
	_forecast_note = _label(GameTheme.SMALL_FONT_SIZE, Palette.TEXT_DIM)
	_forecast_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A clipped label asks for no height; this one needs its two lines.
	_forecast_note.clip_text = false
	_forecast_note.max_lines_visible = 2
	_forecast_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_forecast.add_child(_forecast_note)


func _build_orders(rows: VBoxContainer) -> void:
	_orders = VBoxContainer.new()
	_orders.add_theme_constant_override(&"separation", 2)
	_orders.visible = false
	rows.add_child(_orders)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_orders.add_child(row)
	_order_note = _label(GameTheme.SMALL_FONT_SIZE, Palette.TEXT_DIM)
	_order_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_orders.add_child(_order_note)
	for order: StringName in TacticsText.ORDERS:
		var button := PressButton.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, ORDER_BUTTON_HEIGHT_PX)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var face := _OrderFace.new()
		face.order = order
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(face)
		button.pressed.connect(func() -> void:
			Sound.play(&"ui_tap")
			order_chosen.emit(order))
		row.add_child(button)
		_order_buttons[order] = button


func _label(font_px: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_px)
	label.add_theme_color_override(&"font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _panel_style() -> StyleBoxFlat:
	var box := GameTheme.make_panel(Palette.PANEL, 20, 6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 8
	return box


## An order button's face: the icon and the order's name under it.
class _OrderFace extends Control:
	var order: StringName
	var caption: String = ""
	var is_current: bool = false

	func _draw() -> void:
		var color := Palette.GOLD if is_current else Palette.CREAM
		if is_current:
			draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 10)), Palette.GOLD, false, 4.0)
		TacticsPainter.draw_order_icon(self, order, Vector2(size.x / 2.0, size.y * 0.36), minf(size.x * 0.5, size.y * 0.5), color)
		var font := get_theme_default_font()
		var font_px := GameTheme.SMALL_FONT_SIZE
		var width := minf(font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x, size.x - 8.0)
		draw_string(font, Vector2((size.x - width) / 2.0, size.y - 14.0), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8.0, font_px, color)
