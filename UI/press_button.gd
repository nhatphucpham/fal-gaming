class_name PressButton
extends Button
## A Button that sinks a little while held and springs back on release, so
## every press is felt within 0.1 s, on touch and mouse alike.

const PRESSED_SCALE := Vector2(0.94, 0.94)

var _tween: Tween


func _ready() -> void:
	button_down.connect(_animate_to.bind(PRESSED_SCALE, 0.06))
	button_up.connect(_animate_to.bind(Vector2.ONE, 0.16))
	resized.connect(func() -> void: pivot_offset = size / 2.0)
	pivot_offset = size / 2.0


## A quick bounce, for presses made through code (the same feedback).
func bounce() -> void:
	scale = PRESSED_SCALE
	_animate_to(Vector2.ONE, 0.16)


func _animate_to(target: Vector2, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"scale", target, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
