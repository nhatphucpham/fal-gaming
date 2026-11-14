class_name RunInterludes
extends RefCounted
## The cutscenes between stages, played over the run screen: a pending Kỳ
## Ngộ (its choice goes to RunState.choose_epiphany the moment a card is
## taken), a pending road encounter ("Dọc đường", its choice goes to
## RunState.choose_encounter the same way) and, once per run, the story
## scene before the boss stage. Each takes a callback for when it is over.
## See Docs/systems/cutscene.md and Docs/systems/encounter.md.

## The cutscene playing now, or null (tests step through it).
var cutscene: CutsceneScreen

var _run: RunState
var _host: Control


func _init(run: RunState, host: Control) -> void:
	_run = run
	_host = host


## Plays the pending Kỳ Ngộ. The card taken goes to the run at once and
## `chosen` is called (the screen saves there, so closing the app during
## the closing wipe keeps it); `then` once the wipe is over. False (and
## nothing played) when none is pending.
func play_epiphany(chosen: Callable, then: Callable) -> bool:
	var data := EpiphanyCutscene.build(_run)
	if data == null:
		return false
	var title := _host.tr("EPIPHANY_TITLE_FORMAT") % _host.tr(_family_name_key(_run.epiphanies.get_pending_family()))
	var take := func(choice: int) -> void:
		if _run.epiphanies.has_pending():
			_run.choose_epiphany(maxi(choice, 0))
			chosen.call()
	_play(data, title, func(choice: int) -> void:
		take.call(choice)
		then.call())
	cutscene.choice_made.connect(take)
	return true


## Plays the pending road encounter. The card taken goes to the run at once
## (which begins the next preparation) and `chosen` is called; `then` once
## the wipe is over. A card the run cannot pay is greyed and refused. False
## (and nothing played) when none is pending.
func play_encounter(chosen: Callable, then: Callable) -> bool:
	var data := EncounterCutscene.build(_run)
	if data == null:
		return false
	var title := _host.tr("ENCOUNTER_TITLE_FORMAT") % _host.tr(_run.encounters.get_pending().name_key)
	_play(data, title, func(_choice: int) -> void: then.call())
	cutscene.choice_made.connect(func(choice: int) -> void:
		if _run.choose_encounter(choice) == RunState.Result.OK:
			chosen.call())
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
