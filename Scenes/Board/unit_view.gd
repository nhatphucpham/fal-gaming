class_name UnitView
extends Node2D
## One unit on the board: base ring, figure, hp bar, Khí bar and star pips,
## the skill marks (skill_overlay) and every animation a unit plays (drop in,
## pop out, glide, lunge, wind up, hit, die, cheer). A rigged figure moves
## by its PoseAnimator's clips (the pose's step toward the target pushes the
## whole figure); tweens here place the view and move figures outside the
## rig (the boss). Only the figure turns toward its target (flips); bars,
## ring and marks never do.
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
const BAR_SIZE := UnitBar.BAR_SIZE
const BAR_Y: float = UnitBar.BAR_Y
const BREATH_AMOUNT: float = 0.035
const BREATH_SPEED: float = 2.4
## A boss is drawn this much bigger; its feet stay in its cell and its
## shoulders reach over the neighbours. Its hp shows in the wide boss bar.
const BOSS_SCALE: float = 1.6
const STONE_TINT := Color(0.62, 0.6, 0.58)
## How long a rigged figure lies still before it fades.
const FALLEN_SEC: float = 1.1

## Multiplies the speed of every animation (the battle speed button);
## running moves and poses change speed too.
var playback_speed: float = 1.0:
	set(value):
		playback_speed = value
		_animator.playback_speed = value
		_bar.playback_speed = value
		for tween: Tween in [_motion_tween, _figure_tween, _fade_tween, _flash_tween]:
			if tween != null and tween.is_valid():
				tween.set_speed_scale(value)
## Offset of the figure from its feet position, for lunges, hops and shakes.
var anim_offset: Vector2 = Vector2.ZERO
## Squash and stretch of the figure, multiplied with breathing.
var squash: Vector2 = Vector2.ONE
## Height of the walking bob, in pixels.
var bob: float = 0.0
## Tilt of the figure in radians (charging, falling).
var lean: float = 0.0
var is_dead: bool = false
## Turned to stone (Hóa Đá): grey, not breathing.
var is_petrified: bool = false
## False hides the hp bar but keeps the star pips (bench and preparation:
## full health says nothing).
var is_hp_bar_shown: bool:
	get:
		return _bar.is_hp_bar_shown
	set(value):
		_bar.is_hp_bar_shown = value
## True holds the idle sway still (only blinks redraw): for figures that
## only wait, on the bench or in the dimmed enemy line-up.
var is_idle_calm: bool = false:
	set(value):
		is_idle_calm = value
		_animator.is_swaying = not value

var unit: UnitData
var side: int = 0
## Cast glow, status icons and passive blink, drawn over the figure.
var skill_overlay: SkillOverlay

var _figure: UnitFigure
var _animator: PoseAnimator
var _is_rigged: bool = false
var _bar: UnitBar
var _dust: float = 0.0
var _breath_phase: float = 0.0
var _time: float = 0.0
var _motion_tween: Tween
var _figure_tween: Tween
var _fade_tween: Tween
var _flash_tween: Tween
# The figure tween of a wind-up outside the rig (the boss), while it runs.
var _wind_tween: Tween
var _size_scale: float = 1.0
var _stone: StoneLayer


func _init() -> void:
	_figure = UnitFigure.new()
	_figure.position = FEET
	add_child(_figure)
	_animator = PoseAnimator.new(_figure)
	_figure.animator = _animator
	add_child(_animator)
	_stone = StoneLayer.new()
	add_child(_stone)
	_bar = UnitBar.new()
	add_child(_bar)
	skill_overlay = SkillOverlay.new(self)
	add_child(skill_overlay)


## Sets what the view shows. Side 0 faces up and right with a blue ring,
## side 1 down and left with a red ring.
func setup(unit_data: UnitData, unit_side: int, star_level: int) -> void:
	unit = unit_data
	side = unit_side
	_bar.hp_color = Palette.PLAYER_HP if unit_side == 0 else Palette.ENEMY_HP
	_bar.star = star_level
	_bar.is_boss = unit_data.is_boss
	_figure.unit = unit_data
	_figure.facing = UnitPainter.FACING_UP if unit_side == 0 else UnitPainter.FACING_DOWN
	_figure.face_side(unit_side)
	_animator.set_class(unit_data.class_id)
	_animator.set_view(UnitPainter.view_of(_figure.facing))
	# Bosses and the sage stand still: their animator has no kit, so no
	# pose and no idle redraws.
	_is_rigged = UnitPainter.is_posable(unit_data.class_id)
	_size_scale = BOSS_SCALE if unit_data.is_boss else 1.0
	_figure.pixels_per_unit = FIGURE_SCALE * _size_scale
	_stone.size_scale = _size_scale
	_breath_phase = float(hash(unit_data.id) % 628) / 100.0 + randf() * 0.5
	queue_redraw()
	_bar.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	# A rigged figure breathes in its pose; the others bob their scale.
	var breath := 0.0 if is_petrified or _is_rigged else sin(_time * BREATH_SPEED + _breath_phase) * BREATH_AMOUNT
	_figure.scale = squash * Vector2((1.0 - breath * 0.4) * _figure.flip, 1.0 + breath) * FIGURE_SCALE * _size_scale
	var push := _figure.get_push() * FIGURE_SCALE * _size_scale if _is_rigged else Vector2.ZERO
	_figure.position = FEET + anim_offset + Vector2(0.0, -bob) + push
	_figure.rotation = lean


func _draw() -> void:
	var ring_color := Palette.PLAYER_RING if side == 0 else Palette.ENEMY_RING
	UnitPainter.draw_ring(self, FEET, RING_RADIUS * _size_scale, ring_color, _dust)


## Shows hp as a share of max, 0..1; the bar slides down with a pale trail.
func set_hp_ratio(ratio: float) -> void:
	_bar.set_hp_ratio(ratio)


## Shows Khí as `qi` of `qi_max`; a qi_max of 0 hides the Khí bar.
func set_qi(qi: int, qi_max: int) -> void:
	_bar.set_qi(qi, qi_max)


## The figure's pose, for tests and tools; never change it from outside.
func get_pose() -> UnitPose:
	return _animator.pose


## The pose animator, for tests and tools.
func get_animator() -> PoseAnimator:
	return _animator


## 1 when the figure faces right, -1 when it faces left.
func get_flip() -> float:
	return _figure.flip


## Crouches with the weapon raised and glowing over `seconds` (the skill's
## cast time); the next lunge or recoil releases the strike (or it releases
## itself just after `seconds`).
func wind_up(seconds: float) -> void:
	_animator.wind_up(seconds)
	if not _is_rigged:
		_wind_tween = _new_figure_tween()
		FigureTweens.wind_up(_wind_tween, self, seconds)


## Falls into the cell with a squash and a puff of dust.
func drop_in() -> void:
	FigureTweens.drop_in(_new_figure_tween(), self, _set_dust)


## Shows `star_level` stars, stamping them on one at a time.
func stamp_stars(star_level: int, delay_sec: float = 0.0) -> void:
	_bar.stamp_stars(star_level, delay_sec)


## The merge result: shrinks, then grows past full size and bounces.
func grow_in() -> void:
	FigureTweens.grow_in(_new_figure_tween(), self)


## Jumps in an arc to `target` (local position) over `seconds`.
func hop_to(target: Vector2, seconds: float) -> void:
	_reset_tween(_motion_tween)
	lean = 0.0
	_motion_tween = _new_tween()
	BoardMotions.hop(_motion_tween, self, target, seconds)


## Flies to `target` (local position) while shrinking away, then frees
## itself (a sold unit going into the gold counter).
func shrink_to(target: Vector2, seconds: float) -> void:
	is_dead = true
	_reset_tween(_motion_tween)
	_motion_tween = _new_tween()
	BoardMotions.shrink(_motion_tween, self, target, seconds)


## Pops up and vanishes, then frees itself.
func pop_out() -> void:
	is_dead = true
	FigureTweens.pop_out(_new_figure_tween(), self)


## A short side-to-side shake: "that did not work".
func shake() -> void:
	FigureTweens.shake(_new_figure_tween(), self)


## Slides to `target` (local position) over `duration_sec` of battle time.
## `kind` is the unit_moved kind: walk bobs, charge leans in, knockback skids.
func glide_to(target: Vector2, duration_sec: float, kind: StringName) -> void:
	_reset_tween(_motion_tween)
	# A knockback cut short never reaches its lean-back step.
	lean = 0.0
	_motion_tween = _new_tween()
	if kind == &"knockback":
		_animator.flinch_for(duration_sec)
	else:
		_animator.walk(duration_sec, kind == &"charge")
	BoardMotions.glide(_motion_tween, self, target, duration_sec, kind, _is_rigged)


## A quick lunge toward `direction` and back, for melee swings: the figure
## turns to the target and strikes at it (a rigged figure's clip steps in).
func lunge(direction: Vector2) -> void:
	_attack_toward(direction)
	if _is_rigged:
		FigureTweens.unsquash(_new_figure_tween(), self)
	else:
		FigureTweens.lunge(_new_figure_tween(), self, direction)


## A small recoil, for shooting and casting: the figure turns to the target
## and looses or casts at it (or releases a wound-up skill).
func recoil(direction: Vector2) -> void:
	_attack_toward(direction)
	if _is_rigged:
		FigureTweens.unsquash(_new_figure_tween(), self)
	else:
		FigureTweens.recoil(_new_figure_tween(), self, direction)


## Flashes white and flinches with hurt eyes (a shield raises its shield).
## Stone takes no flash: a hit that lands late (an arrow in flight) leaves
## a statue as it is.
func hit_flash() -> void:
	if is_petrified:
		return
	_animator.hit()
	_reset_tween(_flash_tween)
	_flash_tween = _new_tween()
	_figure.flash = 1.0
	_flash_tween.tween_property(_figure, ^"flash", 0.0, 0.2)
	if not _is_rigged:
		FigureTweens.flinch(_flash_tween, self)


## Drops a wind-up whose cast was cancelled (stun, stone): no strike
## follows, the glow goes and the figure settles to its rest pose. A figure
## outside the rig straightens only if its wind-up still plays (any other
## figure animation, such as a drop in, goes on).
func cancel_wind_up() -> void:
	_animator.cancel_wind_up()
	if _is_winding_figure():
		FigureTweens.unsquash(_new_figure_tween(), self)


## Falls (the rig lies down; the boss tips over) and fades out; stays in
## the tree, hidden.
func die() -> void:
	is_dead = true
	_stone.is_stone = false
	skill_overlay.clear()
	_reset_tween(_motion_tween)
	_animator.die()
	var tween := _new_figure_tween()
	tween.tween_property(self, ^"squash", Vector2.ONE, 0.1)
	tween.parallel().tween_property(self, ^"anim_offset", Vector2.ZERO, 0.1)
	if _is_rigged:
		tween.tween_interval(FALLEN_SEC)
	else:
		tween.tween_property(self, ^"lean", -_figure.flip * 1.4, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, ^"modulate:a", 0.0, 0.35)
	tween.tween_callback(hide)


## Turns the figure to grey stone (Hóa Đá), its pose frozen as it is, or
## back to life. Stone cancels a wind-up and keeps no hit flash.
func set_petrified(petrified: bool) -> void:
	is_petrified = petrified
	_stone.is_stone = petrified
	_animator.set_frozen(petrified)
	if petrified:
		_reset_tween(_flash_tween)
		_figure.flash = 0.0
		if _is_winding_figure():
			_reset_tween(_figure_tween)
	var tween := _new_tween()
	tween.tween_property(_figure, ^"modulate", STONE_TINT if petrified else Color.WHITE, 0.15)
	if petrified:
		FigureTweens.stone_thud(tween, self)


## The boss's end: shakes, cracks spread, then it crumbles into a heap of
## dust and fades (instead of falling over). Stays in the tree, hidden.
func crumble() -> void:
	is_dead = true
	skill_overlay.clear()
	_reset_tween(_motion_tween)
	_stone.is_stone = false
	FigureTweens.crumble(_new_figure_tween(), self, _stone, _set_dust)


## Two happy hops with the weapon raised, for the winners (a rigged
## figure hops in its cheer clip).
func cheer() -> void:
	_animator.cheer()
	if not _is_rigged:
		FigureTweens.cheer(_new_figure_tween(), self)


## Fades to `alpha` (0..1) over `duration_sec`; used to dim and cross-fade.
func fade_to(alpha: float, duration_sec: float = 0.2) -> void:
	_reset_tween(_fade_tween)
	_fade_tween = _new_tween()
	_fade_tween.tween_property(self, ^"modulate:a", alpha, duration_sec)


## Tints the view darker by `amount` 0..1 (the enemy half during setup).
func set_dim(amount: float) -> void:
	var value := 1.0 - amount
	is_idle_calm = amount > 0.0
	var tween := _new_tween()
	# Only the colour channels: alpha may be mid-animation (drop in, fades).
	for channel: NodePath in [^"modulate:r", ^"modulate:g", ^"modulate:b"]:
		tween.parallel().tween_property(self, channel, value, 0.2)


# Turns the figure toward `direction` (board pixels) and attacks along it.
func _attack_toward(direction: Vector2) -> void:
	_animator.attack(_figure.turn_toward(direction, _animator.aims_off_hand()))


# True while a figure outside the rig plays its wind-up tween.
func _is_winding_figure() -> bool:
	return _wind_tween != null and _wind_tween == _figure_tween and _wind_tween.is_valid()


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
