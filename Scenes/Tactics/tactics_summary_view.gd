class_name TacticsSummaryView
extends Control
## After a tactics battle with the roster: the result, then every roster
## soldier who fought (face, name, what became of it, the marks it earned),
## any soldier named for its marks with its name and biography, and the
## karma carried to the next battle, the side goals met or missed and the
## supplies won. "Sổ quân" opens the roster; "Tiếp
## tục" goes on. Rows come in one after another, each naming its own sound.
## [codeblock]
## var view := TacticsSummaryView.new()
## view.campaign = campaign
## view.summary = campaign.finish_battle(battle, people)
## view.continue_requested.connect(open_campaign)
## [/codeblock]

signal continue_requested()

const FACE_PX: float = 52.0
const NAMED_FACE_PX: float = 120.0

var campaign: TacticsCampaign
## TacticsCampaign.finish_battle()'s result.
var summary: Dictionary = {}
var player_side: int = 0
## Tests and stills: no row animation.
var is_instant: bool = false

var _body: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(Palette.BACKDROP, 0.96)
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
	var is_win: bool = summary.get("is_finished", false) and int(summary.get("winner", -1)) == player_side
	var title_key := ("RESULT_WIN" if is_win else "RESULT_LOSS") if summary.get("is_finished", false) else "SUMMARY_RETREAT"
	var title := TacticsViews.label(title_key, 44, Palette.GOLD if is_win else Palette.VERMILION.lightened(0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_body)
	for id: int in summary.get("named", []):
		_body.add_child(_named_card(id))
	_body.add_child(_goals_panel())
	_body.add_child(_people_panel())
	_body.add_child(_karma_panel())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	page.add_child(buttons)
	buttons.add_child(TacticsViews.button("BUTTON_ROSTER", open_roster, false))
	buttons.add_child(TacticsViews.button("BUTTON_CONTINUE", continue_requested.emit, true))
	if not is_instant:
		TacticsViews.slide_in(self)
		TacticsViews.stagger_in(_body.get_children())
	if not (summary.get("named", []) as Array).is_empty():
		Sound.play(&"epiphany")


func open_roster() -> TacticsRosterView:
	var view := TacticsRosterView.new()
	view.campaign = campaign
	add_child(view)
	return view


# A soldier named for its marks: big face, its new name, its biography.
func _named_card(id: int) -> Control:
	var person := campaign.get_person(id)
	var box := TacticsViews.panel(Palette.INDIGO_DARK)
	box.name = "NamedCard%d" % id
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	rows.add_child(head)
	var face := TacticsFace.FaceView.new()
	face.look = person["look"]
	face.ring = Palette.GOLD
	face.custom_minimum_size = Vector2(NAMED_FACE_PX, NAMED_FACE_PX)
	head.add_child(face)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(texts)
	texts.add_child(TacticsViews.label("SUMMARY_NAMED", 22, Palette.JADE_LIGHT))
	texts.add_child(TacticsViews.label(campaign.bio.person_name(person), 40, Palette.GOLD))
	texts.add_child(TacticsViews.wrapped(tr("SUMMARY_NAMED_LEADS_FORMAT") % campaign.rules.named_lead_capacity, 19, Palette.TEXT))
	rows.add_child(TacticsViews.wrapped(" ".join(campaign.bio.biography(person)), 22, Palette.CREAM))
	return box


func _people_panel() -> Control:
	var box := TacticsViews.panel()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	rows.add_child(TacticsViews.label("SUMMARY_PEOPLE", 28, Palette.GOLD))
	var sorted: Array = (summary.get("rows", []) as Array).duplicate()
	sorted.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return _rank(left) < _rank(right))
	for row: Dictionary in sorted:
		rows.add_child(_person_row(row))
	return box


func _person_row(row: Dictionary) -> Control:
	var person := campaign.get_person(row["id"])
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	var face := TacticsFace.FaceView.new()
	face.look = person["look"]
	face.ring = Palette.GOLD if person["is_named"] else Palette.INK
	face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if row["status"] == &"dead":
		face.modulate = Color(0.6, 0.6, 0.6)
	line.add_child(face)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override(&"separation", -2)
	line.add_child(texts)
	texts.add_child(TacticsViews.label(campaign.bio.display_name(person), 22, Palette.GOLD if person["is_named"] else Palette.CREAM))
	var fate := _fate(row)
	var marks: Array = row["marks"]
	var names: PackedStringArray = []
	for incident: StringName in marks:
		names.append(campaign.text.incident_name(incident))
	var detail: String = fate[0] if names.is_empty() else "%s · %s" % [fate[0], tr("SUMMARY_MARKS_FORMAT") % ", ".join(names)]
	var detail_label := TacticsViews.wrapped(detail, 18, fate[1])
	texts.add_child(detail_label)
	var icons := TacticsViews.MarkRow.new()
	icons.count = (person["marks"] as Array).size()
	icons.custom_minimum_size = Vector2(72, 24)
	icons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icons)
	return line


# Named now first, then marks earned, the living, the gone, the fallen.
static func _rank(row: Dictionary) -> int:
	var rank := 0 if row["is_named_now"] else 10 if not (row["marks"] as Array).is_empty() else 20
	if row["status"] == &"dead":
		rank += 40
	elif row["status"] == &"fled" or row["has_defected"]:
		rank += 5
	return rank * 1000 + int(row["id"])


# What became of one person in this battle: [text, colour].
func _fate(row: Dictionary) -> Array:
	if row["status"] == &"dead":
		return [tr("SUMMARY_FELL"), Palette.TEXT_DIM]
	if row["status"] == &"fled":
		return [tr("SUMMARY_FLED"), Palette.VERMILION.lightened(0.3)]
	if row["has_defected"]:
		var is_to_us: bool = int(row["start_side"]) != player_side
		return [tr("SUMMARY_JOINED") if is_to_us else tr("SUMMARY_DEFECTED"), Palette.JADE_LIGHT if is_to_us else Palette.VERMILION.lightened(0.3)]
	if int(row["start_side"]) != player_side:
		return [tr("SUMMARY_ENEMY_SURVIVED"), Palette.VERMILION.lightened(0.3)]
	if row.get("is_recruit", false):
		return [tr("SUMMARY_RECRUITED"), Palette.JADE_LIGHT]
	if row["status"] == &"escaped":
		return [tr("SUMMARY_ESCAPED"), Palette.JADE_LIGHT]
	return [tr("SUMMARY_RETURNED"), Palette.CREAM]


func _karma_panel() -> Control:
	var box := TacticsViews.panel()
	var karma: Dictionary = summary.get("karma", {})
	var text := tr("SUMMARY_KARMA_FORMAT") % [int(karma.get("bait", 0)), int(karma.get("rescue", 0)), int(karma.get("next_bait", 0)), int(karma.get("next_rescue", 0))]
	box.add_child(TacticsViews.wrapped(text, 20, Palette.TEXT))
	return box


# The side goals, met (with their supplies) or missed, and the store.
func _goals_panel() -> Control:
	var box := TacticsViews.panel()
	box.name = "GoalsPanel"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	box.add_child(rows)
	var goals: Array = summary.get("goals", [])
	if not goals.is_empty():
		rows.add_child(TacticsViews.label("SUMMARY_GOALS", 28, Palette.GOLD))
	for goal: Dictionary in goals:
		var what := tr("GOAL_BY_ROUND_FORMAT") % goal["value"] if goal["kind"] == &"goal.by_round" else tr("GOAL_" + String(goal["kind"]).trim_prefix("goal.").to_upper())
		if goal["is_met"]:
			rows.add_child(TacticsViews.wrapped(tr("SUMMARY_GOAL_MET_FORMAT") % [what, goal["supplies"]], 22, Palette.JADE_LIGHT))
		else:
			rows.add_child(TacticsViews.wrapped(tr("SUMMARY_GOAL_MISSED_FORMAT") % what, 22, Palette.TEXT_DIM))
	rows.add_child(TacticsViews.wrapped(tr("SUMMARY_SUPPLIES_FORMAT") % [int(summary.get("supplies", 0)), int(summary.get("supplies_total", 0))], 22, Palette.GOLD))
	return box
