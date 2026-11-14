class_name RunLayout
extends Control
## Builds the run screen's widgets in a 720-wide portrait column and slides
## between the preparation and battle layouts. Top to bottom: stage and
## morale with the countdown, the board (cells of 80 px), the info row
## (Hợp Lực ring, formation chips, "+N", units on the board), the bench, the shop (which becomes the sell zone), gold, supply
## and level with their buttons, and "Ra trận". RunScreen wires them up.

const COLUMN_WIDTH_PX: float = 720.0
const SIDE_GUTTER_PX: int = 16
## The board is drawn at 88 px cells and scaled to about 80 px here.
const BOARD_SCALE: float = 80.0 / 88.0
const SLIDE_PX: float = 360.0

var board: BoardView
var bench: BenchBar
var shop: ShopBar
var sell_zone: SellZone
var stage_label: Label
var stage_name_label: Label
var morale_chip: ResourceChip
var timer_badge: TimerBadge
var capacity_chip: ResourceChip
var synergy_bar: SynergyBar
## Formation outlines, on the board under the pieces.
var outlines: FormationOutlines
var gold_chip: ResourceChip
var supply_chip: ResourceChip
var level_chip: ResourceChip
var refresh_button: CostButton
var supply_button: CostButton
var level_button: CostButton
var fight_button: PressButton
var speed_button: PressButton
var battle_status: BattleStatus
## Above the board and bench, scaled like them: flights and confetti.
var piece_overlay: Node2D
var ghost: DragGhost
var banner: ResultBanner
var info_panel: UnitInfoPanel
var synergy_panel: SynergyPanel

var _prep_panel: Control
var _battle_panel: Control
var _phase_tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := Backdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var column := Control.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_bottom = 1.0
	column.offset_left = -COLUMN_WIDTH_PX / 2.0
	column.offset_right = COLUMN_WIDTH_PX / 2.0
	add_child(column)
	var rows := _vbox(0)
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_child(rows)
	rows.add_child(_build_top_bar())
	rows.add_child(_spacer(4))
	rows.add_child(_build_board())
	rows.add_child(_build_info_row())
	rows.add_child(_spacer(2))
	rows.add_child(_build_lower())
	rows.add_child(_spacer(8))
	_build_overlay()


## Slides the bench, shop and buttons away and the battle bars in.
func show_battle_layout() -> void:
	_restart_phase_tween()
	_phase_tween.tween_property(_prep_panel, ^"position:y", SLIDE_PX, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_phase_tween.parallel().tween_property(_prep_panel, ^"modulate:a", 0.0, 0.25)
	# The battle bars count the units; the board counter would say it twice.
	_phase_tween.parallel().tween_property(capacity_chip, ^"modulate:a", 0.0, 0.2)
	_phase_tween.parallel().tween_property(_battle_panel, ^"position:y", 0.0, 0.3).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_phase_tween.parallel().tween_property(_battle_panel, ^"modulate:a", 1.0, 0.2).set_delay(0.15)
	_battle_panel.visible = true
	_battle_panel.mouse_filter = Control.MOUSE_FILTER_PASS


## Slides the preparation layout back.
func show_prep_layout() -> void:
	_restart_phase_tween()
	# The slid-away battle panel still overlaps the fight button on short
	# screens: it must not take presses meant for the preparation.
	_battle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_tween.tween_property(_battle_panel, ^"position:y", SLIDE_PX, 0.25).set_ease(Tween.EASE_IN)
	_phase_tween.parallel().tween_property(_battle_panel, ^"modulate:a", 0.0, 0.2)
	_phase_tween.parallel().tween_property(_prep_panel, ^"position:y", 0.0, 0.3).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_phase_tween.parallel().tween_property(_prep_panel, ^"modulate:a", 1.0, 0.2).set_delay(0.1)
	_phase_tween.parallel().tween_property(capacity_chip, ^"modulate:a", 1.0, 0.2)
	_phase_tween.chain().tween_callback(_battle_panel.set_visible.bind(false))


func _build_top_bar() -> Control:
	var bar := _margins(SIDE_GUTTER_PX, 6, SIDE_GUTTER_PX, 0)
	bar.custom_minimum_size = Vector2(0, 84)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	bar.add_child(row)
	var titles := _vbox(-6)
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	stage_label = Label.new()
	stage_label.theme_type_variation = &"TitleLabel"
	stage_label.add_theme_font_size_override(&"font_size", 32)
	titles.add_child(stage_label)
	stage_name_label = Label.new()
	stage_name_label.theme_type_variation = &"DimLabel"
	stage_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(stage_name_label)
	morale_chip = ResourceChip.new()
	morale_chip.setup(&"morale")
	morale_chip.custom_minimum_size = Vector2(112, 60)
	morale_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(morale_chip)
	timer_badge = TimerBadge.new()
	row.add_child(timer_badge)
	return bar


func _build_board() -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_px := BoardView.FRAME_PX * BOARD_SCALE
	var board_size := Vector2(BoardView.COLS, BoardView.ROWS) * BoardView.CELL_PX * BOARD_SCALE
	slot.custom_minimum_size = board_size + Vector2(frame_px, frame_px) * 2.0
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board = (load("res://Scenes/Board/board_view.tscn") as PackedScene).instantiate() as BoardView
	board.scale = Vector2(BOARD_SCALE, BOARD_SCALE)
	board.position = Vector2(frame_px, frame_px)
	slot.add_child(board)
	outlines = FormationOutlines.new()
	board.get_outline_layer().add_child(outlines)
	return slot


func _build_info_row() -> Control:
	var margins := _margins(SIDE_GUTTER_PX + 8, 0, SIDE_GUTTER_PX, 0)
	margins.custom_minimum_size = Vector2(0, 50)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	margins.add_child(row)
	synergy_bar = SynergyBar.new()
	synergy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	synergy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(synergy_bar)
	capacity_chip = ResourceChip.new()
	capacity_chip.setup(&"troops")
	capacity_chip.custom_minimum_size = Vector2(120, 46)
	capacity_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(capacity_chip)
	return margins


func _build_lower() -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(0, 96 + 160 + 90 + 88 + 3 * 6)
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prep_panel = _vbox(6)
	_prep_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(_prep_panel)
	bench = BenchBar.new()
	_prep_panel.add_child(bench)
	_prep_panel.add_child(_build_shop_area())
	_prep_panel.add_child(_build_resource_row())
	var fight_row := _margins(SIDE_GUTTER_PX, 0, SIDE_GUTTER_PX, 0)
	fight_button = _button("BUTTON_FIGHT", Vector2(0, 88))
	fight_button.theme_type_variation = &"PrimaryButton"
	fight_row.add_child(fight_button)
	_prep_panel.add_child(fight_row)
	slot.add_child(_build_battle_panel())
	return slot


func _build_shop_area() -> Control:
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.custom_minimum_size = Vector2(0, 160)
	shop = ShopBar.new()
	shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(shop)
	sell_zone = SellZone.new()
	sell_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	sell_zone.offset_left = SIDE_GUTTER_PX
	sell_zone.offset_right = -SIDE_GUTTER_PX
	area.add_child(sell_zone)
	return area


func _build_resource_row() -> Control:
	var margins := _margins(SIDE_GUTTER_PX, 0, SIDE_GUTTER_PX, 0)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 4)
	margins.add_child(row)
	gold_chip = _chip(row, &"coin")
	supply_chip = _chip(row, &"supply")
	level_chip = _chip(row, &"level")
	refresh_button = _cost_button(row, "BUTTON_REFRESH", &"coin")
	supply_button = _cost_button(row, "BUTTON_BUY_SUPPLY", &"coin")
	level_button = _cost_button(row, "BUTTON_LEVEL_UP", &"supply")
	return margins


func _build_battle_panel() -> Control:
	_battle_panel = _vbox(8)
	_battle_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_panel.position.y = SLIDE_PX
	_battle_panel.modulate.a = 0.0
	_battle_panel.visible = false
	battle_status = BattleStatus.new()
	battle_status.custom_minimum_size = Vector2(0, 2 * BattleStatus.ROW_HEIGHT_PX)
	_battle_panel.add_child(battle_status)
	var speed_row := _margins(SIDE_GUTTER_PX, 0, SIDE_GUTTER_PX, 0)
	speed_button = _button("x1", Vector2(200, 88))
	speed_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	speed_row.add_child(speed_button)
	_battle_panel.add_child(speed_row)
	_battle_panel.add_child(_spacer(0))
	return _battle_panel


func _build_overlay() -> void:
	piece_overlay = Node2D.new()
	piece_overlay.name = "PieceOverlay"
	piece_overlay.scale = Vector2(BOARD_SCALE, BOARD_SCALE)
	add_child(piece_overlay)
	ghost = DragGhost.new()
	add_child(ghost)
	banner = ResultBanner.new()
	add_child(banner)
	info_panel = UnitInfoPanel.new()
	add_child(info_panel)
	synergy_panel = SynergyPanel.new()
	add_child(synergy_panel)


func _chip(row: HBoxContainer, kind: StringName) -> ResourceChip:
	var chip := ResourceChip.new()
	chip.setup(kind)
	chip.custom_minimum_size = Vector2(98, 64)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	return chip


func _cost_button(row: HBoxContainer, title_key: String, icon: StringName) -> CostButton:
	var button := CostButton.new()
	button.setup(title_key, icon)
	button.custom_minimum_size = Vector2(118, 88)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	return button


func _button(text_key: String, min_size: Vector2) -> PressButton:
	var button := PressButton.new()
	button.text = text_key
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	return button


func _vbox(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", separation)
	return box


func _margins(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var box := MarginContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair: Array in [["margin_left", left], ["margin_top", top], ["margin_right", right], ["margin_bottom", bottom]]:
		box.add_theme_constant_override(pair[0], pair[1])
	return box


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer


func _restart_phase_tween() -> void:
	if _phase_tween != null:
		_phase_tween.kill()
	_phase_tween = create_tween()
