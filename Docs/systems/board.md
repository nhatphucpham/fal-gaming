# Board

## Purpose

Shows the 7 x 8 battlefield and the units on it, turns taps and drags into
cell signals, and keeps the player's formation. It does not run battles
(see [Battle](battle.md)) or decide what a tap means on a given screen.

## Layer and files

- Layer: presentation, plus one pure-data bridge class (`Lineup`).
- `Scenes/Board/`: `board_view.gd` and `board_view.tscn` (`BoardView`),
  `unit_view.gd` (`UnitView`) with `unit_bar.gd` (`UnitBar`, its hp bar,
  Khí bar and star pips), `figure_tweens.gd` (`FigureTweens`, its
  whole-figure squash and offset steps) and `board_motions.gd`
  (`BoardMotions`, its glides, hops and the sold piece's flight),
  `unit_figure.gd` (`UnitFigure`, which also knows its facing and the
  pose's push) with `unit_flash.gdshader` (its hit flash),
  `unit_painter.gd` (`UnitPainter`, the entry point and race looks), the
  bone rig ported from [the approved sketch](../sketches/unit-rig/README.md):
  `unit_pose.gd` (`UnitPose`), `rig_solver.gd` (`RigSolver`),
  `rig_clips.gd` (`RigClips`), `rig_kit.gd` (`RigKit`) with one
  `kit_<class>.gd` per class (`KitSword`, `KitShield`, `KitSpear`,
  `KitArcher`, `KitMage`, `KitCavalry`), the pieces (`rig_piece.gd`
  `RigPiece`, `rig_body.gd` `RigBody`, `rig_torso.gd` `RigTorso`,
  `rig_heads.gd` `RigHeads`, `rig_weapons.gd` `RigWeapons`, `rig_bow.gd`
  `RigBow`, `rig_horse.gd` `RigHorse`), the drawing (`rig_path.gd`
  `RigPath`, `rig_mesh.gd` `RigMesh`, `rig_palette.gd` `RigPalette`,
  `rig_painter.gd` `RigPainter`) and `pose_animator.gd` (`PoseAnimator`)
  with `weapon_trail.gd` (`WeaponTrail`) and `pose_redraws.gd`
  (`PoseRedraws`, when it redraws and blinks);
  `figure_brush.gd` (`FigureBrush`, outlined shapes for the figures outside
  the rig),
  `lineup_views.gd` (`LineupViews`),
  `piece_drag.gd` (`PieceDrag`), `formation_outlines.gd`
  (`FormationOutlines`) and `outline_geometry.gd` (`OutlineGeometry`), see
  [Formation](formation.md), `stone_layer.gd` (`StoneLayer`, the stone
  look of a petrified or crumbling unit) and `extra_figures.gd`
  (`ExtraFigures`, figures outside the six classes: the boss Cự Nham's
  stone giant and the hermit of the Kỳ Ngộ cutscenes, registered in
  `UnitPainter`'s class registry).
- `Systems/Lineup/`: `lineup.gd` (`Lineup`), `lineup_slot.gd`
  (`LineupSlot`), `lineup_preset.gd` (`LineupPreset`).
- `UI/pointer_gesture.gd` (`PointerGesture`): tap, long press and drag from
  pointer events, shared by the board and the roster strip.
- The screens that use them: the sandbox (`Scenes/Sandbox/sandbox_screen.gd`,
  `SandboxScreen`, and `Scenes/Sandbox/setup_controller.gd`,
  `SetupController`) and the run (`Scenes/Run/`, see [Run](run.md)), with
  widgets from `UI/`.
- Depends on: `Battle` for coordinates (`local_to_global`,
  `global_to_local`) and stats, `Catalog` for unit data, `Palette`.

## Data

- `LineupSlot` (Resource): `unit_id` (`unit.<name>`), `star` 1..3,
  `local_col` 1..7, `local_rank` 1..4 (1 is the front rank), in the local
  coordinates of its side as in [Battle](battle.md).
- `LineupPreset` (Resource): `id` (`preset.<name>`), `name_key`, `slots`.
- `SandboxData` (`Systems/Content/sandbox_data.gd`, file
  `Data/Sandbox/sandbox.tres`): `enemy_presets`, the line-ups "Đổi địch"
  cycles through. `validate(catalog)` reports unknown units and doubled
  cells; the sandbox reports problems with `push_error` at start.

## Coordinates and input

Board cells are global `Vector2i(col, row)`, col 0..6 from the left, row 0
at the bottom; rows 0..3 are side 0 (the player), rows 4..7 side 1. A cell is
`BoardView.CELL_PX` (88) pixels square in the 720 x 1280 base size, so never
below 44 screen pixels on a phone. Every other touch target (buttons, roster
cards) is at least 88 px tall in the base size for the same reason. `Lineup`
stores local (col, rank); `LineupViews.to_board_cell()` and
`to_local_cell()` convert.

Touch arrives as emulated mouse events, so `PointerGesture` handles mouse
and touch the same way: a press that moves less than 14 px and is released
is a tap; held 0.4 s it is a long press (a right click is one too); moved
further it is a drag. Other mouse buttons are ignored while a press is held
(a right click mid-drag does nothing; the left release still drops). A
widget that only acts on a release (the sell zone, the reward cards) sets
`is_long_press_enabled = false`: then a press held any time is still a tap,
and right clicks are ignored.
`is_dragging()` and `is_pressed()` (a press held, dragging or not) let a
widget draw its pressed state.

The first finger down owns the press. Touch indexes are not 0-based: on the
web Godot passes on the browser's touch identifier, and iOS Safari hands out
ever-growing numbers, so the gesture remembers the owner's index instead of
assuming one. Another finger going down while the press is held cancels it;
releases of other fingers are ignored. A cancelled touch, the mouse leaving
the window, the window or app losing focus, or the app pausing also cancel
the press; a drag then emits `drag_cancelled`, and the setup controller puts
the piece back, hides the ghost and clears the cell marks. A cancelled press
never taps or drops. On native builds Godot marks a cancelled touch's
emulated mouse release `canceled` and sends it before the touch itself, so
the gesture checks the flag on the release.

On the web export a browser `touchcancel` reaches Godot as an ordinary
release (`canceled` is never true), so a touch the browser interrupts while
the page stays in front ends as a normal drop where the finger last was: the
same result as lifting the finger there, never a half-finished drag. When the
interruption hides the page or takes its focus (a call, the app switcher, a
system sheet), the focus-out or pause notification arrives first and the drag
is cancelled instead.

In the roster strip a sideways drag scrolls and an upward drag picks a card
up; a soft fade on an edge shows that more cards lie that way. A dragged
piece is shown by the `DragGhost`
above the finger; the drop cell is the cell the ghost appears to stand in.

## Public API

`BoardView` (Control, 616 x 704 px):

| Member | Kind | Description |
| --- | --- | --- |
| `cell_tapped(cell)` | signal | A tap on a board cell |
| `cell_long_pressed(cell)` | signal | A long press or right click on a cell |
| `drag_started(cell, global_pointer)` | signal | A press on `cell` became a drag (any cell) |
| `drag_moved(global_pointer)`, `drag_ended(global_pointer)` | signals | The drag continues or ends |
| `drag_cancelled()` | signal | The drag stopped without a drop (see above) |
| `get_piece_layer()`, `get_fx_layer()` | methods | Nodes for UnitViews (y-sorted) and for effects above them |
| `get_outline_layer()` | method | Node under the pieces for drawings tied to cells (formation outlines) |
| `cell_to_local(cell)`, `cell_to_global(cell)` | methods | Centre of a cell in board or canvas coordinates |
| `cell_at_global(position) -> Vector2i` | method | The cell under a canvas position, or `INVALID_CELL` |
| `is_on_board(cell)`, `side_of_cell(cell)` | static | Bounds check; 0 for rows 0..3, 1 above |
| `set_target_cells(cells)`, `set_hover_cell(cell)`, `set_selected_cell(cell)`, `clear_marks()` | methods | Valid targets, the cell under a drag, a pulsing selection ring |
| `set_top_half_dim(amount)` | method | Darkens the enemy half's cells, animated |
| `cancel_gesture()` | method | Drops a press in progress |

`UnitView` (Node2D at a cell centre): `setup(unit, side, star)`,
`set_hp_ratio(ratio)`, `drop_in()`, `pop_out()` (frees itself), `shake()`,
`glide_to(position, seconds, kind)` (`walk`, `charge`, `knockback`),
`lunge(direction)`, `recoil(direction)`, `wind_up(seconds)`,
`hit_flash()`, `cancel_wind_up()` (the cast was cancelled: no strike),
`die()` (hides itself), `cheer()`, `fade_to(alpha)`,
`set_dim(amount)`; `playback_speed` scales every animation, the pose ones
included, and changing it also changes the speed of animations already
running (a battle slowed mid-cast keeps the wind-up in step with the cast).
`is_idle_calm` holds the idle sway still so the figure only redraws to
blink: `set_dim()` sets it for the waiting enemy line-up and `PieceViews`
for units on the bench. Side 0 faces up and right with a blue ring, side 1 faces down and
left with a red ring. Rigged figures breathe and blink in their pose; the
boss and the sage bob their scale (3.5%, phase per unit). `get_pose()`,
`get_animator()` and `get_flip()` are for tests and tools. Each frame the
view works out its figure's scale, position and rotation but writes only
the ones that changed: any write to a transform makes the renderer draw a
frame, so an idle board would never let low processor mode skip one (see
[Performance](performance.md)). `UnitBar` processes only while a full Khí
bar pulses, and `SkillOverlay` only while its cast glow shows.

Each view owns a `PoseAnimator` that plays the class's key-pose clips;
the view's existing methods drive it, so callers need nothing new. Player
units (side 0) are seen three-quarters from behind (`RigSolver.VIEW_BACK`)
and play the `Up` clips; enemies are seen from the front (`VIEW_FRONT`)
and play the `Down` clips. Every clip eases from the pose it starts at and
ends by settling to the rest pose: the class's stance in a fight, its idle
pose otherwise.

| View method | Animator call | Clip |
| --- | --- | --- |
| `lunge(direction)`, `recoil(direction)` | `attack(aim)` | `attackUp` from behind, `attackDown` from the front; during a wind-up it is `release()` |
| `wind_up(seconds)` | `wind_up(seconds)` | the first `RigKit.skill_wind_keys` keys of `skillUp`/`skillDown`, stretched over the cast; the last key is held, glowing and without breathing, until the next attack releases it, or it releases itself `RELEASE_GRACE_SEC` after the cast |
| (next attack) | `release()` | the rest of the skill clip (the strike) |
| `cancel_wind_up()` (stun, the battle's end) | `cancel_wind_up()` | none: the wind-up ends without its strike and settles to the stance from what shows; during a run the figure keeps running. The boss straightens only if its wind-up squash still plays (a drop in goes on) |
| `hit_flash()` | `hit()` | `hit` (a shield braces); ignored while winding up or running. A statue ignores it (no flash, no flinch): a hit landing late after the stone leaves it as it is |
| `glide_to(..., &"walk")` | `walk(seconds, false)` | the run cycle (a gallop for the rider), blended in and settled out; drops the fight stance and cancels a wind-up |
| `glide_to(..., &"charge")` | `walk(seconds, true)` | the run 1.5 times faster; keeps a wind-up glowing (its keys play on under the gallop), so Breakthrough's resolve (same tick) strikes while the horse gallops on; a charge that ends before the release settles to the stance; under a strike the gallop rises and slows smoothly (`WALK_BLEND_SEC`, `WALK_SETTLE_SEC`) |
| `glide_to(..., &"knockback")` | `flinch_for(seconds)` | the first `hit` pose without the flash, held for the slide, then a settle |
| `die()` | `die()` | `fall` (the first keys of `die`), held: the unit stays down, no idle |
| `cheer()` | `cheer()` | `cheer` (weapon raised, happy eyes, a hop); ends a wind-up without its strike |
| `set_petrified(bool)` | `set_frozen(bool)` | none: the pose and its redraws freeze as they are, without a hit's white flash (the view's too), the weapon trail or a wind-up's glow; a wind-up is cancelled (the boss's squash too) and the running clip and run end there, even a strike released in the same frame, so after the thaw the figure settles from the stone pose to rest without a jump, a strike or running in place. A statue takes no new run, knockback lean or cheer (it still slides with a knockback) |
| `setup()` | `set_class()`, `set_view()` | the idle pose |

A pose's step toward the target (`dx`) moves the whole figure along the
attack direction (`UnitFigure.PUSH_PER_STEP` forward, `PULL_PER_STEP` back, like the
sketch's board) instead of shifting the body inside it. Turning: the
figure (only the figure: never the ring, bars, pips, stone or skill marks)
is mirrored to face the target when the target is more than 6 px to the
side; archers turn their bow hand toward it. For a target straight ahead
other figures keep their facing, while an archer turns its bow hand as the
sketch does: its tie has no side term and counts as "to the right", so
archers of both sides take flip -1, whatever they faced before. The sketch also turns idle archers
toward their target; the board does not know targets outside a battle,
so an archer turns only when it shoots. Whole-body squashes, lunges and
hops stay for the boss and the sage only.

Redraws: a figure redraws only when its pose changed. While idle it
breathes 10 times a second of real time (so also at x4), on one of the
three phases of the shared idle tick (`IdleTicks`, `UI/idle_ticks.gd`:
every 100 ms tick is split into three 33 ms steps and each figure takes
one). `IdleTicks` reads the clock once per process frame, so every node
sees the same step in a frame and a step boundary costs one frame: a
board of idle figures redraws on at most 30 distinct frames a second (one
per step) and low processor mode can skip the others; a
calm figure (bench, dimmed line-up) only redraws when it blinks (checked on
its idle ticks too), and a
held wind-up does not breathe at all. Blinks last 0.12 s of real time
every 3.4 s, so the idle sampling sees them at any battle speed. While a
clip, the run or a weapon trail plays it redraws at most 30 times a second
of real time, on the same shared steps, and once more when it ends. The
shop cards' glow and merge stars pulse on those steps too. The weapon trail holds a fixed
number of samples (`WeaponTrail.SAMPLES`, 14), one taken every frame,
so its length is in frames, as in the sketch. Each frame steps the clips by
its time times the battle speed, so the poses keep up with the board's
tweens at any frame rate, up to `PoseAnimator.MAX_BATTLE_STEP_SEC` (0.25 s
of battle time, mirroring the `SimClock`'s catch-up limit of 5 ticks at 20
a second) for a long frame (a hitch), as far as the battle itself steps. `PoseAnimator.set_clock()` replaces the real-time clock of the
redraws and blinks, for tests. A petrified figure, a dead one after its fall, a boss and the sage
(they ignore poses, `UnitPainter.is_posable()`) never redraw on their own.

`UnitPose` (RefCounted): the sketch's 48 pose fields in one
`PackedFloat32Array` (`values`, indexed by constants such as
`UnitPose.BLADE`): bone angles in degrees, the hips and feet (`hip`, `fF`,
`fB`, lifts, steps, heels), leg IK, the step `dx`, `jump`, `glow`,
`trail`, `flash`, `eyes` (0 open, 1 shut or hurt, 2 happy), the weapon's
length, slide and two-hand grip, the bow (`draw`, `nock`, `bowUp`), the
seat and the horse's gallop. `make(fields)` and `with_fields(fields)` are
the sketch's `P()` and `with_()` (the feet narrowed toward the centre
line, steps added for a lunge or a crouch); `merged()` lays fields over
without that; `blend(from, to, t)`.

`RigSolver.solve(pose, view)` returns a `Frame`: a `Transform2D` per bone
(15 bones, figure units, feet on y = 0), the on-screen length scale of
each bone and the heel lifts. Seen from the front or the back a leg never
bends sideways: a bent knee shortens the thigh and shin on screen. An off
hand on a two-handed weapon reaches for the grip by IK.

`RigKit.get_kit(class_id)` (built once per class by the builder in
`RigKit.BUILDERS`; an unknown class gets the plain body with empty hands):
the pieces, the idle and stance poses per view, the class's own clips
(others come from `RigClips`, laid over by the kit's `fit`), its run, the
weapon tip for the trail, where the glow sits, how many skill keys are the
wind-up, `is_mounted` and `aims_off_hand`.

`UnitPainter` (static): `draw_figure(canvas, unit, facing, flash, origin,
scale, pose = null, animator = null, pixels_per_unit = 0)`,
`draw_bust(canvas, unit, center, scale)` (front view),
`draw_star_pips(canvas, center, count, radius)` and `draw_ring(canvas,
center, radius, color, dust)` (a view's base ring and dust puff). `flash`
whitens only the figures outside the rig; a rigged `UnitFigure` flashes
through its own material (`unit_flash.gdshader`, set when the figure gets
its unit so it compiles early; `FLASH_WHITE` at most), so a flash never
rebuilds or re-caches the figure's triangles. `RigPainter.paint()` returns
how many of its points are the weapon trail and the glow, and
`draw_figure` marks the rest with UV.x = 1: the flash whitens only those,
so the trail and the glow keep their colours as in the sketch. `pixels_per_unit` is the
on-screen size of one figure unit (0: `scale`; `UnitFigure` passes the
view's figure scale, not its squashed transform).
Without a pose a figure stands in its class's idle pose (shop cards, the
roster, the drag ghost, the info panel, the end screen, the cutscene).
`FACING_UP` draws the back view, `FACING_DOWN` the front. The race picks
the colours from `RACE_LOOKS` (human; wolf folk with fur, ears and a
muzzle; unknown races look human). Classes in `ExtraFigures.DRAWERS` (the
boss and the sage) keep their own `FigureBrush` drawers.

`RigPainter.paint()` turns a pose into one triangle list: the weapon
trail, the glow (four translucent discs, no gradients), then the pieces in
the view's draw order, the ink outlines of all pieces of one draw order
before their fills so touching pieces read as one shape. Curves become
polygons once: each piece's mesh is cached by piece, race, the inputs it
uses (rounded: limb scale, heel, weapon length, eyes, sway, glow, view)
and the line softness level (1 to 5, from the figure's on-screen size, so
board figures, busts and the big cutscene figures each use one), so a
frame only transforms cached triangles. Parts that would multiply the
cache are their own pieces: a weapon's slide along its hand is a move of
the cached weapon, the spear's tassel, the lance's pennant, the staff's
orb, the face and the scarf tails sway or change on their own, and the
torso no longer sways. The bow and the horse are built per frame from
cached parts. The cache holds at most `RigPainter.MAX_MESHES` (1,500)
meshes; past that the oldest quarter is dropped. `UnitPainter` submits the list as one triangle array: one draw
call per figure. Every line gets a feather on each side fading to
transparent (about 0.75 px on screen), which stands in for antialiasing.

`Lineup` (RefCounted, the only owner of a side's formation):

| Member | Kind | Description |
| --- | --- | --- |
| `max_size` | property | Most units, 8 in the sandbox |
| `place(unit_id, star, cell) -> int` | method | Entry id, or `NO_ENTRY` when full, off the half or taken |
| `move(entry_id, cell) -> bool`, `swap(first, second) -> bool`, `remove(entry_id) -> bool`, `clear()` | methods | Change the formation |
| `load_slots(slots)`, `to_slots()` | methods | Replace with, or copy out, `LineupSlot`s |
| `get_entry_at(cell)`, `get_slot(entry_id)`, `get_entry_ids()`, `size()`, `is_full()` | methods | Queries; slots are read only |
| `entry_added(id)`, `entry_moved(id, from, to)`, `entries_swapped(a, b)`, `entry_removed(id, slot)`, `cleared()` | signals | One per change |

`LineupViews` (RefCounted) keeps one `UnitView` per `Lineup` entry on a
board and animates each signal: drop in, glide, pop out. `rebuild()` makes
fresh views (after a battle), `fade_out_all()` cross-fades a preset away,
`set_dim(amount)` darkens the enemy while it only waits and
`set_hp_bars_shown(shown)` hides the hp bars outside a battle (full health
says nothing).

`UnitView` also has `is_hp_bar_shown`, and the run's animations:
`stamp_stars(star, delay)` (a merge's new star lands), `grow_in()`,
`hop_to(position, seconds)` (a short arc between bench and board) and
`shrink_to(position, seconds)` (a sold piece flies into the coin pile).
A boss (`UnitData.is_boss`) is drawn `BOSS_SCALE` (1.6) times larger on its
one cell. `set_petrified(bool)` turns the figure to grey stone with cracks
and `crumble()` cracks it apart and fades it out, for a boss's death (see
[Boss](boss.md)).

`PieceDrag` (RefCounted) is the one drag of a unit over the board, shared
by `SetupController` and the run's `PrepController`:

| Member | Kind | Description |
| --- | --- | --- |
| `begin(unit, pointer, source)` | method | Shows the `DragGhost`; `source` is the view being moved (it fades) or null for a card |
| `follow(pointer) -> Vector2` | method | Moves the ghost, lights the cell under its feet, returns the drop point |
| `get_drop_point(pointer) -> Vector2` | method | Where the ghost's feet are for this pointer (the ghost floats above the finger) |
| `accept()` | method | The piece landed: the ghost fades, the source shows again |
| `reject(home)` | method | The ghost flies to `home` and the piece shakes (from its stored rest position) |
| `cancel()` | method | Focus lost or a second finger: everything goes back at once |
| `is_active() -> bool` | method | A drag is in progress |

The caller decides what a drop means; `PieceDrag` only shows it.

`SetupController` (sandbox only): `tap_roster_card(unit_id)`,
`tap_cell(cell)`, `drop_card(unit_id, cell)`, `drop_piece(entry_id, cell)`,
`deselect()`, `is_dragging()`, `is_enabled`; signals `info_requested(unit, star)` and
`action_refused()`. Gestures call these; the sandbox test calls them too.
Rules: a selected card stays selected so several units can be placed; tap a
unit to select it, then an empty cell to move or another unit to swap, or
the same unit to deselect; dragging a unit off the board removes it; a
refused drop flies back and shakes.

## Log events

None. Data problems are reported with `push_error` (`Sandbox: ...`,
`Lineup: ...`, `LineupViews: ...`, `UnitStats: ...`).

## How to extend

- **New class look:** write `kit_<class>.gd` with a `static func build()
  -> RigKit` and register it by class id in `RigKit.BUILDERS`. Start from
  `RigBody.base_pieces()` and swap, drop or add pieces with
  `RigKit.remix()` (headgear in `RigHeads`, torso dressing in `RigTorso`,
  weapons in `RigWeapons`); set the rest poses, any clips of its own (per
  view when they differ), a `fit` laid over the generic clips, the run,
  the weapon tip and glow point. Use static functions bound with
  `Callable(...).bind()`, never lambdas: kits live in a static cache and a
  lambda outliving its script crashes Godot at exit. Draw it on a pose
  sheet laid out like the sketch's in both views before shipping. Units of
  an unknown class get the plain body.
- **New race look:** add an entry to `UnitPainter.RACE_LOOKS` (skin, tunic,
  mount and hair colours, `has_fur` for ears and a muzzle) and
  `RACE_<NAME>` to `Locale/strings.csv`.
- **New sandbox enemy:** add a `LineupPreset` to `Data/Sandbox/sandbox.tres`
  and its `name_key` to `Locale/strings.csv`.
- **Another screen** reuses `BoardView`, `UnitView`, `Lineup`,
  `LineupViews`, `PieceDrag` and `BattlePlayback`, and writes its own
  controller like `SetupController` or `PrepController`.

## Tests

`Tests/sandbox_test.gd` (headless, in CI) instantiates the main scene,
places units through `SetupController`, checks the 8-unit cap, move, swap,
deselect, remove by dragging off the board, drops on the enemy half and the
third enemy preset. It then pushes real pointer events through the viewport:
a right click during a drag is ignored, and a second finger, the mouse
leaving the window, focus loss or an app pause cancels the drag and restores
the piece. Touches go through Godot's own `Input` path (touch to mouse
emulation included) with first-finger indexes 1, 7 and 123456: a tap selects
and places, a drag moves, and a second finger with another arbitrary index
cancels while releases of other fingers are ignored. A cancelled release
(index 5000) neither drops a dragged unit nor selects a roster card. It checks that a
selected card, a tap on a free cell and drops are refused during a battle,
plays the battle to its end at x4, checks that "Xếp lại" restores the
line-up and its views, and that the speed button afterwards does not touch
the freed battle views. The look is checked by eye from screenshots.

`Tests/unit_pose_test.gd` (headless, in CI) plays every clip and the run
of every class from both sides in both races three times at 30 poses a
second and checks the mesh cache stays under 1,300 meshes and grows by
less than 5% on the last play, then paints 3,000 random blends at random
sizes and checks the cache never passes `MAX_MESHES`. It draws every class
(with the boss, the sage and an unknown one) x race (and an unknown one)
in several poses, unposed and as a bust inside a real draw notification
(the headless renderer still runs `_draw`) and fails on any logged error.
It solves every class, view and clip at sampled times (keys and the blends
between them, rests and the run) and fails on a NaN bone, and checks that
every standing pose plants each foot its leg can reach where the sketch
puts it. It also checks that the hit flash marks skip the trail and the
glow, and that a rigged figure gets its flash material with its unit.

`Tests/pose_animator_test.gd` (headless, in CI; the four share
`Tests/pose_test_kit.gd`, whose `Stepper` drives animators by hand at
fixed 1/60 s frames with a clock of its own; only the animators: the
view's tweens (glides, the hit flash, squashes, the boss's drop in and
wind-up) still run on real time) checks through `UnitView`, for every class from
both sides, that each action (attack, skill, hit, knockback, walk, cheer,
and the event orders of real battles: a resolve followed one tick later by
a walk or an attack, a cast then a cheer) ends at the rest pose with no
clip, trail, glow, flash or step left and the figure unsquashed. It also
checks that a dead unit, still shown, stays in its last fall pose with no
redraws whatever comes next; that the boss and the sage never pose or
redraw; that idle redraws stay at 10 a second (within one) at x1 and x4
and blinks still show at x4, swaying or calm; that a calm figure only
blinks; that x4 speed plays the clip four times as fast; that a glide or
hop clears a knockback's lean; that the trail takes a sample every frame;
that a frame steps the clips by its time times the speed, and a 1 s frame
by `MAX_BATTLE_STEP_SEC`; and that an archer shooting straight ahead turns
as the sketch does on both sides. The idle redraw, blink, trail and step
checks are stepped; the others run on the engine's frames and real time.

`Tests/pose_cast_test.gd` (headless, in CI) checks, stepping every frame,
that a wind-up holds its last key glowing through the grace window (also
with a charge during its keys) and then releases by itself when the
window ends; that a stun (`cancel_wind_up()`) mid-cast never plays the
strike (no trail, no step toward the target, no glow coming back), for
every class; that the battle's end cancels casts and their feet glow;
that slowing from x4 to x1 mid-cast keeps the wind-up held; that
Breakthrough's resolve, sent before the automatic release could come,
releases the strike while the horse gallops on; that the gallop under a
strike changes no faster than its blend (`1 / WALK_BLEND_SEC` a second,
with a margin); and that the boss straightens from a wind-up cancelled
by a stun or stone, while a cancel during its drop in leaves the drop in
running. The boss checks have no animator to step and wait real time for
its tweens.

`Tests/pose_stone_test.gd` (headless, in CI) checks, stepping every frame,
that stone mid-cast cancels it, for every class, and the thaw plays no
strike; that stone freezes the pose and redraws and drops the trail, and a
statue made mid-hit keeps no flash in its pose or on its figure; that a
hit landing on a statue (rigged or the boss) neither flashes it nor makes
it flinch (the stone's squash is a real-time tween, which it waits
for); that the thaw starts from the stone pose (no jump); that a strike
released in the frame the stone came does not play after the thaw; that a
knockback on a statue leaves no lean after the thaw; and that stone
mid-walk ends the run, so the thawed figure does not run in place.

## Known limits

- Stars are always 1 in the sandbox; the run uses 1 to 3. Star pips are
  drawn in code (the default font has no star glyph).
- Long-press info during a battle finds the unit by its current cell.
- A rigged figure costs about 0.2 ms of GDScript to redraw in the debug
  build on a desktop CPU once its meshes are cached (0.3 ms for the archer,
  whose bow is built per frame, 0.43 ms for the rider and horse), about
  3,300 to 5,000 triangles in one draw call. Throttled redraws keep it in
  hand. The animator itself costs about 0.01 to 0.025 ms a frame per figure
  during an attack, the weapon trail's rig solve included. Not measured on
  a phone or in a release build.
- The mesh cache is not freed while the game runs. Playing every clip of
  every class from both sides in both races fills it with about 1,060
  meshes (18.5 MB of points and colours, measured in
  `Tests/unit_pose_test.gd`'s set-up), and further plays add next to
  nothing. Busts and the big cutscene figures add their own softness
  level. `MAX_MESHES` (1,500, about 27 MB) is a backstop: past it the
  oldest quarter of the meshes is dropped and rebuilt when next needed, a
  short stutter.
- Differences from the sketch: the pose's `alpha` is not drawn (the view
  fades instead); `dx` pushes the whole figure (see above) instead of the
  body; a hit is ignored during a wind-up or a run; cost tiers (trim,
  cape, crown) are gone; the mage's orb is one colour, not its element's;
  curves are flattened and cached, so sways and limb scales move in small
  steps; the sketch's own ground shadow is left to the board's ring.
- No safe-area insets for phone notches yet; Safari's own bars keep the
  canvas clear of them in a browser tab.
