# Board

## Purpose

Shows the 7 x 8 battlefield and the units on it, turns taps and drags into
cell signals, and keeps the player's formation. It does not run battles
(see [Battle](battle.md)) or decide what a tap means on a given screen.

## Layer and files

- Layer: presentation, plus one pure-data bridge class (`Lineup`).
- `Scenes/Board/`: `board_view.gd` and `board_view.tscn` (`BoardView`),
  `unit_view.gd` (`UnitView`), `unit_figure.gd` (`UnitFigure`),
  `unit_painter.gd` (`UnitPainter`, the entry point and registries),
  `figure_brush.gd` (`FigureBrush`, outlined shapes and a transform stack),
  `figure_parts.gd` (`FigureParts`, body parts, heads and headgear),
  `class_figures.gd` (`ClassFigures`, the six class figures),
  `unit_pose.gd` (`UnitPose`), `pose_animator.gd` (`PoseAnimator`),
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
`hit_flash()`, `die()` (hides itself), `cheer()`, `fade_to(alpha)`,
`set_dim(amount)`; `playback_speed` scales every animation, the pose ones
included. Side 0 faces up and right with a blue ring, side 1 faces down and
left with a red ring. Idle units breathe (a slow 3.5% scale bob, phase per
unit), sway and blink. `get_pose()` and `get_flip()` are for tests.

Each view owns a `PoseAnimator` that moves the figure's limbs and weapon;
the view's existing methods drive it, so callers need nothing new:

| Method | Whole body (view) | Pose (limbs, weapon, eyes) |
| --- | --- | --- |
| `lunge(direction)` | short lunge toward the target | turns to the target, swings at it with a smear |
| `recoil(direction)` | small squash and recoil | turns to the target; archers loose and draw again, mages thrust the staff with a flash; releases a wound-up skill |
| `glide_to(..., &"walk")` | glide with a step bob | legs and arms walk; drops the combat stance |
| `glide_to(..., &"charge")` | gallop bob, stretched | horse gallops, lance levelled |
| `glide_to(..., &"knockback")` | skid with a tilt | flinches back for the slide |
| `wind_up(seconds)` | crouch and rise | crouches, weapon raised and glowing in the class colour, a horse rears; held until the next `lunge`/`recoil` releases the strike (or just after `seconds`) |
| `hit_flash()` | white flash, squash | flinches with hurt eyes; a shield raises its shield instead |
| `die()` | after the collapse, falls over backwards and fades | collapses limp, weapon sinks, dead eyes; no more idle |
| `cheer()` | two hops | weapon raised, happy eyes; a horse rears |
| `set_petrified(true)` | grey stone | the pose freezes exactly as it is (no tween, sway or blink) |

Turning: the figure (only the figure: never the ring, bars, pips, stone or
skill marks) is mirrored to face the target when the target is more than
6 px to the side; the weapon aims along `atan2(abs(dx), -dy)` in the
figure's own space (0 up, PI / 2 straight ahead). After a unit's first
attack it holds its weapon half wound up (the bow drawn) until it walks or
cheers.

Redraws: a figure redraws only when its pose changed. While idle the sway
and blink advance about 15 times a second, at a phase offset per unit, so
16 units do not redraw on the same frame; breathing is a node scale and
costs no redraw. While a pose tween runs or the legs walk it redraws every
frame. A petrified figure, a dead one after its fall, a boss and the sage
(they ignore poses, `UnitPainter.is_posable()`) never redraw on their own.

`UnitPose` (RefCounted): the figure's posable fields, all tweenable
floats (`step`, `stride`, `strike` -1 wound up .. +1 struck, `raise`,
`guard`, `flinch`, `limp`, `crouch`, `sway`, `aim`, `trail`, `glow`,
`gallop`, `rear`, `arrow`) plus `eyes` (`OPEN`, `BLINK`, `HURT`, `HAPPY`,
`DEAD`). `UnitPose.get_rest()` is the shared rest pose.

`PoseAnimator` (Node, one per view): `walk(seconds, is_charge)`,
`attack(aim)`, `wind_up(seconds)`, `release()`, `hit()`,
`flinch_for(seconds)`, `die()`, `cheer()`, `reset()`, `set_frozen(bool)`,
`get_stance()`; `playback_speed`. Differences between classes (how they
attack, the stance they hold, who guards, who rears, the step rate) are
data in its `CLASS_MOTION` registry, not branches.

`UnitPainter` (static): `draw_figure(canvas, unit, facing, flash, origin,
scale, pose = null)`, `draw_bust(canvas, unit, center, scale)` and
`draw_star_pips(canvas, center, count, radius)`. Without a pose a figure
stands in the rest pose (shop cards, the roster, the drag ghost, the info
panel, the end screen). Stars are always drawn this way, never typed: the
default font has no star glyph. The class picks the figure from a registry
of drawers by class id (`ClassFigures`: shield, sword, spear, cavalry,
archer, mage; an unknown class gets a plain figure with empty hands) and
the headgear from a second registry (helmet, red headband, war hat, plumed
helmet, feather band, pointed hat); the race picks the head and palette
from `RACE_LOOKS` (human, wolf folk with ears, snout and a fur collar;
unknown races look human); the cost picks the trim colour
(`Palette.COST_COLORS`, the same as the roster cards), pauldrons from cost
3 (gold from 4), a cape from 4 and a crown at 5. Mages carry an orb in
their element's colour; weapons glow in `Palette.CLASS_COLORS`. The visual
reference is [the figure page](../concept-page/unit-figures.html) (the
prototype these figures are ported from).

`FigureBrush` draws every shape as batched canvas primitives (quads and
lines), so all figures on the board take a few draw calls in total
instead of one per shape (`draw_colored_polygon`, `draw_circle` and
antialiased polylines cost one or more draw calls each). Only lines
thinner than 2 units are antialiased: thick antialiased lines are many
triangles each and look the same at board size. It keeps `poly`,
`outline`, `circle`, `stick` and `canvas` for `ExtraFigures` and adds a
transform stack (`push(origin, rotation, scale)`, `pop()`), `stick_path`
(bent sticks with round ends), `limb` (two bones), `fill_ellipse`, `dot`,
`line`, `arc` and `glow` (concentric translucent discs, no gradients).

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

- **New class look:** add a drawer to `ClassFigures` that builds the body
  with `FigureParts.draw_humanoid` (or its own body, like the mage and
  the rider) and places its weapon from four key poses (`Grip`s for ready,
  wind, strike and raise) blended by `FigureParts.weapon_grip`; register it
  by class id in `UnitPainter._get_drawers()` and its headgear in
  `_get_headgear()`. If it moves differently (attack style, stance,
  guarding, rearing), add an entry to `PoseAnimator.CLASS_MOTION`. Check it
  in every pose of the reference sheet. Units of an unknown class get a
  plain figure.
- **New race look:** add an entry to `UnitPainter.RACE_LOOKS` with a head
  function in `FigureParts` and `has_fur`. Add `RACE_<NAME>` to
  `Locale/strings.csv`.
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

`Tests/unit_pose_test.gd` (headless, in CI) draws every class (and an
unknown one) x race (and an unknown one) x cost 1..5 in the rest pose and
in each extreme pose inside a real draw notification (the headless
renderer still runs `_draw`) and fails on any logged error; it also draws
without a pose and as a bust. It then checks the animator through
`UnitView`: an attack turns the figure and settles at the combat stance
(the bow drawn for archers), walking drops the stance, a wind-up holds
until the next recoil releases it, death ends limp and dead-eyed with no
more sway or redraws, stone freezes the pose and its redraws, idle redraws
stay near 15 a second, and x4 speed plays the swing four times as fast.

## Known limits

- Stars are always 1 in the sandbox; the run uses 1 to 3. Star pips are
  drawn in code (the default font has no star glyph).
- Long-press info during a battle finds the unit by its current cell.
- A posed figure costs about ten times the GDScript time of the old static
  one to redraw (0.25 to 0.35 ms per figure in the debug build on a desktop
  CPU), so a busy fight spends a few ms per frame redrawing figures; draw
  calls went down (about 550 instead of 1200 in a 16-unit battle). Thick
  lines are not antialiased (see above).
- No safe-area insets for phone notches yet; Safari's own bars keep the
  canvas clear of them in a browser tab.
