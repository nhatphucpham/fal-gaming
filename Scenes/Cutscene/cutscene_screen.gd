class_name CutsceneScreen
extends Control
## Plays a CutsceneData over the current screen: the band is wiped in with
## ink, the two speakers stand on it at 4-5x and breathe, and each line
## types out under the band. A tap finishes the line, the next tap moves
## on. "Bỏ qua" skips the lines but never the choice: a cutscene with
## choices always ends on its two cards, and a gold flash marks the one
## taken. `finished` gives the choice (-1 without choices) once the ink has
## wiped the band away. See Docs/systems/cutscene.md.
## [codeblock]
## var cutscene := CutsceneScreen.new()
## add_child(cutscene)
## cutscene.finished.connect(_on_cutscene_finished)
## cutscene.present(data, catalog, tr("EPIPHANY_TITLE"))
## [/codeblock]

signal finished(choice: int)

const CHARS_PER_SEC: float = 38.0
const BLIP_EVERY_CHARS: int = 3
const FIGURE_SCALE: float = 4.4
const WIPE_SEC: float = 0.45
const BAND_TOP: float = 0.17
const BAND_BOTTOM: float = 0.58
const BOX_TOP: float = 0.61
const BOX_BOTTOM: float = 0.8
const SIDE_MARGIN_PX: float = 24.0
const QUIET_TINT := Color(0.55, 0.55, 0.6)

var _data: CutsceneData
var _band: Control
var _backdrop: CutsceneBackdrop
var _wipe: InkWipe
var _figures: Array[UnitFigure] = []
var _title: Label
var _box: PanelContainer
var _speaker_label: Label
var _line_label: Label
var _next_mark: Control
var _skip_button: PressButton
var _cards_row: HBoxContainer
var _cards: Array[CutsceneChoiceCard] = []
var _flash: ColorRect
var _line_index: int = -1
var _shown_chars: float = 0.0
var _last_blip: int = 0
var _time: float = 0.0
var _is_busy: bool = true
var _is_choosing: bool = false
var _is_done: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GameTheme.create()
	var shade := ColorRect.new()
	shade.color = Color(Palette.BACKDROP, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override(&"font_size", 46)
	_title.add_theme_color_override(&"font_color", Palette.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_title, 0.0, 0.07, 1.0, BAND_TOP - 0.01)
	add_child(_title)
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.clip_contents = true
	_place(_band, 0.0, BAND_TOP, 1.0, BAND_BOTTOM)
	add_child(_band)
	_backdrop = CutsceneBackdrop.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.add_child(_backdrop)
	for side: int in 2:
		var figure := UnitFigure.new()
		figure.facing = UnitPainter.FACING_DOWN
		_band.add_child(figure)
		_figures.append(figure)
	_wipe = InkWipe.new()
	_wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.add_child(_wipe)
	_band.resized.connect(_place_figures)
	_build_box()
	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override(&"separation", 20)
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_row.visible = false
	_place(_cards_row, 0.0, BOX_TOP, 1.0, 0.9)
	add_child(_cards_row)
	_skip_button = PressButton.new()
	_skip_button.text = "CUTSCENE_SKIP"
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.custom_minimum_size = Vector2(150, 64)
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_right = 1.0
	_skip_button.offset_left = -150.0 - SIDE_MARGIN_PX
	_skip_button.offset_right = -SIDE_MARGIN_PX
	_skip_button.offset_top = 32.0
	_skip_button.offset_bottom = 96.0
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)
	_flash = ColorRect.new()
	_flash.color = Color(Palette.GOLD, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


## Starts `data`: the band wipes in, then the first line types out.
## `title` is shown over the band (empty for none).
func present(data: CutsceneData, catalog: Catalog, title: String = "") -> void:
	_data = data
	_title.text = title
	_backdrop.kind = data.backdrop
	var units: Array[StringName] = [data.left_unit, data.right_unit]
	for side: int in 2:
		var unit := _speaker_unit(units[side], catalog)
		_figures[side].unit = unit
		_figures[side].set_meta(&"name", tr(unit.name_key) if unit != null else "")
	_place_figures()
	_line_index = -1
	_is_busy = true
	_is_choosing = false
	_is_done = false
	_box.visible = true
	_cards_row.visible = false
	_skip_button.visible = true
	modulate.a = 0.0
	_wipe.is_closing = false
	_wipe.cover = 1.0
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, 0.15)
	tween.tween_property(_wipe, ^"cover", 0.0, WIPE_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		_is_busy = false
		_next_line())


## A tap: finishes the typing line, or goes to the next line (or to the
## choice, or ends). Ignored while the ink moves or the cards are up.
func tap() -> void:
	if _is_busy or _is_choosing or _is_done or _data == null:
		return
	if not is_line_complete():
		_shown_chars = _line_label.get_total_character_count()
		_line_label.visible_characters = -1
		return
	_next_line()


## Skips the remaining lines: to the cards when there is a choice, else
## the cutscene ends.
func skip() -> void:
	if _is_busy or _is_choosing or _is_done or _data == null:
		return
	Sound.play(&"ui_tap")
	_line_index = _data.line_keys.size()
	_next_line()


## Takes choice `index` (0 or 1), as if its card was tapped. False when no
## choice is up.
func choose(index: int) -> bool:
	if not _is_choosing or index < 0 or index >= _cards.size():
		return false
	_is_choosing = false
	Sound.play(&"epiphany")
	var card := _cards[index]
	_flash.color = Color(Palette.GOLD, 0.75)
	var tween := create_tween()
	tween.tween_property(_flash, ^"color:a", 0.0, 0.45)
	tween.parallel().tween_property(card, ^"scale", Vector2(1.12, 1.12), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for other: CutsceneChoiceCard in _cards:
		if other != card:
			tween.parallel().tween_property(other, ^"modulate:a", 0.0, 0.25)
	tween.tween_interval(0.2)
	tween.tween_callback(_close.bind(index))
	return true


## Index of the line shown now (-1 before the first).
func get_line_index() -> int:
	return _line_index


## The text of the line as far as it has typed.
func get_visible_text() -> String:
	if _line_label.visible_characters < 0:
		return _line_label.text
	return _line_label.text.left(_line_label.visible_characters)


func is_line_complete() -> bool:
	return _line_label.visible_characters < 0 or _line_label.visible_characters >= _line_label.get_total_character_count()


func is_choosing() -> bool:
	return _is_choosing


func is_done() -> bool:
	return _is_done


## The two cards' texts while choosing (tests, screenshots).
func get_choice_texts() -> Array[String]:
	var texts: Array[String] = []
	for card: CutsceneChoiceCard in _cards:
		texts.append(card.get_text())
	return texts


func _process(delta: float) -> void:
	_time += delta
	_breathe()
	_next_mark.visible = not _is_busy and not _is_choosing and _line_index >= 0 and is_line_complete()
	_next_mark.queue_redraw()
	if _is_busy or _is_choosing or is_line_complete():
		return
	_shown_chars += delta * CHARS_PER_SEC
	var count := int(_shown_chars)
	_line_label.visible_characters = count
	if count - _last_blip >= BLIP_EVERY_CHARS:
		_last_blip = count
		Sound.play(&"text_blip")


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	var is_release := mouse != null and not mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if is_release or (touch != null and not touch.pressed):
		accept_event()
		tap()


func _next_line() -> void:
	_line_index += 1
	if _line_index >= _data.line_keys.size():
		if _data.has_choices():
			_show_choices()
		else:
			_close(-1)
		return
	var speaker: int = _data.line_speakers[_line_index] if _line_index < _data.line_speakers.size() else CutsceneData.LEFT
	_speaker_label.text = _figures[speaker].get_meta(&"name", "")
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if speaker == CutsceneData.LEFT else HORIZONTAL_ALIGNMENT_RIGHT
	_line_label.text = tr(_data.line_keys[_line_index])
	_line_label.visible_characters = 0
	_shown_chars = 0.0
	_last_blip = 0
	for side: int in 2:
		var tween := create_tween()
		tween.tween_property(_figures[side], ^"modulate", Color.WHITE if side == speaker else QUIET_TINT, 0.15)


func _show_choices() -> void:
	_is_choosing = true
	_box.visible = false
	_skip_button.visible = false
	for card: CutsceneChoiceCard in _cards:
		card.queue_free()
	_cards.clear()
	for index: int in _data.choice_titles.size():
		var card := CutsceneChoiceCard.new()
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		card.setup(tr(_data.choice_titles[index]), tr(_data.choice_texts[index]))
		card.chosen.connect(func() -> void: choose(index))
		_cards_row.add_child(card)
		_cards.append(card)
		card.modulate.a = 0.0
		card.scale = Vector2(0.7, 0.7)
		var tween := create_tween()
		tween.tween_property(card, ^"modulate:a", 1.0, 0.2).set_delay(0.08 * index)
		tween.parallel().tween_property(card, ^"scale", Vector2.ONE, 0.3).set_delay(0.08 * index).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cards_row.visible = true
	for figure: UnitFigure in _figures:
		figure.modulate = Color.WHITE


func _close(choice: int) -> void:
	_is_busy = true
	_is_choosing = false
	_skip_button.visible = false
	_wipe.is_closing = true
	_wipe.cover = 0.0
	var tween := create_tween()
	tween.tween_property(_wipe, ^"cover", 1.0, WIPE_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, ^"modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		_is_done = true
		visible = false
		finished.emit(choice))


func _breathe() -> void:
	for side: int in _figures.size():
		var figure := _figures[side]
		var breath := sin(_time * 2.2 + side * 1.7) * 0.03
		var lift := 1.06 if not _is_choosing and _line_index >= 0 and figure.modulate == Color.WHITE else 1.0
		# The right speaker is mirrored so the two face each other.
		var mirror := -1.0 if side == CutsceneData.RIGHT else 1.0
		figure.scale = Vector2(mirror * (1.0 - breath * 0.4), 1.0 + breath) * FIGURE_SCALE * lift


func _place_figures() -> void:
	var ground := _backdrop.get_ground_y() if _backdrop.size.y > 0.0 else _band.size.y * CutsceneBackdrop.GROUND_RATIO
	for side: int in _figures.size():
		_figures[side].position = Vector2(_band.size.x * (0.27 if side == CutsceneData.LEFT else 0.73), ground + 8.0)


func _speaker_unit(unit_id: StringName, catalog: Catalog) -> UnitData:
	if unit_id == ExtraFigures.SAGE_UNIT_ID:
		return ExtraFigures.make_sage()
	return catalog.get_unit(unit_id) if catalog != null else null


func _build_box() -> void:
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_stylebox_override(&"panel", GameTheme.make_panel(Palette.PANEL, 20, 6))
	_place(_box, 0.0, BOX_TOP, 1.0, BOX_BOTTOM)
	_box.offset_left = SIDE_MARGIN_PX
	_box.offset_right = -SIDE_MARGIN_PX
	add_child(_box)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 6)
	_box.add_child(rows)
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override(&"font_size", 30)
	_speaker_label.add_theme_color_override(&"font_color", Palette.GOLD)
	rows.add_child(_speaker_label)
	_line_label = Label.new()
	_line_label.add_theme_font_size_override(&"font_size", 30)
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	rows.add_child(_line_label)
	# The "next" triangle bobs in the box's bottom right corner.
	_next_mark = Control.new()
	_next_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_next_mark, 1.0, BOX_BOTTOM, 1.0, BOX_BOTTOM)
	_next_mark.offset_left = -SIDE_MARGIN_PX - 52.0
	_next_mark.offset_top = -40.0
	_next_mark.offset_right = -SIDE_MARGIN_PX - 28.0
	_next_mark.offset_bottom = -20.0
	_next_mark.draw.connect(func() -> void:
		var bob := sin(_time * 6.0) * 3.0
		_next_mark.draw_colored_polygon(PackedVector2Array([Vector2(0, bob), Vector2(24, bob), Vector2(12, 16 + bob)]), Palette.GOLD))
	add_child(_next_mark)


# Anchors `control` to a fraction of the screen.
func _place(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
