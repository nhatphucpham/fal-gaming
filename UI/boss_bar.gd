class_name BossBar
extends Control
## The boss's wide health bar, shown in the top bar in place of the stage
## title while the boss fights: its name over a long bar with a trailing
## hit band. Turned to stone (Hóa Đá) the bar goes grey and says so.
## [codeblock]
## boss_bar.present(tr(unit.name_key))
## boss_bar.show_hp(hp, max_hp)
## boss_bar.set_petrified(true)
## [/codeblock]

const BAR_HEIGHT_PX: float = 20.0

var _name_label: Label
var _state_label: Label
var _ratio: float = 1.0
var _trail: float = 1.0
var _is_petrified: bool = false
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(200, 64)
	_name_label = Label.new()
	_name_label.theme_type_variation = &"TitleLabel"
	_name_label.add_theme_font_size_override(&"font_size", 26)
	_name_label.add_theme_color_override(&"font_color", Palette.GOLD)
	_name_label.position = Vector2(0, 0)
	add_child(_name_label)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override(&"font_size", 22)
	_state_label.add_theme_color_override(&"font_color", Palette.STEEL)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_state_label.text = "STATUS_PETRIFIED"
	_state_label.visible = false
	add_child(_state_label)
	resized.connect(func() -> void:
		_state_label.position = Vector2(size.x - 160.0, 2.0)
		_state_label.size = Vector2(160.0, 30.0))


func present(boss_name: String) -> void:
	_name_label.text = boss_name
	_ratio = 1.0
	_trail = 1.0
	set_petrified(false)
	queue_redraw()


## Sets the bar to `hp` of `max_hp`; the trail catches up a moment later.
func show_hp(hp: int, max_hp: int) -> void:
	var ratio := clampf(float(hp) / maxi(1, max_hp), 0.0, 1.0)
	if is_equal_approx(ratio, _ratio):
		return
	_ratio = ratio
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(0.25)
	_tween.tween_method(func(value: float) -> void:
		_trail = value
		queue_redraw(), _trail, ratio, 0.3)
	queue_redraw()


func set_petrified(petrified: bool) -> void:
	_is_petrified = petrified
	_state_label.visible = petrified
	queue_redraw()


func get_ratio() -> float:
	return _ratio


func is_petrified() -> bool:
	return _is_petrified


func _draw() -> void:
	var frame := Rect2(4.0, size.y - BAR_HEIGHT_PX - 8.0, size.x - 8.0, BAR_HEIGHT_PX)
	draw_rect(frame.grow(3.0), Palette.INK)
	draw_rect(frame, Palette.PANEL)
	draw_rect(Rect2(frame.position, Vector2(frame.size.x * _trail, frame.size.y)), Palette.CREAM)
	var fill := ExtraFigures.STONE_LIGHT if _is_petrified else Palette.ENEMY_HP
	draw_rect(Rect2(frame.position, Vector2(frame.size.x * _ratio, frame.size.y)), fill)
	# Quarter ticks, so a big hit reads as a share of the boss.
	for quarter: int in [1, 2, 3]:
		var x := frame.position.x + frame.size.x * quarter / 4.0
		draw_line(Vector2(x, frame.position.y), Vector2(x, frame.end.y), Color(Palette.INK, 0.6), 2.0)
