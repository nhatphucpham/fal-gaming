# Tactics sites

## Purpose

Places on a tactics map that a leader can use or take: villages, shrines,
camps and strongholds (keep, pass fort, watchtower). They give the map
things to do besides fighting: heal, recruit, loot, charge a skill, rest,
win supplies, hold ground. They do not decide who wins; the objective does
(see [Tactics objectives](tactics_objectives.md)).

## Layer and files

- Layer: simulation (rules), bridge (data, queries), presentation (icons,
  panel, playback).
- Code: `Native/src/tactics/tactics_sites.{h,cpp}` (the handlers),
  `tactics_sim_sites.cpp` (using a site, what each side knows, units that
  join or leave), `tactics_site_data.{h,cpp}` (`TacticsSiteData`),
  `tactics_battle_sites.cpp` (bridge queries); the screen in
  `Scenes/Tactics/` (`tactics_painter.gd` icons, `tactics_map_view.gd` site
  layer, `tactics_screen.gd` panel buttons and choice, `tactics_playback.gd`
  steps).
- Depends on: the tactics simulation (moves, karma, buffs, skill charge,
  incidents, vision).

## Data

`TacticsSiteData` (`Data/Tactics/Sites/*.tres`, id `site.<name>`), placed
by a map's `sites`, `site_cells` and `site_owners` (-1 none, 0, 1):

| Field | Meaning | Range |
| --- | --- | --- |
| `kind` | the handler: `site_kind.village`, `.shrine`, `.camp`, `.stronghold` | registered id |
| `reach_cells` | how far (Manhattan) a leader may stand to use it | 0..64 |
| `uses` | uses before a shrine is spent | 1..20 |
| `heal_pct` | village heal and camp rest, % of max hp | 0..100 |
| `recruits` | the two troops a village offers | 1+ |
| `supplies` | supplies a loot or a camp capture gives | 0..100 |
| `karma_kept`, `karma_burned`, `karma_looted` | karma points (see Karma) | 0..10 |
| `calm_radius_cells`, `bless_stat`, `bless_amount` | shrine calm reach and blessing | 0..64, a stat, -100..100 |
| `radius_cells` | camp rest reach | 0..64 |
| `capture_phases` | own phase ends on a stronghold to take it | 1..20 |
| `vision_cells` | sight a stronghold gives its owner | 0..64 |
| `armor_bonus` | armor for the owner's unit on it | 0..1000 |
| `reinforce_round`, `reinforce_leader`, `reinforce_squad` | the owner's reinforcements, once, from that round (0: none) | 0..99 |
| `ends_turn` | using it ends the leader's turn | bool |

The numbers in use: village heal 40%, recruits militia or hunter, loot 2
supplies, karma kept 1 / burned 1 / looted 2; shrine charge, calm (radius
2) or bless (+10% attack for the rest of the battle), one use; camp 2
supplies, rest 15% within 1 cell; keep and pass fort taken in 1 phase
(keep +10 armor, pass fort +5), sight 3; watchtower 2 phases, +5 armor,
sight 4, reinforcements
from round 6. The river pass fort brings Hổ Báo and a spearman from round
10.

## Rules

- A leader of the active side, still able to act, within `reach_cells`,
  takes one choice of one site a phase (`use_site`). It is never taken
  back: using a site ends the steps back (undo) for everyone.
- Village: heal (only with someone hurt in the squad), recruit one of two
  (only with room in the squad; the recruit joins the squad and, for us,
  the roster), or loot (supplies, burned). Used or burned, it is spent.
- Side B burns a village it knows is standing when it is in reach and it
  is not playing guard (see Tactics, Guard AI).
- Karma: our loot is `karma_looted` bait; a village the enemy burns is
  `karma_burned` bait for us; every village still standing when the
  battle ends is `karma_kept` rescue.
- Shrine: charge fills the leader's skill; calm settles wavering soldiers
  of the side within `calm_radius_cells`; bless buffs the squad.
- Camp: capture it (not with an enemy next to the leader) for supplies;
  at the end of its owner's phase, its hurt units within `radius_cells`
  rest.
- Stronghold: at the end of a side's phase, a leader of it standing on the
  stronghold with no enemy next to it adds one phase; with an enemy next
  to it the count waits (contested); with none of its leaders on it the
  count is lost. At `capture_phases` it changes hands. The owner's unit on
  it gets `armor_bonus`; the owner sees `vision_cells` around it. From
  `reinforce_round`, at the start of the owner's phase, its reinforcements
  arrive next to it, once.
- Fog: each side keeps a memory of each site, updated whenever it sees
  the site's cell. A site never seen is told only by its place and kind;
  a site seen keeps its last seen state (a village burned out of sight
  still stands for us). Events about sites carry who saw them.
- The panel: a leader with a site choice open stays open (not done).

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `use_site(unit, site, choice, option = 0) -> Array` | method | Events; [] and an error when refused |
| `can_use_site(unit, site, choice, option = 0) -> bool` | method | Whether `use_site` would be taken |
| `get_site_actions(unit) -> Array` | method | Sites in reach: `{site, site_id, cell, choices: [{choice, options, can, reason}]}` |
| `get_sites(side) -> Array` | method | Every site as that side knows it: `site, id, kind, cell, is_known, status (ready/used/burned), owner, uses, capture_side, capture_progress, capture_phases, burned_by, has_reinforced, reinforce_round, vision_cells, armor_bonus, reach_cells, is_visible` |
| `get_supplies(side) -> int` | method | Supplies won this battle |

## Log events

| Level | Event | Fields |
| --- | --- | --- |
| info | `site_used` | `unit`, `side`, `site`, `site_id`, `choice`, `option`, `cell`, `seen_mask` |
| info | `site_changed` | `site`, `site_id`, `side`, `kind` (used, looted, captured), `status`, `owner`, `cell`, `seen_mask` |
| info | `capture_progressed` | `site`, `side`, `progress`, `phases`, `kind` (advanced, contested, lost), `cell`, `seen_mask` |
| info | `unit_healed` | `unit`, `amount`, `hp_after`, `source_id` |
| info | `unit_arrived` | `unit`, `side`, `leader`, `cell`, `kind` (recruit, reinforce, wave, convoy), `unit_id`, `seen_to` |
| info | `supplies_gained` | `side`, `amount`, `total`, `source_id` |

`seen_mask` has bit 0 for side 0 and bit 1 for side 1: the screen plays the
step only for a side that saw it.

## How to extend

A new site of an existing kind is a `.tres` under `Data/Tactics/Sites/`
placed on a map. A new kind is a `SiteHandler` (choices, check, apply,
phase hooks, validate) added to `SITE_HANDLERS` in `tactics_sites.cpp`,
names and descriptions in `Locale/strings.csv` (`SITE_*`,
`SITE_CHOICE_*`), and an icon in `TacticsPainter.draw_site`.

## Tests

`Tests/tactics_site_test.gd` (every rule above, fog memory, undo and
determinism); `Tests/tactics_fuzz_test.gd` (sites on most seeds, uses
checked against `can_use_site`); `Tests/tactics_screen_sync_test.gd`
(icons, buttons and steps agree with the battle).

## Known limits

- The enemy AI loots villages but uses no shrine or camp choice, and a
  guard never burns.
- One site use per leader per phase, whatever the site.
