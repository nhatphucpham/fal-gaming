class_name DragGhost
extends Node2D
## The unit figure that follows the pointer while a card or a placed unit is
## dragged. It floats above the finger so the finger does not hide it; the
## drop point is its feet (see get_drop_point()).

## How far above the pointer the figure's feet float.
const LIFT := Vector2(0.0, -56.0)
const GHOST_SCALE: float = 1.15

var unit: UnitData
var facing: int = UnitPainter.FACING_UP
var _tween: Tween


func _ready() -> void:
	hide()


## Shows the ghost for `unit_data` at the pointer.
func begin(unit_data: UnitData, global_pointer: Vector2) -> void:
	unit = unit_data
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0
	scale = Vector2(0.6, 0.6)
	follow(global_pointer)
	show()
	queue_redraw()
	_tween = create_tween()
	_tween.tween_property(self, ^"scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func follow(global_pointer: Vector2) -> void:
	position = _to_local_space(global_pointer)


## The global point a drop is tested at: the centre of the cell the figure
## appears to stand in (its feet stand below a cell centre on the board).
func get_drop_point(global_pointer: Vector2) -> Vector2:
	return global_pointer + LIFT - UnitView.FEET


## Hides at once; the board takes over showing the unit.
func finish() -> void:
	if _tween != null:
		_tween.kill()
	hide()


## Flies back to `global_home` (a cell or portrait centre), shakes and
## fades: the drop was refused.
func reject(global_home: Vector2) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	var home := _to_local_space(global_home) + UnitView.FEET - LIFT
	_tween.tween_property(self, ^"position", home, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for offset_x: float in [-8.0, 7.0, -4.0, 0.0]:
		_tween.tween_property(self, ^"position", home + Vector2(offset_x, 0), 0.04)
	_tween.tween_property(self, ^"modulate:a", 0.0, 0.1)
	_tween.tween_callback(hide)


func _draw() -> void:
	if unit == null:
		return
	var shadow := FigureBrush.ellipse(LIFT + Vector2(0, 2), 24.0, 8.0, 16)
	draw_colored_polygon(shadow, Color(Palette.INK, 0.3))
	UnitPainter.draw_figure(self, unit, facing, 0.0, LIFT, GHOST_SCALE)


func _to_local_space(global_point: Vector2) -> Vector2:
	var parent_item := get_parent() as CanvasItem
	if parent_item == null:
		return global_point
	return parent_item.get_global_transform_with_canvas().affine_inverse() * global_point
