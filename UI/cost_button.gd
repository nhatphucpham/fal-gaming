class_name CostButton
extends PressButton
## A button with a title over a drawn cost ("Làm mới" over a coin and 2).
## When the player cannot afford it, it looks disabled but stays pressable:
## a press then shakes it (refuse()) and the screen flashes the lacking
## resource, so the player learns why.
## [codeblock]
## button.setup("BUTTON_REFRESH", &"coin")
## button.set_cost(2, run.gold >= 2)
## [/codeblock]

const COST_ICON_PX: float = 26.0

var _title: Label
var _cost: Label
var _icon: Control
var _icon_kind: StringName = &"coin"
var _is_affordable: bool = true
var _shake_tween: Tween
var _rest_x: float = 0.0


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(120, 88)
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override(&"separation", -2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	_title = _make_label(21)
	rows.add_child(_title)
	var cost_row := HBoxContainer.new()
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_theme_constant_override(&"separation", 4)
	rows.add_child(cost_row)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(COST_ICON_PX, COST_ICON_PX)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(func() -> void: IconPainter.draw(_icon, _icon_kind, _icon.size / 2.0, COST_ICON_PX))
	cost_row.add_child(_icon)
	_cost = _make_label(26)
	cost_row.add_child(_cost)


func setup(title_key: String, icon_kind: StringName) -> void:
	_title.text = title_key
	_icon_kind = icon_kind
	_icon.queue_redraw()


## Shows the price; an unaffordable price dims the button. A negative
## amount hides the price row (nothing left to buy).
func set_cost(amount: int, is_affordable: bool) -> void:
	_cost.text = str(amount)
	_icon.visible = amount >= 0
	_cost.visible = amount >= 0
	if is_affordable == _is_affordable:
		return
	_is_affordable = is_affordable
	create_tween().tween_property(self, ^"modulate", Color.WHITE if is_affordable else Color(0.62, 0.62, 0.68), 0.15)


func is_affordable() -> bool:
	return _is_affordable


## Shakes: the press was refused.
func refuse() -> void:
	if _shake_tween != null and _shake_tween.is_running():
		_shake_tween.kill()
	else:
		_rest_x = position.x
	position.x = _rest_x
	_shake_tween = create_tween()
	for offset_x: float in [-8.0, 7.0, -5.0, 3.0, 0.0]:
		_shake_tween.tween_property(self, ^"position:x", _rest_x + offset_x, 0.045)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_outline_color", Palette.INK)
	label.add_theme_constant_override(&"outline_size", 4)
	return label
