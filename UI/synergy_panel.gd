class_name SynergyPanel
extends Control
## The "+N" panel: everything the synergy bar sums up, for one side. Active
## formations with level and effect, formations one unit short ("thiếu 1"),
## class and race milestones with their count and next threshold ("Khiên
## 2/4") and every tier's effect, and the Hợp Lực tiers. It covers the
## screen while open; a tap anywhere closes it.
## [codeblock]
## panel.open(result, catalog)
## [/codeblock]

signal closed()

const PANEL_WIDTH_PX: float = 620.0
const MAX_HEIGHT_PX: float = 1040.0
const TEXT_WIDTH_PX: float = PANEL_WIDTH_PX - 64.0
const DIM := Color(1, 1, 1, 0.55)

var _shade: ColorRect
var _panel: PanelContainer
var _scroll: ScrollContainer
var _rows: VBoxContainer
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
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(&"panel", GameTheme.make_panel(Palette.CREAM, 22, 8))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 4)
	_rows.custom_minimum_size.x = PANEL_WIDTH_PX - 40.0
	_scroll.add_child(_rows)


## Opens the panel on an evaluate() result. `title` replaces the heading
## (the enemy's line-up).
func open(result: Dictionary, catalog: Catalog, title: String = "") -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_add_text(title if not title.is_empty() else tr("SYNERGY_PANEL_TITLE"), 30)
	_fill_formations(result, catalog)
	_fill_near(result, catalog)
	_fill_milestones(tr("SYNERGY_CLASSES"), result.get("class_milestones", []), catalog)
	_fill_milestones(tr("SYNERGY_RACES"), result.get("race_milestones", []), catalog)
	_fill_hop_luc(result, catalog)
	visible = true
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


## "Khiên 2/4": the count and the next threshold; past the last one, just
## the count.
static func count_text(milestone_name: String, count: int, thresholds: Array, reached: int) -> String:
	if reached >= thresholds.size():
		return "%s %d" % [milestone_name, count]
	return TranslationServer.translate("SYNERGY_COUNT_FORMAT") % [milestone_name, count, thresholds[reached]]


## The texts shown, top to bottom, for tests.
func get_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for child: Node in _rows.get_children():
		var label := child as Label
		if label != null:
			lines.append(label.text)
	return lines


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()


func _fill_formations(result: Dictionary, catalog: Catalog) -> void:
	_add_heading(tr("SYNERGY_FORMATIONS"))
	var formations: Array = result.get("formations", [])
	if formations.is_empty():
		_add_text(tr("SYNERGY_NONE"), 20, DIM)
	for entry: Dictionary in formations:
		var formation := catalog.get_formation(entry["id"])
		_add_text("● %s · %s" % [tr(formation.name_key), tr("SYNERGY_LEVEL_FORMAT") % entry["level"]], 22, Color.WHITE, formation.color.darkened(0.45))
		_add_text(tr(formation.description_key), 19, DIM)


func _fill_near(result: Dictionary, catalog: Catalog) -> void:
	var seen: Dictionary[StringName, bool] = {}
	var lines: Array[String] = []
	for entry: Dictionary in result.get("near_formations", []):
		var id: StringName = entry["id"]
		if seen.has(id):
			continue
		seen[id] = true
		var needed: StringName = entry["needed_class"]
		var class_data := catalog.get_class_data(needed) if needed != &"" else null
		var unit_text := tr(class_data.name_key) if class_data != null else tr("SYNERGY_ANY_UNIT")
		lines.append("%s · %s" % [tr(catalog.get_formation(id).name_key), tr("SYNERGY_MISSING_FORMAT") % unit_text])
	if lines.is_empty():
		return
	_add_heading(tr("SYNERGY_NEAR"))
	for line: String in lines:
		_add_text(line, 20)


# Milestones with at least one unit counted; the rest would only be noise.
func _fill_milestones(heading: String, entries: Array, catalog: Catalog) -> void:
	var counted := entries.filter(func(entry: Dictionary) -> bool: return entry["count"] > 0)
	if counted.is_empty():
		return
	_add_heading(heading)
	for entry: Dictionary in counted:
		var milestone := catalog.get_milestone(entry["id"])
		var thresholds: Array = entry["thresholds"]
		var reached: int = entry["reached"]
		var tint := Palette.JADE if reached > 0 else Palette.INK
		_add_text(SynergyPanel.count_text(tr(milestone.name_key), entry["count"], thresholds, reached), 22, Color.WHITE, tint)
		for index: int in milestone.tiers.size():
			var tier: SynergyTierData = milestone.tiers[index]
			_add_text("%d: %s" % [tier.at, tr(tier.description_key)], 19, Color.WHITE if index < reached else DIM)


func _fill_hop_luc(result: Dictionary, catalog: Catalog) -> void:
	if catalog.hop_luc == null:
		return
	var points: int = result.get("hop_luc", 0)
	_add_heading("%s · %d" % [tr("SYNERGY_HOP_LUC_TIERS"), points])
	for tier: SynergyTierData in catalog.hop_luc.tiers:
		_add_text("%d: %s" % [tier.at, tr(tier.description_key)], 19, Color.WHITE if points >= tier.at else DIM)


func _add_heading(text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	_rows.add_child(spacer)
	_add_text(text, 24, Color.WHITE, Palette.VERMILION_DARK)


func _add_text(text: String, font_size: int, tint: Color = Color.WHITE, color: Color = Palette.INK) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TEXT_WIDTH_PX
	label.modulate = tint
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(label)


func _place_panel() -> void:
	var content := _rows.get_combined_minimum_size().y
	var height := minf(content, minf(MAX_HEIGHT_PX, size.y - 120.0))
	_scroll.custom_minimum_size = Vector2(PANEL_WIDTH_PX - 40.0, height)
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
