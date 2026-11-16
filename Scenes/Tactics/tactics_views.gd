class_name TacticsViews
extends RefCounted
## Small builders the tactics menus share (the roster, the character
## sheet, the after-battle summary, the muster): labels, panels, buttons,
## the mark icons, and the slide and stagger they open with, each with its
## sound.
## [codeblock]
## page.add_child(TacticsViews.label("ROSTER_TITLE", 40, Palette.GOLD))
## [/codeblock]

const STAGGER_SEC: float = 0.05
const ROW_IN_SEC: float = 0.2


static func label(text: String, font_px: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override(&"font_size", font_px)
	result.add_theme_color_override(&"font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return result


## A label that wraps to its width.
static func wrapped(text: String, font_px: int, color: Color) -> Label:
	var result := label(text, font_px, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	result.custom_minimum_size.x = 120
	return result


static func panel(fill: Color = Palette.PANEL) -> PanelContainer:
	var box := PanelContainer.new()
	var style := GameTheme.make_panel(fill, 16, 4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	box.add_theme_stylebox_override(&"panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func button(text_key: String, action: Callable, is_primary: bool) -> PressButton:
	var result := PressButton.new()
	result.text = text_key
	result.focus_mode = Control.FOCUS_NONE
	result.custom_minimum_size = Vector2(0, 96)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_primary:
		result.theme_type_variation = &"PrimaryButton"
	result.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		action.call())
	return result


static func clear(box: Node) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


## An overlay slides up and fades in, with a page sound.
static func slide_in(view: Control) -> void:
	view.modulate.a = 0.0
	view.position.y = 40.0
	var tween := view.create_tween().set_parallel()
	tween.tween_property(view, ^"modulate:a", 1.0, 0.18)
	tween.tween_property(view, ^"position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	Sound.play(&"card_flip")


## Rows fade in one after another.
static func stagger_in(rows: Array) -> void:
	for index: int in rows.size():
		var row := rows[index] as CanvasItem
		if row == null:
			continue
		row.modulate.a = 0.0
		var tween := row.create_tween()
		tween.tween_property(row, ^"modulate:a", 1.0, ROW_IN_SEC).set_delay(STAGGER_SEC * mini(index, 12))


## One mark as a diamond: gold for a good incident, red for a bad one.
class MarkIcon extends Control:
	var is_good: bool = true

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 1.0
		var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(points, Palette.GOLD if is_good else Palette.VERMILION)
		points.append(points[0])
		draw_polyline(points, Palette.INK, 2.0)


## Up to three mark diamonds and "+n" past them.
class MarkRow extends Control:
	var count: int = 0:
		set(value):
			count = value
			queue_redraw()

	func _draw() -> void:
		var r := minf(size.y / 2.0 - 1.0, 9.0)
		for index: int in 3:
			var c := Vector2(r + 1.0 + index * (r * 2.0 + 3.0), size.y / 2.0)
			var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			draw_colored_polygon(points, Palette.GOLD if index < count else Color(Palette.INK, 0.35))
			points.append(points[0])
			draw_polyline(points, Palette.INK, 1.5)
		if count > 3:
			var font := get_theme_default_font()
			draw_string(font, Vector2(3 * (r * 2.0 + 3.0) + 2.0, size.y / 2.0 + 7.0), "+%d" % (count - 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.GOLD)
