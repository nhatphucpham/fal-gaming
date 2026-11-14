extends SceneTree

# Synthesises every sound effect and the two music loops as 16-bit mono
# 22.05 kHz WAV files into Assets/Sfx/, deterministically (sines, a seeded
# noise generator, envelopes), and writes Data/Audio/sounds.tres listing
# them. Not shipped (Tools/ is excluded from every export preset). Run it
# after changing a sound, then import:
#   godot --headless --path . --script res://Tools/make_sfx.gd
# See Docs/systems/audio.md. OGG cannot be written from here, so the loops
# are WAV with a `smpl` loop chunk that Godot's importer reads.

const RATE: int = 22050
const OUT_DIR: String = "res://Assets/Sfx/"
const BANK_PATH: String = "res://Data/Audio/sounds.tres"
## Peak level after normalising (about -2 dBFS), so nothing clips.
const PEAK: float = 0.8
const TAU_F: float = TAU
const FADE_SEC: float = 0.006

## Sound id -> [builder method, length in seconds, volume_db].
const EFFECTS: Dictionary = {
	&"ui_tap": [&"_ui_tap", 0.06, -6.0],
	&"coin": [&"_coin", 0.22, -4.0],
	&"card_flip": [&"_card_flip", 0.09, -8.0],
	&"buy": [&"_buy", 0.16, -4.0],
	&"sell": [&"_sell", 0.2, -4.0],
	&"merge": [&"_merge", 0.42, -2.0],
	&"level_up": [&"_level_up", 0.55, -2.0],
	&"timer_tick": [&"_timer_tick", 0.05, -6.0],
	&"battle_drum": [&"_battle_drum", 0.7, 0.0],
	&"hit_light": [&"_hit_light", 0.08, -9.0],
	&"hit_heavy": [&"_hit_heavy", 0.16, -6.0],
	&"arrow": [&"_arrow", 0.18, -10.0],
	&"spell": [&"_spell", 0.35, -7.0],
	&"skill_cast": [&"_skill_cast", 0.3, -5.0],
	&"block": [&"_block", 0.22, -6.0],
	&"charge": [&"_charge", 0.42, -5.0],
	&"death": [&"_death", 0.4, -6.0],
	&"formation_on": [&"_formation_on", 0.45, -5.0],
	&"formation_break": [&"_formation_break", 0.3, -5.0],
	&"petrify": [&"_petrify", 0.6, -2.0],
	&"win": [&"_win", 1.0, -2.0],
	&"lose": [&"_lose", 0.95, -2.0],
	&"epiphany": [&"_epiphany", 1.2, -2.0],
	&"text_blip": [&"_text_blip", 0.03, -12.0],
}
## Loop id -> [builder, seconds, volume_db]; lengths hold whole cycles of
## every drone, so the loop is seamless.
const MUSIC: Dictionary = {
	&"music_prep": [&"_music_prep", 4.0, -8.0],
	&"music_battle": [&"_music_battle", 4.0, -8.0],
}
const PENTATONIC: Array[float] = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33]

var _noise_state: int = 0x2545F491


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var total := 0
	var entries: Array = []
	for group: Dictionary in [EFFECTS, MUSIC]:
		for id: StringName in group:
			var spec: Array = group[id]
			_noise_state = 0x2545F491 + String(id).hash() % 1000
			var buffer := PackedFloat32Array()
			buffer.resize(int(spec[1] * RATE))
			call(spec[0], buffer)
			var is_music := group == MUSIC
			if not is_music:
				_fade_out(buffer)
			var bytes := _write_wav(OUT_DIR + String(id) + ".wav", _normalise(buffer), is_music)
			total += bytes
			entries.append([id, is_music, spec[2]])
			print("%s %d bytes" % [id, bytes])
	_write_bank(entries)
	print("total %d bytes" % total)
	quit(0)


# --- Building blocks -----------------------------------------------------

func _noise() -> float:
	# xorshift32: the same bits on every machine.
	var x := _noise_state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_noise_state = x & 0xFFFFFFFF
	return float(_noise_state) / 2147483648.0 - 1.0


## A tone from `start` seconds: frequency glides from `freq` to `freq_end`,
## attack then exponential decay (`decay` per second), with `harmonics`
## [multiple, level] pairs. `wrap` adds the tail to the buffer's start
## (seamless loops).
func _tone(buffer: PackedFloat32Array, start: float, length: float, freq: float, level: float, decay: float, freq_end: float = -1.0, harmonics: Array = [], attack: float = 0.004, wrap: bool = false) -> void:
	var first := int(start * RATE)
	var count := int(length * RATE)
	var phase := 0.0
	var end_freq := freq if freq_end < 0.0 else freq_end
	for index: int in count:
		var t := float(index) / RATE
		var f := lerpf(freq, end_freq, t / length)
		phase += TAU_F * f / RATE
		var envelope := minf(1.0, t / attack) * exp(-decay * t)
		var value := sin(phase)
		for pair: Array in harmonics:
			value += sin(phase * pair[0]) * pair[1]
		var at := first + index
		if wrap:
			at %= buffer.size()
		elif at >= buffer.size():
			break
		buffer[at] += value * level * envelope


## Noise from `start`: one-pole low-pass (`smooth` 0..1, higher is darker)
## with an attack and exponential decay.
func _hiss(buffer: PackedFloat32Array, start: float, length: float, level: float, decay: float, smooth: float, wrap: bool = false) -> void:
	var first := int(start * RATE)
	var low := 0.0
	for index: int in int(length * RATE):
		var t := float(index) / RATE
		low = lerpf(_noise(), low, smooth)
		var at := first + index
		if wrap:
			at %= buffer.size()
		elif at >= buffer.size():
			break
		buffer[at] += low * level * minf(1.0, t / 0.002) * exp(-decay * t)


## Ramps the last few milliseconds to 0, so an effect never ends in a click
## (loops are not faded: they wrap).
func _fade_out(buffer: PackedFloat32Array) -> void:
	var count := mini(int(FADE_SEC * RATE), buffer.size())
	for index: int in count:
		buffer[buffer.size() - 1 - index] *= float(index) / count


func _normalise(buffer: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for value: float in buffer:
		peak = maxf(peak, absf(value))
	if peak > 0.0:
		for index: int in buffer.size():
			buffer[index] *= PEAK / peak
	return buffer


# --- Effects -------------------------------------------------------------

func _ui_tap(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.06, 1300.0, 1.0, 70.0, 1100.0)


func _coin(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.08, 1568.0, 0.8, 30.0, -1.0, [[2.0, 0.3]])
	_tone(b, 0.06, 0.16, 2093.0, 1.0, 22.0, -1.0, [[2.0, 0.25], [3.0, 0.1]])


func _card_flip(b: PackedFloat32Array) -> void:
	_hiss(b, 0.0, 0.09, 1.0, 45.0, 0.3)
	_tone(b, 0.0, 0.05, 500.0, 0.3, 60.0, 900.0)


func _buy(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.07, 660.0, 0.9, 25.0, -1.0, [[2.0, 0.2]])
	_tone(b, 0.07, 0.09, 990.0, 1.0, 22.0, -1.0, [[2.0, 0.2]])


func _sell(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.2, 1760.0, 0.8, 18.0, 1175.0, [[2.0, 0.2]])
	_hiss(b, 0.0, 0.05, 0.25, 60.0, 0.1)


func _merge(b: PackedFloat32Array) -> void:
	for step: int in 3:
		_tone(b, step * 0.08, 0.3, PENTATONIC[[0, 2, 5][step]] * 2.0, 0.8, 9.0, -1.0, [[2.0, 0.3], [3.0, 0.1]])
	_hiss(b, 0.2, 0.2, 0.15, 20.0, 0.0)


func _level_up(b: PackedFloat32Array) -> void:
	for step: int in 4:
		_tone(b, step * 0.09, 0.28, [392.0, 523.25, 659.25, 783.99][step], 0.8, 8.0, -1.0, [[2.0, 0.35]])


func _timer_tick(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.05, 950.0, 1.0, 90.0, 800.0, [[2.7, 0.3]])


func _battle_drum(b: PackedFloat32Array) -> void:
	for hit: int in 2:
		_tone(b, hit * 0.22, 0.45, 85.0, 1.0, 7.0, 45.0, [[1.5, 0.3]])
		_hiss(b, hit * 0.22, 0.12, 0.35, 30.0, 0.6)


func _hit_light(b: PackedFloat32Array) -> void:
	_hiss(b, 0.0, 0.08, 0.8, 55.0, 0.4)
	_tone(b, 0.0, 0.06, 320.0, 0.6, 50.0, 200.0)


func _hit_heavy(b: PackedFloat32Array) -> void:
	_hiss(b, 0.0, 0.16, 0.8, 28.0, 0.6)
	_tone(b, 0.0, 0.16, 150.0, 1.0, 20.0, 70.0, [[2.0, 0.3]])


func _arrow(b: PackedFloat32Array) -> void:
	_hiss(b, 0.0, 0.18, 0.7, 14.0, 0.15)
	_tone(b, 0.0, 0.18, 1800.0, 0.15, 14.0, 900.0)


func _spell(b: PackedFloat32Array) -> void:
	for pair: Array in [[880.0, 0.0], [1320.0, 0.05], [1760.0, 0.1]]:
		_tone(b, pair[1], 0.25, pair[0], 0.5, 9.0, pair[0] * 1.06, [[1.5, 0.2]], 0.03)


func _skill_cast(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.3, 300.0, 0.9, 6.0, 900.0, [[2.0, 0.4], [3.0, 0.15]], 0.04)
	_hiss(b, 0.0, 0.3, 0.2, 8.0, 0.2)


func _block(b: PackedFloat32Array) -> void:
	for pair: Array in [[820.0, 1.0], [1290.0, 0.6], [1930.0, 0.4]]:
		_tone(b, 0.0, 0.22, pair[0], pair[1], 16.0)
	_hiss(b, 0.0, 0.03, 0.5, 80.0, 0.0)


func _charge(b: PackedFloat32Array) -> void:
	for hit: int in 4:
		_tone(b, hit * 0.1, 0.1, 110.0, 0.9, 30.0, 70.0)
		_hiss(b, hit * 0.1, 0.06, 0.3, 50.0, 0.7)


func _death(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.4, 420.0, 0.8, 6.0, 120.0, [[1.5, 0.3]])
	_hiss(b, 0.05, 0.3, 0.3, 10.0, 0.7)


func _formation_on(b: PackedFloat32Array) -> void:
	for pair: Array in [[523.25, 0.0], [659.25, 0.04], [783.99, 0.08]]:
		_tone(b, pair[1], 0.37, pair[0], 0.6, 7.0, -1.0, [[2.0, 0.25], [4.0, 0.08]])


func _formation_break(b: PackedFloat32Array) -> void:
	_hiss(b, 0.0, 0.3, 1.0, 14.0, 0.2)
	_tone(b, 0.0, 0.3, 700.0, 0.5, 10.0, 260.0, [[1.41, 0.4]])


func _petrify(b: PackedFloat32Array) -> void:
	_hiss(b, 0.0, 0.6, 1.0, 4.0, 0.85)
	_tone(b, 0.0, 0.6, 60.0, 0.8, 4.0, 40.0, [[2.0, 0.4], [3.1, 0.2]])
	_tone(b, 0.05, 0.3, 240.0, 0.3, 12.0, 180.0)


func _win(b: PackedFloat32Array) -> void:
	var notes: Array = [[523.25, 0.0], [659.25, 0.14], [783.99, 0.28], [1046.5, 0.42]]
	for pair: Array in notes:
		_tone(b, pair[1], 0.55, pair[0], 0.7, 4.0, -1.0, [[2.0, 0.3], [3.0, 0.12]], 0.01)
	_tone(b, 0.0, 0.6, 130.81, 0.5, 5.0)


func _lose(b: PackedFloat32Array) -> void:
	var notes: Array = [[392.0, 0.0], [349.23, 0.25], [293.66, 0.5]]
	for pair: Array in notes:
		_tone(b, pair[1], 0.45, pair[0], 0.7, 4.0, -1.0, [[2.0, 0.2]], 0.02)
	_tone(b, 0.5, 0.45, 146.83, 0.4, 4.0)


func _epiphany(b: PackedFloat32Array) -> void:
	for pair: Array in [[110.0, 1.0], [163.0, 0.5], [227.0, 0.35], [331.0, 0.2]]:
		_tone(b, 0.0, 1.2, pair[0], pair[1], 2.5, pair[0] * 0.99)
	for step: int in 5:
		_tone(b, 0.25 + step * 0.12, 0.5, PENTATONIC[step + 2] * 2.0, 0.18, 6.0)


func _text_blip(b: PackedFloat32Array) -> void:
	_tone(b, 0.0, 0.03, 760.0, 1.0, 90.0)


# --- Music loops ---------------------------------------------------------

## Calm pentatonic plucks, two bars of eighth notes at 120 bpm, over a soft
## drone of whole cycles.
func _music_prep(b: PackedFloat32Array) -> void:
	var melody: Array[int] = [0, 2, 4, 2, 3, 4, 6, 4, 5, 3, 2, 0, 1, 2, 4, 2]
	for step: int in melody.size():
		_tone(b, step * 0.25, 0.6, PENTATONIC[melody[step]], 0.5, 5.0, -1.0, [[2.0, 0.25], [3.0, 0.08]], 0.005, true)
	_tone(b, 0.0, 4.0, 65.0, 0.2, 0.0, -1.0, [[2.0, 0.3]], 0.0001, true)
	_tone(b, 0.0, 4.0, 98.0, 0.12, 0.0, -1.0, [], 0.0001, true)


## A war-drum pattern with a low drone (55 Hz: 220 cycles in 4 s).
func _music_battle(b: PackedFloat32Array) -> void:
	var pattern: Array[float] = [0.0, 0.75, 1.0, 1.5, 2.0, 2.75, 3.0, 3.25, 3.5]
	for at: float in pattern:
		var is_strong := fmod(at, 1.0) == 0.0
		_tone(b, at, 0.4, 90.0 if is_strong else 120.0, 1.0 if is_strong else 0.6, 8.0, 50.0, [[1.5, 0.3]], 0.002, true)
		_hiss(b, at, 0.1, 0.3, 30.0, 0.6, true)
	_tone(b, 0.0, 4.0, 55.0, 0.25, 0.0, -1.0, [[2.0, 0.3], [3.0, 0.1]], 0.0001, true)


# --- Files ---------------------------------------------------------------

# RIFF/WAVE, PCM 16-bit mono; loops add a `smpl` chunk over the whole file.
# Returns the file size in bytes.
func _write_wav(path: String, samples: PackedFloat32Array, is_loop: bool) -> int:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index: int in samples.size():
		data.encode_s16(index * 2, clampi(roundi(samples[index] * 32767.0), -32767, 32767))
	var file := FileAccess.open(path, FileAccess.WRITE)
	var smpl_size := 60 if is_loop else 0
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(4 + (8 + 16) + (8 + data.size()) + (8 + smpl_size if is_loop else 0))
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(RATE)
	file.store_32(RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data.size())
	file.store_buffer(data)
	if is_loop:
		file.store_buffer("smpl".to_ascii_buffer())
		file.store_32(smpl_size)
		for value: int in [0, 0, 1000000000 / RATE, 60, 0, 0, 0, 1, 0]:
			file.store_32(value)
		for value: int in [0, 0, 0, samples.size() - 1, 0, 0]:
			file.store_32(value)
	var size := file.get_length()
	file.close()
	return size


func _write_bank(entries: Array) -> void:
	var lines: PackedStringArray = ['[gd_resource type="Resource" script_class="SoundBank" format=3]', ""]
	lines.append('[ext_resource type="Script" path="res://Systems/Audio/sound_bank.gd" id="1_bank"]')
	lines.append('[ext_resource type="Script" path="res://Systems/Audio/sound_data.gd" id="2_sound"]')
	for entry: Array in entries:
		lines.append('[ext_resource type="AudioStream" path="%s%s.wav" id="wav_%s"]' % [OUT_DIR, entry[0], entry[0]])
	lines.append("")
	var refs: PackedStringArray = []
	for entry: Array in entries:
		lines.append('[sub_resource type="Resource" id="sound_%s"]' % entry[0])
		lines.append('script = ExtResource("2_sound")')
		lines.append('id = &"%s"' % entry[0])
		lines.append('stream = ExtResource("wav_%s")' % entry[0])
		lines.append("volume_db = %s" % String.num(entry[2], 1))
		lines.append("is_music = %s" % ("true" if entry[1] else "false"))
		lines.append("")
		refs.append('SubResource("sound_%s")' % entry[0])
	lines.append("[resource]")
	lines.append('script = ExtResource("1_bank")')
	lines.append('sounds = Array[ExtResource("2_sound")]([%s])' % ", ".join(refs))
	var file := FileAccess.open(BANK_PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
