class_name TacticsMarketView
extends Control
## Chợ: one region's market over the world map. Each offer is a row with
## what it is, its price and what is left this turn, and a "Mua" button;
## healing is one row too: how many are wounded and the face of the one
## it treats next (the one with the most marks), so one tap heals the one
## who matters most. A purchase spends
## the supplies, saves the roster at once, rings (buy, or the healing
## chime) and flashes its row; a refused one buzzes and the hint says why.
## A menu: rows are built on open and after each purchase, nothing redraws
## by itself.
## [codeblock]
## var view := TacticsMarketView.new()
## view.campaign = TacticsCampaign.new(roster, catalog, null)
## view.region_id = &"region.ferry"
## add_child(view)
## [/codeblock]

signal closed()
## After a purchase was saved.
signal bought(result: Dictionary)

const FACE_PX: float = 56.0
const ROW_MIN_PX: float = 96.0
const FLASH_SEC: float = 0.35

## A view-only campaign (no scenario) for names and the roster.
var campaign: TacticsCampaign
var region_id: StringName = &""
## Tests: no slide, no save.
var is_instant: bool = false

var _market: TacticsMarket
var _list: VBoxContainer
var _supplies: Label
var _held: Label
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var region := campaign.roster.world.data.get_region(region_id)
	_market = TacticsMarket.new(campaign.roster, region)
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
	var title := TacticsViews.label(_title_text(region), 40, Palette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	_supplies = TacticsViews.label("", 28, Palette.GOLD)
	_supplies.name = "Supplies"
	_supplies.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_supplies)
	_held = TacticsViews.wrapped("", 22, Palette.TEXT_DIM)
	_held.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_held)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_list)
	_hint = TacticsViews.wrapped(tr("MARKET_HINT"), 22, Palette.CREAM)
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_hint)
	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	buttons.add_child(TacticsViews.button("BUTTON_CLOSE", close, true))
	_refresh()
	if is_instant:
		Sound.play(&"card_flip")
	else:
		TacticsViews.slide_in(self)


func close() -> void:
	closed.emit()
	queue_free()


func get_hint() -> String:
	return _hint.text


## Buys offer `index` (healing treats `person_id`, or the next patient
## when -1); false, with a buzz and the reason in the hint, when refused.
func buy(index: int, person_id: int = -1) -> bool:
	var result := _market.buy(index, person_id)
	if not result["ok"]:
		Sound.play(&"block")
		_hint.text = tr("MARKET_REFUSED_" + String(result["reason"]).to_upper())
		return false
	if not is_instant:
		campaign.roster.save()
	var offer: TacticsOfferData = _market.region.offers[index]
	Sound.play(&"site_heal" if offer.kind == &"offer.heal" else &"buy")
	_hint.text = _bought_text(offer, result)
	_refresh()
	_flash(index)
	bought.emit(result)
	return true


func _title_text(region: TacticsRegionData) -> String:
	var market := tr(region.market_name_key)
	return market.substr(0, 1).to_upper() + market.substr(1)


func _bought_text(offer: TacticsOfferData, result: Dictionary) -> String:
	if offer.kind == &"offer.heal":
		return tr("MARKET_BOUGHT_HEAL_FORMAT") % _person_name(campaign.get_person(result["person"]))
	if offer.kind == &"offer.item":
		return tr("MARKET_BOUGHT_ITEM_FORMAT") % tr(offer.item.name_key)
	return tr("MARKET_BOUGHT_HIRE_FORMAT") % campaign.text.unit_name(offer.troop.id)


# Rebuilds the rows (a menu: nothing here runs per frame).
func _refresh() -> void:
	_supplies.text = tr("MARKET_SUPPLIES_FORMAT") % campaign.roster.supplies
	var held: PackedStringArray = []
	for item: TacticsItemData in campaign.roster.world.data.items:
		if campaign.roster.get_item_count(item.id) > 0:
			held.append(tr("ITEM_TOGGLE_FORMAT") % [tr(item.name_key), campaign.roster.get_item_count(item.id)])
	_held.text = tr("MARKET_ITEMS_HELD_FORMAT") % ", ".join(held) if not held.is_empty() else ""
	_held.visible = not held.is_empty()
	TacticsViews.clear(_list)
	for row: Dictionary in _market.get_offers():
		_list.add_child(_offer_row(row))


func _offer_row(row: Dictionary) -> Control:
	var offer: TacticsOfferData = _market.region.offers[row["index"]]
	var box := TacticsViews.panel()
	box.name = "Offer%d" % row["index"]
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 6)
	box.add_child(rows)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	head.custom_minimum_size.y = ROW_MIN_PX - 20.0
	rows.add_child(head)
	var icon := _OfferIcon.new()
	icon.kind = offer.kind
	icon.glyph = TacticsPainter.glyph_for(offer.troop.base_class.id, offer.troop.keywords.map(func(k: TacticsKeywordData) -> StringName: return k.id)) if offer.troop != null else &""
	icon.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override(&"separation", 0)
	head.add_child(texts)
	texts.add_child(TacticsViews.label(_offer_name(offer), 26, Palette.CREAM))
	texts.add_child(TacticsViews.wrapped(_offer_desc(offer), 22, Palette.TEXT_DIM))
	texts.add_child(TacticsViews.label(tr("OFFER_PRICE_LEFT_FORMAT") % [row["price"], row["left"]], 22, Palette.GOLD if row["reason"] == &"" else Palette.TEXT_DIM))
	head.add_child(_buy_button(row["index"], -1, row["reason"] == &""))
	if offer.kind == &"offer.heal":
		rows.add_child(_patient_row())
	return box


# Healing: how many are wounded, and who is treated next.
func _patient_row() -> Control:
	var wounded := campaign.roster.get_wounded()
	if wounded.is_empty():
		return TacticsViews.label("OFFER_HEAL_NONE", 22, Palette.TEXT_DIM)
	var person := _market.get_next_patient()
	var line := HBoxContainer.new()
	line.name = "Patient"
	line.add_theme_constant_override(&"separation", 12)
	var face := TacticsFace.FaceView.new()
	face.look = person["look"]
	face.ring = Palette.VERMILION
	face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(face)
	var name := TacticsViews.wrapped(tr("OFFER_HEAL_NEXT_FORMAT") % [_person_name(person), wounded.size()], 22, Palette.CREAM)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name)
	return line


func _buy_button(index: int, person_id: int, can_buy: bool) -> PressButton:
	var button := PressButton.new()
	button.name = "Buy%d_%d" % [index, person_id] if person_id >= 0 else "Buy%d" % index
	button.text = "BUTTON_BUY"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 88)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if can_buy:
		button.theme_type_variation = &"PrimaryButton"
	# A refused tap still answers: the buzz and the reason.
	button.pressed.connect(func() -> void: buy(index, person_id))
	return button


func _offer_name(offer: TacticsOfferData) -> String:
	if offer.kind == &"offer.hire":
		return tr("OFFER_HIRE_FORMAT") % campaign.text.unit_name(offer.troop.id)
	if offer.kind == &"offer.item":
		return tr(offer.item.name_key)
	return tr("OFFER_HEAL")


func _offer_desc(offer: TacticsOfferData) -> String:
	if offer.kind == &"offer.hire":
		return tr("OFFER_HIRE_DESC")
	if offer.kind == &"offer.item":
		return tr(offer.item.desc_key)
	return tr("OFFER_HEAL_DESC")


func _person_name(person: Dictionary) -> String:
	if person.is_empty():
		return ""
	return campaign.bio.person_name(person) if person["is_named"] else campaign.bio.plain_name(person)


func _flash(index: int) -> void:
	var row := _list.get_node_or_null("Offer%d" % index) as CanvasItem
	if row == null or is_instant:
		return
	row.modulate = Color(1.6, 1.4, 0.8)
	row.create_tween().tween_property(row, ^"modulate", Color.WHITE, FLASH_SEC)


## What an offer sells, drawn small: the troop's token, a bandage, a drum.
class _OfferIcon extends Control:
	var kind: StringName = &"offer.hire"
	var glyph: StringName = &""

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 2.0
		if kind == &"offer.hire":
			TacticsPainter.draw_token(self, c, 0, false, glyph, false)
			return
		draw_circle(c, r, Palette.INK)
		draw_circle(c, r - 3.0, Palette.JADE if kind == &"offer.heal" else Palette.OCHRE)
		if kind == &"offer.heal":
			draw_rect(Rect2(c - Vector2(r * 0.18, r * 0.55), Vector2(r * 0.36, r * 1.1)), Palette.CREAM)
			draw_rect(Rect2(c - Vector2(r * 0.55, r * 0.18), Vector2(r * 1.1, r * 0.36)), Palette.CREAM)
		else:
			draw_rect(Rect2(c - Vector2(r * 0.5, r * 0.35), Vector2(r, r * 0.7)), Palette.VERMILION)
			draw_line(c + Vector2(-r * 0.5, -r * 0.35), c + Vector2(r * 0.5, r * 0.35), Palette.CREAM, 2.0)
