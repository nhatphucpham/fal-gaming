class_name UnitPose
extends RefCounted
## How a unit figure stands right now: the joints and props UnitPainter reads
## when it draws (legs, weapon, shield, eyes, horse). Every number is a plain
## float so a PoseAnimator can tween it. Angles named `aim` follow the figure
## convention: 0 points up, positive turns toward the figure's front (+x).
## Figures drawn without a pose use the shared rest pose (get_rest()).
## [codeblock]
## var pose := UnitPose.new()
## pose.strike = 1.0
## UnitPainter.draw_figure(self, unit, UnitPainter.FACING_UP, 0.0, Vector2.ZERO, 1.0, pose)
## [/codeblock]

enum Eyes { OPEN, BLINK, HURT, HAPPY, DEAD }

## Walk cycle phase, in radians.
var step: float = 0.0
## 0..1, how much the legs and arms follow `step`.
var stride: float = 0.0
## -1 wound up (bow drawn), 0 at rest, +1 full strike (arrow loosed).
var strike: float = 0.0
## 0..1, weapon held high (skill wind-up, cheer).
var raise: float = 0.0
## 0..1, the off hand or the shield pulled up in front.
var guard: float = 0.0
## 0..1, knocked back by a hit.
var flinch: float = 0.0
## 0..1, collapsing (death).
var limp: float = 0.0
## 0..1, knees bent.
var crouch: float = 0.0
## -1..1, idle sway of cloth, tails and plumes.
var sway: float = 0.0
## Angle toward the target in the figure's own (flipped) space: 0 up .. PI down.
var aim: float = PI / 2.0
## 0..1, the weapon smear right after a strike.
var trail: float = 0.0
## 0..1, weapon or orb glow.
var glow: float = 0.0
var eyes: Eyes = Eyes.OPEN
## The horse's leg phase, in radians.
var gallop: float = 0.0
## 0..1, the horse rearing.
var rear: float = 0.0
## 0..1, an arrow is on the string.
var arrow: float = 1.0

static var _rest: UnitPose


## The shared pose of a figure standing still. Never change it.
static func get_rest() -> UnitPose:
	if _rest == null:
		_rest = UnitPose.new()
	return _rest


## Copies every field of `other` into this pose.
func copy_from(other: UnitPose) -> void:
	for property: Dictionary in get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			set(property["name"], other.get(property["name"]))
