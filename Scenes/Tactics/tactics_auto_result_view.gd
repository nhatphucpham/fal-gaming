class_name TacticsAutoResultView
extends Control
## After an Auto region: won or lost, how many stood at the end on each
## side (two bars that drain from full to what is left), who of ours was
## wounded and sits out the next battle (no one dies in Auto), the
## supplies, the reminder that Auto leaves no marks or bonds, and what the
## world turn changed. "Sổ quân" opens the roster; "Tiếp tục" goes back to
## the world map. Rows fade in one after another; the win or loss sound
## plays once. A menu: only the bars redraw, while they drain.
## [codeblock]
## var view := TacticsAutoResultView.new()
## view.campaign = campaign
## view.summary = campaign.apply_auto(TacticsAutoResolve.resolve(campaign))
## [/codeblock]

signal continue_requested()

const FACE_PX: float = 52.0
const DRAIN_SEC: float = 0.8

var campaign: TacticsCampaign
## TacticsCampaign.apply_auto()'s result.
var summary: Dictionary = {}
## Tests and stills: no animation.
var is_instant: bool = false

var _body: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(Palette.BACKDROP, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 16
	page.offset_right = -16
	page.offset_top = 16
	page.offset_bottom = -16
	page.add_theme_constant_override(&"separation", 8)
	add_child(page)
	var is_won: bool = summary.get("is_won", false)
	var title := TacticsViews.label("AUTO_TITLE_WIN" if is_won else "AUTO_TITLE_LOSS", 44, Palette.GOLD if is_won else Palette.VERMILION.lightened(0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var subtitle := TacticsViews.label(TacticsWorldText.region_name(campaign.roster.world, campaign.region_id), 28, Palette.CREAM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_body)
	_body.add_child(_forces_panel())
	_body.add_child(_wounded_panel())
	_body.add_child(_rewards_panel())
	var lines := TacticsWorldText.change_lines(campaign.roster.world, summary.get("world", {}))
	if not lines.is_empty():
		_body.add_child(_world_panel(lines))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	page.add_child(buttons)
	buttons.add_child(TacticsViews.button("BUTTON_ROSTER", open_roster, false))
	var go_on := TacticsViews.button("BUTTON_CONTINUE", continue_requested.emit, true)
	go_on.name = "ContinueButton"
	buttons.add_child(go_on)
	Sound.play(&"win" if is_won else &"lose")
	if not is_instant:
		TacticsViews.slide_in(self)
		TacticsViews.stagger_in(_body.get_children())


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
	var counts: Array = summary.get("counts", [[0, 0, 0], [0, 0, 0]])
	var formats := ["AUTO_OURS_FORMAT", "AUTO_ENEMY_FORMAT"]
	var colors := [TacticsPainter.PLAYER_FILL, TacticsPainter.ENEMY_FILL]
	for side: int in 2:
		var alive: int = counts[side][0]
		var placed: int = counts[side][1]
		rows.add_child(TacticsViews.label(tr(formats[side]) % [alive, placed], 22, Palette.CREAM))
		var bar := _Bar.new()
		bar.color = colors[side]
		bar.custom_minimum_size = Vector2(0, 22)
		bar.value = 1.0
		rows.add_child(bar)
		var left := float(alive) / maxf(float(placed), 1.0)
		if is_instant:
			bar.value = left
		else:
			bar.create_tween().tween_property(bar, ^"value", left, DRAIN_SEC).set_delay(0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var fortune: int = summary.get("fortune", 0)
	rows.add_child(TacticsViews.wrapped(tr("AUTO_FORTUNE_FORMAT") % fortune, 22, Palette.TEXT_DIM))
	return box


func _wounded_panel() -> Control:
	var box := TacticsViews.panel()
	box.name = "WoundedPanel"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	rows.add_child(TacticsViews.label("AUTO_WOUNDED", 28, Palette.GOLD))
	var wounded: Array = summary.get("wounded", [])
	if wounded.is_empty():
		rows.add_child(TacticsViews.wrapped(tr("AUTO_NO_WOUNDED"), 22, Palette.TEXT_DIM))
	for id: int in wounded:
		var person := campaign.get_person(id)
		var line := HBoxContainer.new()
		line.name = "Wounded%d" % id
		line.add_theme_constant_override(&"separation", 12)
		rows.add_child(line)
		var face := TacticsFace.FaceView.new()
		face.look = person["look"]
		face.ring = Palette.VERMILION
		face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
		line.add_child(face)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override(&"separation", -2)
		line.add_child(texts)
		var name := campaign.bio.person_name(person) if person["is_named"] else campaign.bio.plain_name(person)
		texts.add_child(TacticsViews.label(name, 24, Palette.CREAM))
		texts.add_child(TacticsViews.label("ROSTER_STATUS_WOUNDED", 20, Palette.VERMILION.lightened(0.3)))
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
