# Tactics screen

## Purpose

Shows a tactics battle on a phone and takes its taps: the muster screen
("Điểm binh") before it, the map with flat tokens, the bottom panel with a
unit card, an engagement or skill forecast and the buttons, the playback of
every event with sound, the side-view close-up of a leader's attack or skill,
and the result. With the [roster](tactics_roster.md) it also shows the
soldiers as people (faces, names, marks), the wavering mark and the
incidents as they fire, the after-battle summary and the roster with each
soldier's character sheet. It holds no rules: every list of cells, every target, the
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
  - `tactics_map_view.gd` (`TacticsMapView`): a clipping window onto the
    board, which zooms and pans; the board's layers redraw only when their
    content changes and a camera move only moves the board; the terrain is
    painted once into a `SubViewport` texture at the screen's pixel scale
    times the zoom (at most 2.5x), painted again only when a closer zoom
    needs more pixels.
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
  - `tactics_tip.gd` (`TacticsTip`): the first-time tips over the map.
  - `tactics_text.gd` (`TacticsText`): player-facing names from the catalog,
    plus runtime leaders (`register_unit`) and roster names (`person_names`).
  - `tactics_face.gd` (`TacticsFace`): a soldier's face drawn from its
    `look` seed (skin, head cover, eyes, brows, beard, scar); `FaceView`.
  - `tactics_views.gd` (`TacticsViews`): labels, panels, buttons, mark
    icons and the slide and stagger the menus share.
  - `tactics_summary_view.gd` (`TacticsSummaryView`): after the battle.
  - `tactics_roster_view.gd` (`TacticsRosterView`): the roster and the
    character sheet.
- Depends on: `TacticsBattle` and the tactics catalog
  (`Data/Tactics/tactics_catalog.tres`), `UnitView` and `CutsceneBackdrop`
  for the close-up figures and backdrop, `ResultBanner`, `PressButton`,
  `GameTheme`, `Palette`, `Sound`, `TacticsCampaign` and `TacticsRoster`
  (`Systems/Tactics/`). `Main.open_campaign()` loads the roster, builds a
  `TacticsCampaign` and opens the muster screen from the title's "Chiến
  Dịch" button; `Main.open_tactics()` opens
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
`FORECAST_*`, `SKILL_PREVIEW_*`, `INTENT_*`, `CLOSEUP_*`, `INCIDENT_*`,
`ROSTER_*`, `SUMMARY_*`, `NAME_*`, `BIO_*` and `BUTTON_*` rows.

Incidents on the map:

- A wavering soldier gets a bubble over its token: a gold star when the
  incident is good, a red "!" when it is bad, with a float of the
  incident's name and "?" and a tick. While one of ours wavers with a bad
  incident the hint line says "Binh dao động: kéo tướng lại gần nó."; with
  only good ones it says "Binh sắp lập công: cứ để nó.". Its card adds
  "Dao động (<incident>): <what it means and what calms it>". Dormant
  seeds are never shown.
- `incident_calmed`: the bubble goes, a float ("Đã yên", or "Tướng trấn
  an" when its leader did it), a soft sound.
- `incident_fired`: a ring burst and a flash on the soldier and its name
  in large type (0.8 s), the epiphany sound for a good one and the
  formation-break sound for a bad one; then its effect's own events.
- `mark_earned`: a medal rises and the token gains a gold diamond (up to
  three), with a coin sound.
- `unit_fled`: the token slides to its escape edge and fades.
- `unit_defected`: the token squashes and comes back in the other side's
  colours.

Taps (the flow a phone player uses):

- Tap one of our leaders: it is selected; blue cells are where it can
  still go with the move points it has left this phase, red rings the
  enemies it can strike (after a walk within those points too), cream
  circles its squad's slots, and the panel shows its card, the row of five
  orders and Kỹ năng, Chờ, (Hoàn tác,) Kết lượt. The card's turn line says
  what is left: "Còn 2/4 điểm đi · còn đòn đánh" (or "đã đánh"), and
  "Đã Chờ: xong lượt." once it waited.
- Tap a blue cell: the leader moves at once with its squad. While it has
  points left it stays selected with the blue cells it can still reach,
  and the hint says "Đi tiếp ô xanh, đánh địch viền đỏ, xong thì Chờ."
  (with no enemy in reach "Chưa với tới địch: chạm ô xanh, xong thì
  Chờ.", after its attack "Đã đánh: đi tiếp ô xanh, hoặc Chờ."); with
  none left, "Hết điểm đi: chạm địch, Hoàn tác hoặc Chờ." (with no
  enemy in reach "Hết điểm đi, chưa với tới địch: Hoàn tác hoặc Chờ.";
  with only its
  skill left, "Còn Kỹ năng: bấm Kỹ năng hoặc Chờ."). It may
  attack before or after moving, cast its skill as well, and change its
  order any number of times until it waits. "Hoàn tác" takes back one
  move at a time: `TacticsBattle.undo_move()` restores the exact state
  from before that move (same hash, points included), and the pieces slide
  home (0.25 s, card-flip sound). It is offered only while the battle
  allows it: after moves whose events were only moves and charge changes,
  until an attack, a skill, Chờ, an order change or the end of the phase
  (see the battle doc for the full list).
- Press on the selected leader and drag: the ghosts of the leader and its
  squad follow the finger over blue cells, with the path; lifting on a
  blue cell moves there, anywhere else (or a pinch) cancels. A finger
  that lands on any other piece and slides pans the map, so a pan never
  moves a leader.
- Tap a red-ringed enemy: the battle picks the cell to strike from
  (`get_strike_cell`, within the points left: not dying, fewest enemies
  able to reach it, least counter, better terrain, shortest walk) and the
  forecast shows the walk
  ("Đi 3 ô rồi đánh"), the ghosts and both sides' hits and hp
  (`forecast_move_attack`, exact). A second tap on the enemy or "Đánh"
  walks there and attacks, played as one. To choose the cell by hand, tap
  a blue cell first, then the enemy.
- Tap an order in the row: the squad takes it at once (its slots on the
  map follow); the line under the row says what it does. After Chờ the row
  is greyed out (only the current order stays bright).
- Chờ closes the leader: its squad strikes (if it has not yet) and the
  leader can do nothing more this phase. A leader is also done when
  nothing is left for it (`TacticsBattle.is_closed`: no cell to reach, no
  strike and no skill); its token dims. A leader that moved and still has
  points is not done, even with no enemy near. When all of ours are done, the hint
  says "Tự kết lượt…" and the phase ends after 1 s (1.8 s while the last
  move can be undone); any tap holds it, and "Kết lượt" is always there.
  Only Chờ closes a leader, but a leader that acted this phase (moved,
  struck or cast) and has no strike and no skill left has only walks:
  once every leader of ours is done or in that state (never at the start
  of a phase, even with no enemy in reach), "Kết lượt" turns primary and the hint says "Hết đòn để đánh: đi
  tiếp, hay Kết lượt.", so one tap ends the phase instead of a Chờ per
  leader. "Kết lượt" asks nothing; the open leaders' squads strike as at
  any end of phase. The phase does not end by itself then: a walk may
  still matter.
- Tap any unit for its card: hp, a leader's skill and charge, its order
  (an enemy leader's declared intent instead), and its passives and
  keywords with what they do ("Vũ khí dài: Bị áp sát thì ra đòn trước.").

First-time tips: the first time the player selects a leader of ours,
moves one (a move that can be taken back), first spends its last move
point on such moves, changes an order and sees a soldier of ours waver
with a bad incident, one line slides up in a
gold-edged box just above the panel with the text-blip sound, stays 4.5 s
and fades ("Tướng đi đâu, toán binh dàn quanh đó.", "Còn điểm thì đi
tiếp. Xong thì bấm Chờ.", "Đi nhầm? Hoàn tác lùi từng bước
tới khi đánh hay đổi lệnh.", "Đổi lệnh không mất lượt: tướng vẫn đi,
đánh được.", "Dấu ! đỏ: binh sắp gây chuyện. Đưa tướng lại gần nó.", or
for a soldier out of its leader's sight "Binh khuất mắt tướng chỉ yên
khi tướng thấy nó: đưa tướng tới."; the `TACTICS_TIP_*` rows). A tip that comes while another shows waits for it.
Each is saved as shown (`RunSettings.save_seen_tip("tactics.<id>")`) and
never offered again. Tips never catch taps.

Map camera: it opens at the zoom that fits eight columns across (90 layout
px a cell, 45 px on a 360-px-wide phone), centred on our leaders; one
finger drags it (a press that slides more than 24 px is a drag, not a
tap), two fingers pinch it between the whole board and 1.4x that zoom
(the mouse wheel too), and "Toàn cảnh" / "Phóng to" switches to the whole
board and back. Every leader move, attack and soldier fight in the
playback brings it into view (0.28 s glide) unless it is already well
inside. A tap never moves the camera while what it tapped is in view
(`reveal`), so a second tap lands on the same piece: a fast double tap on
an enemy strikes it. When our phase begins with no leader of ours on
screen (the enemy's moves or a drag took the camera away), it glides back
to the first one.

Campaign flow: muster (roster soldiers fill the squads; named soldiers are
extra leaders of ours, returning traitors extra enemy leaders) → battle →
summary (also after a retreat) → "Tiếp tục" back to the muster. The
campaign takes the catalog's scenarios in turn, one per battle fought:
the river crossing, then the night raid, then the river again.

Fog, weather and night (see [Tactics vision](tactics_vision.md)):

- One `TextureRect` over the terrain and under the zones and marks holds an
  `ImageTexture` of one pixel a cell, drawn with linear filtering so the
  edges are soft: never-seen cells near black, seen ones dimmed, visible
  ones clear; at dusk and night the visible cells take the night tint
  (`darkness_pct`) except the lit ones, which glow warm. A change blends
  the old colours to the new (one write a frame of only the cells that
  change, `fog_change_count` blends) with the soft `fog_reveal` sound;
  nothing is written while nothing changes. No shader, no node per cell.
  A walk's sight changes (the leader's and each soldier's, which the
  battle sends between the steps) are folded into the walk: the squad
  still steps with its leader, the fog blends once over the walk's own
  time (at least 0.15 s), and enemies spotted show after it; alone (a
  death, a flight) a change blends over 0.25 s. So a walk under fog draws
  about as many frames as one without: on the web build (Chromium,
  iPhone 13, software GL, where every drawn frame costs about 100 ms) a
  river walk went from 11-13 drawn frames (22.1-23.3 ms average, p95
  100 ms) to 5-9 (19.2-21.2 ms, p95 16.8 ms on three of four walks); an
  idle map still draws nothing.
- Hidden enemies have no piece shown; one seen walking out of sight fades
  at the end of its walk, and a hidden enemy's move plays at once. A
  "last seen" ghost (a dimmed token with "?") stands where the battle
  remembers each enemy; it goes when that enemy is seen again or its cell
  is seen empty. A hidden enemy's own steps (its charge, buffs, passives,
  order, wait, wavering, incident, mark, a hit or its death:
  `TacticsPlayback.PRIVATE_STEPS`) play no sound, ring, word or pause;
  they only set its hidden piece. One that defects to us fades in.
- An ambush: the hidden enemy bursts into sight with a ring and "Phục
  kích!", the walker shakes, sound `ambush`; the camera follows.
- The objective (gold frame and flag) is drawn over the fog and the
  night, and its cell is never darker than a cell seen before: it is
  known from the map. While it is out of view a gold flag mark on the
  edge of the map view points at it (`get_edge_marks()` entries with
  `is_objective`), so at the night raid's dark start you know which way
  to go. Edge marks keep their pointer inside the view, clear of the top
  bar.
- A wavering soldier of ours out of view gets a mark on the edge of the
  map view pointing at it; its card says when it is out of its leader's
  sight ("Ngoài tầm mắt tướng: dễ dao động, chưa trấn an được"; never on
  an enemy's card). One that wavers only because it is out of sight
  (`is_wavering_unseen`) gives that reason and cure on its wavering line
  ("khuất mắt tướng; cho tướng thấy nó") instead of its incident's own;
  while a bad wavering soldier is out of its leader's sight (or wavers
  for it) the hint says "Binh khuất mắt dao động: cho tướng thấy nó." and
  the first time it offers the tip `waver_unseen` instead of `waver`
  (which names no incident: "binh sắp gây chuyện").
- The weather and time chip (top right of the map, 132 x 88): their icons;
  a tap shows both descriptions, the coming weather change and the fog
  line on the panel. A round before the weather turns, a banner says so;
  each change of weather or time plays a banner with its one-line
  description (wrapped onto a taller band when it does not fit) and the
  `weather_turn` sound.
- The first battle with fog offers the fog tip ("Ô tối: chưa thấy...").
- Muster: a "Trời đất" panel under our forces with the weather and time
  icons and lines, the weather change, the time cycle, the fog line and
  the scouts we bring; scouts carry an eye badge on their chips.

## Public API

`TacticsScreen` (Control). Set `scenario` (and `squads` from the muster)
before adding it. The tap methods are the ones the map and panel call, so a
test drives the screen through them.

| Member | Kind | Description |
| --- | --- | --- |
| `scenario`, `squads`, `catalog`, `player_side` | property | The battle to load; `squads` empty keeps the scenario's; the side not `player_side` is played by the AI |
| `is_instant` | property | Tests: playback steps end at once, close-ups are counted but not shown, camera moves and the auto end's beat are immediate |
| `auto_end` | property | End our phase by itself once every leader of ours is done (default true) |
| `tap_cell(cell)` | method | A tap on the map: select, move at once (a blue cell), forecast a strike (a red-ringed enemy), confirm (a second tap on the target or the skill cell), or step back (a tap elsewhere) |
| `select_unit(unit)`, `move_to(cell)`, `undo()`, `confirm()`, `cancel()` | method | Select a unit; move the selected leader; take its move back; confirm the strike or skill previewed; step back one level |
| `press_button(action)`, `choose_order(order)` | method | A panel button (`end_turn`, `wait`, `skill`, `undo`, `attack`, `cast`, `cancel`); an order of the row |
| `is_auto_end_pending()` | method | The phase is about to end by itself |
| `campaign`, `squad_people` | property | Optional `TacticsCampaign` and the person ids per squad slot (from the muster): the battle gets the rules, karma and records before it starts, and its end opens the summary |
| `get_summary()` | method | The `TacticsSummaryView` shown, or null |
| `campaign_continue_requested` | signal | The summary's "Tiếp tục" |
| `retreat()` | method | "Rút": the first tap asks, a second within 3 s emits `home_requested` (with a campaign: shows the summary, the battle counted as a retreat). The top bar sits above the skip catcher and the close-up, so it works during any playback |
| `get_round_text()` | method | The top bar's round and phase line |
| `is_busy()`, `get_mode()`, `get_selected()` | method | Playback running; `Mode` (`IDLE`, `SELECTED`, `MOVE_PREVIEW` (a drag), `FORECAST`, `SKILL_TARGET`, `SKILL_PREVIEW`, `BUSY`, `ENDED`); the selected unit |
| `get_battle()`, `get_map()`, `get_panel()`, `get_playback()`, `get_close_up()`, `get_result_banner()`, `get_retreat_button()`, `get_hint()` | method | Parts and the hint line, for tests and screenshots |
| `home_requested` | signal | The result's "Về màn hình chính" or a confirmed retreat |
| `became_idle` | signal | After each playback, when the next tap is taken |

`MusterScreen` (Control): `scenario`; its leader cards (`LeaderCard<slot>`)
and soldier chips pass drags on to the page's ScrollContainer, and a card
takes a tap only when press and release are within 24 px; `get_squad(slot)`, `get_capacity(slot)`
(from a scratch `TacticsBattle`), `select_soldier(leader_slot, soldier_slot)`
(again to put it back), `get_picked()`, `move_selected_to(leader_slot) ->
bool` (false when full), `start_battle()`; signals `battle_requested(squads)`
and `back_requested`. With `campaign` set it takes the campaign's
scenario and squads and moves the person ids with the soldiers
(`get_people()`); chips show the soldier's face, troop glyph, short troop
name (`TROOP_<X>_SHORT`: "Giáo", "Cung") on its own line under the face
and marks; a
named leader's card shows its face and name; the enemy panel lists
returning traitors; "Sổ quân" opens the roster (`open_roster()`).

`TacticsSummaryView` (Control): `campaign`, `summary` (from
`TacticsCampaign.finish_battle()`), `player_side`, `is_instant`; a card per
soldier named in this battle (face, name, biography), every roster soldier
who fought with its fate and new marks (named first, the fallen last), the
karma line; buttons "Sổ quân" (`open_roster()`) and "Tiếp tục"
(`continue_requested`). The epiphany sound plays when someone was named.

No text on the muster, the roster, the character sheet or the summary is
under `GameTheme.SMALL_FONT_SIZE` (`TacticsViews.label` and the muster's
labels raise a smaller size to it), and a roster row is at least 88 layout
px tall.

`TacticsRosterView` (Control): `campaign`; `show_list()` (named first,
then the living, traitors, deserters, the fallen), `show_sheet(id)`
(face, name, troop and first leader, status, what a named one leads with,
biography, each mark with its round, place and leader), `get_sheet_id()`,
`close()`; signal `closed`. Built on open; it never redraws on its own.

`TacticsMapView` (Control, fills the space between the top bar and the
panel): `setup(battle, objective_cell)`, `cell_to_local` and
`local_to_cell` (board coordinates), `view_to_cell`, `board_to_view`,
`view_to_board`, `get_terrain_at`, `add_piece`, `get_piece(unit)`,
`get_pieces()`, `get_zones()`, `set_marks(marks)` (`reachable`, `threat`,
`attackable`, `skill_cells`, `area`, `selected`, `target`, `path`,
`slots`, `ghosts`; an equal value is ignored), `set_intents(intents)`,
`set_zones(zones)` (likewise), `float_text(...)` (stacks above text still
rising from the same spot, stays inside the part of the board on screen
with its rise, never under `GameTheme.SMALL_FONT_SIZE`); camera: `center_on(point)`, `follow(point)`,
`reveal(point)` (only when it is out of view),
`zoom_to(zoom, point, smooth)`, `toggle_whole_map()`, `get_zoom()`,
`get_default_zoom()`, `get_whole_zoom()`, `get_max_zoom()`,
`get_cell_px()`, `get_camera_offset()`, `is_whole_map()`, `is_in_view()`,
`is_camera_moving()`, `get_whole_map_button()`, `get_layer_draw_count()`
(tests); `hold_cells` (where a press starts a drag), `is_instant`;
signals `cell_tapped(cell)` (press and release on the same cell within
24 px), `cell_held(cell)` (a press on a hold cell, then each new cell under
the finger), `hold_released(cell)`, `hold_cancelled()`.

`TacticsPanel` (PanelContainer, 430 layout px tall): `show_card(title,
color, side_note, lines)` (up to four lines, each wrapped; the lines that
no longer fit are left out from the last one up, never cut),
`get_card_texts()`, `get_shown_card_lines()`,
`show_forecast(left, right, note)`, `show_order_row(current, text,
enabled)`, `hide_order_row()`, `is_order_row_shown()`,
`get_current_order()`, `get_order_note()`, `set_buttons([{action, text,
enabled, primary}])`, `get_buttons()` (the same keys plus `button`), `get_order_buttons()`; signals
`action_pressed(action)`, `order_chosen(order)`. Order buttons are 88 px
tall, action buttons 92 px (44 and 46 px on a 360-px-wide phone); no text
on the screen is under `GameTheme.SMALL_FONT_SIZE` (22 layout px, 11 px on
that phone).

`TacticsPlayback` (Node): `reset(units, zones)`, `await play(events)`,
`skip_step()`, `stop()` (no further step starts; the summary uses it),
`close_up_count`; signal `played` when the last step is
done, before the screen syncs the map (the map must already agree with the
battle then), and `phase_shown(side, round_number)` when a phase banner
starts, so the top bar and the panel say whose phase it is while the enemy
plays. Handlers are a registry by event type.
A leader's move plays with its squad setting off one step behind (squads
at most 0.55 s), soldier fights of a squad are batched (0.3 s each, starts
staggered at most 0.14 s apart and all within 0.6 s), a leader's attack
plays on the map (lunge or shot, heavy hit, the numbers, the counter with
a block sound; 0.5 s), and only a skill or a blow that kills a leader
opens the close-up. The camera follows the leader's move, its target and
each squad's fights.

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
- A new incident: its playback needs nothing; add its `INCIDENT_<X>` and
  `_HINT` rows and a `BIO_MARK_<X>_FORMAT` row.
- Another scenario: point `Main.TACTICS_SCENARIO_PATH` at it (one scenario
  for now).

## Tests

- `Tests/tactics_screen_test.gd`: the river crossing through the screen's
  public methods and the map's signals: selection (its buttons and the
  order row) and stepping back, a drag preview (ghosts, no state change),
  a one-step tap that moves at once and keeps the leader selected with
  the cells its points still reach, the turn line on its card, a second
  move, two "Hoàn tác" each back one move to the same hash, a drag
  released on a cell, one tap on the order row (slots and the description
  follow), strikes by tapping the enemy twice or "Đánh" (the walk, the
  ghosts, the forecast against the battle), skills aimed, previewed and
  cast (the preview's damage checked against the cast), the hint of each
  step, and a scripted policy that wins; it counts close-ups and presses
  the result's button. Before each "Kết lượt" of that policy, the button
  is primary exactly when every leader is done or acted and has no strike
  and no skill left, with the hint saying so (some phase must end that
  way; not the first phase before any move), and
  a leader that struck with points left says so in the hint. The first select, move and order change each offer
  their tip once, the shown one with its text, and a new tip view never
  shows a saved tip again.
- `Tests/tactics_feel_test.gd`: the default zoom (a cell at least 88
  layout px), an idle map with a leader selected drawing no frame and no
  layer, a one-finger drag through the viewport panning without a redraw
  or a selection, a tap and a press-drag-lift on a leader through the
  viewport, a pinch, "Toàn cảnh" and back, the auto end (held by a tap in
  its beat, then ending a phase without "Kết lượt"), the taps of full
  turns (9 for three leaders that each walk and strike), and that nothing
  is cut or too small at 720 layout px wide: every hint fits the top bar,
  every unit's card shows its first two lines whole (each incident's
  wavering line too), no label is clipped by its panel, no text is under
  the small font size and every button is at least 88 px tall; a float
  at the corner of a zoomed view is drawn inside it, and one asked for
  at 18 px is drawn at the small font size; a hidden enemy's incident,
  wait and hit play no step and add no effect, a seen one's do.
- `Tests/tactics_screen_sync_test.gd`: random taps (cells, leaders and
  marches toward the enemy, drags,
  enabled buttons with undo, the order row) on six seeds in instant mode,
  with the auto end on (waited out); after every
  playback, before the sync, tokens, hp, deaths, pips, zones and the top
  bar's round and phase must match the battle, and after every tap the
  marks (strike targets, slots), the order row (greyed out exactly when
  the leader can no longer act), the card's turn line, buttons (undo only
  when the battle can), intents and the "done" look must match its
  queries, with
  no error logged. Odd seeds play through a campaign with forced incident
  seeds: each token's side, wavering bubble and mark count must match the
  battle, and some incident steps must have played.
- `Tests/tactics_screen_input_test.gd`: real playback with taps pushed
  through the viewport: taps during a playback send nothing, a tap skips
  the close-up, the enemy card's intent words ("hành quân" when its arrow
  moves, "đứng chờ" when it stays), the top bar and panel during the
  enemy's phase, a leader of ours on screen when our phase starts after
  the camera was moved away, the rally's close-up line for our side and the enemy's,
  every skill outcome line, "Rút" during the enemy's phase (and its hint
  coming back after 3 s), with a campaign a double "Rút" while the enemy
  plays opening the summary with nothing playing on behind it, and no
  error after the screen is freed mid-playback.
- `Tests/tactics_touch_test.gd`: touches pushed as a phone sends them
  (the first finger's emulated mouse event and touch, a second finger's
  touch) with real camera glides: a slide from a leader that is not
  selected pans and moves no one, a drag of the selected leader lifted
  over the panel or on a cell it cannot reach moves nothing, a pinch begun
  on the selected leader zooms and moves nothing, a fast double tap on
  an enemy in the view's outer row strikes it without the camera moving,
  and after a one-step move a double tap on an enemy walks there within
  the points left and strikes.
- `Tests/muster_test.gd`: Main's title "Chiến Dịch" to the muster screen,
  squads and capacities, a soldier moved and one refused, "Xuất quân" to the
  tactics screen with those squads, a double "Rút" to the summary (the
  roster then counts one battle), "Tiếp tục" back to the muster and "Về"
  to the title;
  then, with touch emulated, taps on a chip and a leader card move a
  soldier, and drags that start on a card or a chip scroll the page
  without picking or moving anyone; last, with a roster holding marks, a
  named soldier and a traitor, no text on the muster, the roster, three
  character sheets or the summary is cut or under the small font size,
  and no button is under 88 px.

Run one with
`godot --headless --path . --script res://Tests/tactics_screen_test.gd`.

## Known limits

- The default zoom shows eight columns and about nine rows; the rest of
  the board is a drag (or "Toàn cảnh") away. At the whole-map zoom a cell
  is under the 44 px touch target again.
- Undo steps back over the plain moves of the selected leader only: a
  move during which the squad attacked, a passive fired, a zone was made,
  a rescue counted or an incident stirred cannot be taken back, and an
  attack, a skill, Chờ or an order change clears what could be.
- A melee leader that strikes ends next to its target and is held there
  by the zone of control, so it usually closes on its own; when the blow
  kills, it is free again with its points left and needs Chờ (or the end
  of the phase).
- The auto end also ends the phase while a soldier of ours wavers (the
  leaders have nothing left to do about it); a tap during the beat holds
  it.
- No reduced-motion setting exists in the project, so the close-up and skill
  effects always play (a tap skips them).
- One scenario (the river crossing), reached from the title; only the
  roster is saved between battles.
- In fast playback (taps skipping steps) floats from several incidents and
  hits can pile up over the same tokens.
- The muster screen moves soldiers only; it does not change leaders or
  their start cells.
- About 125 draw calls a frame on the map at the start and 180 with a
  leader selected (360x640, Mesa), from about 240 and 250 before the zoom
  (tokens outside the view are clipped); the terrain is one. An idle map
  draws no frame.
