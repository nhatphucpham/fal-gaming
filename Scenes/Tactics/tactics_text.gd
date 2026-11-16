class_name TacticsText
extends RefCounted
## Player-facing text for the tactics screens, looked up from the tactics
## catalog by id: names of units, terrains, keywords, passives, skills,
## zones, orders and charges, terrain effect lines and the forecast's
## modifier names. Leaders made at runtime (named soldiers) and the names of
## roster soldiers are registered on it. Presentation only; it formats
## data, it decides nothing.
## [codeblock]
## var text := TacticsText.new(catalog)
## label.text = text.unit_name(battle.get_unit_state(0))
## [/codeblock]

## The five orders, in the order the picker shows them.
const ORDERS: Array[StringName] = [&"order.follow", &"order.vanguard", &"order.flank", &"order.hold", &"order.free"]

var catalog: TacticsCatalog
## Leaders that are not in the catalog, by id (register_unit).
var extra_units: Dictionary = {}
## Names of roster soldiers by record id (get_unit_state's record_id).
var person_names: Dictionary = {}


func _init(tactics_catalog: TacticsCatalog) -> void:
	catalog = tactics_catalog


## Lets unit_name() and unit_data() find a leader made at runtime.
func register_unit(data: TacticsUnitData) -> void:
	extra_units[data.id] = data


## The translated name of a unit dictionary (get_unit_state) or a leader
## or troop id; a roster soldier with a name goes by it.
func unit_name(unit: Variant) -> String:
	if unit is Dictionary and person_names.has(int(unit.get("record_id", -1))):
		return person_names[int(unit["record_id"])]
	var id: StringName = unit["id"] if unit is Dictionary else unit
	var data := unit_data(id)
	return tr(data.name_key) if data != null else String(id)


## The leader or troop resource with this id, or null.
func unit_data(id: StringName) -> TacticsUnitData:
	if extra_units.has(id):
		return extra_units[id]
	var leader := catalog.get_leader(id)
	if leader != null:
		return leader
	return catalog.get_troop(id)


## The auto-battle figure behind a leader or troop (for the close-up).
func base_unit(id: StringName) -> UnitData:
	var data := unit_data(id)
	return data.base_unit if data != null else null


func terrain_name(id: StringName) -> String:
	var terrain := catalog.get_terrain(id)
	return tr(terrain.name_key) if terrain != null else String(id)


## "Đi 2 · Giáp +5 · Cung +1 tầm": what the terrain does, from its data.
func terrain_effects(id: StringName) -> String:
	var terrain := catalog.get_terrain(id)
	if terrain == null:
		return ""
	if terrain.is_impassable:
		return tr("TERRAIN_IMPASSABLE")
	var parts: PackedStringArray = [tr("TERRAIN_MOVE_FORMAT") % terrain.move_cost]
	if terrain.armor_bonus != 0:
		parts.append(tr("TERRAIN_ARMOR_FORMAT") % terrain.armor_bonus)
	if terrain.damage_taken_pct != 0:
		parts.append(tr("TERRAIN_TAKEN_FORMAT") % terrain.damage_taken_pct)
	if terrain.ranged_damage_taken_pct != 0:
		parts.append(tr("TERRAIN_RANGED_TAKEN_FORMAT") % terrain.ranged_damage_taken_pct)
	if terrain.ranged_range_bonus != 0:
		parts.append(tr("TERRAIN_RANGE_FORMAT") % terrain.ranged_range_bonus)
	return " · ".join(parts)


func skill_name(id: StringName) -> String:
	var skill := catalog.get_skill(id)
	return tr(skill.name_key) if skill != null else String(id)


func zone_name(id: StringName) -> String:
	var zone := catalog.get_zone(id)
	return tr(zone.name_key) if zone != null else String(id)


func incident_name(id: StringName) -> String:
	var incident := catalog.get_incident(id)
	return tr(incident.name_key) if incident != null else String(id)


func passive_name(id: StringName) -> String:
	var passive := catalog.get_passive(id)
	return tr(passive.name_key) if passive != null else String(id)


## An order id (`order.vanguard`) as its key (`ORDER_VANGUARD`), translated.
func order_name(order: StringName) -> String:
	return tr(id_to_key(order))


func order_description(order: StringName) -> String:
	return tr(id_to_key(order) + "_DESC")


## A charge mechanism's name (`charge.focus` is "Tụ lực").
func charge_name(charge: StringName) -> String:
	return tr(id_to_key(charge))


## The name of any id the forecast lists: keyword, terrain, zone, passive
## or skill (a buff names its skill).
func modifier_name(id: StringName) -> String:
	var keyword := catalog.get_keyword(id)
	if keyword != null:
		return tr(keyword.name_key)
	var prefix := String(id).get_slice(".", 0)
	var by_prefix: Dictionary[String, Callable] = {
		"terrain": terrain_name, "zone": zone_name, "tactics_passive": passive_name, "tactics_skill": skill_name,
	}
	var lookup: Callable = by_prefix.get(prefix, Callable())
	return lookup.call(id) if lookup.is_valid() else String(id)


## Names of the keywords of a unit dictionary, joined.
func keyword_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for id: StringName in ids:
		names.append(modifier_name(id))
	return ", ".join(names)


## What a skill did or would do, for the close-up and the preview: the
## enemies it hits ("ours" when the other side cast it), the soldiers it
## strengthens, the zone it leaves, or that it reached nobody.
func skill_outcome(is_ours: bool, hit_count: int, buffed_count: int, zone_id: StringName) -> String:
	var parts: PackedStringArray = []
	if hit_count > 0:
		parts.append(tr("SKILL_PREVIEW_TARGETS_FORMAT" if is_ours else "SKILL_HITS_OURS_FORMAT") % hit_count)
	if buffed_count > 0:
		parts.append(tr("SKILL_BUFF_OURS_FORMAT" if is_ours else "SKILL_BUFF_ENEMY_FORMAT") % buffed_count)
	if not zone_id.is_empty():
		parts.append(tr("SKILL_PREVIEW_ZONE_FORMAT") % zone_name(zone_id))
	return " · ".join(parts) if not parts.is_empty() else tr("SKILL_NO_EFFECT")


## The passive names of a leader id, joined; empty for a troop.
func leader_passive_names(id: StringName) -> String:
	var leader := unit_data(id) as TacticsLeaderData
	if leader == null:
		return ""
	var names: PackedStringArray = []
	for passive: TacticsPassiveData in leader.passives:
		names.append(tr(passive.name_key))
	return ", ".join(names)


## `order.follow` -> `ORDER_FOLLOW`.
static func id_to_key(id: StringName) -> String:
	return String(id).replace(".", "_").to_upper()
