class_name HowToScreen
extends Control
## "Cách chơi": four short tips over the title, each with a numbered gold
## seal, and "Quay lại". Opened from the title screen.

const TIP_KEYS: Array[String] = ["HOWTO_TIP_1", "HOWTO_TIP_2", "HOWTO_TIP_3", "HOWTO_TIP_4"]
const SIDE_PX: int = 32

signal closed()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Palette.BACKDROP
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: StringName in [&"margin_left", &"margin_right"]:
		margins.add_theme_constant_override(side, SIDE_PX)
	margins.add_theme_constant_override(&"margin_top", 72)
	margins.add_theme_constant_override(&"margin_bottom", 40)
	add_child(margins)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 22)
	margins.add_child(rows)
	var title := Label.new()
	title.text = "HOWTO_TITLE"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override(&"font_size", 56)
	title.add_theme_color_override(&"font_color", Palette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	for index: int in TIP_KEYS.size():
		rows.add_child(_tip(index + 1, TIP_KEYS[index]))
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	var back := PressButton.new()
	back.text = "BUTTON_BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.theme_type_variation = &"PrimaryButton"
	back.custom_minimum_size = Vector2(360, 96)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	rows.add_child(back)


func close() -> void:
	Sound.play(&"ui_tap")
	closed.emit()
	queue_free()


## The tip texts in order (tests).
func get_tips() -> PackedStringArray:
	var tips := PackedStringArray()
	for key: String in TIP_KEYS:
		tips.append(tr(key))
	return tips


func _tip(number: int, key: String) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := GameTheme.make_panel(Palette.PANEL, 18, 6)
	box.content_margin_left = 92
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	panel.add_theme_stylebox_override(&"panel", box)
	var text := Label.new()
	text.text = key
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override(&"font_size", 27)
	panel.add_child(text)
	# The numbered seal sits in the panel's wide left margin.
	panel.draw.connect(func() -> void:
		var center := Vector2(48, panel.size.y / 2.0)
		panel.draw_circle(center, 30.0, Palette.INK)
		panel.draw_circle(center, 27.0, Palette.GOLD)
		var font := panel.get_theme_default_font()
		var label := str(number)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		panel.draw_string(font, center + Vector2(-width / 2.0, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Palette.INK))
	return panel
