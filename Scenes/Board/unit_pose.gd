class_name UnitPose
extends RefCounted
## One key pose of the bone rig: bone angles in degrees plus the controls a
## RigSolver and the piece drawers read (hip height, feet, weapon length,
## glow, eyes...). Values sit in one float array indexed by the constants
## below, so a PoseAnimator can blend two poses cheaply. Field names and
## defaults follow the approved sketch (Docs/sketches/unit-rig/rig2.js,
## `BASE` and `P()`); see Docs/systems/board.md.
## [codeblock]
## var stance := UnitPose.make({"uaF": -30, "laF": -82, "blade": -66, "hip": 26})
## var frame := RigSolver.solve(stance, RigSolver.VIEW_BACK)
## [/codeblock]

const KEYS: Array[StringName] = [
	&"root", &"torso", &"head", &"uaF", &"laF", &"uaB", &"laB", &"thF", &"shF", &"thB", &"shB", &"ftF", &"ftB",
	&"blade", &"hip", &"fF", &"fB", &"lF", &"lB", &"stF", &"stB", &"heF", &"heB", &"ik", &"flat", &"dx", &"jump",
	&"glow", &"trail", &"flash", &"alpha", &"eyes", &"wl", &"wo", &"grip", &"gw", &"draw", &"nock", &"tilt",
	&"ride", &"hph", &"hg", &"hl", &"bowUp", &"kUF", &"kLF", &"kUB", &"kLB",
]
const ROOT: int = 0
const TORSO: int = 1
const HEAD: int = 2
const UA_F: int = 3
const LA_F: int = 4
const UA_B: int = 5
const LA_B: int = 6
const TH_F: int = 7
const SH_F: int = 8
const TH_B: int = 9
const SH_B: int = 10
const FT_F: int = 11
const FT_B: int = 12
## Screen angle of the weapon: 0 toward the sword side, -90 up, 90 down.
const BLADE: int = 13
## Height of the hips above the ground.
const HIP: int = 14
## Feet: x of each foot, lift, step ahead along the facing, heel raised 0..1.
const F_F: int = 15
const F_B: int = 16
const L_F: int = 17
const L_B: int = 18
const ST_F: int = 19
const ST_B: int = 20
const HE_F: int = 21
const HE_B: int = 22
## 1 places the feet by IK; 0 lets the legs use their own angles.
const IK: int = 23
const FLAT: int = 24
## Step toward the target (> 0) or back (< 0); the board turns it into a push.
const DX: int = 25
const JUMP: int = 26
const GLOW: int = 27
const TRAIL: int = 28
const FLASH: int = 29
## The sketch's fade, kept in the table but not drawn: UnitView fades the
## whole unit instead.
const ALPHA: int = 30
## 0 open, 1 shut or hurt, 2 happy.
const EYES: int = 31
## Weapon length scale (foreshortening) and slide along the weapon.
const WL: int = 32
const WO: int = 33
## The off hand holds the weapon `grip` along it with weight `gw`.
const GRIP: int = 34
const GW: int = 35
## Bow string drawn, arrow nocked, bow held upright.
const DRAW: int = 36
const NOCK: int = 37
const TILT: int = 38
## Seated on a horse; the horse's gallop phase, gallop amount and rear.
const RIDE: int = 39
const HPH: int = 40
const HG: int = 41
const HL: int = 42
const BOW_UP: int = 43
## Arm bone length scales (an arm pointing at the viewer looks shorter).
const K_UF: int = 44
const K_LF: int = 45
const K_UB: int = 46
const K_LB: int = 47

static var _index: Dictionary[StringName, int] = {}
static var _base := PackedFloat32Array()

var values := PackedFloat32Array()


func _init() -> void:
	values = _get_base()


## A pose from `fields` (sketch names, such as "uaF") over the defaults, with
## the sketch's narrowing: feet pulled under the body, and a lunge (dx > 0)
## or flinch (dx < 0) turned into a step when no step is given.
static func make(fields: Dictionary) -> UnitPose:
	return _narrowed(UnitPose.new(), fields, fields.has("stF"))


## This pose with `fields` changed, narrowed again like the sketch's
## `P(Object.assign({}, pose, fields))`.
func with_fields(fields: Dictionary) -> UnitPose:
	return _narrowed(copy(), fields, true)


## This pose with `fields` changed and nothing else (the sketch's class
## `fit`, which does not narrow).
func merged(fields: Dictionary) -> UnitPose:
	var pose := copy()
	pose.apply(fields)
	return pose


func copy() -> UnitPose:
	var pose := UnitPose.new()
	pose.values = values.duplicate()
	return pose


func apply(fields: Dictionary) -> void:
	for key: Variant in fields:
		var at: int = _get_index().get(StringName(key), -1)
		assert(at >= 0, "Board: unknown pose field %s" % key)
		values[at] = float(fields[key])


func get_value(key: StringName) -> float:
	return values[_get_index()[key]]


## The pose between `from` and `to` at `t` 0..1; the eyes switch at 0.3.
static func blend(from: UnitPose, to: UnitPose, t: float) -> UnitPose:
	var pose := UnitPose.new()
	var mixed := from.values.duplicate()
	for index: int in mixed.size():
		mixed[index] = lerpf(from.values[index], to.values[index], t)
	mixed[EYES] = to.values[EYES] if t > 0.3 else from.values[EYES]
	pose.values = mixed
	return pose


static func _narrowed(pose: UnitPose, fields: Dictionary, has_step: bool) -> UnitPose:
	pose.apply(fields)
	var v := pose.values
	v[F_F] = 3.0 + (v[F_F] - 3.8) * 0.25
	v[F_B] = -3.0 + (v[F_B] + 3.8) * 0.25
	if not has_step:
		if v[DX] > 0.0:
			v[ST_F] = 5.0
			v[ST_B] = -4.0
			v[HE_B] = 0.7
		elif v[DX] < 0.0:
			v[ST_F] = -1.0
			v[ST_B] = -4.0
			v[HE_F] = 0.3
		elif v[HIP] < 26.5 and v[IK] == 1.0:
			v[ST_F] = 2.0
			v[ST_B] = -2.0
	pose.values = v
	return pose


static func _get_index() -> Dictionary[StringName, int]:
	if _index.is_empty():
		for index: int in KEYS.size():
			_index[KEYS[index]] = index
	return _index


static func _get_base() -> PackedFloat32Array:
	if _base.is_empty():
		_base.resize(KEYS.size())
		_base.fill(0.0)
		for key: StringName in [&"ik", &"flat", &"alpha", &"wl", &"kUF", &"kLF", &"kUB", &"kLB"]:
			_base[_get_index()[key]] = 1.0
		_base[BLADE] = 30.0
		_base[HIP] = 27.0
		_base[F_F] = 3.8
		_base[F_B] = -3.8
	return _base.duplicate()
