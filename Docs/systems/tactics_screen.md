# Tactics screen

## Purpose

Shows a tactics battle on a phone and takes its taps: the muster screen
("Điểm binh") before it, the map with flat tokens, the bottom panel with a
unit card, an engagement or skill forecast and the buttons, the playback of
every event with sound, the side-view close-up of a leader's attack or skill,
and the result. It holds no rules: every list of cells, every target, the
forecast and the skill preview come from `TacticsBattle` (see
[Tactics](tactics.md)), and the map is brought back in line with the battle
after each command.

## Layer and files

- Layer: presentation.
- Code: `Scenes/Tactics/`:
  - `muster_screen.gd` (`MusterScreen`): objective, terrain legend, our
    leaders with their squads, the enemy's leaders; moves soldiers between
    leaders within capacity.
  - `tactics_screen.gd` (`TacticsScreen`): owns the `TacticsBattle` node, the
    tap state machine and the layout (top bar, map, panel, overlays).
  - `tactics_map_view.gd` (`TacticsMapView`): the board, in layers that
    redraw only when their content changes; the terrain is painted once into
    a `SubViewport` texture at the screen's pixel scale.
  - `tactics_piece_view.gd` (`TacticsPieceView`): one token with its hp bar
    and charge pips.
  - `tactics_painter.gd` (`TacticsPainter`): static drawing of terrains,
    tokens, ghosts, hp bars, pips, order and intent icons, by registries.
  - `tactics_panel.gd` (`TacticsPanel`): the bottom panel.
  - `tactics_playback.gd` (`TacticsPlayback`): plays a command's events.
  - `tactics_close_up.gd` (`TacticsCloseUp`), `tactics_skill_fx.gd`
    (`TacticsSkillFx`): the close-up and the three skill layers.
  - `tactics_skill_look.gd` (`TacticsSkillLook`),
    `tactics_skill_look_set.gd` (`TacticsSkillLookSet`): skill look data.
  - `tactics_banner.gd` (`TacticsBanner`): "Lượt ta" / "Lượt địch".
  - `tactics_text.gd` (`TacticsText`): player-facing names from the catalog.
- Depends on: `TacticsBattle` and the tactics catalog
  (`Data/Tactics/tactics_catalog.tres`), `UnitView` and `CutsceneBackdrop`
  for the close-up figures and backdrop, `ResultBanner`, `PressButton`,
  `GameTheme`, `Palette`, `Sound`. `Main.open_campaign()` opens the muster
  screen from the title's "Chiến Dịch" button; `Main.open_tactics()` opens
  the battle.

## Data

`Data/Tactics/Looks/<skill>.tres` (`TacticsSkillLook`), one per leader skill,
listed in `Data/Tactics/Looks/skill_looks.tres` (`TacticsSkillLookSet`, with
`fallback.tres` for a skill without a look):

| Field | Meaning |
| --- | --- |
| `skill_id` | The tactics skill id (`tactics_skill.fire_rain`) |
| `color_main`, `color_accent` | The signature colour pair |
| `motif` | `motif.feather`, `motif.crescent`, `motif.flame`, `motif.fang`, `motif.chevron` |
| `aura` | Layer a, on the caster: `aura.swirl`, `aura.sigil`, `aura.rise` |
| `path` | Layer b: `path.arc`, `path.fall`, `path.beam`, `path.dash`, `path.wave` |
| `path_order` | `together` (all targets at once) or `chain` (target to target) |
| `impact` | Layer c: `impact.burst`, `impact.slash`, `impact.marks` (support) |
| `cast_sec`, `path_sec`, `impact_sec` | Seconds of each layer, 0.2-2.0 |
| `motif_count` | Motifs drawn by the aura and impact, 1-16 |
| `shake_px` | Close-up shake at each impact, 0-12 px |
| `path_sound`, `impact_sound` | Sound ids from `Data/Audio/sounds.tres` |

The five sample skills: Hiệu triệu (jade and gold chevrons rising, waves to
the squad, marks over each ally), Xuyên tâm (silver-blue crescents, a thrust
beam, a cross cut), Liên tiễn (teal feathers, arrows chained from target to
target), Mưa lửa (vermilion flames, a ground sigil, fire falling, bursts),
Huyết thệ (crimson fangs, a dash afterimage, cuts).

Every player string is a `Locale/strings.csv` key: names of leaders, troops,
terrains, keywords, passives, skills, zones, orders and charges come from
the catalog's `name_key` (orders and charges by id: `order.flank` is
`ORDER_FLANK`); the screen's own texts are the `MUSTER_*`, `TACTICS_*`,
`FORECAST_*`, `SKILL_PREVIEW_*`, `INTENT_*`, `CLOSEUP_*` and `BUTTON_*` rows.

## Public API

`TacticsScreen` (Control). Set `scenario` (and `squads` from the muster)
before adding it. The tap methods are the ones the map and panel call, so a
test drives the screen through them.

| Member | Kind | Description |
| --- | --- | --- |
| `scenario`, `squads`, `catalog`, `player_side` | property | The battle to load; `squads` empty keeps the scenario's; the side not `player_side` is played by the AI |
| `is_instant` | property | Tests: playback steps end at once, close-ups are counted but not shown |
| `tap_cell(cell)` | method | A tap on the map: select, preview a move or forecast, confirm (a second tap on the same cell or target), or step back (a tap elsewhere) |
| `select_unit(unit)`, `confirm()`, `cancel()` | method | Select a unit; confirm the move, attack or skill previewed; step back one level |
| `press_button(action)`, `choose_order(order)` | method | A panel button (`end_turn`, `wait`, `skill`, `order`, `confirm_move`, `attack`, `cast`, `cancel`); an order of the picker |
| `retreat()` | method | "Rút": the first tap asks, a second within 3 s emits `home_requested`. The top bar sits above the skip catcher and the close-up, so it works during any playback |
| `get_round_text()` | method | The top bar's round and phase line |
| `is_busy()`, `get_mode()`, `get_selected()` | method | Playback running; `Mode` (`IDLE`, `SELECTED`, `MOVE_PREVIEW`, `FORECAST`, `ORDER_PICK`, `SKILL_TARGET`, `SKILL_PREVIEW`, `BUSY`, `ENDED`); the selected unit |
| `get_battle()`, `get_map()`, `get_panel()`, `get_playback()`, `get_close_up()`, `get_result_banner()`, `get_retreat_button()`, `get_hint()` | method | Parts and the hint line, for tests and screenshots |
| `home_requested` | signal | The result's "Về màn hình chính" or a confirmed retreat |
| `became_idle` | signal | After each playback, when the next tap is taken |

`MusterScreen` (Control): `scenario`; its leader cards (`LeaderCard<slot>`)
and soldier chips pass drags on to the page's ScrollContainer, and a card
takes a tap only when press and release are within 24 px; `get_squad(slot)`, `get_capacity(slot)`
(from a scratch `TacticsBattle`), `select_soldier(leader_slot, soldier_slot)`
(again to put it back), `get_picked()`, `move_selected_to(leader_slot) ->
bool` (false when full), `start_battle()`; signals `battle_requested(squads)`
and `back_requested`.

`TacticsMapView` (Control): `setup(battle, objective_cell)`, `cell_to_local`,
`local_to_cell`, `get_terrain_at`, `add_piece`, `get_piece(unit)`,
`get_pieces()`, `get_zones()`, `set_marks(marks)` (`reachable`, `threat`, `attackable`,
`skill_cells`, `area`, `selected`, `target`, `path`, `ghosts`),
`set_intents(intents)`, `set_zones(zones)`, `float_text(...)` (stacks above
text still rising from the same spot); signal `cell_tapped(cell)` (press and
release on the same cell within 24 px).

`TacticsPanel` (PanelContainer): `show_card(title, color, side_note,
lines)`, `get_card_texts()`, `show_forecast(left, right, note)`, `show_orders(current, text)`,
`set_buttons([{action, text, enabled, primary}])`, `get_buttons()`,
`get_order_buttons()`; signals `action_pressed(action)`,
`order_chosen(order)`.

`TacticsPlayback` (Node): `reset(units, zones)`, `await play(events)`,
`skip_step()`, `close_up_count`; signal `played` when the last step is
done, before the screen syncs the map (the map must already agree with the
battle then), and `phase_shown(side, round_number)` when a phase banner
starts, so the top bar and the panel say whose phase it is while the enemy
plays. Handlers are a registry by event type.
Squads step together (at most 0.55 s), soldier fights are batched (0.3 s
each, starts staggered at most 0.28 s apart and all within 1.1 s), a
leader's attack and every skill open the close-up.

`TacticsCloseUp` (Control): `await play_engagement(attacker, defender, hits,
is_first_strike, backdrop_kind)` (about 2.8 s for four hits and a counter),
`await play_skill(look, caster, targets, results, mark_text, title,
subtitle, backdrop_kind)` (the look's three layers, about 3 s), `skip()`,
`get_actors()`, `get_title()`, `get_subtitle()`, `is_playing`, `elapsed`.
A tap skips it. A skill's subtitle comes from
`TacticsText.skill_outcome(is_ours, hit_count, buffed_count, zone)`:
"Trúng 2 địch" (or "Trúng 2 quân ta" when the enemy cast it), "4 binh ta
được tăng công" ("binh địch" for the enemy's), "Để lại Lửa", joined with
" · ", or "Chiêu không tác động đến ai"; the skill preview's side note uses
the same words. It and its backdrop
process only while it plays.

## Log events

None: the battle logs its own events (see [Tactics](tactics.md)).

## How to extend

- A new leader skill's look: add `Data/Tactics/Looks/<skill>.tres` with its
  colours, motif, layers and timings and list it in `skill_looks.tres`. No
  code changes unless it needs a new piece.
- A new aura, path, impact or motif: add a drawing function to
  `TacticsSkillFx` and register it in its `_auras`, `_paths`, `_impacts` or
  `_motifs` dictionary; each draws as a pure function of the time.
- A new terrain or troop class: register its cell detail or glyph in
  `TacticsPainter._ensure_registries()` (a terrain also needs a fill in
  `TERRAIN_FILLS`); the close-up backdrop for a terrain is in
  `TacticsPlayback.BACKDROPS`.
- A new event type: add a handler to `TacticsPlayback._handlers`.
- Another scenario: point `Main.TACTICS_SCENARIO_PATH` at it (one scenario
  for now).

## Tests

- `Tests/tactics_screen_test.gd`: the river crossing through the screen's
  public methods: selection and its undo, a move preview (ghosts, no state
  change) and its confirm, the order picker, forecasts checked against the
  battle, skills aimed, previewed and cast (the preview's damage checked
  against the cast), the hint of each step (a moved leader, the forecast,
  the skill preview), and a scripted policy that wins (by rout in round 6);
  it counts close-ups and presses the result's button.
- `Tests/tactics_screen_sync_test.gd`: random taps (cells, leaders,
  enabled buttons, orders) on six seeds in instant mode; after every
  playback, before the sync, tokens, hp, deaths, pips, zones and the top
  bar's round and phase must match the battle, and after every tap the
  marks, buttons, intents and the "done" look must match its queries, with
  no error logged.
- `Tests/tactics_screen_input_test.gd`: real playback with taps pushed
  through the viewport: taps during a playback send nothing, a tap skips
  the close-up, the enemy card's intent words ("hành quân" when its arrow
  moves, "đứng chờ" when it stays), the top bar and panel during the
  enemy's phase, the rally's close-up line for our side and the enemy's,
  every skill outcome line, "Rút" during the enemy's phase (and its hint
  coming back after 3 s), and no error after the screen is freed
  mid-playback.
- `Tests/muster_test.gd`: Main's title "Chiến Dịch" to the muster screen,
  squads and capacities, a soldier moved and one refused, "Xuất quân" to the
  tactics screen with those squads, and a double "Rút" back to the title;
  then, with touch emulated, taps on a chip and a leader card move a
  soldier, and drags that start on a card or a chip scroll the page
  without picking or moving anyone.

Run one with
`godot --headless --path . --script res://Tests/tactics_screen_test.gd`.

## Known limits

- On a 360-px-wide phone a cell is 29 px, under the 44 px touch target the
  rest of the screen keeps (every button is at least 44 px); twelve columns
  across a portrait phone do not leave more.
- No reduced-motion setting exists in the project, so the close-up and skill
  effects always play (a tap skips them).
- One scenario (the river crossing), reached from the title; no campaign
  progress is saved.
- The muster screen moves soldiers only; it does not change leaders or
  their start cells.
- About 240 draw calls a frame on the map (tokens and their hp bars); the
  terrain is one.
