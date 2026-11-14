class_name UnitView
extends Node2D
## One unit on the board: base ring, figure, hp bar, Khí bar and star pips,
## the skill marks (skill_overlay) and every animation a unit plays (drop in,
## pop out, glide, lunge, wind up, hit, die, cheer).
## Its origin is the centre of its cell. It never reads simulation state;
## callers tell it what happened. See Docs/systems/board.md.
## [codeblock]
## var view := UnitView.new()
## view.setup(catalog.get_unit(&"unit.archer"), Battle.SIDE_A, 1)
## board.get_piece_layer().add_child(view)
## view.position = board.cell_to_local(cell)
## view.drop_in()
## [/codeblock]

## Where the feet stand, from the cell centre.
const FEET := Vector2(0.0, 33.0)
const FIGURE_SCALE: float = 1.08
const RING_RADIUS := Vector2(28.0, 9.0)
const BAR_SIZE := Vector2(54.0, 6.0)
const BAR_Y: float = -40.0
const QI_BAR_HEIGHT: float = 3.0
const BREATH_AMOUNT: float = 0.035
const BREATH_SPEED: float = 2.4

## Multiplies the speed of every animation (the battle speed button).
var playback_speed: float = 1.0
## Offset of the figure from its feet position, for lunges, hops and shakes.
var anim_offset: Vector2 = Vector2.ZERO
## Squash and stretch of the figure, multiplied with breathing.
var squash: Vector2 = Vector2.ONE
## Height of the walking bob, in pixels.
var bob: float = 0.0
## Tilt of the figure in radians (charging, falling).
var lean: float = 0.0
var is_dead: bool = false
## False hides the hp bar but keeps the star pips (bench and preparation:
## full health says nothing).
var is_hp_bar_shown: bool = true:
	set(value):
		is_hp_bar_shown = value
		_bar.queue_redraw()

var unit: UnitData
var side: int = 0
var star: int = 1
## Cast glow, status icons and passive blink, drawn over the figure.
var skill_overlay: SkillOverlay

var _figure: UnitFigure
var _bar: Node2D
var _hp_ratio: float = 1.0
var _hp_trail: float = 1.0
# Share of full Khí, or below 0 for a unit without a skill (no bar).
var _qi_ratio: float = -1.0
var _dust: float = 0.0
var _breath_phase: float = 0.0
var _time: float = 0.0
var _motion_tween: Tween
var _figure_tween: Tween
var _hp_tween: Tween
var _fade_tween: Tween
# Scale of each star pip, for the stamping animation.
var _star_scales: Array[float] = [1.0, 1.0, 1.0]


func _init() -> void:
	_figure = UnitFigure.new()
	_figure.position = FEET
	add_child(_figure)
	# The bar is drawn behind the figure so hats, crowns and blades stay whole.
	_bar = Node2D.new()
	_bar.show_behind_parent = true
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	skill_overlay = SkillOverlay.new(self)
	add_child(skill_overlay)


## Sets what the view shows. Side 0 faces up with a blue ring, side 1 down
## with a red ring.
func setup(unit_data: UnitData, unit_side: int, star_level: int) -> void:
	unit = unit_data
	side = unit_side
	star = star_level
	_figure.unit = unit_data
	_figure.facing = UnitPainter.FACING_UP if unit_side == 0 else UnitPainter.FACING_DOWN
	_breath_phase = float(hash(unit_data.id) % 628) / 100.0 + randf() * 0.5
	queue_redraw()
	_bar.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var breath := sin(_time * BREATH_SPEED + _breath_phase) * BREATH_AMOUNT
	_figure.scale = squash * Vector2(1.0 - breath * 0.4, 1.0 + breath) * FIGURE_SCALE
	_figure.position = FEET + anim_offset + Vector2(0.0, -bob)
	_figure.rotation = lean
	if _qi_ratio >= 1.0 and is_hp_bar_shown:
		_bar.queue_redraw()


func _draw() -> void:
	var ring_color := Palette.PLAYER_RING if side == 0 else Palette.ENEMY_RING
	var ring := UnitPainter.Brush.ellipse(FEET, RING_RADIUS.x, RING_RADIUS.y, 20)
	draw_colored_polygon(ring, Color(ring_color, 0.35))
	ring.append(ring[0])
	draw_polyline(ring, ring_color, 2.5, true)
	if _dust > 0.0 and _dust < 1.0:
		var alpha := 1.0 - _dust
		for index: int in 6:
			var angle := TAU * index / 6.0 + 0.4
			var offset := Vector2(cos(angle) * (10.0 + 26.0 * _dust), sin(angle) * (4.0 + 8.0 * _dust))
			draw_circle(FEET + offset, 5.0 * (1.0 - _dust * 0.5), Color(Palette.PAPER_DARK, alpha * 0.9))


func _draw_bar() -> void:
	var has_qi := is_hp_bar_shown and _qi_ratio >= 0.0
	# With a Khí bar the hp bar moves up so the pair keeps clear of the head.
	var origin := Vector2(-BAR_SIZE.x / 2.0, BAR_Y - (QI_BAR_HEIGHT if has_qi else 0.0))
	if is_hp_bar_shown:
		var frame := BAR_SIZE + Vector2(4, 4 + (QI_BAR_HEIGHT + 1.0 if has_qi else 0.0))
		_bar.draw_rect(Rect2(origin - Vector2(2, 2), frame), Palette.INK)
		_bar.draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _hp_trail, BAR_SIZE.y)), Palette.CREAM)
		var fill := Palette.PLAYER_HP if side == 0 else Palette.ENEMY_HP
		_bar.draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _hp_ratio, BAR_SIZE.y)), fill)
	if has_qi:
		_draw_qi_bar(origin + Vector2(0, BAR_SIZE.y + 1.0))
	var pips_y := origin.y - 6.0 if is_hp_bar_shown else BAR_Y
	var spacing := 4.5 * 2.2
	for index: int in star:
		var pip_scale: float = _star_scales[mini(index, _star_scales.size() - 1)]
		if pip_scale > 0.01:
			var center := Vector2((index - (star - 1) / 2.0) * spacing, pips_y)
			UnitPainter.draw_star_pips(_bar, center, 1, 4.5 * pip_scale)


## Shows hp as a share of max, 0..1; the bar slides down with a pale trail.
func set_hp_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_reset_tween(_hp_tween)
	_hp_tween = _new_tween()
	_hp_tween.tween_method(_set_shown_hp, _hp_ratio, ratio, 0.15)
	_hp_tween.tween_interval(0.15)
	_hp_tween.tween_method(_set_hp_trail, _hp_trail, ratio, 0.25)


## Shows Khí as `qi` of `qi_max`; a qi_max of 0 hides the Khí bar.
func set_qi(qi: int, qi_max: int) -> void:
	_qi_ratio = clampf(float(qi) / qi_max, 0.0, 1.0) if qi_max > 0 else -1.0
	_bar.queue_redraw()


## Crouches and rises over `seconds`: the wind-up before a skill.
func wind_up(seconds: float) -> void:
	var tween := _new_figure_tween()
	tween.tween_property(self, ^"squash", Vector2(1.18, 0.82), seconds * 0.6).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, ^"anim_offset", Vector2(0, 3), seconds * 0.6)
	tween.tween_property(self, ^"squash", Vector2(0.9, 1.14), seconds * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, ^"anim_offset", Vector2(0, -6), seconds * 0.4)
	tween.tween_property(self, ^"squash", Vector2.ONE, 0.12)
	tween.parallel().tween_property(self, ^"anim_offset", Vector2.ZERO, 0.12)


## Falls into the cell with a squash and a puff of dust.
func drop_in() -> void:
	modulate.a = 0.0
	anim_offset = Vector2(0, -70)
	squash = Vector2(0.8, 1.2)
	var tween := _new_figure_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(self, ^"anim_offset", Vector2.ZERO, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, ^"squash", Vector2(1.3, 0.7), 0.05)
	tween.parallel().tween_method(_set_dust, 0.0, 1.0, 0.35)
	tween.tween_property(self, ^"squash", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Shows `star_level` stars, stamping them on one at a time.
func stamp_stars(star_level: int, delay_sec: float = 0.0) -> void:
	star = star_level
	_star_scales = [0.0, 0.0, 0.0]
	_bar.queue_redraw()
	var tween := _new_tween()
	tween.tween_interval(delay_sec)
	for index: int in star_level:
		tween.tween_method(_set_star_scale.bind(index), 2.2, 1.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The merge result: shrinks, then grows past full size and bounces.
func grow_in() -> void:
	squash = Vector2(0.3, 0.3)
	var tween := _new_figure_tween()
	tween.tween_property(self, ^"squash", Vector2(1.45, 1.45), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, ^"squash", Vector2(0.9, 1.1), 0.08)
	tween.tween_property(self, ^"squash", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Jumps in an arc to `target` (local position) over `seconds`.
func hop_to(target: Vector2, seconds: float) -> void:
	_reset_tween(_motion_tween)
	_motion_tween = _new_tween()
	_motion_tween.tween_method(_hop_step.bind(position, target), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Flies to `target` (local position) while shrinking away, then frees
## itself (a sold unit going into the gold counter).
func shrink_to(target: Vector2, seconds: float) -> void:
	is_dead = true
	_reset_tween(_motion_tween)
	_motion_tween = _new_tween()
	_motion_tween.tween_property(self, ^"position", target, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion_tween.parallel().tween_property(self, ^"squash", Vector2(0.15, 0.15), seconds).set_ease(Tween.EASE_IN)
	_motion_tween.tween_callback(queue_free)


## Pops up and vanishes, then frees itself.
func pop_out() -> void:
	is_dead = true
	var tween := _new_figure_tween()
	tween.tween_property(self, ^"squash", Vector2(1.25, 1.25), 0.08)
	tween.tween_property(self, ^"squash", Vector2(0.1, 0.1), 0.12).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, ^"modulate:a", 0.0, 0.12)
	tween.tween_callback(queue_free)


## A short side-to-side shake: "that did not work".
func shake() -> void:
	var tween := _new_figure_tween()
	for offset_x: float in [-7.0, 6.0, -4.0, 2.0, 0.0]:
		tween.tween_property(self, ^"anim_offset", Vector2(offset_x, 0), 0.05)


## Slides to `target` (local position) over `duration_sec` of battle time.
## `kind` is the unit_moved kind: walk bobs, charge leans in, knockback skids.
func glide_to(target: Vector2, duration_sec: float, kind: StringName) -> void:
	_reset_tween(_motion_tween)
	_motion_tween = _new_tween()
	var from := position
	var cells := maxf(1.0, from.distance_to(target) / 80.0)
	match kind:
		&"charge":
			# Stretched toward the run and bobbing fast: a gallop.
			squash = Vector2(0.9, 1.1)
			_motion_tween.tween_method(_gallop_step.bind(from, target), 0.0, 1.0, duration_sec)
			_motion_tween.tween_property(self, ^"squash", Vector2.ONE, 0.1)
		&"knockback":
			_motion_tween.tween_property(self, ^"position", target, duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_motion_tween.parallel().tween_property(self, ^"lean", -0.2, duration_sec * 0.5)
			_motion_tween.tween_property(self, ^"lean", 0.0, 0.12)
		_:
			_motion_tween.tween_method(_walk_step.bind(from, target, cells), 0.0, 1.0, duration_sec)


## A quick lunge toward `direction` and back, for melee swings.
func lunge(direction: Vector2) -> void:
	var tween := _new_figure_tween()
	tween.tween_property(self, ^"anim_offset", direction.normalized() * 14.0, 0.08).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, ^"anim_offset", Vector2.ZERO, 0.14).set_ease(Tween.EASE_IN_OUT)


## A small recoil, for shooting and casting.
func recoil(direction: Vector2) -> void:
	var tween := _new_figure_tween()
	tween.tween_property(self, ^"squash", Vector2(1.12, 0.9), 0.06)
	tween.parallel().tween_property(self, ^"anim_offset", -direction.normalized() * 4.0, 0.06)
	tween.tween_property(self, ^"squash", Vector2.ONE, 0.12)
	tween.parallel().tween_property(self, ^"anim_offset", Vector2.ZERO, 0.12)


## Flashes white and flinches.
func hit_flash() -> void:
	var tween := _new_tween()
	_figure.flash = 1.0
	tween.tween_property(_figure, ^"flash", 0.0, 0.2)
	tween.parallel().tween_property(self, ^"squash", Vector2(0.92, 1.06), 0.05)
	tween.tween_property(self, ^"squash", Vector2.ONE, 0.1)


## Falls over and fades out; stays in the tree, hidden.
func die() -> void:
	is_dead = true
	skill_overlay.clear()
	_reset_tween(_motion_tween)
	var tween := _new_figure_tween()
	var fall_side := -1.0 if side == 0 else 1.0
	tween.tween_property(self, ^"lean", fall_side * 1.4, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, ^"anim_offset", Vector2(fall_side * 8.0, 2.0), 0.3)
	tween.tween_property(self, ^"modulate:a", 0.0, 0.35)
	tween.tween_callback(hide)


## Two happy hops, for the winners.
func cheer() -> void:
	var tween := _new_figure_tween()
	tween.tween_interval(randf() * 0.15)
	for hop: int in 2:
		tween.tween_property(self, ^"anim_offset", Vector2(0, -16), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(self, ^"squash", Vector2(0.9, 1.12), 0.14)
		tween.tween_property(self, ^"anim_offset", Vector2.ZERO, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(self, ^"squash", Vector2(1.15, 0.85), 0.05)
		tween.tween_property(self, ^"squash", Vector2.ONE, 0.08)


## Fades to `alpha` (0..1) over `duration_sec`; used to dim and cross-fade.
func fade_to(alpha: float, duration_sec: float = 0.2) -> void:
	_reset_tween(_fade_tween)
	_fade_tween = _new_tween()
	_fade_tween.tween_property(self, ^"modulate:a", alpha, duration_sec)


## Tints the view darker by `amount` 0..1 (the enemy half during setup).
func set_dim(amount: float) -> void:
	var value := 1.0 - amount
	var tween := _new_tween()
	# Only the colour channels: alpha may be mid-animation (drop in, fades).
	for channel: NodePath in [^"modulate:r", ^"modulate:g", ^"modulate:b"]:
		tween.parallel().tween_property(self, channel, value, 0.2)


func _draw_qi_bar(origin: Vector2) -> void:
	var width := BAR_SIZE.x
	_bar.draw_rect(Rect2(origin, Vector2(width, QI_BAR_HEIGHT)), Palette.INDIGO_DARK)
	_bar.draw_rect(Rect2(origin, Vector2(width * _qi_ratio, QI_BAR_HEIGHT)), Palette.QI)
	if _qi_ratio >= 1.0:
		# Full: the whole frame glows, pulsing.
		var pulse := 0.55 + 0.45 * sin(_time * 8.0)
		var frame_origin := origin - Vector2(3, BAR_SIZE.y + 4.0)
		var frame_size := Vector2(width + 6.0, BAR_SIZE.y + QI_BAR_HEIGHT + 7.0)
		_bar.draw_rect(Rect2(frame_origin, frame_size), Color(Palette.QI_GLOW, pulse), false, 2.0)


func _walk_step(progress: float, from: Vector2, target: Vector2, cells: float) -> void:
	position = from.lerp(target, progress)
	bob = absf(sin(progress * PI * cells)) * 4.0


func _hop_step(progress: float, from: Vector2, target: Vector2) -> void:
	position = from.lerp(target, progress)
	bob = sin(progress * PI) * minf(40.0, 12.0 + from.distance_to(target) * 0.12)


func _set_star_scale(value: float, index: int) -> void:
	_star_scales[index] = value
	_bar.queue_redraw()


func _gallop_step(progress: float, from: Vector2, target: Vector2) -> void:
	position = from.lerp(target, progress)
	bob = absf(sin(progress * PI * 2.0)) * 6.0


func _set_shown_hp(value: float) -> void:
	_hp_ratio = value
	_bar.queue_redraw()


func _set_hp_trail(value: float) -> void:
	_hp_trail = value
	_bar.queue_redraw()


func _set_dust(value: float) -> void:
	_dust = value
	queue_redraw()


func _new_figure_tween() -> Tween:
	_reset_tween(_figure_tween)
	_figure_tween = _new_tween()
	return _figure_tween


func _new_tween() -> Tween:
	var tween := create_tween()
	tween.set_speed_scale(playback_speed)
	return tween


func _reset_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
