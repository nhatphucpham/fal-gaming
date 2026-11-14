# Board

## Purpose

Shows the 7 x 8 battlefield and the units on it, turns taps and drags into
cell signals, and keeps the player's formation. It does not run battles
(see [Battle](battle.md)) or decide what a tap means on a given screen.

## Layer and files

- Layer: presentation, plus one pure-data bridge class (`Lineup`).
- `Scenes/Board/`: `board_view.gd` and `board_view.tscn` (`BoardView`),
  `unit_view.gd` (`UnitView`), `unit_figure.gd` (`UnitFigure`),
  `unit_painter.gd` (`UnitPainter`), `lineup_views.gd` (`LineupViews`),
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
`lunge(direction)`, `recoil(direction)`, `hit_flash()`, `die()` (hides
itself), `cheer()`, `fade_to(alpha)`, `set_dim(amount)`; `playback_speed`
scales every animation. Side 0 faces up with a blue ring, side 1 faces down
with a red ring. Idle units breathe (a slow 3.5% scale bob, phase per unit).

`UnitPainter` (static): `draw_figure(canvas, unit, facing, flash, origin,
scale)`, `draw_bust(canvas, unit, center, scale)` and
`draw_star_pips(canvas, center, count, radius)`. Stars are always drawn this
way, never typed: the default font has no star glyph. The class picks the
silhouette from a registry of drawers by class id (shield, sword, spear,
cavalry, archer, mage); the race picks the head and palette from
`RACE_LOOKS` (human, wolf folk); the cost picks the trim colour
(`Palette.COST_COLORS`, the same as the roster cards), and cost 5 adds a
crown. Mages carry an orb in their element's colour.

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

- **New class look:** add a drawer function to `UnitPainter` and its class id
  to `_get_drawers()`. Units of an unknown class get a plain figure.
- **New race look:** add an entry to `UnitPainter.RACE_LOOKS` with a head
  function. Add `RACE_<NAME>` to `Locale/strings.csv`.
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

## Known limits

- Stars are always 1 in the sandbox; the run uses 1 to 3. Star pips are
  drawn in code (the default font has no star glyph).
- Long-press info during a battle finds the unit by its current cell.
- No safe-area insets for phone notches yet; Safari's own bars keep the
  canvas clear of them in a browser tab.
