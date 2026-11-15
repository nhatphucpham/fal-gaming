extends SceneTree

# Headless test of the performance budget (PerfBudget, Docs/perf_budget.json)
# without running the probe's scenes: the file parses, names only scenes
# and metrics the probe emits in each section's mode (and scene) and no
# frame times, results within it pass, and results over it, or missing a
# budgeted metric, fail.

const BUDGET_PATH: String = "res://Docs/perf_budget.json"


func _initialize() -> void:
	var ok := true
	for check: Callable in [_check_file, _check_rejects_bad_budgets, _check_over_budget]:
		if not check.call():
			push_error("Perf budget test failed in %s" % check.get_method())
			ok = false
	if ok:
		print("Perf budget test passed")
	quit(0 if ok else 1)


func _check_file() -> bool:
	var budget := PerfBudget.load_file(BUDGET_PATH)
	if budget.is_empty():
		return false
	var problems := PerfBudget.validate(budget)
	for problem: String in problems:
		push_error(problem)
	if not problems.is_empty():
		return false
	# Every scene is budgeted in both modes, so no scene goes unwatched.
	for is_rendering: bool in [false, true]:
		var section: Dictionary = budget[PerfBudget.section_name(is_rendering)]
		for scene: String in PerfBudget.SCENES:
			if not section.has(scene) or (section[scene] as Dictionary).is_empty():
				push_error("%s has no budget for %s" % [PerfBudget.section_name(is_rendering), scene])
				return false
	return true


func _check_rejects_bad_budgets() -> bool:
	var bad: Array[Dictionary] = [
		{"headless": {}},
		{"headless": {"lobby": {"nodes": 10}}, "rendered": {}},
		{"headless": {"title": {"draw_calls_max": 10}}, "rendered": {}},
		{"headless": {"title": {"frame_ms_p95": 20}}, "rendered": {}},
		{"headless": {"title": {"nodes": "many"}}, "rendered": {}},
		{"headless": {}, "rendered": {}, "gpu": {}},
		{"headless": {"battle_x1": {"frames_changed_share": 0.5}}, "rendered": {}},
	]
	for budget: Dictionary in bad:
		if PerfBudget.validate(budget).is_empty():
			push_error("A bad budget passed validation: %s" % budget)
			return false
	var good := {"headless": {"title": {"nodes": 10, "frames_changed_share": 0.6}}, "rendered": {"title": {"frames_drawn_share": 0.6}}}
	return PerfBudget.validate(good).is_empty()


func _check_over_budget() -> bool:
	var budget := {
		"headless": {"title": {"nodes": 100, "cpu_ms_per_frame": 2.0}},
		"rendered": {"title": {"draw_calls_max": 50}},
	}
	var within := {"title": {"nodes": 100, "cpu_ms_per_frame": 1.5, "draw_calls_max": 900}}
	if not PerfBudget.check(budget, within, false).is_empty():
		push_error("Results within the headless budget failed it")
		return false
	if PerfBudget.check(budget, within, true).size() != 1:
		push_error("900 draw calls should break a rendered budget of 50")
		return false
	var over := {"title": {"nodes": 101, "cpu_ms_per_frame": 2.5}}
	if PerfBudget.check(budget, over, false).size() != 2:
		push_error("Both headless metrics over budget should be reported")
		return false
	if PerfBudget.check(budget, {"title": {"nodes": 10}}, false).size() != 1:
		push_error("A budgeted metric that was not measured should fail")
		return false
	return PerfBudget.check(budget, {}, false).size() == 2
