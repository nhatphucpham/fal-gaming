class_name RigPalette
extends RefCounted
## The figure colours of the approved sketch (`PAL`), its `dark` and `mix`,
## and the colour swaps per race: a piece is drawn in the sketch's human
## colours and RigMesh swaps them through the race's palette (wolf folk get
## fur for skin, a rust tunic and a grey horse; see UnitPainter.RACE_LOOKS).

const INK := Color("2b2320")
const CREAM := Color("f3e6c8")
const VERMILION := Color("d2462e")
const GOLD := Color("f2c14e")
const STEEL := Color("d8dde2")
const STEEL_DARK := Color("8f98a3")
const LEATHER := Color("5b3d2a")
const WOOD := Color("8a5a35")
const SKIN := Color("e8b48a")
const HAIR := Color("3a2a22")
const TUNIC := Color("3c5a99")
const TUNIC_DARK := Color("2f4779")
const TROUSERS := Color("4a3b33")
const BOOT := Color("2f2622")
const IRON := Color("a3abb5")
const STRAW := Color("d9b36a")
const MOSS := Color("5d7f45")
const MOSS_DARK := Color("466236")
const PLUM := Color("6a4a9c")
const PLUM_DARK := Color("4f3878")
const BEARD := Color("efe7d8")
const ORB := Color("8fe6ff")
const HORSE := Color("a4703f")
const HORSE_DARK := Color("7a5230")
const MUZZLE := Color("d6b089")
const SOLE := Color("cdb9a0")
const QUILT_SEAM := Color("c9b48c")
const VEST := Color("7a5034")
const HAT_STRAW_DARK := Color("b48d4c")
const NON_HAIR_LINE := Color("5a4438")
const BEARD_BACK := Color("cfc6b6")
const BEARD_LINE := Color("a99f8e")
const PLANK := Color("6e4527")
const ORB_BRIGHT := Color("e9fbff")
const GLOW := Color("ffe066")
const TRAIL := Color("fffaeb")
const SHADE := Color("1a1620")

static var _palettes: Dictionary[StringName, Dictionary] = {}


## `color` blended toward `to` by `t`, rounded to whole channel values.
static func mix(color: Color, to: Color, t: float) -> Color:
	return Color8(roundi(lerpf(color.r8, to.r8, t)), roundi(lerpf(color.g8, to.g8, t)), roundi(lerpf(color.b8, to.b8, t)))


## The sketch's darker shade for the far side of the body.
static func dark(color: Color) -> Color:
	return mix(color, SHADE, 0.14)


## The colour swaps of a race look (a UnitPainter.RACE_LOOKS entry), cached
## by `race_id`. Humans keep the sketch's colours (an empty palette).
static func get_palette(race_id: StringName, look: Dictionary) -> Dictionary:
	if _palettes.has(race_id):
		return _palettes[race_id]
	var swaps := {}
	var pairs: Array[Array] = [
		[SKIN, look["skin"]], [TUNIC, look["tunic"]], [TUNIC_DARK, look["tunic_dark"]],
		[HORSE, look["mount"]], [HORSE_DARK, look["mount_dark"]], [HAIR, look["hair"]],
	]
	for pair: Array in pairs:
		var from: Color = pair[0]
		var to: Color = pair[1]
		if from != to:
			swaps[from] = to
			swaps[dark(from)] = dark(to)
	_palettes[race_id] = swaps
	return swaps
