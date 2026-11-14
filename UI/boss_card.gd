class_name BossCard
extends Control
## The boss card the top-bar badge opens: the boss drawn large, its name
## and stage, its rule in one sentence and a hint. Any tap closes it.
## [codeblock]
## boss_card.open(catalog.get_unit(&"unit.boss_cu_nham"), 12)
## [/codeblock]

const CARD_SIZE := Vector2(560, 700)
const FIGURE_SCALE: float = 3.2

var _card: Control
var _figure: UnitFigure
var _title: Label
var _rule: Label
var _hint: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(Palette.BACKDROP, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size = CARD_SIZE
	_card.pivot_offset = CARD_SIZE / 2.0
	_card.draw.connect(func() -> void:
		GameTheme.make_panel(Palette.CREAM, 26, 10).draw(_card.get_canvas_item(), Rect2(Vector2.ZERO, CARD_SIZE))
		_card.draw_rect(Rect2(24, 72, CARD_SIZE.x - 48, 330), Color("47607a"))
		_card.draw_rect(Rect2(24, 330, CARD_SIZE.x - 48, 72), Color("6f6a4a"))
		_card.draw_rect(Rect2(24, 72, CARD_SIZE.x - 48, 330), Palette.INK, false, 3.0))
	add_child(_card)
	_title = _label(36, Vector2(16, 14), Vector2(CARD_SIZE.x - 32, 52), Palette.VERMILION_DARK)
	_figure = UnitFigure.new()
	_figure.facing = UnitPainter.FACING_DOWN
	_figure.position = Vector2(CARD_SIZE.x / 2.0, 372)
	_figure.scale = Vector2.ONE * FIGURE_SCALE
	_card.add_child(_figure)
	_rule = _label(26, Vector2(28, 420), Vector2(CARD_SIZE.x - 56, 150), Palette.INK)
	_hint = _label(26, Vector2(28, 580), Vector2(CARD_SIZE.x - 56, 90), Palette.VERMILION_DARK)
	resized.connect(_center)


## Shows `boss`, met at stage `boss_stage`.
func open(boss: UnitData, boss_stage: int) -> void:
	_figure.unit = boss
	_title.text = tr("BOSS_CARD_TITLE") % [boss_stage, tr(boss.name_key)]
	_rule.text = tr("BOSS_RULE")
	_hint.text = tr("BOSS_HINT")
	visible = true
	_center()
	modulate.a = 0.0
	_card.scale = Vector2(0.85, 0.85)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, ^"modulate:a", 1.0, 0.15)
	tween.tween_property(_card, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	visible = false


func get_texts() -> PackedStringArray:
	return PackedStringArray([_title.text, _rule.text, _hint.text])


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and not mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		Sound.play(&"ui_tap")
		close()


func _center() -> void:
	_card.position = (size - CARD_SIZE) / 2.0


func _label(font_size: int, at: Vector2, label_size: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = at
	label.size = label_size
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	_card.add_child(label)
	return label
