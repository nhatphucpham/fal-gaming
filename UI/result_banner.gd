class_name ResultBanner
extends Control
## The end-of-battle banner: slides in with "Thắng trận" or "Thua trận", an
## optional reason line and a "Xếp lại" button.
## [codeblock]
## banner.rearrange_pressed.connect(_return_to_setup)
## banner.present(true, "")
## [/codeblock]

signal rearrange_pressed()

const PANEL_WIDTH_PX: float = 560.0
const SLIDE_PX: float = 260.0

var _shade: ColorRect
var _panel: PanelContainer
var _title: Label
var _reason: Label
var _button: PressButton
var _win_box: StyleBoxFlat
var _loss_box: StyleBoxFlat
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_shade = ColorRect.new()
	_shade.color = Color(Palette.BACKDROP, 0.55)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_win_box = GameTheme.make_panel(Palette.JADE, 26, 10)
	_loss_box = GameTheme.make_panel(Palette.VERMILION_DARK, 26, 10)
	for box: StyleBoxFlat in [_win_box, _loss_box]:
		box.content_margin_top = 26
		box.content_margin_bottom = 26
		box.content_margin_left = 28
		box.content_margin_right = 28
	_panel = PanelContainer.new()
	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 14)
	_panel.add_child(rows)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override(&"font_size", 64)
	_title.add_theme_constant_override(&"outline_size", 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_title)
	_reason = Label.new()
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.add_theme_font_size_override(&"font_size", 24)
	# A wrapping label needs a fixed width, or it measures one word per line.
	_reason.custom_minimum_size = Vector2(PANEL_WIDTH_PX - 56.0, 0)
	rows.add_child(_reason)
	_button = PressButton.new()
	_button.text = "BUTTON_REARRANGE"
	_button.custom_minimum_size = Vector2(300, 84)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.theme_type_variation = &"PrimaryButton"
	_button.pressed.connect(func() -> void: rearrange_pressed.emit())
	rows.add_child(_button)


## Slides the banner in. `reason_text` is shown under the title when not empty.
func present(is_win: bool, reason_text: String) -> void:
	_title.text = "RESULT_WIN" if is_win else "RESULT_LOSS"
	_title.add_theme_color_override(&"font_color", Palette.GOLD if is_win else Palette.CREAM)
	_panel.add_theme_stylebox_override(&"panel", _win_box if is_win else _loss_box)
	_reason.text = reason_text
	_reason.visible = not reason_text.is_empty()
	visible = true
	_panel.size = Vector2(PANEL_WIDTH_PX, 0)
	_panel.reset_size()
	_panel.size.x = PANEL_WIDTH_PX
	var target := Vector2((size.x - PANEL_WIDTH_PX) / 2.0, size.y * 0.36 - _panel.get_combined_minimum_size().y / 2.0)
	_panel.position = target - Vector2(0, SLIDE_PX)
	_panel.modulate.a = 0.0
	_shade.modulate.a = 0.0
	_restart_tween()
	_tween.tween_property(_shade, ^"modulate:a", 1.0, 0.2)
	_tween.parallel().tween_property(_panel, ^"position", target, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_panel, ^"modulate:a", 1.0, 0.15)


## Slides the banner away.
func dismiss() -> void:
	if not visible:
		return
	_restart_tween()
	_tween.tween_property(_panel, ^"position:y", _panel.position.y - SLIDE_PX, 0.2).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_panel, ^"modulate:a", 0.0, 0.2)
	_tween.parallel().tween_property(_shade, ^"modulate:a", 0.0, 0.2)
	_tween.tween_callback(hide)


func _restart_tween() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
