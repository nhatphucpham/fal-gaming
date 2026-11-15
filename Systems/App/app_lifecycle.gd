class_name AppLifecycleService
extends Node
## The app's lifecycle, as the autoload `AppLifecycle`: knows whether the
## app is hidden (a browser tab in the background via `visibilitychange`, a
## phone app sent away via NOTIFICATION_APPLICATION_PAUSED; a desktop window
## losing focus is not hidden). While hidden the SceneTree is paused and
## every sound is held; once visible again the tree unpauses one frame
## later, so the first long frame does not reach timers, tweens or the
## battle clock. It also owns the power-saving switch (low processor mode)
## that a battle turns off while it plays. See Docs/systems/app_lifecycle.md.
## [codeblock]
## AppLifecycleService.hold_full_frame_rate(self, true)   # a battle starts
## AppLifecycle.set_hidden(true)                          # tests
## [/codeblock]

## The app was hidden or shown again (before the tree unpauses).
signal visibility_changed(is_hidden: bool)

## Frames to wait after becoming visible before unpausing: the first one
## carries the whole hidden time as its delta.
const RESUME_DELAY_FRAMES: int = 1

## The service in the tree (the autoload), for the static calls; null when
## none is.
static var instance: AppLifecycleService

## True when idle screens should save power: low processor mode, which
## draws a frame only when something changed. From the project setting
## application/run/low_processor_mode at start.
var is_power_saving_wanted: bool = false:
	set(value):
		is_power_saving_wanted = value
		_apply_power_mode()

var _is_hidden: bool = false
# Whether the tree was paused before it was hidden: it stays so.
var _was_paused: bool = false
# The process frame after which the tree unpauses; -1 when none is due.
var _resume_after_frame: int = -1
# Objects (by instance id) that need every frame drawn now.
var _full_frame_holders: Dictionary[int, bool] = {}
# The browser's document and the visibilitychange callback; kept so the
# callback is not collected while the page lives.
var _document: JavaScriptObject
var _on_visibility_change: JavaScriptObject


## Asks for every frame to be drawn while `holder` needs it (a battle
## playing), or gives that back; power saving returns when no one holds.
static func hold_full_frame_rate(holder: Object, is_held: bool) -> void:
	if instance != null:
		instance.set_full_frame_rate(holder, is_held)


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_power_saving_wanted = OS.low_processor_usage_mode
	if OS.has_feature("web"):
		_document = JavaScriptBridge.get_interface("document")
		_on_visibility_change = JavaScriptBridge.create_callback(_on_web_visibility_change)
		_document.call("addEventListener", "visibilitychange", _on_visibility_change)


func _notification(what: int) -> void:
	# Only phones send these; desktop focus changes are ignored on purpose.
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			set_hidden(true)
		NOTIFICATION_APPLICATION_RESUMED:
			set_hidden(false)


func _process(_delta: float) -> void:
	if _resume_after_frame >= 0 and Engine.get_process_frames() > _resume_after_frame:
		_resume_after_frame = -1
		get_tree().paused = _was_paused


func is_hidden() -> bool:
	return _is_hidden


## Hides (pauses the tree, holds the sound) or shows the app again (sound
## back now, the tree unpaused RESUME_DELAY_FRAMES later). The platform
## calls it; tests call it to simulate.
func set_hidden(hidden: bool) -> void:
	if hidden == _is_hidden:
		return
	_is_hidden = hidden
	if hidden:
		# Hidden again before it unpaused: keep the state from before.
		if _resume_after_frame < 0:
			_was_paused = get_tree().paused
		_resume_after_frame = -1
		get_tree().paused = true
	else:
		_resume_after_frame = Engine.get_process_frames() + RESUME_DELAY_FRAMES
	if AudioService.instance != null:
		AudioService.instance.set_suspended(hidden)
	visibility_changed.emit(hidden)


## See hold_full_frame_rate().
func set_full_frame_rate(holder: Object, is_held: bool) -> void:
	if is_held:
		_full_frame_holders[holder.get_instance_id()] = true
	else:
		_full_frame_holders.erase(holder.get_instance_id())
	_apply_power_mode()


## True while low processor mode is on.
func is_power_saving() -> bool:
	return OS.low_processor_usage_mode


# The only place that switches low processor mode. On desktop it sleeps
# part of every frame, which a battle cannot spare; idle screens gain.
func _apply_power_mode() -> void:
	OS.low_processor_usage_mode = is_power_saving_wanted and _full_frame_holders.is_empty()


func _on_web_visibility_change(_args: Array) -> void:
	set_hidden(bool(JavaScriptBridge.eval("document.hidden", true)))
