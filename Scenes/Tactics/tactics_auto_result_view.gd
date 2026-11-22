class_name TacticsAutoResultView
extends Control
## An Auto region, fought then told. With `auto` (a started
## TacticsAutoResolve) it opens on "Giao chiến": the battle runs a slice a
## frame (never more than FRAME_BUDGET_USEC of a frame, so a slow phone
## never freezes) while the two bars of who still stands drain live and a
## hit sounds as units fall; then `fought` carries the result and the world
## screen answers with show_summary(). With a `summary` it opens on the
## outcome: won or lost, how many stood on each side, who of ours was
## wounded and sits out the next battle (no one dies in Auto), the
## supplies, the reminder that Auto leaves no marks or bonds, and what the
## world turn changed. "Sổ quân" opens the roster; "Tiếp tục" goes back to
## the world map. Rows fade in one after another; the win or loss sound
## plays once. Only the bars redraw, while they move.
## [codeblock]
## var view := TacticsAutoResultView.new()
## view.campaign = campaign
## view.auto = auto  # or: view.summary = campaign.apply_auto(result)
## view.fought.connect(func(result: Dictionary) -> void: view.show_summary(campaign.apply_auto(result)))
## [/codeblock]

signal continue_requested()
## The battle (`auto`) is over: TacticsAutoResolve.get_result().
signal fought(result: Dictionary)

const FACE_PX: float = 44.0
const DRAIN_SEC: float = 0.8
## The fight plays at about this many battle ticks a second (a battle is
## 450..850 ticks: about a second).
const FIGHT_TICKS_PER_SEC: float = 650.0
## Most of a frame the fight may take.
const FRAME_BUDGET_USEC: int = 4000

var campaign: TacticsCampaign
## TacticsCampaign.apply_auto()'s result; empty while the battle runs.
var summary: Dictionary = {}
## A started TacticsAutoResolve to play before the summary, or null.
var auto: TacticsAutoResolve
## Tests and stills: no animation.
var is_instant: bool = false

var _body: VBoxContainer
var _page: VBoxContainer
var _title: Label
var _buttons: HBoxContainer
var _bars: Array[_Bar] = []
var _bar_labels: Array[Label] = []
var _fight_sec: float = 0.0
var _alive: Array[int] = []
var _ticks_run: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Palette.BACKDROP
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_page = VBoxContainer.new()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.offset_left = 16
	_page.offset_right = -16
	_page.offset_top = 16
	_page.offset_bottom = -16
	_page.add_theme_constant_override(&"separation", 8)
	add_child(_page)
	_title = TacticsViews.label("AUTO_TITLE_FIGHTING", 44, Palette.CREAM)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(_title)
	var subtitle := TacticsViews.label(TacticsWorldText.region_name(campaign.roster.world, campaign.region_id), 28, Palette.CREAM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_body)
	_body.add_child(_forces_panel())
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 16)
	_page.add_child(_buttons)
	if not is_instant:
		TacticsViews.slide_in(self)
	if summary.is_empty() and auto != null:
		Sound.play(&"battle_drum")
		set_process(true)
	else:
		set_process(false)
		show_summary(summary)


## Whether the battle is still being played here.
func is_fighting() -> bool:
	return summary.is_empty() and auto != null and not auto.is_finished()


## The outcome, after `fought`: the title, the bars at what stood, the
## wounded, supplies and the world turn, then the buttons.
func show_summary(result: Dictionary) -> void:
	summary = result
	set_process(false)
	var is_won: bool = summary.get("is_won", false)
	_title.text = "AUTO_TITLE_WIN" if is_won else "AUTO_TITLE_LOSS"
	_title.add_theme_color_override(&"font_color", Palette.GOLD if is_won else Palette.VERMILION.lightened(0.2))
	var counts: Array = summary.get("counts", [[0, 0, 0], [0, 0, 0]])
	for side: int in 2:
		_set_side(side, int(counts[side][0]), int(counts[side][1]), not is_instant)
	var rows: Array = [_wounded_panel(), _rewards_panel()]
	var lines := TacticsWorldText.change_lines(campaign.roster.world, summary.get("world", {}))
	if not lines.is_empty():
		rows.append(_world_panel(lines))
	for row: Control in rows:
		_body.add_child(row)
	_buttons.add_child(TacticsViews.button("BUTTON_ROSTER", open_roster, false))
	var go_on := TacticsViews.button("BUTTON_CONTINUE", continue_requested.emit, true)
	go_on.name = "ContinueButton"
	_buttons.add_child(go_on)
	Sound.play(&"win" if is_won else &"lose")
	if not is_instant:
		_title.pivot_offset = _title.size / 2.0
		_title.scale = Vector2(1.25, 1.25)
		_title.create_tween().tween_property(_title, ^"scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		TacticsViews.stagger_in(rows + [_buttons])


# The fight, a slice a frame: as many ticks as the pace asks for, within
# the frame budget; the bars follow who still stands.
func _process(delta: float) -> void:
	if not is_fighting():
		set_process(false)
		return
	_fight_sec += delta
	var wanted := int(_fight_sec * FIGHT_TICKS_PER_SEC)
	var started := Time.get_ticks_usec()
	var done := false
	var ran := 0
	while ran < wanted - _ticks_run and Time.get_ticks_usec() - started < FRAME_BUDGET_USEC:
		done = auto.advance(TacticsAutoResolve.TICKS_PER_CHUNK)
		ran += TacticsAutoResolve.TICKS_PER_CHUNK
		if done:
			break
	_ticks_run += ran
	var alive := auto.get_alive_counts()
	var placed := auto.get_placed_counts()
	if alive != _alive:
		if not _alive.is_empty():
			Sound.play(&"hit_heavy" if alive[0] < _alive[0] else &"hit_light")
		_alive = alive
		for side: int in 2:
			_set_side(side, alive[side], placed[side], false)
	if done:
		set_process(false)
		fought.emit(auto.get_result())


func open_roster() -> TacticsRosterView:
	var view := TacticsRosterView.new()
	view.campaign = campaign
	add_child(view)
	return view


func _forces_panel() -> Control:
	var box := TacticsViews.panel()
	box.name = "ForcesPanel"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	rows.add_child(TacticsViews.label("AUTO_FORCES", 28, Palette.GOLD))
	var placed: Array[int] = auto.get_placed_counts() if auto != null else [0, 0]
	var colors := [TacticsPainter.PLAYER_FILL, TacticsPainter.ENEMY_FILL]
	for side: int in 2:
		var line := TacticsViews.label("", 22, Palette.CREAM)
		_bar_labels.append(line)
		rows.add_child(line)
		var bar := _Bar.new()
		bar.color = colors[side]
		bar.custom_minimum_size = Vector2(0, 22)
		_bars.append(bar)
		rows.add_child(bar)
		_set_side(side, placed[side], placed[side], false)
	var fortune: int = auto.get_fortune() if auto != null else int(summary.get("fortune", 0))
	rows.add_child(TacticsViews.wrapped(tr("AUTO_FORTUNE_FORMAT") % fortune, 22, Palette.TEXT_DIM))
	return box


# One side's line and bar: `alive` of `placed` standing; `is_drained`
# drains the bar to it, else it is set at once.
func _set_side(side: int, alive: int, placed: int, is_drained: bool) -> void:
	var formats := ["AUTO_OURS_FORMAT", "AUTO_ENEMY_FORMAT"]
	_bar_labels[side].text = tr(formats[side]) % [alive, placed]
	var left := float(alive) / maxf(float(placed), 1.0)
	if is_drained:
		_bars[side].create_tween().tween_property(_bars[side], ^"value", left, DRAIN_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_bars[side].value = left


# The wounded as a wrap of faces under how many they are; the named ones
# (veterans with marks) by name too, as they are the ones missed.
func _wounded_panel() -> Control:
	var box := TacticsViews.panel()
	box.name = "WoundedPanel"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	var wounded: Array = summary.get("wounded", [])
	rows.add_child(TacticsViews.label(tr("AUTO_WOUNDED_FORMAT") % wounded.size(), 28, Palette.GOLD))
	if wounded.is_empty():
		rows.add_child(TacticsViews.wrapped(tr("AUTO_NO_WOUNDED"), 22, Palette.TEXT_DIM))
		return box
	var faces := HFlowContainer.new()
	faces.name = "WoundedFaces"
	faces.add_theme_constant_override(&"h_separation", 6)
	faces.add_theme_constant_override(&"v_separation", 6)
	rows.add_child(faces)
	var named: PackedStringArray = []
	for id: int in wounded:
		var person := campaign.get_person(id)
		var face := TacticsFace.FaceView.new()
		face.name = "Wounded%d" % id
		face.look = person["look"]
		face.ring = Palette.VERMILION
		face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
		faces.add_child(face)
		if person["is_named"]:
			named.append(campaign.bio.person_name(person))
	if not named.is_empty():
		rows.add_child(TacticsViews.wrapped(tr("AUTO_WOUNDED_NAMED_FORMAT") % ", ".join(named), 22, Palette.CREAM))
	return box


func _rewards_panel() -> Control:
	var box := TacticsViews.panel()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	box.add_child(rows)
	rows.add_child(TacticsViews.wrapped(tr("AUTO_SUPPLIES_FORMAT") % [summary.get("supplies", 0), summary.get("supplies_total", 0)], 24, Palette.GOLD))
	rows.add_child(TacticsViews.wrapped(tr("AUTO_NO_MARKS"), 22, Palette.TEXT_DIM))
	return box


func _world_panel(lines: PackedStringArray) -> Control:
	var box := TacticsViews.panel(Palette.INDIGO_DARK)
	box.name = "WorldPanel"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	box.add_child(rows)
	rows.add_child(TacticsViews.label("SUMMARY_WORLD", 28, Palette.GOLD))
	for line: String in lines:
		rows.add_child(TacticsViews.wrapped(line, 22, Palette.CREAM))
	return box


## A bar of what is left (0..1); redraws only when the value changes.
class _Bar extends Control:
	var color: Color = Palette.JADE
	var value: float = 1.0:
		set(new_value):
			if new_value != value:
				value = new_value
				queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.INK)
		draw_rect(Rect2(Vector2(3, 3), Vector2(maxf((size.x - 6.0) * value, 0.0), size.y - 6.0)), color)
