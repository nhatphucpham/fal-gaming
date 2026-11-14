class_name SoundData
extends Resource
## One sound the game can play by id: its stream, loudness and whether it
## is a music loop. An entry of the SoundBank in Data/Audio/sounds.tres.

## Stable id (`ui_tap`, `music_prep`); presentation code plays it by this.
@export var id: StringName = &""
@export var stream: AudioStream
## Added to the bus volume.
@export_range(-40.0, 6.0, 0.5) var volume_db: float = 0.0
## Music loops play on the Music bus, one at a time.
@export var is_music: bool = false
