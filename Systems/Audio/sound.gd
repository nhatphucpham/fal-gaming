class_name Sound
extends RefCounted
## How presentation code reaches the `Audio` autoload: static calls that
## forward to the AudioService in the tree, and do nothing when there is
## none (scripts run with --script load no autoloads; a test adds its own
## AudioService). Sound never blocks and never fails a caller.
## [codeblock]
## Sound.play(&"coin")
## Sound.play_music(&"music_prep")
## [/codeblock]


static func play(id: StringName) -> void:
	if AudioService.instance != null:
		AudioService.instance.play(id)


static func play_music(id: StringName) -> void:
	if AudioService.instance != null:
		AudioService.instance.play_music(id)


## Battle speed 1, 2 or 4: effects pitch up a little with it.
static func set_battle_speed(speed: int) -> void:
	if AudioService.instance != null:
		AudioService.instance.battle_speed = speed


static func is_muted() -> bool:
	return AudioService.instance != null and AudioService.instance.is_muted()


## Flips mute and saves it; false without an AudioService.
static func toggle_muted() -> bool:
	return AudioService.instance != null and AudioService.instance.toggle_muted()


static func is_unlocked() -> bool:
	return AudioService.instance == null or AudioService.instance.is_unlocked


static func unlock() -> void:
	if AudioService.instance != null:
		AudioService.instance.unlock()
