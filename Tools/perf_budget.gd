class_name PerfBudget
extends RefCounted
## The performance budget of Docs/perf_budget.json and the check the probe
## (Tools/perf_probe.gd) runs against it. The file has a `headless` and a
## `rendered` section, each mapping scene -> metric -> max; the probe uses
## the section of its mode. Kept apart from the probe so tests can check a
## budget without running the scenes. See Docs/systems/performance.md.
## [codeblock]
## var problems := PerfBudget.check(PerfBudget.load_file(path), results, true)
## [/codeblock]

const SECTION_HEADLESS: String = "headless"
const SECTION_RENDERED: String = "rendered"
## The window size the rendered section is measured at (--resolution).
## Draw calls depend on it: below about half the design size (720 x 1280)
## font oversampling rasterizes glyphs so small that they share fewer atlas
## textures, so text breaks fewer batches. From this size up the counts are
## those of the design size, and llvmpipe still draws the title at 60 fps.
const RENDERED_WINDOW: Vector2i = Vector2i(360, 640)
## The scenes the probe measures, in order.
const SCENES: Array[String] = ["title", "prep_full", "battle_x1", "battle_x4"]
## Numbers the probe emits in every mode.
const COMMON_METRICS: Array[String] = [
	"frames", "seconds", "cpu_ms_per_frame", "cpu_percent_of_one_core", "frame_ms_p95", "frame_ms_max",
	"long_frames", "redraws_per_sec", "nodes", "objects", "static_memory_mb", "rig_meshes",
]
## Numbers the probe emits only when it renders.
const RENDERED_METRICS: Array[String] = [
	"draw_calls_max", "primitives_max", "render_objects_max", "video_memory_mb", "frames_drawn_share",
]
## Numbers the probe emits headless, on the idle scenes only.
const HEADLESS_IDLE_METRICS: Array[String] = ["frames_changed_share"]
const IDLE_SCENES: Array[String] = ["title", "prep_full"]
## Measured but never budgeted: frame times depend on the machine, not on
## the change (see Docs/systems/performance.md).
const UNBUDGETED_METRICS: Array[String] = ["frames", "seconds", "frame_ms_p95", "frame_ms_max", "long_frames"]


## The budget section a probe in this mode reads.
static func section_name(is_rendering: bool) -> String:
	return SECTION_RENDERED if is_rendering else SECTION_HEADLESS


## The metrics the probe emits for `scene` in a mode.
static func emitted_metrics(is_rendering: bool, scene: String) -> Array[String]:
	var metrics: Array[String] = []
	metrics.append_array(COMMON_METRICS)
	if is_rendering:
		metrics.append_array(RENDERED_METRICS)
	elif IDLE_SCENES.has(scene):
		metrics.append_array(HEADLESS_IDLE_METRICS)
	return metrics


## The parsed budget file, or an empty dictionary (with an error) when it
## cannot be read.
static func load_file(path: String) -> Dictionary:
	# A path relative to the working directory, or to the project.
	if not FileAccess.file_exists(path) and FileAccess.file_exists("res://" + path):
		path = "res://" + path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("PerfBudget: cannot read the budget file %s" % path)
		return {}
	return parsed


## Problems with the budget itself: a missing section, a scene or metric the
## probe does not emit in that section's mode, a frame time, a non-number.
static func validate(budget: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for key: Variant in budget:
		if not key in [SECTION_HEADLESS, SECTION_RENDERED, "_comment"]:
			problems.append("PerfBudget: unknown section '%s'" % key)
	for is_rendering: bool in [false, true]:
		var section := section_name(is_rendering)
		if not budget.get(section) is Dictionary:
			problems.append("PerfBudget: the section '%s' is missing" % section)
			continue
		var scenes: Dictionary = budget[section]
		for scene: Variant in scenes:
			if not SCENES.has(scene):
				problems.append("PerfBudget: %s names an unknown scene '%s'" % [section, scene])
				continue
			var metrics := emitted_metrics(is_rendering, scene)
			if not scenes[scene] is Dictionary:
				problems.append("PerfBudget: %s.%s is not a metric map" % [section, scene])
				continue
			var limits: Dictionary = scenes[scene]
			for metric: Variant in limits:
				if not metrics.has(metric):
					problems.append("PerfBudget: %s.%s names '%s', which the probe does not emit there" % [section, scene, metric])
				elif UNBUDGETED_METRICS.has(metric):
					problems.append("PerfBudget: %s.%s budgets '%s'; frame times are not budgeted" % [section, scene, metric])
				elif not (limits[metric] is float or limits[metric] is int):
					problems.append("PerfBudget: %s.%s.%s is not a number" % [section, scene, metric])
	return problems


## Over-budget lines for `results` (scene -> metric -> value, as the probe
## prints them) against the section of the mode; empty when all fit.
static func check(budget: Dictionary, results: Dictionary, is_rendering: bool) -> Array[String]:
	var problems := validate(budget)
	if not problems.is_empty():
		return problems
	var section: Dictionary = budget[section_name(is_rendering)]
	for scene: String in section:
		var limits: Dictionary = section[scene]
		var result: Dictionary = results.get(scene, {})
		for metric: String in limits:
			if not result.has(metric):
				problems.append("Over budget: %s %s was not measured" % [scene, metric])
			elif float(result[metric]) > float(limits[metric]):
				problems.append("Over budget: %s %s is %s, the budget is %s" % [scene, metric, result[metric], limits[metric]])
	return problems


## A Markdown table of the main numbers per scene, for a CI job summary.
static func summary_table(results: Dictionary, is_rendering: bool) -> String:
	var columns: Array[String] = ["cpu_ms_per_frame", "redraws_per_sec", "frames_changed_share", "nodes", "objects", "static_memory_mb"]
	if is_rendering:
		columns = ["draw_calls_max", "primitives_max", "frames_drawn_share", "redraws_per_sec", "nodes", "video_memory_mb"]
	var lines: Array[String] = [
		"### Performance probe (%s)" % section_name(is_rendering), "",
		"| scene | %s |" % " | ".join(columns), "| --- |%s" % " ---: |".repeat(columns.size()),
	]
	for scene: String in SCENES:
		var result: Dictionary = results.get(scene, {})
		var cells: Array[String] = [scene]
		for column: String in columns:
			cells.append(str(result.get(column, "-")))
		lines.append("| %s |" % " | ".join(cells))
	return "\n".join(lines) + "\n"
