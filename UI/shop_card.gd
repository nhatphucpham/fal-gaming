class_name ShopCard
extends Control
## One shop offer: the unit's bust on its cost colour, its name and a coin
## with the price. Cost 4 and 5 glow; a card whose purchase would merge
## shows two pulsing stars, one that would raise a class or race milestone
## or complete a formation a jade link badge; an empty (bought) slot is a
## faint outline. Input is handled by the ShopBar; the card only draws and
## animates.

const CARD_SIZE := Vector2(128, 156)
const PORTRAIT_PX := Vector2(116, 100)
const GLOW_FROM_COST: int = 4
const NAME_FONT_SIZE: int = 18
const NAME_MIN_FONT_SIZE: int = 13

var unit: UnitData
var is_selected: bool = false:
	set(value):
		is_selected = value
		_animate_scale(Vector2(1.06, 1.06) if value else Vector2.ONE)
		queue_redraw()

var _name_label: Label
var _is_affordable: bool = true
var _merge_hint: bool = false
var _synergy_hint: bool = false
var _time: float = 0.0
var _tween: Tween


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override(&"font_outline_color", Palette.INK)
	_name_label.add_theme_constant_override(&"outline_size", 4)
	_name_label.position = Vector2(4, PORTRAIT_PX.y + 6)
	_name_label.size = Vector2(CARD_SIZE.x - 40, CARD_SIZE.y - PORTRAIT_PX.y - 8)
	add_child(_name_label)


## Shows `unit_data`, or an empty slot for null.
func set_unit(unit_data: UnitData) -> void:
	unit = unit_data
	_name_label.text = tr(unit_data.name_key) if unit_data != null else ""
	_fit_name()
	_merge_hint = false
	_synergy_hint = false
	queue_redraw()


func set_affordable(value: bool) -> void:
	if value != _is_affordable:
		_is_affordable = value
		queue_redraw()


## Two pulsing stars: buying this card merges at once.
func set_merge_hint(value: bool) -> void:
	_merge_hint = value
	queue_redraw()


## A jade badge: buying this card raises a milestone or completes a
## formation one unit short.
func set_synergy_hint(value: bool) -> void:
	if value != _synergy_hint:
		_synergy_hint = value
		queue_redraw()


func has_synergy_hint() -> bool:
	return _synergy_hint


## Turns over into view after `delay_sec` (a reroll).
func flip_in(delay_sec: float) -> void:
	_kill_tween()
	scale = Vector2(0.0, 1.0)
	_tween = create_tween()
	_tween.tween_interval(delay_sec)
	_tween.tween_property(self, ^"scale", Vector2(1.08, 1.0), 0.14).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"scale", Vector2.ONE, 0.1)


## Centre of the portrait in global canvas coordinates.
func get_portrait_center() -> Vector2:
	return get_global_transform_with_canvas() * Vector2(CARD_SIZE.x / 2.0, 6.0 + PORTRAIT_PX.y / 2.0)


func _process(delta: float) -> void:
	if unit != null and (unit.cost >= GLOW_FROM_COST or _merge_hint):
		_time += delta
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	if unit == null:
		draw_rect(rect.grow(-6.0), Color(Palette.PANEL, 0.5))
		draw_rect(rect.grow(-6.0), Color(Palette.TEXT_DIM, 0.25), false, 2.0)
		return
	var fill := Palette.cost_color(unit.cost)
	if unit.cost >= GLOW_FROM_COST:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		for ring: int in 3:
			draw_rect(rect.grow(2.0 + ring * 2.5), Color(Palette.GOLD, (0.45 - ring * 0.13) * (0.6 + 0.4 * pulse)), false, 3.0)
	var box := GameTheme.make_panel(fill.darkened(0.25) if _is_affordable else fill.darkened(0.6), 16, 5)
	box.border_color = Palette.GOLD if is_selected else Palette.INK
	box.set_border_width_all(4 if is_selected else 3)
	box.border_width_bottom = 6
	box.draw(get_canvas_item(), rect)
	var portrait := Rect2(Vector2((CARD_SIZE.x - PORTRAIT_PX.x) / 2.0, 6.0), PORTRAIT_PX)
	draw_rect(portrait, fill if _is_affordable else fill.darkened(0.45))
	draw_circle(portrait.get_center() + Vector2(0, -8), 34.0, Color(fill.lightened(0.3), 0.9 if _is_affordable else 0.4))
	UnitPainter.draw_bust(self, unit, portrait.get_center() + Vector2(0, 14), 1.6)
	draw_rect(portrait, Palette.INK, false, 2.0)
	var coin := Vector2(CARD_SIZE.x - 22.0, CARD_SIZE.y - 26.0)
	IconPainter.draw(self, &"coin", coin, 30.0)
	_draw_cost_number(coin)
	if _merge_hint:
		var lift := sin(_time * 5.0) * 3.0
		UnitPainter.draw_star_pips(self, Vector2(CARD_SIZE.x / 2.0, 14.0 + lift), 2, 9.0)
	if _synergy_hint:
		_draw_synergy_badge(Vector2(20.0, 20.0))


# Two linked rings on a jade disc, in the portrait's top-left corner.
func _draw_synergy_badge(center: Vector2) -> void:
	draw_circle(center, 14.0, Palette.INK)
	draw_circle(center, 12.0, Palette.JADE)
	draw_arc(center + Vector2(-3.5, 0), 5.5, 0.0, TAU, 16, Palette.CREAM, 2.5, true)
	draw_arc(center + Vector2(3.5, 0), 5.5, 0.0, TAU, 16, Palette.CREAM, 2.5, true)


func _draw_cost_number(coin: Vector2) -> void:
	var font := get_theme_default_font()
	var text := str(unit.cost)
	var font_size := 22
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := coin + Vector2(-width / 2.0, 8.0)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Palette.INK)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.CREAM)


func _animate_scale(target: Vector2) -> void:
	if not is_inside_tree():
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, ^"scale", target, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


# One line always: a long name gets a smaller font instead of a second line.
func _fit_name() -> void:
	var font := _name_label.get_theme_font(&"font")
	var font_size := NAME_FONT_SIZE
	while font_size > NAME_MIN_FONT_SIZE and font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > _name_label.size.x - 8.0:
		font_size -= 1
	_name_label.add_theme_font_size_override(&"font_size", font_size)
