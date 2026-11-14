class_name TitleScreen
extends Control
## The title screen: the game name over a few idle unit figures, "Ván mới",
## "Chơi tiếp" (only when a save exists), "Bàn thử" (the sandbox), "Cách
## chơi", the preparation-time setting and the sound switch (both stored in
## user://settings.json). Its first tap unlocks audio (the web needs a
## gesture first).

signal new_run_requested()
signal continue_requested()
signal sandbox_requested()

## Who stands on the title backdrop, and where (fractions of the column).
const FIGURES: Array[Array] = [
	[&"unit.shield_guard", Vector2(0.18, 0.4)], [&"unit.wolf_rider", Vector2(0.82, 0.38)],
	[&"unit.archer", Vector2(0.34, 0.47)], [&"unit.lac_hong", Vector2(0.66, 0.47)],
	[&"unit.moon_spear", Vector2(0.5, 0.39)],
]

var has_save: bool = false
var catalog: Catalog
var prep_seconds: int = RunSettings.DEFAULT_PREP_SECONDS
var _time_button: PressButton
## "Cách chơi" while it is open, else null.
var how_to: HowToScreen
var _figures: Array[UnitView] = []
var _time: float = 0.0


func _ready() -> void:
	theme = GameTheme.create()
	var backdrop := Backdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var column := Control.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_bottom = 1.0
	column.offset_left = -360.0
	column.offset_right = 360.0
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_add_figures(column)
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override(&"separation", 18)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rows)
	rows.add_child(_spacer(0.12))
	var title := Label.new()
	title.text = "GAME_TITLE"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override(&"font_size", 110)
	title.add_theme_constant_override(&"outline_size", 14)
	title.add_theme_color_override(&"font_color", Palette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	rows.add_child(_spacer(0.5))
	if has_save:
		rows.add_child(_button("BUTTON_CONTINUE_RUN", continue_requested.emit, true))
	rows.add_child(_button("BUTTON_NEW_RUN", new_run_requested.emit, not has_save))
	var pair := _pair_row(rows)
	pair.add_child(_button("BUTTON_SANDBOX", sandbox_requested.emit, false, true))
	pair.add_child(_button("BUTTON_HOWTO", open_how_to, false, true))
	pair = _pair_row(rows)
	_time_button = _button("", cycle_prep_time, false, true)
	pair.add_child(_time_button)
	var mute := MuteButton.new()
	mute.shows_text = true
	mute.custom_minimum_size = Vector2(232, 96)
	mute.add_theme_font_size_override(&"font_size", 24)
	pair.add_child(mute)
	rows.add_child(_spacer(0.08))
	_update_time_label()
	Sound.play_music(&"music_prep")


func _input(event: InputEvent) -> void:
	# The browser allows sound only after a gesture: the first one is it.
	if not Sound.is_unlocked() and (event is InputEventMouseButton or event is InputEventScreenTouch):
		Sound.unlock()


func open_how_to() -> HowToScreen:
	if how_to == null:
		how_to = HowToScreen.new()
		how_to.closed.connect(func() -> void: how_to = null)
		add_child(how_to)
	return how_to


## The next preparation time (60 s, 90 s, unlimited), saved at once.
func cycle_prep_time() -> void:
	prep_seconds = RunSettings.next_prep_seconds(prep_seconds)
	RunSettings.save_prep_seconds(prep_seconds)
	_update_time_label()


func _process(delta: float) -> void:
	# Now and then a figure hops or cheers, so the backdrop is never still.
	_time += delta
	if _time > 1.6 and not _figures.is_empty():
		_time = 0.0
		var figure := _figures[randi() % _figures.size()]
		if randf() < 0.5:
			figure.cheer()
		else:
			figure.lunge(Vector2(randf_range(-1.0, 1.0), -0.3))


func _add_figures(column: Control) -> void:
	var layer := Node2D.new()
	layer.y_sort_enabled = true
	column.add_child(layer)
	column.resized.connect(func() -> void: _place_figures(column))
	for entry: Array in FIGURES:
		var unit := catalog.get_unit(entry[0])
		if unit == null:
			continue
		var view := UnitView.new()
		# Star 0: no pips, these are decoration.
		view.setup(unit, Battle.SIDE_A if _figures.size() % 2 == 0 else Battle.SIDE_B, 0)
		view.is_hp_bar_shown = false
		view.scale = Vector2(1.5, 1.5)
		layer.add_child(view)
		_figures.append(view)
	_place_figures(column)


func _place_figures(column: Control) -> void:
	for index: int in _figures.size():
		var spot: Vector2 = FIGURES[index][1]
		_figures[index].position = Vector2(spot.x * column.size.x, spot.y * column.size.y)


func _update_time_label() -> void:
	var value := tr("PREP_UNLIMITED") if prep_seconds == 0 else tr("TIMER_FORMAT") % prep_seconds
	_time_button.text = tr("PREP_TIME_FORMAT") % value


func _button(text_key: String, action: Callable, is_primary: bool, is_half: bool = false) -> PressButton:
	var button := PressButton.new()
	button.text = text_key
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(232 if is_half else 480, 96)
	if is_half:
		button.add_theme_font_size_override(&"font_size", 24)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if is_primary:
		button.theme_type_variation = &"PrimaryButton"
	button.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		action.call())
	return button


# Two half-width buttons side by side.
func _pair_row(rows: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	rows.add_child(row)
	return row


func _spacer(ratio: float) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = ratio
	return spacer
