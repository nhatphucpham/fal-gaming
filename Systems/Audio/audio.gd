class_name AudioService
extends Node
## The game's sound, as the autoload `Audio`: sound effects by id from a
## pool of players on the Sfx bus, one music loop on the Music bus, and the
## mute switch saved in the settings. Presentation code reaches it through
## Sound's static calls on signals and events; the simulation never does.
## On the web nothing plays until the first user gesture ([method unlock]),
## and nothing here ever waits for audio. See Docs/systems/audio.md.
## [codeblock]
## Sound.play(&"coin")         # from presentation code
## Audio.set_muted(true)        # the autoload itself
## [/codeblock]

const BANK_PATH: String = "res://Data/Audio/sounds.tres"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"Sfx"
const POOL_SIZE: int = 8
## The same id plays again only after this long.
const COOLDOWN_MSEC: int = 40
## At most this many voices of one id at once.
const MAX_VOICES_PER_ID: int = 4
const MUSIC_DB: float = -10.0
const SFX_DB: float = -3.0
## Pitch rises by this per battle speed step above 1 (x2, x4).
const PITCH_PER_SPEED: float = 0.04

## The service in the tree (the autoload), for Sound's static calls; null
## when none is (a --script run without autoloads).
static var instance: AudioService

## Battle speed (1, 2, 4); the playback sets it, effects pitch up a little.
var battle_speed: int = 1
## False on the web until the first gesture; true elsewhere.
var is_unlocked: bool = true
## True with no sound device (headless runs and CI): nothing is started, so
## quitting mid-sound leaves no playback behind. Ids are still checked.
var is_silent: bool = false

var _bank: SoundBank
var _players: Array[AudioStreamPlayer] = []
## The id each pool player plays (or last played).
var _player_ids: Array[StringName] = []
var _music: AudioStreamPlayer
var _music_id: StringName = &""
var _last_played_msec: Dictionary[StringName, int] = {}
var _warned_ids: Dictionary[StringName, bool] = {}
var _is_muted: bool = false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	# Let go of every stream, so quitting while sounds play leaks nothing.
	for player: AudioStreamPlayer in _players + [_music]:
		if player != null:
			player.stop()
			player.stream = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS, MUSIC_DB)
	_ensure_bus(SFX_BUS, SFX_DB)
	for index: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
		_player_ids.append(&"")
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
	if _bank == null and ResourceLoader.exists(BANK_PATH):
		_bank = load(BANK_PATH) as SoundBank
	is_unlocked = not OS.has_feature("web")
	is_silent = AudioServer.get_driver_name() == "Dummy"
	set_muted(RunSettings.load_muted())


## Uses another bank (tests).
func set_bank(bank: SoundBank) -> void:
	_bank = bank


## Called on the first user gesture (the title's first tap): from then on
## sounds play; on the web the browser allows audio only after one.
func unlock() -> void:
	if is_unlocked:
		return
	is_unlocked = true
	if _music_id != &"":
		_start_music(_music_id)


## Plays a sound effect. An unknown id warns once and plays nothing; the
## same id is skipped within COOLDOWN_MSEC and past MAX_VOICES_PER_ID.
func play(id: StringName) -> void:
	var sound := _find(id)
	if sound == null or not is_unlocked or _is_muted or is_silent:
		return
	var now := Time.get_ticks_msec()
	if now - _last_played_msec.get(id, -COOLDOWN_MSEC) < COOLDOWN_MSEC or count_voices(id) >= MAX_VOICES_PER_ID:
		return
	_last_played_msec[id] = now
	var index := _free_player_index()
	var player := _players[index]
	player.stream = sound.stream
	player.volume_db = sound.volume_db
	player.pitch_scale = 1.0 + PITCH_PER_SPEED * (maxi(battle_speed, 1) - 1)
	_player_ids[index] = id
	player.play()


## Starts a music loop (keeps playing when it is already the one); an
## empty id stops the music.
func play_music(id: StringName) -> void:
	if id == _music_id and (_music.playing or not is_unlocked or _is_muted):
		return
	_music_id = id
	if id == &"":
		_music.stop()
		return
	_start_music(id)


func set_muted(muted: bool) -> void:
	_is_muted = muted
	AudioServer.set_bus_mute(0, muted)
	if muted:
		for player: AudioStreamPlayer in _players:
			player.stop()
		_music.stop()
	elif _music_id != &"":
		_start_music(_music_id)


func is_muted() -> bool:
	return _is_muted


## Flips mute and saves it in the settings.
func toggle_muted() -> bool:
	set_muted(not _is_muted)
	RunSettings.save_muted(_is_muted)
	return _is_muted


## Voices of `id` playing now.
func count_voices(id: StringName) -> int:
	var count := 0
	for index: int in _players.size():
		count += 1 if _player_ids[index] == id and _players[index].playing else 0
	return count


func get_music_id() -> StringName:
	return _music_id


func _start_music(id: StringName) -> void:
	var sound := _find(id)
	if sound == null or not is_unlocked or _is_muted or is_silent:
		return
	_music.stream = sound.stream
	_music.volume_db = sound.volume_db
	_music.play()


func _find(id: StringName) -> SoundData:
	var sound := _bank.get_sound(id) if _bank != null else null
	if sound == null and not _warned_ids.has(id):
		_warned_ids[id] = true
		push_warning("Audio: unknown sound id '%s'" % id)
	return sound


# A player that is not playing, else the one that started first (index
# order among busy ones is the start order closely enough for effects).
func _free_player_index() -> int:
	var oldest := 0
	var oldest_position := -1.0
	for index: int in _players.size():
		if not _players[index].playing:
			return index
		var position := _players[index].get_playback_position()
		if position > oldest_position:
			oldest = index
			oldest_position = position
	return oldest


func _ensure_bus(bus_name: StringName, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	AudioServer.set_bus_volume_db(index, volume_db)
