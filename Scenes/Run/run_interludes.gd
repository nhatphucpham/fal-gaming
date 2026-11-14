class_name RunInterludes
extends RefCounted
## The cutscenes between stages, played over the run screen: a pending Kỳ
## Ngộ (its choice goes to RunState.choose_epiphany) and, once per run, the
## story scene before the boss stage. Each takes a callback for when it is
## over. See Docs/systems/cutscene.md.

## The cutscene playing now, or null (tests step through it).
var cutscene: CutsceneScreen

var _run: RunState
var _host: Control


func _init(run: RunState, host: Control) -> void:
	_run = run
	_host = host


## Plays the pending Kỳ Ngộ, takes the card chosen, then calls `then`.
## False (and nothing played) when none is pending.
func play_epiphany(then: Callable) -> bool:
	var data := EpiphanyCutscene.build(_run)
	if data == null:
		return false
	var title := _host.tr("EPIPHANY_TITLE_FORMAT") % _host.tr(_family_name_key(_run.epiphanies.get_pending_family()))
	_play(data, title, func(choice: int) -> void:
		_run.choose_epiphany(maxi(choice, 0))
		then.call())
	return true


## Plays the story scene when the run has just reached the boss stage for
## the first time (`previous_stage` was the one before it), then `then`.
## False when it is not due.
func play_story_if_due(previous_stage: int, then: Callable) -> bool:
	if previous_stage != _run.rules.boss_stage - 1 or _run.stage != _run.rules.boss_stage:
		return false
	var data := EpiphanyCutscene.load_story()
	if data == null:
		return false
	_play(data, "", func(_choice: int) -> void: then.call())
	return true


func is_playing() -> bool:
	return cutscene != null


func _play(data: CutsceneData, title: String, done: Callable) -> void:
	cutscene = CutsceneScreen.new()
	_host.add_child(cutscene)
	cutscene.finished.connect(func(choice: int) -> void:
		cutscene.queue_free()
		cutscene = null
		done.call(choice))
	cutscene.present(data, _run.catalog, title)


# "CLASS_SHIELD" or "RACE_WOLF" for a milestone family.
func _family_name_key(family_id: StringName) -> String:
	var milestone := _run.catalog.get_milestone(family_id)
	if milestone == null:
		return ""
	var counted := String(milestone.counted_id)
	return counted.replace(".", "_").to_upper()
