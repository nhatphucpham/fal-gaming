# Tactics roster

## Purpose

Sổ quân: keeps every soldier of ours as a person between tactics battles.
A person has a stable id, a face, a status and the marks (Dấu) incidents
left on it. The muster prefers roster soldiers. Death is permanent. A
soldier with three marks gets a name and a biography and leads a small
squad of its own. A deserter or traitor with two marks comes back as an
enemy leader the next time `river_crossing` is played. The roster does not
decide what happens in a battle; the [Tactics](tactics.md) simulation
does, and the roster reads its end-of-battle report.

## Layer and files

- Layer: game systems (GDScript), between the screens and the bridge.
- `Systems/Tactics/tactics_roster.gd` (`TacticsRoster`): the people, karma
  and the versioned JSON save.
- `Systems/Tactics/tactics_campaign.gd` (`TacticsCampaign`): one muster and
  battle. It fills the squads, adds named and returning leaders, sets up
  the battle's incidents, karma and records, and writes the report back.
- `Systems/Tactics/tactics_biography.gd` (`TacticsBiography`): names and
  biographies from Locale templates.
- Screens: `Scenes/Tactics/muster_screen.gd`, `tactics_roster_view.gd`
  (roster and character sheet), `tactics_summary_view.gd` (after the
  battle), `tactics_face.gd` (faces). See
  [Tactics screen](tactics_screen.md).
- Depends on: `TacticsBattle` (`set_incident_rules`, `set_karma`,
  `set_unit_record`, `set_incident_seed`, `get_battle_report`), the
  catalog's `incident_rules` and `SaveReader`.

## Data

Save file `user://tactics_roster.json` (`TacticsRoster.path`; tests set
their own), `version` 1. A wrong version or a broken file is warned about
once and replaced by an empty roster.

| Field | Meaning |
| --- | --- |
| `seed` | Roster seed, as a decimal string. Battle seed = hash(seed, battles) |
| `battles` | Battles fought (a retreat counts) |
| `next_id` | Next person id |
| `karma_bait`, `karma_rescue` | Karma carried into the next battle |
| `troop_counts` | Per troop id, how many were recruited: a person's `number` |
| `people` | `[{id, troop, number, look, status, first_leader, is_named, marks}]` |

`status` is one of `active`, `dead`, `deserted` or `traitor`. `marks` is a
list of `{incident, leader_id, terrain, round, battle}`. `look` is the
face seed, spread from the roster seed and the id.

The roster numbers come from `TacticsIncidentRulesData`
(`Data/Tactics/Incidents/incident_rules.tres`):

| Field | Default | Meaning |
| --- | --- | --- |
| `marks_to_name` | 3 | Marks that name a soldier; the name and biography use the first this many |
| `traitor_marks_to_return` | 2 | Marks a deserter or traitor needs to come back as an enemy leader |
| `karma_keep_pct` | 50 | Share of (carried + this battle's) karma kept for the next battle |
| `named_lead_capacity` | 2 | Soldiers a named leader leads |
| `named_hp_pct` | 130 | A named leader's hp, as % of its class (scenario leaders use 150..200) |
| `named_attack_pct` | 110 | % of its troop's attack |
| `named_skill` | `tactics_skill.named_rally` | Skill of every named leader |

## Rules

- Muster: each troop slot of the scenario's squads takes the active,
  unnamed roster person of that troop with the most marks (then the lower
  id) that is not taken yet. With none left, a recruit is made. The muster
  screen can move people between leaders, as it moves soldiers.
- Named soldiers (active, `is_named`) muster as extra leaders of ours on the
  spare spawn cells (`spawn_cells_a` beyond the scenario's leaders; 2 on
  `river_crossing`). Such a leader has id `leader.named_<id>`, the troop's
  figure, ranges, move and keywords, `named_lead_capacity`, hp and attack
  as above, the `mark_passive` of the incident most of its marks name (the
  earliest wins a tie), and `named_skill`. It starts with no soldiers; move
  some to it in the muster.
- Returning enemies: deserters and traitors with at least
  `traitor_marks_to_return` marks take the spare enemy spawn cells (1 on
  `river_crossing`). Each is built the same way, with a squad of
  `named_lead_capacity` soldiers of its troop, and gets its name.
- Before the battle starts: `set_incident_rules(rules, battle seed)`,
  `set_karma(A, carried bait, carried rescue)`, then for every roster unit
  `set_unit_record(unit, person id, good marks, bad marks)`. The good or bad
  count is how many of its marks name a good or a bad incident.
- After the battle (or a retreat), each report row with a person:
  - Its marks are added.
  - Status: `dead` → dead. Fled → deserted (ours). Defected → traitor (ours)
    or active (a returning enemy who came over). Otherwise unchanged.
  - An enemy soldier who defected to us and is alive becomes a recruit,
    with its marks.
  - An active, unnamed person who now has `marks_to_name` marks is named.
  - Karma for the next battle = (carried + this battle's) ×
    `karma_keep_pct` / 100, for bait and rescue.
  - The roster is saved.
- Name: the number word (`NAME_NUMBER_n`: Cả, Hai, Ba, Tư, Năm, Sáu, Bảy,
  Tám, Chín, Mười, cycling) plus the place word of the terrain where most
  of the first `marks_to_name` marks were left (`NAME_PLACE_<TERRAIN>`;
  the earliest wins a tie). Example: "Bảy Cầu", the seventh spearman, two
  marks at the bridge.
- Biography: `BIO_OPENING_FORMAT` ("Binh giáo thứ bảy của toán Liễu
  Mi."), one `BIO_MARK_<INCIDENT>_FORMAT` line per first mark (when,
  terrain, leader), then `BIO_CLOSING_FORMAT` ("Người trong toán gọi là
  Bảy Cầu."). "When" is `BIO_WHEN_ROUND_FORMAT` ("Vòng 2") when those
  marks are from one battle, else `BIO_WHEN_BATTLE_FORMAT` ("Trận 1, vòng
  2"), so two alike marks from two battles never read as one sentence
  twice. Later marks change neither the name nor the biography.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `TacticsRoster.load_roster(path = "")`, `create(seed = 0)`, `delete(path = "")` | static | Load (empty roster when missing or unreadable), make, remove |
| `save(path = "") -> bool`, `to_save_data()` | method | Write; the dictionary written |
| `recruit(troop_id, leader_id) -> Dictionary` | method | A new active person |
| `get_person(id)`, `find_soldiers(troop_id, taken)`, `get_named()`, `get_returning(min_marks)` | method | Lookups |
| `TacticsRoster.main_incident(person)` | static | The incident most of its marks name |
| `TacticsCampaign.new(roster, catalog, scenario)` | constructor | Builds `scenario`, `squads`, `people`, `leader_people`, `enemy_people`, `runtime_leaders` |
| `prepare_battle(battle, people) -> bool` | method | Rules, karma, records (and `forced_seeds`, for tests and stills) |
| `finish_battle(battle, people, is_saved = true) -> Dictionary` | method | `apply_report` on the battle's report, then save |
| `apply_report(report, unit_to_person) -> Dictionary` | method | The summary: `is_finished`, `winner`, `reason`, `round`, `rows` (`[{id, unit, status, has_defected, start_side, role, marks, is_named_now, before, after}]`), `named` (ids), `karma` (`bait`, `rescue`, `next_bait`, `next_rescue`) |
| `make_leader(person) -> TacticsLeaderData` | method | A person as a leader |
| `fill_text(text)` | method | Registers runtime leaders and named soldiers' names on a `TacticsText` |
| `TacticsBiography.person_name(person)`, `plain_name`, `display_name`, `biography(person)`, `mark_line(mark)` | method | Text |

## Log events

None. A save that cannot be read or written is reported once with
`push_warning` ("TacticsRoster: ...").

## How to extend

- Another name or biography line: add Locale rows (`NAME_PLACE_<TERRAIN>`
  for a new terrain, `BIO_MARK_<INCIDENT>_FORMAT` for a new incident, with
  when, place and leader in that order).
- A new save field: bump `VERSION`, write it in `to_save_data()` and read
  it in `_read()`. Older saves are then replaced by an empty roster.
- A second scenario: build a `TacticsCampaign` with it; spare spawn cells
  decide how many named and returning leaders fit.

## Tests

`Tests/tactics_roster_test.gd` covers:

- The save round trip; a newer version, a broken file and a missing file.
- The muster fill: recruits, the marked soldier first, the dead left out.
- A report writing deaths, desertions, defections and a defector recruit.
- Naming at three marks: "Bảy Cầu" with its biography, unchanged by a
  fourth mark; alike marks from three battles give three different lines
  that name the battle.
- A named leader's capacity, passive, skill and name.
- A traitor returning as the third enemy leader, with his record in the
  report.
- Karma carried at half.
- Twelve AI-vs-AI battles leaving marks that the saved roster keeps.

`Tests/muster_test.gd` retreats through the summary into the roster.
`Tests/tactics_screen_sync_test.gd` plays campaign battles with incidents.
All are in CI.

## Known limits

- One scenario. Named and returning leaders only fit on spare spawn cells,
  so on `river_crossing` at most two named leaders of ours and one
  returning enemy appear (the lowest ids first).
- A named leader's look is its face in menus; on the map it is a leader
  token with its troop glyph.
- Names can repeat (two "Bảy Cầu" from two troops); nothing makes them
  unique.
- Leaving the muster with "Về" drops that muster's new recruits (they are
  saved only after a battle).
