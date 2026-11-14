class_name SkillOverlay
extends Node2D
## The skill marks drawn over one UnitView: the glow at the feet while it
## casts, small status icons beside the hp bar and the passive icon that
## blinks once when the passive fires. UnitView owns one; BattlePlayback
## drives it through the view. Animations follow the view's playback_speed.

const ICON_RADIUS: float = 6.5
const ICON_GAP: float = 15.0
const BLINK_SEC: float = 0.4

## The colour of the cast glow and the passive icon (the class colour).
var accent: Color = Palette.GOLD

var _view: UnitView
var _is_casting: bool = false
var _cast_time: float = 0.0
var _blink: float = 0.0
# Active statuses, in the order they were applied.
var _statuses: Array[StringName] = []
var _painters: Dictionary[StringName, Callable] = {}


func _init(view: UnitView) -> void:
	_view = view
	_painters = {
		&"status.taunted": _paint_taunted,
		&"status.guard": _paint_guard,
		&"status.armor_break": _paint_armor_break,
		&"status.stun": _paint_stun,
		&"status.petrified": _paint_petrified,
	}


func _process(delta: float) -> void:
	if _is_casting:
		_cast_time += delta * _view.playback_speed
		queue_redraw()


## Starts or stops the glow at the feet.
func set_casting(is_casting: bool) -> void:
	_is_casting = is_casting
	_cast_time = 0.0
	queue_redraw()


func add_status(status: StringName) -> void:
	if not _statuses.has(status):
		_statuses.append(status)
		queue_redraw()


func remove_status(status: StringName) -> void:
	_statuses.erase(status)
	queue_redraw()


func clear() -> void:
	_statuses.clear()
	_is_casting = false
	queue_redraw()


## Blinks the passive icon once.
func blink_passive() -> void:
	var tween := create_tween()
	tween.set_speed_scale(_view.playback_speed)
	tween.tween_method(_set_blink, 0.0, 1.0, BLINK_SEC)
	tween.tween_callback(_set_blink.bind(0.0))


func _set_blink(value: float) -> void:
	_blink = value
	queue_redraw()


func _draw() -> void:
	if _view.is_dead:
		return
	if _is_casting:
		_draw_cast_glow()
	if _blink > 0.0:
		_draw_passive_icon()
	var right := UnitView.BAR_SIZE.x / 2.0 + ICON_RADIUS + 4.0
	for index: int in _statuses.size():
		var painter: Callable = _painters.get(_statuses[index], Callable())
		if painter.is_valid():
			painter.call(Vector2(right, UnitView.BAR_Y + 3.0 - index * ICON_GAP))


func _draw_cast_glow() -> void:
	var pulse := 0.5 + 0.5 * sin(_cast_time * TAU * 3.0)
	var radius := UnitView.RING_RADIUS * (1.15 + 0.12 * pulse)
	var ring := FigureBrush.ellipse(UnitView.FEET, radius.x, radius.y, 24)
	draw_colored_polygon(ring, Color(accent, 0.25 + 0.15 * pulse))
	ring.append(ring[0])
	draw_polyline(ring, Color(accent.lightened(0.3), 0.9), 3.0, true)


func _draw_passive_icon() -> void:
	# Up fast, then fade: one blink.
	var alpha := minf(_blink * 4.0, 1.0) * (1.0 - maxf(_blink - 0.5, 0.0) * 2.0)
	var grow := 1.0 + 0.5 * sin(_blink * PI)
	var center := Vector2(-UnitView.BAR_SIZE.x / 2.0 - ICON_RADIUS - 4.0, UnitView.BAR_Y + 3.0)
	var size := ICON_RADIUS * grow
	var diamond := PackedVector2Array([center + Vector2(0, -size), center + Vector2(size, 0), center + Vector2(0, size), center + Vector2(-size, 0)])
	draw_colored_polygon(diamond, Color(accent.lightened(0.2), alpha))
	diamond.append(diamond[0])
	draw_polyline(diamond, Color(Palette.INK, alpha), 2.0, true)
	draw_circle(center, size * 0.3, Color(Palette.CREAM, alpha))


func _icon_base(center: Vector2, fill: Color) -> void:
	draw_circle(center, ICON_RADIUS + 1.5, Palette.INK)
	draw_circle(center, ICON_RADIUS, fill)


func _paint_taunted(center: Vector2) -> void:
	_icon_base(center, Palette.VERMILION)
	draw_line(center + Vector2(0, -3.8), center + Vector2(0, 1.0), Palette.CREAM, 2.2)
	draw_circle(center + Vector2(0, 3.4), 1.2, Palette.CREAM)


func _paint_guard(center: Vector2) -> void:
	_icon_base(center, Palette.INDIGO)
	draw_colored_polygon(_shield_shape(center), Palette.STEEL)


func _paint_armor_break(center: Vector2) -> void:
	_icon_base(center, Palette.OCHRE)
	draw_colored_polygon(_shield_shape(center), Palette.CREAM)
	draw_polyline(PackedVector2Array([center + Vector2(-1, -4), center + Vector2(1, -1), center + Vector2(-1, 1), center + Vector2(1, 4)]), Palette.VERMILION_DARK, 1.6)


func _paint_stun(center: Vector2) -> void:
	_icon_base(center, Palette.GOLD)
	for corner: int in 5:
		var angle := TAU * corner / 5.0 - PI / 2.0
		draw_line(center, center + Vector2.from_angle(angle) * 4.5, Palette.INK, 1.6)


func _paint_petrified(center: Vector2) -> void:
	_icon_base(center, Palette.STEEL)
	draw_polyline(PackedVector2Array([center + Vector2(-3.5, -3.0), center + Vector2(-0.5, 0.0), center + Vector2(-2.0, 1.5), center + Vector2(2.5, 4.0)]), Palette.INK, 1.6)
	draw_line(center + Vector2(-0.5, 0.0), center + Vector2(3.5, -2.5), Palette.INK, 1.4)


func _shield_shape(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-3.5, -3.8), center + Vector2(3.5, -3.8),
		center + Vector2(3.0, 1.2), center + Vector2(0, 4.2), center + Vector2(-3.0, 1.2),
	])
