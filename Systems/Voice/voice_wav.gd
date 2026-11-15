class_name VoiceWav
extends RefCounted
## Mono 16-bit PCM WAV helpers for the voice cache and bundled lines. Static
## only; [VoiceService] uses them to write and read [code]<key>.wav[/code].
## [codeblock]
## var bytes := VoiceWav.wav_bytes(pcm, 24000)
## var stream := VoiceWav.read_wav(bytes)  # null if it is not one
## [/codeblock]


## An [AudioStreamWAV] playing raw 16-bit mono [param pcm] at [param rate] Hz.
static func pcm_stream(pcm: PackedByteArray, rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = pcm
	return stream


## A mono 16-bit PCM WAV file around [param pcm].
static func wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(44)
	out.encode_u32(0, 0x46464952)  # "RIFF"
	out.encode_u32(4, 36 + pcm.size())
	out.encode_u32(8, 0x45564157)  # "WAVE"
	out.encode_u32(12, 0x20746d66)  # "fmt "
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)  # PCM
	out.encode_u16(22, 1)  # mono
	out.encode_u32(24, rate)
	out.encode_u32(28, rate * 2)
	out.encode_u16(32, 2)
	out.encode_u16(34, 16)
	out.encode_u32(36, 0x61746164)  # "data"
	out.encode_u32(40, pcm.size())
	out.append_array(pcm)
	return out


## Reads a mono or stereo 16-bit PCM WAV file. Returns null if it is not one
## or is truncated.
static func read_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44 or bytes.decode_u32(0) != 0x46464952 \
			or bytes.decode_u32(8) != 0x45564157:
		return null
	var pos := 12
	var channels := 0
	var rate := 0
	while pos + 8 <= bytes.size():
		var id := bytes.decode_u32(pos)
		var size := bytes.decode_u32(pos + 4)
		pos += 8
		# Check the whole chunk is there before decoding any field in it.
		if pos + size > bytes.size():
			return null
		if id == 0x20746d66:  # "fmt "
			if size < 16 or bytes.decode_u16(pos) != 1 or bytes.decode_u16(pos + 14) != 16:
				return null
			channels = bytes.decode_u16(pos + 2)
			rate = bytes.decode_u32(pos + 4)
		elif id == 0x61746164:  # "data"
			if rate == 0 or channels < 1 or channels > 2:
				return null
			var stream := pcm_stream(bytes.slice(pos, pos + size), rate)
			stream.stereo = channels == 2
			return stream
		pos += size + (size & 1)
	return null
