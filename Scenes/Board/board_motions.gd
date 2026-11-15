class_name BoardMotions
extends RefCounted
## The steps of a UnitView moving across the board: gliding (walk, charge,
## knockback), hopping and flying off when sold. Each adds steps to the
## view's motion tween (made at the battle speed) and moves the view's
## `position`, `bob`, `lean` and `squash`; the view tells its PoseAnimator.
## A rigged figure bobs in its own run cycle, so its glides do not bob.


## Walk or charge (`kind`) to `target` over `seconds`: the run bobs once a
## cell, a charge stretches and bobs twice as fast; a knockback skids,
## tilting back, and straightens.
static func glide(tween: Tween, view: UnitView, target: Vector2, seconds: float, kind: StringName, is_rigged: bool) -> void:
	var from := view.position
	match kind:
		&"charge":
			if not is_rigged:
				view.squash = Vector2(0.9, 1.1)
			tween.tween_method(_run_step.bind(view, from, target, 2.0, 0.0 if is_rigged else 6.0), 0.0, 1.0, seconds)
			tween.tween_property(view, ^"squash", Vector2.ONE, 0.1)
		&"knockback":
			tween.tween_property(view, ^"position", target, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(view, ^"lean", -0.2, seconds * 0.5)
			tween.tween_property(view, ^"lean", 0.0, 0.12)
		_:
			var cells := maxf(1.0, from.distance_to(target) / 80.0)
			tween.tween_method(_run_step.bind(view, from, target, cells, 0.0 if is_rigged else 4.0), 0.0, 1.0, seconds)


## An arc to `target` over `seconds`, higher for a longer jump.
static func hop(tween: Tween, view: UnitView, target: Vector2, seconds: float) -> void:
	tween.tween_method(_hop_step.bind(view, view.position, target), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Flies to `target` while shrinking away, then frees the view.
static func shrink(tween: Tween, view: UnitView, target: Vector2, seconds: float) -> void:
	tween.tween_property(view, ^"position", target, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(view, ^"squash", Vector2(0.15, 0.15), seconds).set_ease(Tween.EASE_IN)
	tween.tween_callback(view.queue_free)


# A glide's step: `bobs` hops of `height` px on the way.
static func _run_step(progress: float, view: UnitView, from: Vector2, target: Vector2, bobs: float, height: float) -> void:
	view.position = from.lerp(target, progress)
	view.bob = absf(sin(progress * PI * bobs)) * height


static func _hop_step(progress: float, view: UnitView, from: Vector2, target: Vector2) -> void:
	view.position = from.lerp(target, progress)
	view.bob = sin(progress * PI) * minf(40.0, 12.0 + from.distance_to(target) * 0.12)
