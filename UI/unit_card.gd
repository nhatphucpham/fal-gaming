class_name UnitCard
extends Control
## A roster card: a rounded square portrait of the unit (bust drawn by
## UnitPainter) on its cost colour, with the name under it. Input is handled
## by the strip that holds it; the card only draws and animates.

const CARD_SIZE := Vector2(112, 154)
const PORTRAIT_PX: float = 98.0
const BUST_SCALE: float = 1.65
const NAME_FONT_SIZE: int = 19

var unit: UnitData
var is_selected: bool = false:
	set(value):
		is_selected = value
		_animate_selection()
		queue_redraw()

var _portrait: Control
var _name_label: Label
var _tween: Tween


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait = Control.new()
	_portrait.clip_contents = true
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.position = Vector2((CARD_SIZE.x - PORTRAIT_PX) / 2.0, 4)
	_portrait.size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	_portrait.draw.connect(_draw_portrait)
	add_child(_portrait)
	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.max_lines_visible = 2
	_name_label.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	_name_label.add_theme_constant_override(&"line_spacing", -4)
	_name_label.position = Vector2(0, PORTRAIT_PX + 7)
	_name_label.size = Vector2(CARD_SIZE.x, CARD_SIZE.y - PORTRAIT_PX - 7)
	add_child(_name_label)


func setup(unit_data: UnitData) -> void:
	unit = unit_data
	_name_label.text = tr(unit_data.name_key)
	_portrait.queue_redraw()


## Centre of the portrait in global canvas coordinates.
func get_portrait_center() -> Vector2:
	return _portrait.get_global_transform_with_canvas() * (_portrait.size / 2.0)


## A quick squeeze, for taps.
func pop() -> void:
	scale = Vector2(0.9, 0.9)
	_animate_selection()


func _draw() -> void:
	if is_selected:
		var rect := Rect2(_portrait.position, _portrait.size).grow(6.0)
		var box := GameTheme.make_panel(Palette.GOLD, 22, 3)
		box.draw(get_canvas_item(), rect)


func _draw_portrait() -> void:
	var rect := Rect2(Vector2.ZERO, _portrait.size)
	var fill := Palette.cost_color(unit.cost if unit != null else 1)
	var box := GameTheme.make_panel(fill, 18, 3)
	box.draw_center = true
	box.set_border_width_all(0)
	box.draw(_portrait.get_canvas_item(), rect)
	# A pale disc behind the head, like a printed medallion.
	_portrait.draw_circle(rect.get_center() + Vector2(0, -8), 36.0, Color(fill.lightened(0.3), 0.9))
	if unit != null:
		UnitPainter.draw_bust(_portrait, unit, rect.get_center() + Vector2(0, 14), BUST_SCALE)
	var frame := GameTheme.make_panel(fill, 18, 5)
	frame.draw_center = false
	frame.draw(_portrait.get_canvas_item(), rect)


func _animate_selection() -> void:
	if not is_inside_tree():
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	var target := Vector2(1.06, 1.06) if is_selected else Vector2.ONE
	_tween.tween_property(self, ^"scale", target, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
