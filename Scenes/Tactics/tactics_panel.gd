class_name TacticsPanel
extends PanelContainer
## The bottom panel of the tactics screen: a content area that shows a
## unit card, an engagement or skill forecast, or the order picker, over
## one row of up to four buttons. Every button is at least 88 px tall
## (44 px on a 360-wide phone). It emits what was pressed; the screen
## decides what that means.
## [codeblock]
## panel.show_card("Lạc Hồng", Palette.GOLD, "Máu 900/900", lines, hint)
## panel.set_buttons([{"action": &"end_turn", "text": "BUTTON_END_TURN"}])
## panel.action_pressed.connect(_on_action)
## [/codeblock]

signal action_pressed(action: StringName)
signal order_chosen(order: StringName)

const CONTENT_HEIGHT_PX: float = 140.0
const BUTTON_HEIGHT_PX: float = 92.0
const ORDER_BUTTON_PX := Vector2(124, 140)

var _card: VBoxContainer
var _card_title: Label
var _card_side: Label
var _card_lines: Array[Label] = []
var _forecast: VBoxContainer
var _forecast_columns: Array[VBoxContainer] = []
var _forecast_note: Label
var _orders: HBoxContainer
var _order_buttons: Dictionary[StringName, PressButton] = {}
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
	_build_orders(content)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 10)
	_buttons.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_PX)
	rows.add_child(_buttons)


## A unit card: title (name) with a side note on its right and up to
## three lines, the last one dim (a hint).
func show_card(title: String, title_color: Color, side_note: String, lines: Array[String]) -> void:
	_show(_card)
	_card_title.text = title
	_card_title.add_theme_color_override(&"font_color", title_color)
	_card_side.text = side_note
	for index: int in _card_lines.size():
		_card_lines[index].text = lines[index] if index < lines.size() else ""


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


## The five order buttons; `current` is outlined gold.
func show_orders(current: StringName, text: TacticsText) -> void:
	_show(_orders)
	for order: StringName in _order_buttons:
		var button := _order_buttons[order]
		button.text = ""
		(button.get_child(0) as _OrderFace).caption = text.order_name(order)
		(button.get_child(0) as _OrderFace).is_current = order == current
		button.get_child(0).queue_redraw()


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


## The order buttons by order id, for tests and screenshots.
func get_order_buttons() -> Dictionary[StringName, PressButton]:
	return _order_buttons


func _show(view: Control) -> void:
	for child: Control in [_card, _forecast, _orders]:
		child.visible = child == view


func _build_card(content: Control) -> void:
	_card = VBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_theme_constant_override(&"separation", 2)
	content.add_child(_card)
	var head := HBoxContainer.new()
	_card.add_child(head)
	_card_title = _label(28, Palette.GOLD)
	_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_card_title)
	_card_side = _label(22, Palette.CREAM)
	_card_side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Its text is short and must show whole; the title gives way instead.
	_card_side.clip_text = false
	_card_side.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	head.add_child(_card_side)
	for index: int in 3:
		var line := _label(21, Palette.TEXT if index < 2 else Palette.TEXT_DIM)
		_card.add_child(line)
		_card_lines.append(line)


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
			var line := _label(24 if index == 0 else 21, Palette.GOLD if index == 0 else Palette.TEXT)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			column.add_child(line)
		_forecast_columns.append(column)
	_forecast_note = _label(18, Palette.TEXT_DIM)
	_forecast_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A clipped label asks for no height; this one needs its two lines.
	_forecast_note.clip_text = false
	_forecast_note.max_lines_visible = 2
	_forecast_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_forecast.add_child(_forecast_note)


func _build_orders(content: Control) -> void:
	_orders = HBoxContainer.new()
	_orders.set_anchors_preset(Control.PRESET_FULL_RECT)
	_orders.alignment = BoxContainer.ALIGNMENT_CENTER
	_orders.add_theme_constant_override(&"separation", 10)
	content.add_child(_orders)
	for order: StringName in TacticsText.ORDERS:
		var button := PressButton.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = ORDER_BUTTON_PX
		var face := _OrderFace.new()
		face.order = order
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(face)
		button.pressed.connect(func() -> void:
			Sound.play(&"ui_tap")
			order_chosen.emit(order))
		_orders.add_child(button)
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
			draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 12)), Palette.GOLD, false, 4.0)
		TacticsPainter.draw_order_icon(self, order, Vector2(size.x / 2.0, size.y * 0.4), size.x * 0.56, color)
		var font := get_theme_default_font()
		var font_px := 19
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		draw_string(font, Vector2((size.x - width) / 2.0, size.y - 18.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)
