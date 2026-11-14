class_name ResultBanner
extends Control
## The end-of-battle banner: slides in with "Thắng trận" or "Thua trận", an
## optional reason line, optional resource changes that count up (gold and
## supply won, morale lost), optional extra gold chips that pop in after
## them with a coin sound ("+1 chuỗi thắng") and one button ("Xếp lại"
## unless set).
## [codeblock]
## banner.button_pressed.connect(_return_to_setup)
## banner.present(true, "")
## banner.present(false, "", [[&"morale", -12]], "BUTTON_CONTINUE")
## banner.present(true, "", [[&"coin", 1]], "BUTTON_CONTINUE", [["chuỗi thắng", 1]])
## [/codeblock]

signal button_pressed()

const PANEL_WIDTH_PX: float = 560.0
const SLIDE_PX: float = 260.0
const EXTRA_SIZE := Vector2(300, 56)

var _shade: ColorRect
var _panel: PanelContainer
var _title: Label
var _reason: Label
var _button: PressButton
var _deltas_row: HBoxContainer
var _extras_row: HBoxContainer
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
	_deltas_row = HBoxContainer.new()
	_deltas_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_deltas_row.add_theme_constant_override(&"separation", 16)
	rows.add_child(_deltas_row)
	_extras_row = HBoxContainer.new()
	_extras_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_extras_row.add_theme_constant_override(&"separation", 12)
	rows.add_child(_extras_row)
	_button = PressButton.new()
	_button.text = "BUTTON_REARRANGE"
	_button.custom_minimum_size = Vector2(300, 88)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.theme_type_variation = &"PrimaryButton"
	_button.pressed.connect(func() -> void: button_pressed.emit())
	rows.add_child(_button)


## Slides the banner in. `reason_text` is shown under the title when not
## empty; each of `deltas` ([icon kind, amount]) counts up from 0 in a chip;
## each of `extras` ([caption, gold]) pops in after them as its own chip.
func present(is_win: bool, reason_text: String, deltas: Array = [], button_key: String = "BUTTON_REARRANGE", extras: Array = []) -> void:
	_button.text = button_key
	_show_deltas(deltas)
	_show_extras(extras, 0.35 + deltas.size() * 0.2)
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


func _show_deltas(deltas: Array) -> void:
	for child: Node in _deltas_row.get_children():
		child.queue_free()
	_deltas_row.visible = not deltas.is_empty()
	for index: int in deltas.size():
		var pair: Array = deltas[index]
		var chip := ResourceChip.new()
		chip.setup(pair[0])
		chip.custom_minimum_size = Vector2(130, 64)
		_deltas_row.add_child(chip)
		chip.set_value(0, false)
		var amount: int = pair[1]
		chip.is_signed = true
		# Count up after the banner has landed, one chip after another.
		var tween := chip.create_tween()
		tween.tween_interval(0.35 + index * 0.2)
		tween.tween_callback(func() -> void: chip.set_value(amount))
		chip.modulate = Palette.CREAM if amount >= 0 else Color("ffb4a6")


# Gold chips with a caption, after the deltas: each pops from small with
# the coin sound.
func _show_extras(extras: Array, start_sec: float) -> void:
	for child: Node in _extras_row.get_children():
		child.queue_free()
	_extras_row.visible = not extras.is_empty()
	for index: int in extras.size():
		var extra: Array = extras[index]
		var chip := ResourceChip.new()
		chip.setup(&"coin", " " + String(extra[0]))
		chip.is_signed = true
		chip.custom_minimum_size = EXTRA_SIZE
		_extras_row.add_child(chip)
		chip.set_value(extra[1], false)
		chip.pivot_offset = EXTRA_SIZE / 2.0
		chip.scale = Vector2(0.2, 0.2)
		chip.modulate.a = 0.0
		var tween := chip.create_tween()
		tween.tween_interval(start_sec + index * 0.25)
		tween.tween_callback(func() -> void: Sound.play(&"coin"))
		tween.tween_property(chip, ^"modulate:a", 1.0, 0.1)
		tween.parallel().tween_property(chip, ^"scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _restart_tween() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
