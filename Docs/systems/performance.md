# Performance

## Purpose

The standing rule of the project: **every change is reviewed for
smoothness, performance and energy.** This page says what the three
factors are, how to measure them with the probe, the budget CI holds every
pull request to, and what is still slow. It is about the game as played:
a web build on iPhones and on weak Windows PCs, with the GL Compatibility
renderer.

| Factor | What the player feels | Measured by |
| --- | --- | --- |
| Smoothness | No hitch, no stutter | Frame time (p95, max) and long frames (over 1.5 frames) |
| Performance | The game keeps 60 fps on a weak device | CPU per frame, draw calls, primitives, redraws, nodes and objects, memory, download size |
| Energy | The phone stays cool and the battery lasts | Frames drawn while idle, work while the app is hidden, per-frame work that changes nothing |

## Layer and files

- Layer: tooling and rules; no game system depends on it.
- Code: `Tools/perf_probe.gd` (the probe), `Tools/perf_budget.gd`
  (`PerfBudget`, the budget check), `Docs/perf_budget.json` (the budget),
  `UI/idle_ticks.gd` (`IdleTicks`, the shared idle clock),
  `Systems/App/app_lifecycle.gd` (power saving and the hidden app; see
  [App lifecycle](app_lifecycle.md)).
- CI: the `godot` job in `.github/workflows/ci.yml` runs the probe after
  the tests.

## Data

`Docs/perf_budget.json` has two sections, `headless` and `rendered`, each
mapping scene -> metric -> maximum. The probe reads the section of the way
it runs. Scenes: `title`, `prep_full` (stage 11, eight units on the board,
a full bench, the stage's eight enemies), `battle_x1` and `battle_x4` (that
battle at x1 and x4). The budget names only metrics the probe emits in
that mode, and never a frame time (`PerfBudget.validate()`; the test
`Tests/perf_budget_test.gd` checks the file).

## How to run the probe

Headless (CPU, redraws, changed frames, nodes, memory):

```bash
godot --headless --path . --script res://Tools/perf_probe.gd -- --budget=Docs/perf_budget.json
```

Rendered, under a virtual display with Mesa's software OpenGL (adds draw
calls, primitives and frames drawn). CI runs it at a tiny window, where
the title reaches 60 fps in software and `frames_drawn_share` means
something; draw calls and primitives do not depend on the window size:

```bash
xvfb-run -a -s "-screen 0 400x400x24" godot --rendering-driver opengl3 --audio-driver Dummy --resolution 90x160 --path . --script res://Tools/perf_probe.gd -- --budget=Docs/perf_budget.json
```

Options after `--`: `--json=<file>` writes the results, `--budget=<file>`
fails (exit 1) on any metric over budget, `--summary=<file>` appends a
Markdown table (CI passes `$GITHUB_STEP_SUMMARY`). The probe also fails on
any error logged while it runs. It uses a fixed seed, its own save and
settings files (deleted at the end) and 60 fps. It is not part of
`Tools/build_and_test.sh` or `.bat`: run it before and after a change.

## Reading the numbers

| Metric | Meaning | Notes |
| --- | --- | --- |
| `cpu_ms_per_frame` | CPU time of the whole process per frame, from `/proc` | Headless: the game's own work. Rendered: includes Mesa drawing in software, so not comparable |
| `cpu_percent_of_one_core` | The same, as a share of one core | |
| `frame_ms_p95`, `frame_ms_max`, `long_frames` | Frame times and frames over 25 ms | Smoothness; only meaningful on the device. Never budgeted |
| `redraws_per_sec` (and `_by_class`) | `draw` signals a second: canvas items that re-recorded their drawing | Each costs GDScript time; the by-class list says who |
| `frames_changed_share` | Headless, title and preparation only: share of frames after which something on screen changed | What low processor mode must draw; 1.0 means every frame |
| `frames_drawn_share` | Rendered only: frames the renderer drew / frames processed | Below 1 when low processor mode skips frames; needs a machine that draws every frame in time |
| `draw_calls_max`, `primitives_max`, `render_objects_max` | The most in one frame | Draw calls cost most on phones and in WebGL |
| `nodes`, `objects`, `static_memory_mb`, `video_memory_mb`, `rig_meshes` | Size of the scene and memory | |

## The budget

Budgets are set from measurements after a change: draw calls, primitives
and nodes about +5%, redraws per second about +15%, the share of changed
frames about +15%, and `cpu_ms_per_frame` about 2.5 times the local number,
since CI machines are slower and noisy: the CPU budget is a tripwire for
gross regressions, not a measurement. Frame times are never budgeted.

A budget is **lowered** in the pull request that makes things better, to
the new numbers with the same margins. It is **never raised** without a
written reason in the pull request description (what got heavier, why it
is worth it, and the before and after numbers).

## The rules

The rules for code are in `Docs/conventions.md`, section 11 (smoothness,
performance and energy). In short: draw only when the picture changes,
write only values that changed, batch many small shapes into one mesh,
stop what is hidden, put idle animation on the shared ticks, stop loops
when the app is hidden, and report the probe's before and after in every
pull request (`.github/pull_request_template.md`).

How the pieces of this round work:

- `IdleTicks` cuts real time into 33 ms steps; an idle figure breathes 10
  times a second on one of three phases, and pulses (shop card glows,
  merge stars, near-miss outlines) redraw on the steps. A screen of idle
  things changes on at most 30 frames a second, which low processor mode
  (`application/run/low_processor_mode`, see
  [App lifecycle](app_lifecycle.md)) turns into 30 frames drawn instead of
  60. Battles turn the mode off while they play.
- `UnitView` writes its figure's transform only when it changed: any
  transform write makes a frame.
- `Backdrop` draws its lattice as one triangle array (2 draw calls instead
  of about 275).
- `FormationOutlines` redraws only while an outline animates.
- `RunLayout` hides and stops the panel it slid away.
- `CutsceneBackdrop` draws its painting once; only the mist and the camp
  fire redraw.
- While the app is hidden the tree pauses and the sound is held.

## Measurements

Worst case: stage 11, eight board units, six on the bench, eight enemies.
Headless on the build machine (one run; CPU varies by about 10% between
runs). Rendered: Mesa llvmpipe under xvfb at 720 x 1280, where frame
times are meaningless.

| Scene | Metric | Before (master) | After this round |
| --- | --- | ---: | ---: |
| title | draw calls | 323 | 51 |
| title | CPU ms per frame (headless) | 1.8 | 1.8 |
| title | redraws per second (headless) | 66 | 65 |
| title | frames changed / drawn while idle | 1.0 / 1.0 | 0.52 / 0.56 |
| prep_full | draw calls | 933 | 661 |
| prep_full | primitives | 135k | 135k |
| prep_full | CPU ms per frame (headless) | 2.6 | 2.4 |
| prep_full | redraws per second (headless) | 448 | 240 |
| prep_full | frames changed while idle (headless) | 1.0 | 0.5 |
| battle_x1 | draw calls | ~990 | ~716 |
| battle_x1 | CPU ms per frame (headless) | 6.1-6.6 | 5.9-6.1 |
| battle_x1 | redraws per second (headless) | 1940 | 1615 |
| battle_x4 | draw calls | ~990 | ~730 |
| battle_x4 | CPU ms per frame (headless) | 6.7-7.8 | 7.3 |
| battle_x4 | redraws per second (headless) | 2260 | 2030 |

The 933 draw calls of the preparation before this round were: backdrop
274, piece layer 180 (11-13 per `UnitView`), formation outlines 131, shop
92, bench 66, board cells about 66, HUD rows about 121. "Frames drawn"
for the preparation could not be measured in software (it draws 26 frames
a second at most there); the headless changed-frames share stands in.

## How to extend

- Run the probe headless and rendered before and after the change; put
  both in the pull request's Performance section.
- Lower the budget when the numbers went down.
- A new scene in the probe goes into `PerfBudget.SCENES` and gets a budget
  in both sections.

## Tests

- `Tests/perf_budget_test.gd`: the budget file parses and names only
  scenes and metrics the probe emits; the over-budget check fails when it
  should.
- `Tests/idle_frames_test.gd`: an idle unit view writes no transform, the
  Khí bar and cast glow process only while they show, idle figures and
  shop card pulses change at most 30 frames a second, formation outlines
  redraw only while they animate, and the run layout hides and stops the
  panel it slid away. It counts frames with `RenderingServer.has_changed()`
  and draws by hand in between, so it runs headless.
- `Tests/app_lifecycle_test.gd`: the hidden app and the power switch.

## Known limits

- CI has no GPU and no iPhone: real frame rates, frame times and battery
  use must be checked on a device. llvmpipe's numbers show only what is
  drawn, not how fast a phone draws it.
- `cpu_ms_per_frame` on CI is noisy; its budget only catches gross
  regressions.
- Remaining hot spots, for later rounds:
  - Move `RigPainter.paint` and `RigSolver.solve` to C++: drawing one
    figure costs 0.35-1 ms of GDScript per redraw, and a battle has about
    370 figure redraws a second.
  - Fewer draw calls per `UnitView` (11-13 now: ring, bars, pips, marks),
    the board cells as one mesh, battle effects in one layer.
  - A battery-saver setting (for example 30 fps in battle, no idle
    breathing).
