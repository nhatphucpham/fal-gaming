class_name SellZone
extends Control
## Covers the shop while a piece is selected or dragged: "Bán +N vàng" with
## a coin, to tap or drop the piece on. Hidden (and click-through) otherwise.
## Presses go through PointerGesture: any release on the zone sells (a tap,
## however long held, or the end of a slide), a cancelled touch or a release
## off the zone sells nothing.
## [codeblock]
## sell_zone.appear(4)
## sell_zone.tapped.connect(_sell_selected)
## [/codeblock]

signal tapped()

var _label: Label
var _is_hover: bool = false
var _is_shown: bool = false
var _time: float = 0.0
var _tween: Tween
var _gesture := PointerGesture.new()


func _init() -> void:
	_gesture.is_long_press_enabled = false
	_gesture.tapped.connect(_tap_if_inside)
	_gesture.drag_ended.connect(_tap_if_inside)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 40)
	_label.add_theme_color_override(&"font_outline_color", Palette.INK)
	_label.add_theme_constant_override(&"outline_size", 8)
	add_child(_label)


## Shows the zone for a piece that sells for `gold`.
func appear(gold: int) -> void:
	_label.text = tr("SELL_FORMAT") % gold
	if _is_shown:
		return
	_is_shown = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_to(1.0)


func vanish() -> void:
	if not _is_shown:
		return
	_is_shown = false
	_is_hover = false
	_gesture.cancel()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_to(0.0)


func is_shown() -> bool:
	return _is_shown


## True when a global canvas position is over the shown zone.
func contains_global(global_pointer: Vector2) -> bool:
	return _is_shown and get_global_rect().has_point(global_pointer)


## Lights the zone while a dragged piece is over it.
func set_hover(value: bool) -> void:
	if value != _is_hover:
		_is_hover = value
		pivot_offset = size / 2.0
		create_tween().tween_property(self, ^"scale", Vector2(1.03, 1.03) if value else Vector2.ONE, 0.1)


func _gui_input(event: InputEvent) -> void:
	# Every button is eaten, so no press falls through to the shop below.
	if _gesture.handle_input(event) or event is InputEventMouseButton:
		accept_event()


func _input(event: InputEvent) -> void:
	_gesture.handle_global_input(event)


func _notification(what: int) -> void:
	if _gesture != null:
		_gesture.handle_notification(what)


func _process(delta: float) -> void:
	_gesture.update(delta)
	if visible:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size).grow(-6.0)
	var box := GameTheme.make_panel(Palette.VERMILION_DARK if not _is_hover else Palette.VERMILION, 20, 6)
	box.draw(get_canvas_item(), rect)
	# Slow diagonal stripes, so the zone reads as "different" at a glance.
	var stripe := Color(Palette.INK, 0.18)
	var offset := fmod(_time * 30.0, 40.0)
	var x := -rect.size.y + offset
	while x < rect.size.x:
		var from := Vector2(maxf(x, 0.0), rect.position.y + maxf(0.0, -x))
		var to := Vector2(minf(x + rect.size.y, rect.size.x), rect.position.y + rect.size.y - maxf(0.0, x + rect.size.y - rect.size.x))
		draw_line(from + Vector2(rect.position.x, 0), to + Vector2(rect.position.x, 0), stripe, 10.0)
		x += 40.0
	IconPainter.draw(self, &"coin", Vector2(rect.position.x + 64.0, rect.get_center().y), 56.0)
	draw_rect(rect.grow(-10.0), Color(Palette.GOLD, 0.6 if _is_hover else 0.25), false, 3.0)


func _tap_if_inside(pointer: Vector2) -> void:
	if contains_global(pointer):
		tapped.emit()


func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", alpha, 0.15)
	if alpha <= 0.0:
		_tween.tween_callback(hide)
