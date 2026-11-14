class_name ConfettiBurst
extends Node2D
## A small burst of paper confetti (CPU-drawn, no particles node, so it runs
## on the web renderer): coloured slips fly out, flutter, fall and fade,
## then the node frees itself. Add it where the burst should be and call
## play().
## [codeblock]
## var burst := ConfettiBurst.new()
## layer.add_child(burst)
## burst.position = center
## burst.play()
## [/codeblock]

const PIECES: int = 18
const DURATION_SEC: float = 0.9
const GRAVITY_PX: float = 520.0
const COLORS: Array[Color] = [Palette.GOLD, Palette.VERMILION, Palette.JADE_LIGHT, Palette.CREAM, Color("7fa8e6")]

var _velocities: PackedVector2Array = PackedVector2Array()
var _spins: PackedFloat32Array = PackedFloat32Array()
var _colors: Array[Color] = []
var _progress: float = 0.0


## Starts the burst; `power` scales how far the slips fly.
func play(power: float = 1.0) -> void:
	for index: int in PIECES:
		var angle := -PI / 2.0 + randf_range(-1.25, 1.25)
		_velocities.append(Vector2(cos(angle), sin(angle)) * randf_range(160.0, 330.0) * power)
		_spins.append(randf_range(6.0, 16.0) * (1.0 if index % 2 == 0 else -1.0))
		_colors.append(COLORS[index % COLORS.size()])
	var tween := create_tween()
	tween.tween_method(_set_progress, 0.0, 1.0, DURATION_SEC)
	tween.tween_callback(queue_free)


func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()


func _draw() -> void:
	var seconds := _progress * DURATION_SEC
	var alpha := clampf(1.6 - _progress * 1.6, 0.0, 1.0)
	for index: int in _velocities.size():
		var drag := 1.0 - _progress * 0.55
		var point := _velocities[index] * seconds * drag + Vector2(0.0, 0.5 * GRAVITY_PX * seconds * seconds)
		var flutter := absf(cos(seconds * _spins[index]))
		var half := Vector2(6.0, 3.5 * flutter + 0.6)
		draw_set_transform(point, seconds * _spins[index] * 0.4)
		draw_rect(Rect2(-half, half * 2.0), Color(_colors[index], alpha))
	draw_set_transform(Vector2.ZERO)
