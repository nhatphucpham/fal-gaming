class_name EndScreen
extends Control
## The end of a run: "Chiến thắng" or "Thất bại", how many stages were
## cleared, the final line-up as portraits with their stars, and a button
## back to the title screen.

## "Về màn hình chính".
signal home_requested()

const PORTRAIT_PX: float = 96.0

var run: RunState
var _home_button: PressButton


func _ready() -> void:
	theme = GameTheme.create()
	var backdrop := Backdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override(&"separation", 28)
	add_child(rows)
	var is_win := run.phase == RunState.Phase.WON
	var title := _label("END_WIN" if is_win else "END_LOSS", 84)
	title.add_theme_color_override(&"font_color", Palette.GOLD if is_win else Palette.VERMILION)
	title.add_theme_constant_override(&"outline_size", 12)
	rows.add_child(title)
	rows.add_child(_label(tr("END_STAGES_FORMAT") % [run.stages_cleared, run.rules.stage_count], 32))
	rows.add_child(_build_lineup())
	_home_button = PressButton.new()
	_home_button.text = "BUTTON_HOME"
	_home_button.theme_type_variation = &"PrimaryButton"
	_home_button.focus_mode = Control.FOCUS_NONE
	_home_button.custom_minimum_size = Vector2(440, 96)
	_home_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_home_button.pressed.connect(func() -> void: home_requested.emit())
	rows.add_child(_home_button)
	_animate_in(title)


func _build_lineup() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pieces := run.get_board_pieces()
	if pieces.is_empty():
		pieces = run.get_pieces()
	for index: int in pieces.size():
		var piece := pieces[index]
		var portrait := Control.new()
		portrait.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX + 16)
		var unit := run.catalog.get_unit(piece.unit_id)
		var star := piece.star
		portrait.draw.connect(func() -> void: _draw_portrait(portrait, unit, star))
		grid.add_child(portrait)
		portrait.modulate.a = 0.0
		portrait.create_tween().tween_property(portrait, ^"modulate:a", 1.0, 0.25).set_delay(0.4 + index * 0.07)
	return grid


func _draw_portrait(canvas: Control, unit: UnitData, star: int) -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(PORTRAIT_PX, PORTRAIT_PX))
	var fill := Palette.cost_color(unit.cost)
	GameTheme.make_panel(fill, 16, 4).draw(canvas.get_canvas_item(), rect)
	canvas.draw_circle(rect.get_center() + Vector2(0, -6), 32.0, Color(fill.lightened(0.3), 0.9))
	UnitPainter.draw_bust(canvas, unit, rect.get_center() + Vector2(0, 14), 1.5)
	UnitPainter.draw_star_pips(canvas, Vector2(PORTRAIT_PX / 2.0, PORTRAIT_PX + 8.0), star, 7.0)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override(&"font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _animate_in(title: Label) -> void:
	title.pivot_offset = Vector2(360, 50)
	title.scale = Vector2(0.4, 0.4)
	title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(title, ^"scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(title, ^"modulate:a", 1.0, 0.2)
