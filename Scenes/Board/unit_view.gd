class_name UnitView
extends Node2D
## One unit on the board: base ring, figure, hp bar and star pips, and every
## animation a unit plays (drop in, pop out, glide, lunge, hit, die, cheer).
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

var unit: UnitData
var side: int = 0
var star: int = 1

var _figure: UnitFigure
var _bar: Node2D
var _hp_ratio: float = 1.0
var _hp_trail: float = 1.0
var _dust: float = 0.0
var _breath_phase: float = 0.0
var _time: float = 0.0
var _motion_tween: Tween
var _figure_tween: Tween
var _hp_tween: Tween
var _fade_tween: Tween


func _init() -> void:
	_figure = UnitFigure.new()
	_figure.position = FEET
	add_child(_figure)
	# The bar is drawn behind the figure so hats, crowns and blades stay whole.
	_bar = Node2D.new()
	_bar.show_behind_parent = true
	_bar.draw.connect(_draw_bar)
	add_child(_bar)


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
	var origin := Vector2(-BAR_SIZE.x / 2.0, BAR_Y)
	_bar.draw_rect(Rect2(origin - Vector2(2, 2), BAR_SIZE + Vector2(4, 4)), Palette.INK)
	_bar.draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _hp_trail, BAR_SIZE.y)), Palette.CREAM)
	var fill := Palette.PLAYER_HP if side == 0 else Palette.ENEMY_HP
	_bar.draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * _hp_ratio, BAR_SIZE.y)), fill)
	UnitPainter.draw_star_pips(_bar, Vector2(0.0, BAR_Y - 6.0), star)


## Shows hp as a share of max, 0..1; the bar slides down with a pale trail.
func set_hp_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_reset_tween(_hp_tween)
	_hp_tween = _new_tween()
	_hp_tween.tween_method(_set_shown_hp, _hp_ratio, ratio, 0.15)
	_hp_tween.tween_interval(0.15)
	_hp_tween.tween_method(_set_hp_trail, _hp_trail, ratio, 0.25)


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


func _walk_step(progress: float, from: Vector2, target: Vector2, cells: float) -> void:
	position = from.lerp(target, progress)
	bob = absf(sin(progress * PI * cells)) * 4.0


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
