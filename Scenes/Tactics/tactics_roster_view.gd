class_name TacticsRosterView
extends Control
## Sổ quân, over the muster or the after-battle summary: every person in
## the roster with face, name, troop, status and marks, the named and the
## living first. Tapping one opens its character sheet: face, name, what it
## is now (soldier, named leader, fallen, deserter, traitor), what it leads
## with if named, its biography and every mark it carries. A menu: it
## builds rows on open and never redraws on its own.
## [codeblock]
## var view := TacticsRosterView.new()
## view.campaign = campaign
## add_child(view)
## [/codeblock]

signal closed()

const FACE_PX: float = 56.0
## A roster row is a touch target.
const ROW_MIN_PX: float = 88.0
const SHEET_FACE_PX: float = 132.0
const STATUS_ORDER: Array[String] = ["active", "traitor", "deserted", "dead"]

var campaign: TacticsCampaign

var _list: VBoxContainer
var _title: Label
var _back: PressButton
var _sheet_id: int = -1


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
	_title = TacticsViews.label("ROSTER_TITLE", 40, Palette.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_list)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	page.add_child(buttons)
	_back = TacticsViews.button("BUTTON_BACK", show_list, false)
	buttons.add_child(_back)
	buttons.add_child(TacticsViews.button("BUTTON_CLOSE", close, true))
	show_list()
	TacticsViews.slide_in(self)


func close() -> void:
	closed.emit()
	queue_free()


## The list of every person.
func show_list() -> void:
	_sheet_id = -1
	_back.visible = false
	_title.text = tr("ROSTER_TITLE")
	TacticsViews.clear(_list)
	var people: Array[Dictionary] = campaign.roster.people.duplicate()
	people.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_rank := STATUS_ORDER.find(left["status"]) - (1 if left["is_named"] else 0) * 10
		var right_rank := STATUS_ORDER.find(right["status"]) - (1 if right["is_named"] else 0) * 10
		return left_rank < right_rank or (left_rank == right_rank and int(left["id"]) < int(right["id"])))
	if people.is_empty():
		_list.add_child(TacticsViews.label("ROSTER_EMPTY", 22, Palette.TEXT_DIM))
	for person: Dictionary in people:
		_list.add_child(_row(person))
	TacticsViews.stagger_in(_list.get_children())


func get_sheet_id() -> int:
	return _sheet_id


## The character sheet of one person.
func show_sheet(id: int) -> void:
	var person := campaign.get_person(id)
	if person.is_empty():
		return
	_sheet_id = id
	_back.visible = true
	_title.text = tr("ROSTER_SHEET_TITLE")
	TacticsViews.clear(_list)
	var bio := campaign.bio
	var box := TacticsViews.panel()
	_list.add_child(box)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	rows.add_child(head)
	var face := TacticsFace.FaceView.new()
	face.look = person["look"]
	face.ring = Palette.GOLD if person["is_named"] else Palette.INK
	face.custom_minimum_size = Vector2(SHEET_FACE_PX, SHEET_FACE_PX)
	head.add_child(face)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(texts)
	texts.add_child(TacticsViews.label(bio.display_name(person), 34, Palette.GOLD if person["is_named"] else Palette.CREAM))
	texts.add_child(TacticsViews.wrapped(tr("ROSTER_TROOP_FORMAT") % [campaign.text.unit_name(person["troop"]), bio.leader_name(person["first_leader"])], 21, Palette.TEXT))
	texts.add_child(TacticsViews.label(status_text(person), 22, status_color(person)))
	if person["is_named"] and person["status"] == "active":
		var leader := campaign.make_leader(person)
		var passive := tr(leader.passives[0].name_key) if not leader.passives.is_empty() else ""
		rows.add_child(TacticsViews.wrapped(tr("ROSTER_LEADS_FORMAT") % [leader.lead_capacity, passive, tr(leader.skill.name_key)], 21, Palette.JADE_LIGHT))
	if person["is_named"]:
		rows.add_child(TacticsViews.label("ROSTER_BIO", 26, Palette.GOLD))
		rows.add_child(TacticsViews.wrapped(" ".join(bio.biography(person)), 22, Palette.CREAM))
	var marks: Array = person["marks"]
	rows.add_child(TacticsViews.label(tr("ROSTER_MARKS_FORMAT") % [marks.size(), campaign.rules.marks_to_name], 26, Palette.GOLD))
	if marks.is_empty():
		rows.add_child(TacticsViews.label("ROSTER_NO_MARKS", 21, Palette.TEXT_DIM))
	for mark: Dictionary in marks:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		rows.add_child(line)
		var diamond := TacticsViews.MarkIcon.new()
		diamond.is_good = campaign.rules.get_incident(mark["incident"]) != null and campaign.rules.get_incident(mark["incident"]).is_good()
		diamond.custom_minimum_size = Vector2(22, 22)
		line.add_child(diamond)
		var text_line := TacticsViews.wrapped(bio.mark_line(mark), 20, Palette.TEXT)
		text_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text_line)
	TacticsViews.stagger_in([box])


## "Còn sống", "Danh tướng", "Tử trận", "Bỏ trốn", "Theo giặc"; a wounded
## soldier says so, a hired one says it was hired.
func status_text(person: Dictionary) -> String:
	if person["status"] != "active":
		return tr("ROSTER_STATUS_" + String(person["status"]).to_upper())
	var text := tr("ROSTER_STATUS_NAMED") if person["is_named"] else tr("ROSTER_STATUS_ACTIVE")
	if campaign.roster.is_resting(person):
		text = tr("ROSTER_STATUS_WOUNDED")
	if person.get("is_hired", false):
		text = "%s · %s" % [tr("ROSTER_HIRED"), text]
	return text


static func status_color(person: Dictionary) -> Color:
	match person["status"]:
		"dead":
			return Palette.TEXT_DIM
		"deserted", "traitor":
			return Palette.VERMILION.lightened(0.3)
	return Palette.JADE_LIGHT if person["is_named"] else Palette.CREAM


func _row(person: Dictionary) -> Control:
	var row := PressButton.new()
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	# A row is a touch target: at least 88 layout px (44 px on a phone).
	row.custom_minimum_size = Vector2(0, maxf(FACE_PX + 16, ROW_MIN_PX))
	row.name = "Person%d" % person["id"]
	row.pressed.connect(func() -> void:
		Sound.play(&"ui_tap")
		show_sheet(person["id"]))
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 10
	line.offset_right = -10
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 12)
	row.add_child(line)
	var face := TacticsFace.FaceView.new()
	face.look = person["look"]
	face.ring = Palette.GOLD if person["is_named"] else Palette.INK
	face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if person["status"] == "dead":
		face.modulate = Color(0.6, 0.6, 0.6)
	line.add_child(face)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override(&"separation", -2)
	line.add_child(texts)
	texts.add_child(TacticsViews.label(campaign.bio.display_name(person), 24, Palette.GOLD if person["is_named"] else Palette.CREAM))
	texts.add_child(TacticsViews.label("%s · %s" % [campaign.text.unit_name(person["troop"]), status_text(person)], 19, status_color(person)))
	var marks := TacticsViews.MarkRow.new()
	marks.count = (person["marks"] as Array).size()
	marks.custom_minimum_size = Vector2(72, 24)
	marks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(marks)
	return row
