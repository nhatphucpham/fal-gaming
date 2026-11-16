class_name UnitBar
extends Node2D
## A unit's hp bar, Khí bar and star pips, drawn behind its UnitView's
## figure so hats, crowns and blades stay whole. The view owns it and
## passes calls through (set_hp_ratio, set_qi, stamp_stars); see UnitView.

const BAR_SIZE := Vector2(54.0, 6.0)
const BAR_Y: float = -40.0
const QI_BAR_HEIGHT: float = 3.0
const PIP_RADIUS: float = 4.5

## Multiplies the speed of the bar's tweens (the battle speed button).
var playback_speed: float = 1.0:
	set(value):
		playback_speed = value
		for tween: Tween in [_hp_tween, _star_tween]:
			if tween != null and tween.is_valid():
				tween.set_speed_scale(value)
## False hides the hp and Khí bars but keeps the star pips.
var is_hp_bar_shown: bool = true:
	set(value):
		is_hp_bar_shown = value
		_update_pulsing()
		queue_redraw()
## The hp fill: the side's colour.
var hp_color: Color = Palette.PLAYER_HP
## Star pips shown.
var star: int = 1
## A boss shows its hp in the wide boss bar: this draws nothing.
var is_boss: bool = false

var _hp_ratio: float = 1.0
var _hp_trail: float = 1.0
# Share of full Khí, or below 0 for a unit without a skill (no bar).
var _qi_ratio: float = -1.0
var _time: float = 0.0
var _hp_tween: Tween
var _star_tween: Tween
# Scale of each star pip, for the stamping animation.
var _star_scales: Array[float] = [1.0, 1.0, 1.0]


func _init() -> void:
	show_behind_parent = true


func _ready() -> void:
	_update_pulsing()


# Only a full Khí bar pulses; any other bar redraws when its values change.
func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## True while a full Khí bar pulses (the only time the bar processes).
func is_pulsing() -> bool:
	return _qi_ratio >= 1.0 and is_hp_bar_shown


## Shows hp as a share of max, 0..1; the bar slides down with a pale trail.
func set_hp_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = _new_tween()
	_hp_tween.tween_method(_set_shown_hp, _hp_ratio, ratio, 0.15)
	_hp_tween.tween_interval(0.15)
	_hp_tween.tween_method(_set_hp_trail, _hp_trail, ratio, 0.25)


## Shows Khí as `qi` of `qi_max`; a qi_max of 0 hides the Khí bar.
func set_qi(qi: int, qi_max: int) -> void:
	_qi_ratio = clampf(float(qi) / qi_max, 0.0, 1.0) if qi_max > 0 else -1.0
	_update_pulsing()
	queue_redraw()


## Shows `star_level` stars, stamping them on one at a time.
func stamp_stars(star_level: int, delay_sec: float = 0.0) -> void:
	star = star_level
	_star_scales = [0.0, 0.0, 0.0]
	queue_redraw()
	if _star_tween != null and _star_tween.is_valid():
		_star_tween.kill()
	_star_tween = _new_tween()
	_star_tween.tween_interval(delay_sec)
	for index: int in star_level:
		_star_tween.tween_method(_set_star_scale.bind(index), 2.2, 1.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if is_boss:
		return
	var has_qi := is_hp_bar_shown and _qi_ratio >= 0.0
	# With a Khí bar the hp bar moves up so the pair keeps clear of the head.
	var origin := Vector2(-BAR_SIZE.x / 2.0, BAR_Y - (QI_BAR_HEIGHT if has_qi else 0.0))
	if is_hp_bar_shown:
		var frame := BAR_SIZE + Vector2(4, 4 + (QI_BAR_HEIGHT + 1.0 if has_qi else 0.0))
		draw_rect(Rect2(origin - Vector2(2, 2), frame), Palette.INK)
		draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _hp_trail, BAR_SIZE.y)), Palette.CREAM)
		draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _hp_ratio, BAR_SIZE.y)), hp_color)
	if has_qi:
		_draw_qi_bar(origin + Vector2(0, BAR_SIZE.y + 1.0))
	var pips_y := origin.y - 6.0 if is_hp_bar_shown else BAR_Y
	var spacing := PIP_RADIUS * 2.2
	for index: int in star:
		var pip_scale: float = _star_scales[mini(index, _star_scales.size() - 1)]
		if pip_scale > 0.01:
			var center := Vector2((index - (star - 1) / 2.0) * spacing, pips_y)
			UnitPainter.draw_star_pips(self, center, 1, PIP_RADIUS * pip_scale)


func _draw_qi_bar(origin: Vector2) -> void:
	var width := BAR_SIZE.x
	draw_rect(Rect2(origin, Vector2(width, QI_BAR_HEIGHT)), Palette.INDIGO_DARK)
	draw_rect(Rect2(origin, Vector2(width * _qi_ratio, QI_BAR_HEIGHT)), Palette.QI)
	if _qi_ratio >= 1.0:
		# Full: the whole frame glows, pulsing.
		var pulse := 0.55 + 0.45 * sin(_time * 8.0)
		var frame_origin := origin - Vector2(3, BAR_SIZE.y + 4.0)
		var frame_size := Vector2(width + 6.0, BAR_SIZE.y + QI_BAR_HEIGHT + 7.0)
		draw_rect(Rect2(frame_origin, frame_size), Color(Palette.QI_GLOW, pulse), false, 2.0)


func _set_shown_hp(value: float) -> void:
	_hp_ratio = value
	queue_redraw()


func _set_hp_trail(value: float) -> void:
	_hp_trail = value
	queue_redraw()


func _set_star_scale(value: float, index: int) -> void:
	_star_scales[index] = value
	queue_redraw()


func _update_pulsing() -> void:
	set_process(is_pulsing())


func _new_tween() -> Tween:
	var tween := create_tween()
	tween.set_speed_scale(playback_speed)
	return tween
