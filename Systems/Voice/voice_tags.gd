class_name VoiceTags
extends RefCounted
## The inline tags of the TTS service ([speed=1.3], [voice=Mai Anh], [reset],
## [cười] ...), which stay in the text sent and in the cache key. Static only;
## [method VoiceService.display_text] uses it to show a line without them.
## Only the exact forms listed in Docs/systems/voice.md count as tags.
## [codeblock]
## VoiceTags.display_text("[shout=2] Đứng lại! [cười]")  # "Đứng lại!"
## [/codeblock]

## Keys that take a number, as [speed=0.85 pitch=-3] (pairs split by
## whitespace, none around "="); "voice" takes a name instead.
const NUMBER_KEYS: Array[String] = ["speed", "pitch", "volume", "effort", "shout"]
## Tags without a value: [reset] and the non-verbal cues. A space in a cue
## matches any whitespace run, since the text is sent normalized.
const WORDS: Array[String] = ["reset", "cười", "thở dài", "hắng giọng"]
const NUMBER := "[-+]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)"
## A removed tag right before one of these takes the whitespace around it
## along. Straight quotes are left out: they open and close alike.
const CLOSING := ",.;:!?…)]}”»’"
## A removed tag right after one of these (or at the start) takes the
## whitespace after it along.
const OPENING := "([{“«‘"
## What a caption treats as whitespace: the ASCII kinds and the no-break space.
const SPACE_CHARS := " \t\r\n\f\v\u00a0"
## Whitespace other than a line break, no-break space included.
const BLANK := "(?:[^\\S\\n]|\\x{A0})"

static var _body := _body_pattern()
static var _tag := RegEx.create_from_string("\\[" + _body + "\\]")
static var _exact := RegEx.create_from_string("^" + _body + "$")
static var _blank := RegEx.create_from_string(BLANK + "+")
static var _line_break := RegEx.create_from_string(BLANK + "*\\n" + BLANK + "*")


## [param text] as the player reads it: tags removed, runs of spaces and tabs
## collapsed to one space, line breaks kept. Other bracketed text is kept.
## A tag between two words leaves a space, so they do not join.
static func display_text(text: String) -> String:
	var out := ""
	var from := 0
	for found: RegExMatch in _tag.search_all(text):
		out += text.substr(from, found.get_start() - from)
		from = found.get_end()
		var next := _skip_whitespace(text, from)
		if next < text.length() and CLOSING.contains(text[next]):
			# "Ha ha [cười]." must not read "Ha ha ."
			out = out.rstrip(SPACE_CHARS)
			from = next
		elif _opens_text(_trim_blanks(out)):
			# "( [thở dài] Thôi)" must not read "( Thôi)"
			out = _trim_blanks(out)
			from = next
		elif _trim_blanks(out).ends_with("\n"):
			# A tag alone on its line: drop the line break after it, so the
			# line does not stay empty.
			out = _trim_blanks(out)
			from = _after_first_line_break(text, from, next)
		elif _needs_space(out):
			out += " "
	return _collapse_whitespace(out + text.substr(from))


## True when [param inner], the text between [ and ], is a tag the server
## reads, in exactly the documented form: number pairs, a voice name after
## zero or more number pairs, or a word.
static func is_tag(inner: String) -> bool:
	return _exact.search(inner) != null


static func _body_pattern() -> String:
	var pair := "(?:%s)=%s" % ["|".join(NUMBER_KEYS), NUMBER]
	var voice := "(?:%s\\s+)*voice=[^\\[\\]\\s](?:[^\\[\\]]*[^\\[\\]\\s])?" % pair
	var words: Array[String] = []
	for word: String in WORDS:
		words.append(word.replace(" ", "\\s+"))
	return "(?:%s(?:\\s+%s)*|%s|%s)" % [pair, pair, voice, "|".join(words)]


## Index of the first character at or after [param from] that is not whitespace.
static func _skip_whitespace(text: String, from: int) -> int:
	var index := from
	while index < text.length() and SPACE_CHARS.contains(text[index]):
		index += 1
	return index


## True when [param trimmed] is empty or ends with an opening character.
static func _opens_text(trimmed: String) -> bool:
	return trimmed.is_empty() or OPENING.contains(trimmed.right(1))


## Index just after the first line break in text[from, to), or [param to] when
## there is none.
static func _after_first_line_break(text: String, from: int, to: int) -> int:
	var line_break := text.find("\n", from)
	return to if line_break < 0 or line_break >= to else line_break + 1


## [param text] without trailing whitespace other than line breaks.
static func _trim_blanks(text: String) -> String:
	var end := text.length()
	while end > 0 and text[end - 1] != "\n" and SPACE_CHARS.contains(text[end - 1]):
		end -= 1
	return text.substr(0, end)


## True when a space is needed between [param out] and what follows it.
static func _needs_space(out: String) -> bool:
	var last := out.right(1)
	return last != "" and not SPACE_CHARS.contains(last) and not OPENING.contains(last)


## Trimmed, runs of blanks as one space, no spaces around line breaks.
static func _collapse_whitespace(text: String) -> String:
	var single := _blank.sub(text, " ", true).strip_edges()
	return _line_break.sub(single, "\n", true)
