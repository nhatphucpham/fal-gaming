class_name TacticsBanner
extends Control
## The phase banner over the tactics map: "Lượt ta" or "Lượt địch" with the
## round, sliding in across a band of our colour or the enemy's. It does
## not catch taps; the playback shows and hides it.

## The battle's round limit, shown as "Vòng 3/30".
var max_rounds: int = 30

var _band: ColorRect
var _title: Label
var _subtitle: Label
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_band = ColorRect.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.anchor_right = 1.0
	_band.anchor_top = 0.4
	_band.anchor_bottom = 0.52
	add_child(_band)
	_title = _make_label(64)
	_title.anchor_top = 0.0
	_title.anchor_bottom = 0.68
	_band.add_child(_title)
	_subtitle = _make_label(26)
	_subtitle.anchor_top = 0.62
	_subtitle.anchor_bottom = 1.0
	_band.add_child(_subtitle)


func present(title: String, subtitle: String, is_ours: bool) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_band.color = Color(TacticsPainter.PLAYER_DARK if is_ours else TacticsPainter.ENEMY_DARK, 0.92)
	visible = true
	_band.position.x = -size.x
	_band.modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_band, ^"position:x", 0.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func dismiss() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_band, ^"modulate:a", 0.0, 0.15)
	_tween.tween_callback(hide)


func _make_label(font_px: int) -> Label:
	var label := Label.new()
	label.anchor_right = 1.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_px)
	label.add_theme_color_override(&"font_color", Palette.CREAM)
	label.add_theme_color_override(&"font_outline_color", Palette.INK)
	label.add_theme_constant_override(&"outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
