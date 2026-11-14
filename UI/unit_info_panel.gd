class_name UnitInfoPanel
extends Control
## A small card with a unit's portrait, name, class, race, cost, derived
## stats, skill and passive (with the Khí during a battle). It covers the
## screen while open so that a tap anywhere closes it.
## [codeblock]
## info_panel.open(unit_data, {"hp": 1100, "max_hp": 1100, "attack": 40, ...})
## [/codeblock]

signal closed()

const PANEL_WIDTH_PX: float = 540.0
const PORTRAIT_PX: float = 120.0
const INK_TEXT := Palette.INK

var _shade: ColorRect
var _panel: PanelContainer
var _portrait: Control
var _name_label: Label
var _tags_label: Label
var _stat_grid: GridContainer
var _ability_rows: VBoxContainer
var _unit: UnitData
var _star: int = 1
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_shade = ColorRect.new()
	_shade.color = Color(Palette.BACKDROP, 0.45)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(&"panel", GameTheme.make_panel(Palette.CREAM, 22, 8))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 10)
	_panel.add_child(rows)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	rows.add_child(header)
	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	_portrait.clip_contents = true
	_portrait.draw.connect(_draw_portrait)
	header.add_child(_portrait)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	_name_label = _make_label(30)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_name_label)
	_tags_label = _make_label(22)
	_tags_label.modulate = Color(1, 1, 1, 0.75)
	titles.add_child(_tags_label)
	_stat_grid = GridContainer.new()
	_stat_grid.columns = 4
	_stat_grid.add_theme_constant_override(&"h_separation", 18)
	_stat_grid.add_theme_constant_override(&"v_separation", 6)
	rows.add_child(_stat_grid)
	_ability_rows = VBoxContainer.new()
	_ability_rows.add_theme_constant_override(&"separation", 2)
	rows.add_child(_ability_rows)


## Opens the panel for `unit`. `stats` holds the UnitStats keys: hp, max_hp,
## attack, attacks_per_second, range_cells, armor, magic_resist, and the
## optional skill, passive and Khí keys.
func open(unit: UnitData, stats: Dictionary, star: int = 1) -> void:
	_unit = unit
	_star = star
	_name_label.text = tr(unit.name_key)
	var race_key := "RACE_" + String(unit.race_id).trim_prefix("race.").to_upper()
	_tags_label.text = "%s · %s · %s" % [tr(_class_key(stats)), tr(race_key), tr("INFO_COST") % unit.cost]
	for child: Node in _stat_grid.get_children():
		child.queue_free()
	var hp_text := str(stats["max_hp"]) if stats["hp"] == stats["max_hp"] else "%d/%d" % [stats["hp"], stats["max_hp"]]
	_add_stat("INFO_HP", hp_text)
	_add_stat("INFO_ATTACK", str(stats["attack"]))
	# Vietnamese writes decimals with a comma.
	var per_second := String.num(stats["attacks_per_second"], 2).replace(".", tr("DECIMAL_SEPARATOR"))
	_add_stat("INFO_ATTACK_SPEED", tr("INFO_ATTACK_SPEED_VALUE") % per_second)
	_add_stat("INFO_RANGE", tr("INFO_RANGE_VALUE") % stats["range_cells"])
	_add_stat("INFO_ARMOR", str(stats["armor"]))
	_add_stat("INFO_MAGIC_RESIST", str(stats["magic_resist"]))
	_fill_abilities(stats)
	_portrait.queue_redraw()
	visible = true
	_panel.reset_size()
	_panel.size.x = PANEL_WIDTH_PX
	await get_tree().process_frame
	_place_panel()
	_animate_in()


func close() -> void:
	if not visible:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, ^"scale", Vector2(0.9, 0.9), 0.1)
	_tween.parallel().tween_property(self, ^"modulate:a", 0.0, 0.1)
	_tween.tween_callback(hide)
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		accept_event()
		close()


func _place_panel() -> void:
	_panel.size = Vector2(PANEL_WIDTH_PX, _panel.get_combined_minimum_size().y)
	_panel.position = (size - _panel.size) / 2.0
	_panel.pivot_offset = _panel.size / 2.0


func _animate_in() -> void:
	if _tween != null:
		_tween.kill()
	_panel.scale = Vector2(0.85, 0.85)
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_panel, ^"scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, ^"modulate:a", 1.0, 0.12)


func _add_stat(key: String, value: String) -> void:
	var name_label := _make_label(22)
	name_label.text = tr(key)
	name_label.modulate = Color(1, 1, 1, 0.7)
	_stat_grid.add_child(name_label)
	var value_label := _make_label(24)
	value_label.text = value
	_stat_grid.add_child(value_label)


func _fill_abilities(stats: Dictionary) -> void:
	for child: Node in _ability_rows.get_children():
		child.queue_free()
	var skill_key: String = stats.get("skill_name_key", "")
	if not skill_key.is_empty():
		# In a battle the Khí it has; outside, what the skill costs.
		var qi_text: String = tr("INFO_QI_COST") % stats["qi_cost"]
		if stats.has("qi"):
			qi_text = "%s %s" % [tr("INFO_QI"), tr("INFO_QI_VALUE") % [stats["qi"], stats["qi_max"]]]
		_add_ability(tr("INFO_SKILL"), tr(skill_key), qi_text, tr(stats["skill_description_key"]))
	var passive_key: String = stats.get("passive_name_key", "")
	if not passive_key.is_empty():
		_add_ability(tr("INFO_PASSIVE"), tr(passive_key), "", tr(stats["passive_description_key"]))


func _add_ability(kind: String, title: String, note: String, description: String) -> void:
	var head := _make_label(22)
	head.text = "%s: %s" % [kind, title] + ("  ·  " + note if not note.is_empty() else "")
	_ability_rows.add_child(head)
	var body := _make_label(19)
	body.text = description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = PANEL_WIDTH_PX - 60.0
	body.modulate = Color(1, 1, 1, 0.75)
	_ability_rows.add_child(body)


func _class_key(stats: Dictionary) -> String:
	return stats.get("class_name_key", "")


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", INK_TEXT)
	return label


func _draw_portrait() -> void:
	var rect := Rect2(Vector2.ZERO, _portrait.size)
	var fill := Palette.cost_color(_unit.cost if _unit != null else 1)
	var box := GameTheme.make_panel(fill, 18, 5)
	box.draw(_portrait.get_canvas_item(), rect)
	if _unit != null:
		UnitPainter.draw_bust(_portrait, _unit, rect.get_center() + Vector2(0, 16), 2.0)
	UnitPainter.draw_star_pips(_portrait, Vector2(rect.get_center().x, 14.0), _star, 7.0)
