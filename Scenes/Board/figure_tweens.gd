class_name FigureTweens
extends RefCounted
## The whole-figure squash, offset and fade steps of UnitView's animations:
## the board motions every figure plays (drop in, grow in, pop out, shake)
## and the stand-ins for clips that figures outside the rig play (the boss
## and the sage: wind up, lunge, recoil, hit, cheer, the boss's crumble).
## Each adds steps to a tween the view made (so it already runs at the
## battle speed) and tweens the view's `squash`, `anim_offset` and
## `modulate:a`.


## Falls into the cell with a squash; `set_dust` (func(amount)) puffs dust.
static func drop_in(tween: Tween, view: UnitView, set_dust: Callable) -> void:
	view.modulate.a = 0.0
	view.anim_offset = Vector2(0, -70)
	view.squash = Vector2(0.8, 1.2)
	tween.tween_property(view, ^"modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2.ZERO, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(view, ^"squash", Vector2(1.3, 0.7), 0.05)
	tween.parallel().tween_method(set_dust, 0.0, 1.0, 0.35)
	tween.tween_property(view, ^"squash", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Shrinks, then grows past full size and bounces.
static func grow_in(tween: Tween, view: UnitView) -> void:
	# It may replace a drop_in() started in the same frame (a gifted piece
	# after a rebuild): finish what that would have restored.
	view.modulate.a = 1.0
	view.anim_offset = Vector2.ZERO
	view.squash = Vector2(0.3, 0.3)
	tween.tween_property(view, ^"squash", Vector2(1.45, 1.45), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2.ZERO, 0.1)
	tween.tween_property(view, ^"squash", Vector2(0.9, 1.1), 0.08)
	tween.tween_property(view, ^"squash", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Pops up and vanishes, then frees the view.
static func pop_out(tween: Tween, view: UnitView) -> void:
	tween.tween_property(view, ^"squash", Vector2(1.25, 1.25), 0.08)
	tween.tween_property(view, ^"squash", Vector2(0.1, 0.1), 0.12).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(view, ^"modulate:a", 0.0, 0.12)
	tween.tween_callback(view.queue_free)


## A short side-to-side shake.
static func shake(tween: Tween, view: UnitView) -> void:
	tween.tween_property(view, ^"anim_offset", Vector2(-7, 0), 0.05)
	tween.parallel().tween_property(view, ^"squash", Vector2.ONE, 0.05)
	for offset_x: float in [6.0, -4.0, 2.0, 0.0]:
		tween.tween_property(view, ^"anim_offset", Vector2(offset_x, 0), 0.05)


## Undoes what a recoil or wind-up cut short may have left (a rigged
## figure's clip does the rest).
static func unsquash(tween: Tween, view: UnitView) -> void:
	tween.tween_property(view, ^"squash", Vector2.ONE, 0.08)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2.ZERO, 0.08)


## Turned to stone: a short squash, back to shape and to the cell centre
## (a wind-up cut short may have left it crouched).
static func stone_thud(tween: Tween, view: UnitView) -> void:
	tween.parallel().tween_property(view, ^"squash", Vector2(1.06, 0.94), 0.08)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2.ZERO, 0.08)
	tween.tween_property(view, ^"squash", Vector2.ONE, 0.1)


## Crouches over 60% of `seconds`, stretches up, and settles.
static func wind_up(tween: Tween, view: UnitView, seconds: float) -> void:
	tween.tween_property(view, ^"squash", Vector2(1.18, 0.82), seconds * 0.6).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2(0, 3), seconds * 0.6)
	tween.tween_property(view, ^"squash", Vector2(0.9, 1.14), seconds * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2(0, -6), seconds * 0.4)
	tween.tween_property(view, ^"squash", Vector2.ONE, 0.12)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2.ZERO, 0.12)


## Jumps 14 px toward `direction` and back.
static func lunge(tween: Tween, view: UnitView, direction: Vector2) -> void:
	tween.tween_property(view, ^"anim_offset", direction.normalized() * 14.0, 0.08).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, ^"squash", Vector2.ONE, 0.08)
	tween.tween_property(view, ^"anim_offset", Vector2.ZERO, 0.14).set_ease(Tween.EASE_IN_OUT)


## Squashes and kicks 4 px back from `direction`.
static func recoil(tween: Tween, view: UnitView, direction: Vector2) -> void:
	tween.tween_property(view, ^"squash", Vector2(1.12, 0.9), 0.06)
	tween.parallel().tween_property(view, ^"anim_offset", -direction.normalized() * 4.0, 0.06)
	tween.tween_property(view, ^"squash", Vector2.ONE, 0.12)
	tween.parallel().tween_property(view, ^"anim_offset", Vector2.ZERO, 0.12)


## A quick squeeze in parallel with the hit flash.
static func flinch(tween: Tween, view: UnitView) -> void:
	tween.parallel().tween_property(view, ^"squash", Vector2(0.92, 1.06), 0.05)
	tween.tween_property(view, ^"squash", Vector2.ONE, 0.1)


## The boss's end: shakes while `stone` cracks, crumbles into a heap while
## `set_dust` (func(amount)) puffs dust, fades and hides the view.
static func crumble(tween: Tween, view: UnitView, stone: StoneLayer, set_dust: Callable) -> void:
	for offset_x: float in [-5.0, 5.0, -4.0, 4.0, -2.0, 0.0]:
		tween.tween_property(view, ^"anim_offset", Vector2(offset_x, 0), 0.06)
	tween.parallel().tween_property(stone, ^"cracks", 1.0, 0.36)
	tween.tween_property(view, ^"squash", Vector2(1.25, 0.15), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_method(set_dust, 0.0, 1.0, 0.6)
	tween.tween_property(view, ^"modulate:a", 0.0, 0.3)
	tween.tween_callback(view.hide)


## Two happy hops after a short random wait.
static func cheer(tween: Tween, view: UnitView) -> void:
	tween.tween_interval(randf() * 0.15)
	for hop: int in 2:
		tween.tween_property(view, ^"anim_offset", Vector2(0, -16), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(view, ^"squash", Vector2(0.9, 1.12), 0.14)
		tween.tween_property(view, ^"anim_offset", Vector2.ZERO, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(view, ^"squash", Vector2(1.15, 0.85), 0.05)
		tween.tween_property(view, ^"squash", Vector2.ONE, 0.08)
