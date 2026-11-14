class_name SoundBank
extends Resource
## Every sound id of the game (Data/Audio/sounds.tres, listed in the
## catalog as `sounds`). The Audio service looks ids up here, so adding a
## sound is a WAV file plus an entry. See Docs/systems/audio.md.

@export var sounds: Array[SoundData] = []


## The entry with this id, or null.
func get_sound(id: StringName) -> SoundData:
	for sound: SoundData in sounds:
		if sound != null and sound.id == id:
			return sound
	return null


## Problems: empty entries, doubled or empty ids, missing streams.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen: Dictionary[StringName, bool] = {}
	for index: int in sounds.size():
		var sound := sounds[index]
		if sound == null or sound.id == &"" or seen.has(sound.id) or sound.stream == null:
			problems.append("Audio: sounds[%d] in %s is empty, has no stream or a doubled id" % [index, resource_path])
			continue
		seen[sound.id] = true
	return problems
