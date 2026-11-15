class_name VoiceStyle
extends Resource
## How a line is spoken: speed, pitch, volume and effort, sent with the request
## to the TTS service. A default style (or none) sends nothing extra and keeps
## the cache key of an unstyled line. Values outside the server limits are
## clamped. Speed and pitch are rounded as the server rounds them; volume and
## effort are rounded to 0.05 so near-equal styles share one cached line. A
## NaN or infinite value counts as the default. Save shared styles as .tres
## data (for example a "shout" style). See Docs/systems/voice.md.
## [codeblock]
## var angry := VoiceStyle.create(1.15, -2.0, 1.3, 2.0)
## Voice.play($Player, "Đứng lại!", "Mai Anh", angry)
## [/codeblock]

const SPEED_MIN := 0.25
const SPEED_MAX := 4.0
## The server rounds speed to this step.
const SPEED_STEP := 0.05
const SPEED_DEFAULT := 1.0
const PITCH_MIN := -12.0
const PITCH_MAX := 12.0
## Semitones; the server rounds pitch to this step.
const PITCH_STEP := 0.5
const PITCH_DEFAULT := 0.0
const VOLUME_MIN := 0.1
const VOLUME_MAX := 4.0
## Not a server step (it takes 1.15); rounded so near-equal styles share a file.
const VOLUME_STEP := 0.05
const VOLUME_DEFAULT := 1.0
const EFFORT_MIN := 0.0
const EFFORT_MAX := 2.0
## Not a server step (it takes 1.5); rounded so near-equal styles share a file.
const EFFORT_STEP := 0.05
const EFFORT_DEFAULT := 0.0

## Speaking rate; 1 is normal.
@export_range(SPEED_MIN, SPEED_MAX, SPEED_STEP) var speed := SPEED_DEFAULT
## Semitones up (positive) or down.
@export_range(PITCH_MIN, PITCH_MAX, PITCH_STEP) var pitch := PITCH_DEFAULT
## Loudness; 1 is normal.
@export_range(VOLUME_MIN, VOLUME_MAX, VOLUME_STEP) var volume := VOLUME_DEFAULT
## 0 normal, 1 raised voice, 2 shouting.
@export_range(EFFORT_MIN, EFFORT_MAX, EFFORT_STEP) var effort := EFFORT_DEFAULT


## A style with the given values (not yet clamped; the getters below clamp).
static func create(speed_value := SPEED_DEFAULT, pitch_value := PITCH_DEFAULT,
		volume_value := VOLUME_DEFAULT, effort_value := EFFORT_DEFAULT) -> VoiceStyle:
	var style := VoiceStyle.new()
	style.speed = speed_value
	style.pitch = pitch_value
	style.volume = volume_value
	style.effort = effort_value
	return style


## [member speed] clamped to the server limits and rounded to [constant SPEED_STEP].
func sent_speed() -> float:
	return _snap(speed, SPEED_MIN, SPEED_MAX, SPEED_STEP, SPEED_DEFAULT)


## [member pitch] clamped to the server limits and rounded to [constant PITCH_STEP].
func sent_pitch() -> float:
	return _snap(pitch, PITCH_MIN, PITCH_MAX, PITCH_STEP, PITCH_DEFAULT)


## [member volume] clamped to the server limits and rounded to [constant VOLUME_STEP].
func sent_volume() -> float:
	return _snap(volume, VOLUME_MIN, VOLUME_MAX, VOLUME_STEP, VOLUME_DEFAULT)


## [member effort] clamped to the server limits and rounded to [constant EFFORT_STEP].
func sent_effort() -> float:
	return _snap(effort, EFFORT_MIN, EFFORT_MAX, EFFORT_STEP, EFFORT_DEFAULT)


## True when every value, as sent, is the server default.
func is_default() -> bool:
	return request_fields().is_empty()


## The request body fields for this style: only the values that differ from
## the server default, clamped and rounded.
func request_fields() -> Dictionary[String, float]:
	var fields: Dictionary[String, float] = {}
	if sent_speed() != SPEED_DEFAULT:
		fields["speed"] = sent_speed()
	if sent_pitch() != PITCH_DEFAULT:
		fields["pitch"] = sent_pitch()
	if sent_volume() != VOLUME_DEFAULT:
		fields["volume"] = sent_volume()
	if sent_effort() != EFFORT_DEFAULT:
		fields["effort"] = sent_effort()
	return fields


## A stable text of the non-default values for the cache key, such as
## "speed=1.30 pitch=-2.0"; empty for a default style.
func key_text() -> String:
	var parts: PackedStringArray = []
	var fields := request_fields()
	for field: String in fields:
		var decimals := 1 if field == "pitch" else 2
		parts.append("%s=%s" % [field, String.num(fields[field], decimals).pad_decimals(decimals)])
	return " ".join(parts)


## Clamps, then rounds to [param step]; NaN and infinity give [param fallback].
## The round trip through text drops the binary noise of snappedf
## (1.3000000000000003), so values compare and print exactly.
static func _snap(value: float, low: float, high: float, step: float, fallback: float) -> float:
	if is_nan(value) or is_inf(value):
		return fallback
	var snapped := clampf(snappedf(clampf(value, low, high), step), low, high)
	return String.num(snapped, 4).to_float()
