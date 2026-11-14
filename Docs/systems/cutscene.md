# Cutscene

## Purpose

Short dialogue scenes over the run screen, driven by data: a painted band
with two speakers, typewriter lines, and optionally two choice cards. Used
for every Kỳ Ngộ ([epiphany.md](epiphany.md)) and once per run for the story
scene before the boss stage. It shows and returns a choice; it changes no
rule itself.

## Layer and files

- Layer: presentation.
- Code: `Scenes/Cutscene/` (`cutscene_data.gd`, `cutscene_screen.gd`,
  `cutscene_backdrop.gd`, `ink_wipe.gd`, `cutscene_choice_card.gd`,
  `epiphany_cutscene.gd`); `Scenes/Run/run_interludes.gd` plays them in the
  run.
- Depends on: UnitPainter figures (and `ExtraFigures` for the sage),
  `Sound` for the text blips and the choice sound.

## Data

`CutsceneData` (`Data/Cutscenes/*.tres`, or built at run time):

| Field | Meaning |
| --- | --- |
| `id` | `cutscene.<name>`. |
| `backdrop` | `backdrop.mountain` (Kỳ Ngộ) or `backdrop.camp` (story). |
| `left_unit`, `right_unit` | Unit ids; `unit.sage` is the sage (not in the catalog). |
| `line_keys` | Translation keys, in order. |
| `line_speakers` | `0` (left) or `1` (right), one per line. |
| `choice_titles`, `choice_texts` | Empty, or exactly two each. |

`Data/Cutscenes/story_before_boss.tres`: Liễu Mi and Ba Khắc at the camp,
5 lines about Cự Nham and its rule.

## Behaviour

- The screen dims the run, the band (about 40% of the height) is wiped in
  with an ink brush, the two figures stand on it at 4.4x and breathe; the
  speaker is lit, the other dimmed, the right one mirrored.
- A line types at 38 characters a second with a blip every 3 characters.
  A tap finishes the line; the next tap goes on. Taps during the wipe do
  nothing.
- "Bỏ qua" skips the remaining lines. With choices it lands on the two
  cards, which nothing skips; without, the scene ends.
- Choosing a card flashes gold, pops the card, wipes the band out with ink
  and emits `finished(choice)` (-1 without choices).
- In the run: after the banner's "Tiếp tục" (and when a run is loaded in
  its reward phase) a pending Kỳ Ngộ plays first; its choice goes to
  `RunState.choose_epiphany`, the run is saved, the synergy views refresh,
  then the reward cards show. The story plays when a reward choice moves
  the run from stage 11 to 12 (so once per run; replays of stage 12 come
  from stage 12), before the preparation starts.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `CutsceneScreen.present(data, catalog, title = "")` | method | Starts the scene. |
| `tap()`, `skip()`, `choose(index) -> bool` | methods | What the input does; tests call them. |
| `get_line_index()`, `get_visible_text()`, `is_line_complete()`, `is_choosing()`, `is_done()`, `get_choice_texts()` | methods | State for tests. |
| `finished(choice: int)` | signal | The ink has wiped the band away. |
| `EpiphanyCutscene.build(run) -> CutsceneData` | static | The pending Kỳ Ngộ's scene (null without one). |
| `RunInterludes.play_epiphany(then)`, `play_story_if_due(previous_stage, then)` | methods | Run integration. |

## How to extend

A new scene is a `CutsceneData` file with its lines in
`Locale/strings.csv`; a new backdrop is a name in `CutsceneData.BACKDROPS`
and its drawing in `CutsceneBackdrop`.

## Tests

`Tests/cutscene_test.gd`: the story data, stepping through lines (tap
finishes, tap moves on, taps during the wipe do nothing), skip ending a
scene without choices, a Kỳ Ngộ scene skipping to its cards, taps and skips
not passing them, and the choice returned. `Tests/run_flow_test.gd` passes
a Kỳ Ngộ cutscene in the real run screen.

## Known limits

- The speakers face the viewer (the figures have only up and down views);
  the right one is mirrored.
