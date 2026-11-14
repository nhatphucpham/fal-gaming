extends SceneTree

# Headless test of the Audio service (the autoload, reached through Sound):
# every id of the bank has a stream (24 effects, 2 looping music tracks),
# an unknown id warns once and plays nothing, the 40 ms cooldown and the
# four-voice limit hold, nothing plays before the web unlock, and mute is
# saved to the settings file and read back. Settings go to
# TEST_SETTINGS_PATH, never the player's file.

const TEST_SETTINGS_PATH: String = "user://settings_test.json"
const EFFECT_COUNT: int = 24
const MUSIC_COUNT: int = 2


class WarningCounter extends Logger:
	var count: int = 0
	var needle: String = ""

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING and (code + rationale).contains(needle):
			count += 1


var _audio: AudioService
var _was_muted: bool = false


func _initialize() -> void:
	RunSettings.path = TEST_SETTINGS_PATH
	await process_frame
	var ok := await _run()
	if _audio != null:
		# Muting stops every voice; then the player's own state comes back.
		_audio.play_music(&"")
		_audio.set_muted(true)
		_audio.set_muted(_was_muted)
		_audio.is_silent = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	# Let the audio server drop the stopped playbacks before quitting.
	await create_timer(0.3).timeout
	if ok:
		print("Audio test passed")
		quit(0)
	else:
		quit(1)


func _run() -> bool:
	_audio = AudioService.instance
	if _audio == null:
		push_error("The Audio autoload is missing")
		return false
	_was_muted = _audio.is_muted()
	_audio.set_muted(false)
	# Headless has no sound device; the test drives the players anyway.
	_audio.is_silent = false
	var checks: Array[Callable] = [_check_bank, _check_unknown_id, _check_limits, _check_unlock, _check_mute_saved]
	for check: Callable in checks:
		if not await check.call():
			push_error("Audio test failed in %s" % check.get_method())
			return false
	return true


# 24 effects and 2 music loops, each with a stream; the music loops.
func _check_bank() -> bool:
	var catalog := load("res://Data/catalog.tres") as Catalog
	var bank := catalog.sounds
	if bank == null or not bank.validate().is_empty():
		push_error("The sound bank is missing or invalid")
		return false
	var effects := 0
	var music := 0
	for sound: SoundData in bank.sounds:
		if sound.is_music:
			music += 1
			var wav := sound.stream as AudioStreamWAV
			if wav == null or wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				push_error("Music %s should be a looping WAV" % sound.id)
				return false
		else:
			effects += 1
	if effects != EFFECT_COUNT or music != MUSIC_COUNT:
		push_error("Expected %d effects and %d music loops, got %d and %d" % [EFFECT_COUNT, MUSIC_COUNT, effects, music])
		return false
	return true


func _check_unknown_id() -> bool:
	var counter := WarningCounter.new()
	counter.needle = "unknown sound id"
	OS.add_logger(counter)
	Sound.play(&"no_such_sound")
	Sound.play(&"no_such_sound")
	Sound.play_music(&"no_such_music")
	OS.remove_logger(counter)
	_audio.play_music(&"")
	if counter.count != 2 or _audio.count_voices(&"no_such_sound") != 0:
		push_error("Unknown ids should warn once each (got %d warnings)" % counter.count)
		return false
	return true


# The same id twice at once plays once; spaced past the cooldown it stacks
# up to four voices and no more.
func _check_limits() -> bool:
	Sound.play(&"win")
	Sound.play(&"win")
	if _audio.count_voices(&"win") != 1:
		push_error("The cooldown should stop a second voice at once, got %d" % _audio.count_voices(&"win"))
		return false
	for attempt: int in 6:
		await create_timer(float(AudioService.COOLDOWN_MSEC + 15) / 1000.0).timeout
		Sound.play(&"win")
	var voices := _audio.count_voices(&"win")
	if voices != AudioService.MAX_VOICES_PER_ID:
		push_error("Expected %d voices of one id, got %d" % [AudioService.MAX_VOICES_PER_ID, voices])
		return false
	return true


# Locked (the web before its first gesture): nothing plays; the unlock
# starts the music that was asked for.
func _check_unlock() -> bool:
	_audio.set_muted(true)
	_audio.set_muted(false)
	_audio.is_unlocked = false
	Sound.play(&"coin")
	Sound.play_music(&"music_prep")
	if _audio.count_voices(&"coin") != 0 or _audio.get_music_id() != &"music_prep":
		push_error("Nothing should play before the unlock")
		return false
	Sound.unlock()
	await process_frame
	Sound.play(&"coin")
	if not _audio.is_unlocked or _audio.count_voices(&"coin") != 1:
		push_error("The unlock should let sounds play")
		return false
	return true


# toggle_muted flips mute, mutes the Master bus and writes the settings
# file; the saved value reads back, and the other setting is kept.
func _check_mute_saved() -> bool:
	RunSettings.save_prep_seconds(90)
	var muted := Sound.toggle_muted()
	if not muted or not RunSettings.load_muted() or not AudioServer.is_bus_mute(0) or RunSettings.load_prep_seconds() != 90:
		push_error("Mute should be on, saved and on the Master bus, with the prep time kept")
		return false
	Sound.play(&"coin")
	if _audio.count_voices(&"coin") != 0:
		push_error("Nothing plays while muted")
		return false
	if Sound.toggle_muted() or RunSettings.load_muted() or AudioServer.is_bus_mute(0):
		push_error("A second toggle should unmute and save it")
		return false
	if FileAccess.file_exists(RunSettings.PATH) and RunSettings.path == RunSettings.PATH:
		push_error("The test must write the test settings file")
		return false
	return true
