class_name TacticsMarket
extends RefCounted
## Chợ theo thành: one region's market between battles. Each offer of the
## region (TacticsOfferData) costs supplies and sells at most its `stock`
## times a world turn; the handler of its kind does the rest: hire a
## soldier of a troop (it joins any leader with room at the next muster),
## heal a wounded soldier (back in the next muster) or buy a one-use item.
## Purchases change the roster; the caller saves it. See
## Docs/systems/tactics_world.md.
## [codeblock]
## var market := TacticsMarket.new(roster, region)
## var result := market.buy(0)
## if result["ok"]: roster.save()
## [/codeblock]

## The offer kinds a market knows (TacticsOfferData.kind).
const KINDS: Array[StringName] = [&"offer.hire", &"offer.heal", &"offer.item"]
const REASON_SUPPLIES: StringName = &"supplies"
const REASON_SOLD_OUT: StringName = &"sold_out"
const REASON_NO_WOUNDED: StringName = &"no_wounded"
const REASON_CLOSED: StringName = &"closed"

var roster: TacticsRoster
var region: TacticsRegionData

var _handlers: Dictionary[StringName, Callable] = {}


func _init(tactics_roster: TacticsRoster, market_region: TacticsRegionData) -> void:
	roster = tactics_roster
	region = market_region
	_handlers = {&"offer.hire": _hire, &"offer.heal": _heal, &"offer.item": _buy_item}


## Per offer: {index, kind, price, left (stock left this turn), reason
## (why it cannot be bought now, empty when it can)}.
func get_offers() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in region.offers.size():
		var offer: TacticsOfferData = region.offers[index]
		rows.append({"index": index, "kind": offer.kind, "price": offer.price, "left": _left(index), "reason": refusal(index, -1)})
	return rows


## Why offer `index` cannot be bought now (for `person_id` when it heals;
## -1 heals the wounded soldier with the most marks), or empty.
func refusal(index: int, person_id: int) -> StringName:
	var offer: TacticsOfferData = region.offers[index]
	if not roster.world.can_shop(region.id):
		return REASON_CLOSED
	if _left(index) <= 0:
		return REASON_SOLD_OUT
	if roster.supplies < offer.price:
		return REASON_SUPPLIES
	if offer.kind == &"offer.heal" and _patient(person_id).is_empty():
		return REASON_NO_WOUNDED
	return &""


## Buys offer `index`: {ok, reason, person (the hired or healed id, -1),
## item (its id or empty)}. Changes the roster only when ok.
func buy(index: int, person_id: int = -1) -> Dictionary:
	var result := {"ok": false, "reason": &"", "person": -1, "item": &""}
	if index < 0 or index >= region.offers.size():
		push_error("TacticsMarket: %s has no offer %d" % [region.id, index])
		return result
	result["reason"] = refusal(index, person_id)
	if result["reason"] != &"":
		return result
	var offer: TacticsOfferData = region.offers[index]
	roster.supplies -= offer.price
	roster.world.note_sold(region.id, index)
	_handlers[offer.kind].call(offer, person_id, result)
	result["ok"] = true
	return result


## The wounded soldier healing treats when no one is named: the one with
## the most marks (then the lower id); empty when no one is wounded.
func get_next_patient() -> Dictionary:
	return _patient(-1)


func _left(index: int) -> int:
	return region.offers[index].stock - roster.world.get_sold(region.id, index)


# The wounded soldier to heal: that person, or the one with the most marks
# (then the lower id).
func _patient(person_id: int) -> Dictionary:
	var wounded := roster.get_wounded()
	if person_id >= 0:
		for person: Dictionary in wounded:
			if person["id"] == person_id:
				return person
		return {}
	wounded.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_marks: int = (left["marks"] as Array).size()
		var right_marks: int = (right["marks"] as Array).size()
		return left_marks > right_marks or (left_marks == right_marks and int(left["id"]) < int(right["id"])))
	return wounded[0] if not wounded.is_empty() else {}


func _hire(offer: TacticsOfferData, _person_id: int, result: Dictionary) -> void:
	# The region's own commander signs the soldier on; it joins whichever
	# leader has room at the muster.
	var leader_id: StringName = region.scenario.leaders_a[0].id if region.scenario != null and not region.scenario.leaders_a.is_empty() else &""
	var person := roster.recruit(offer.troop.id, leader_id)
	person["is_hired"] = true
	result["person"] = person["id"]


func _heal(_offer: TacticsOfferData, person_id: int, result: Dictionary) -> void:
	var person := _patient(person_id)
	person["rest_until"] = 0
	result["person"] = person["id"]


func _buy_item(offer: TacticsOfferData, _person_id: int, result: Dictionary) -> void:
	roster.items[String(offer.item.id)] = roster.get_item_count(offer.item.id) + 1
	result["item"] = offer.item.id
