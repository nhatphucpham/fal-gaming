extends SceneTree

# Headless test of the AppLifecycle autoload: hiding pauses the tree and
# holds the sound (bus silent, players paused), showing gives the sound
# back at once and unpauses one frame later, the player's own mute and an
# earlier pause survive, a phone's pause notification hides while a lost
# desktop focus does not, and battles hold full frame rate against power
# saving. Leaves the tree, the mute and low processor mode as it found them.


# Counts its own process calls: zero while the tree is paused.
class Counter extends Node:
	var frames: int = 0

	func _process(_delta: float) -> void:
		frames += 1


var _app: AppLifecycleService
var _audio: AudioService


func _initialize() -> void:
	await process_frame
	_app = AppLifecycleService.instance
	_audio = AudioService.instance
	if _app == null or _audio == null:
		push_error("The AppLifecycle and Audio autoloads are missing")
		quit(1)
		return
	var was_muted := _audio.is_muted()
	var was_saving := _app.is_power_saving_wanted
	var ok := true
	var checks: Array[Callable] = [_check_hide_and_show, _check_mute_and_pause_kept, _check_notifications, _check_power_switch]
	for check: Callable in checks:
		if not await check.call():
			push_error("App lifecycle test failed in %s" % check.get_method())
			ok = false
			break
	_app.set_hidden(false)
	await process_frame
	await process_frame
	paused = false
	_audio.set_muted(was_muted)
	_app.is_power_saving_wanted = was_saving
	if ok:
		print("App lifecycle test passed")
	quit(0 if ok else 1)


func _check_hide_and_show() -> bool:
	_audio.set_muted(false)
	var counter := Counter.new()
	root.add_child(counter)
	await process_frame
	_app.set_hidden(true)
	var ok := _expect(_app.is_hidden() and paused, "hiding should pause the tree")
	ok = _expect(_audio.is_suspended() and AudioServer.is_bus_mute(0), "hiding should silence the sound") and ok
	var frames := counter.frames
	await process_frame
	await process_frame
	ok = _expect(counter.frames == frames, "nothing should process while hidden") and ok
	_app.set_hidden(false)
	ok = _expect(not _audio.is_suspended() and not AudioServer.is_bus_mute(0), "showing should give the sound back") and ok
	await process_frame
	ok = _expect(paused and counter.frames == frames, "the first frame after showing should stay paused") and ok
	await process_frame
	await process_frame
	ok = _expect(not paused and counter.frames > frames, "the tree should unpause one frame after showing") and ok
	counter.queue_free()
	return ok


# A player who muted stays muted; a tree paused before hiding stays paused.
func _check_mute_and_pause_kept() -> bool:
	_audio.set_muted(true)
	paused = true
	_app.set_hidden(true)
	_app.set_hidden(false)
	await process_frame
	await process_frame
	await process_frame
	var ok := _expect(_audio.is_muted() and AudioServer.is_bus_mute(0), "the player's mute should survive hiding")
	ok = _expect(paused, "a tree paused before hiding should stay paused") and ok
	paused = false
	_audio.set_muted(false)
	return ok


func _check_notifications() -> bool:
	_app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var ok := _expect(not _app.is_hidden() and not paused, "a lost desktop focus should not hide")
	_app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	ok = _expect(_app.is_hidden() and paused, "a phone's pause should hide") and ok
	_app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await process_frame
	await process_frame
	await process_frame
	return _expect(not _app.is_hidden() and not paused, "a phone's resume should show") and ok


# Power saving is on while wanted and nobody holds full frame rate; two
# holders must both let go.
func _check_power_switch() -> bool:
	_app.is_power_saving_wanted = true
	var ok := _expect(OS.low_processor_usage_mode, "power saving should be on when wanted")
	var first := RefCounted.new()
	var second := RefCounted.new()
	AppLifecycleService.hold_full_frame_rate(first, true)
	AppLifecycleService.hold_full_frame_rate(second, true)
	ok = _expect(not OS.low_processor_usage_mode, "a battle should turn power saving off") and ok
	AppLifecycleService.hold_full_frame_rate(first, false)
	ok = _expect(not OS.low_processor_usage_mode, "power saving should wait for every holder") and ok
	AppLifecycleService.hold_full_frame_rate(second, false)
	ok = _expect(OS.low_processor_usage_mode, "power saving should come back after the battle") and ok
	_app.is_power_saving_wanted = false
	return _expect(not OS.low_processor_usage_mode, "power saving should stay off when not wanted") and ok


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("AppLifecycle: " + message)
	return condition
