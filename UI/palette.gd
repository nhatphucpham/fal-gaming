class_name Palette
extends RefCounted
## The game's colours in one place: a warm folk-print palette (cream paper,
## ink lines, vermilion, indigo, ochre, jade) plus the cost colours shared by
## unit cards and unit trim. Presentation only.

const INK := Color("2b2320")
const INK_SOFT := Color("2b2320b0")
const CREAM := Color("f3e6c8")
const PAPER := Color("e9d6ae")
const PAPER_DARK := Color("d7c093")
const VERMILION := Color("d2462e")
const VERMILION_DARK := Color("9e2f1e")
const INDIGO := Color("2f3e6b")
const INDIGO_DARK := Color("1d2644")
const OCHRE := Color("d9a23b")
const GOLD := Color("f2c14e")
const JADE := Color("3e9c7e")
const JADE_LIGHT := Color("7fd1b0")
const STEEL := Color("d8dde2")
const WOOD := Color("8a5a35")

## Screen background around and behind the board.
const BACKDROP := Color("1b2035")
const BACKDROP_LINE := Color("262c47")
const PANEL := Color("262d4a")
const TEXT := Color("f3e6c8")
const TEXT_DIM := Color("b9ad93")

const PLAYER_RING := Color("4f7fd6")
const ENEMY_RING := Color("d2462e")
const PLAYER_HP := Color("4cbf86")
const ENEMY_HP := Color("e2553a")

## Card background and unit trim by cost 1..5: grey, green, blue, purple, red.
const COST_COLORS: Array[Color] = [
	Color("8e8a82"), Color("4e9a5b"), Color("3d6fb5"), Color("8250a8"), Color("c8402e"),
]


## The colour of a unit cost, clamped to 1..5.
static func cost_color(cost: int) -> Color:
	return COST_COLORS[clampi(cost, 1, COST_COLORS.size()) - 1]
