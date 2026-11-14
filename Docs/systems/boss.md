# Boss (Cự Nham)

## Purpose

The last stage's boss: Cự Nham, a stone giant with one rule, Hóa Đá, that
punishes bursts of skills. It is a unit with the boss flag; its rule is an
ordinary passive in the simulation, so it is deterministic and in the state
hash.

## Layer and files

- Data: `Data/Bosses/cu_nham.tres` (`unit.boss_cu_nham`),
  `Data/Classes/colossus.tres`, `Data/Passives/hoa_da.tres`,
  `Data/Stages/stage_12.tres`.
- Simulation: `Native/src/skill/skill_passives.cpp` (trigger
  `trigger.enemy_skill_resolved`, sliding window), `skill_cast.cpp` (the
  notification), `skill_effects.cpp` (`effect.petrify`),
  `battle_sim_actions.cpp` (immunity, no action).
- Presentation: `Scenes/Board/extra_figures.gd` (the figure),
  `unit_view.gd` and `stone_layer.gd` (1.6x size, stone look, crumble),
  `Scenes/Run/boss_hud.gd`, `UI/boss_badge.gd`, `UI/boss_card.gd`,
  `UI/boss_bar.gd`.

## Data

| Field | Value |
| --- | --- |
| `UnitData.is_boss` | true: never in the shop, the sandbox roster or a save; drawn 1.6x; its hp shows in the boss bar. |
| Class `class.colossus` | 2100 hp, 60 attack, 55 attacks per 100 s, range 1, armour 50, magic resist 40, hits a row of 3, blocks arrows, immune to knockback, stops charges. |
| Passive `passive.hoa_da` | trigger `trigger.enemy_skill_resolved`, `every_nth` 3, `window_ticks` 60, effect `effect.petrify` on itself for 40 ticks. |
| `run_rules.boss_stage` | 12: that stage holds exactly one boss (validated). |
| `run_rules.boss_reveal_stage` | 6: from here the prep top bar shows the boss badge. |
| Stage 12 | 7 units: the boss and 6 guards. |

## Hóa Đá

- `trigger.enemy_skill_resolved` fires on each unit of the other side when
  a skill resolves (not an after-skill), in unit index order, after the
  skill's effects.
- `PassiveDef.window_ticks` > 0 makes `every_nth` a sliding window: the
  trigger's ticks older than `window_ticks` are dropped, the new one added,
  and at `every_nth` hits the passive fires and the window empties. The
  window is in the state hash (as ages).
- `effect.petrify` cancels a cast and applies `status.petrified`. While it
  lasts the unit takes no damage (each hit becomes a `damage_dealt` of 0
  with `is_immune`, no Khí, no on-hit passives, no reflection), does not
  act (no move, attack, cast or volley) and its own passive neither fires
  nor counts, so a stream of casts cannot keep it stone forever.
- So the third player skill within 3 s turns the boss to stone for 2 s.

## Presentation

- On the board the boss is drawn 1.6x on its one cell (the GDD's 2 cells
  are not simulated). Petrified: grey, not breathing, a pale sheen and
  cracks, the status icon, a "Hóa Đá" popup and the petrify sound.
- In the boss battle the wide boss bar (name, hp, trailing band, quarter
  ticks; grey with "Hóa Đá" while stone) takes the stage title's place in
  the top bar, so it covers no unit. It gives the place back when the
  banner's "Tiếp tục" leaves the battle (also before the reward cards
  after a loss).
- From stage 6 the prep top bar shows a red "Trùm" badge (pulsing at stage
  12). Tapping it opens the boss card: the figure, its rule in one sentence
  and the hint "Mẹo: đừng tung chiêu dồn dập." The card closes when the
  battle starts (also when the prep timer runs out while it is open).
- When the boss falls it shakes, cracks and crumbles instead of falling; a
  win over it plays "win" and stamps "Cự Nham đã vỡ!" with confetti; the
  banner follows 1.6 s later without a sound of its own.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `UnitData.is_boss` | property | The boss flag. |
| `StageData.get_boss_slot(catalog)` | method | The stage's boss slot or null. |
| `RunState.is_boss_stage()` | method | True on `boss_stage`. |
| `BattlePlayback.unit_petrified(index, is_petrified)` | signal | For the boss bar. |
| `BossHud.show_prep / open_card / close_card / begin_battle / on_tick / end_battle / play_victory` | methods | The run screen's boss views. |

## Tests

`Tests/boss_test.gd`: Hóa Đá against a reference sliding-window model
(fires exactly on the third cast inside 60 ticks, not on spaced casts), no
damage and no action while petrified, determinism, stage 12 (7 units, one
boss), the shop never offering it, a save with it refused, the 1.6x view.
`Tests/run_flow_test.gd`: on the real run screen the boss card closes at
battle start, the boss bar is gone at the reward cards after a stage-12
loss, and a win shows the victory moment before the banner.

## Known limits

- One cell in the simulation (the GDD asks for 2).
