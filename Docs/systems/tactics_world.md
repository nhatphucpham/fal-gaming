# Tactics world

## Purpose

Chiến Dịch's world map ("Thế trận"): regions joined by roads, each holding
one of the five battles; the player picks which to fight next, by hand
("Thủ công") or with the auto battle ("Auto"). Cities we hold have markets.
Leaders who fight side by side build bonds (Duyên). The enemy declares
where it pushes next and what ignoring it costs. The world does not run a
battle itself: Thủ công is the muster and the tactics battle
([Tactics screen](tactics_screen.md)), Auto is the auto chess `Battle`
([Battle](battle.md)) used through its public API only.

## Layer and files

- Layer: rules in GDScript (`Systems/Tactics/`), screens (`Scenes/Tactics/`),
  the bond bonus in the C++ tactics simulation (`Native/src/tactics/`).
- `Systems/Tactics/`:
  - `tactics_world_data.gd` (`TacticsWorldData`): the world's numbers and
    regions; `tactics_region_data.gd`, `tactics_offer_data.gd`,
    `tactics_item_data.gd`: a region, a market offer, a one-use item.
  - `tactics_world.gd` (`TacticsWorld`): the world's state, saved inside the
    roster (who holds what, pressure, the declared push, turn, cycle,
    market sales).
  - `tactics_market.gd` (`TacticsMarket`): buying at one region's market.
  - `tactics_auto_resolve.gd` (`TacticsAutoResolve`): a region played with
    the auto battle, at once (`resolve()`) or a slice at a time
    (`start()`, `advance()`).
  - `tactics_bonds.gd` (`TacticsBonds`): bond points and levels in the
    roster, set on a battle and updated from its report.
  - `TacticsCampaign` takes a plan from the world (region, enemy power,
    items), applies Auto results (`apply_auto()`) and moves the world on
    (`finish_region()`); see [Tactics roster](tactics_roster.md).
- `Scenes/Tactics/`:
  - `tactics_world_screen.gd` (`TacticsWorldScreen`): the world map screen.
  - `tactics_world_map.gd` (`TacticsWorldMap`): the region graph, drawn
    in one `MeshCanvas`.
  - `tactics_region_card.gd` (`TacticsRegionCard`): the card a region tap
    opens.
  - `tactics_auto_result_view.gd` (`TacticsAutoResultView`): Auto's fight
    (played a slice a frame) and its outcome.
  - `tactics_market_view.gd` (`TacticsMarketView`): a market.
  - `tactics_world_text.gd` (`TacticsWorldText`): shared player-facing
    lines (the declared push, pressure, what a region changed).
- `Native/src/tactics/tactics_bonds.h/.cpp` and `tactics_battle_bonds.cpp`:
  the bond rules, bonus and phase tallies (see [Tactics](tactics.md)).
- Depends on: the roster and campaign, the tactics battle, the auto battle
  (`Battle`, `BattleRulesData`, `ClassData`, `UnitData`), `Sound`.

## Data

`Data/Tactics/World/world.tres` (`TacticsWorldData`):

| Field | Value | Meaning |
| --- | --- | --- |
| `regions` | 6 | Home first, then the five battles |
| `items` | 2 | One-use items markets sell |
| `home_region` | `region.home` | Where we start (no battle) |
| `pressure_step_pct` | 10 | Enemy hp and attack % per pressure level |
| `max_pressure` | 3 | Pressure cap |
| `cycle_pressure` | 1 | Levels every region starts at per finished campaign |
| `wound_rest_battles` | 1 | Battles an Auto-wounded soldier sits out |
| `auto_fortune_pct` | 25 | Auto's fortune of war: the enemy's hp and attack move by -25..+25 % from the battle seed |
| `bond_radius_cells` | 2 | Manhattan cells two bonded leaders must be within |
| `bond_attack_pct_per_level` | 5 | Attack % a bond gives each of the two per level |
| `bond_level_points` | 3, 7, 12 | Points for levels 1, 2, 3 |
| `bond_points_per_battle` | 3 | Most points one battle gives a pair |

`Data/Tactics/World/Regions/*.tres` (`TacticsRegionData`): `id`
(`region.<name>`), `name_key`, `scenario` (null for the home),
`map_position` (0..1 of the map area), `neighbours` (roads, either way),
`market_name_key` and `offers` (empty: no market), `auto_enemy_pct` (the
enemy's hp and attack in Auto, standing in for the objective, terrain and
waves the auto battle does not have) and `auto_supplies` (paid on an Auto
win).

| Region | Battle | Roads to | Market | Auto enemy % | Auto pay |
| --- | --- | --- | --- | --- | --- |
| Đại doanh | (home) | Bến Đò, Rừng Sương | none | | |
| Bến Đò | river_crossing | Thành Cổ, Trạm Ngựa | chợ Bến: militia 2 (x2), spearman 3, heal 2 (x2) | 93 | 1 |
| Rừng Sương | night_raid | Trạm Ngựa | none | 139 | 1 |
| Thành Cổ | city_defense | Ải Vây | chợ Thành: shieldman 3, archer 3 (x2), heal 3 (x3), war drum 3, herb kit 2 | 121 | 1 |
| Trạm Ngựa | supply_road | Ải Vây | chợ Trạm: rider 4, heal 2, herb kit 2 (x2) | 104 | 1 |
| Ải Vây | broken_ring | | none | 91 | 2 |

`Data/Tactics/World/Items/*.tres` (`TacticsItemData`): `id` (`item.<name>`),
`name_key`, `desc_key`, `stat` (`stat.attack_pct` or `stat.hp_pct`),
`amount` (%, of our leaders' own percent): war drum +15 % attack, herb kit
+20 % hp, for one battle.

Offers (`TacticsOfferData`): `kind` (`offer.hire` with `troop`, `offer.heal`,
`offer.item` with `item`), `price` (supplies, 1..20) and `stock` (sold at
most this many times per world turn).

## Rules

- **Regions.** The home is ours. A region is ours once won, open (the
  enemy's, reachable) when a road joins it to the home or a region of ours,
  locked otherwise. Open regions can be fought; locked ones cannot.
- **The declared push (địch báo trước ý đồ).** Each world turn the enemy
  names one region: an open one (if we fight elsewhere it hardens: +1
  pressure, so +10 % enemy hp and attack there, up to 3) or one of ours
  with a market that touches an open region (if we fight elsewhere it is
  taken back, its market closes, and it starts at pressure 1). The world
  screen shows the push and its cost all the time; the region's card says
  it too. The war horn sounds once per declared push, when the map first
  shows it (`TacticsWorld.is_threat_heard`, saved), not each time the map
  opens. A region of ours under threat can be fought to defend it; losing
  the defence gives it up too. The push is picked from the roster seed,
  the cycle and the turn, so it is the same on every machine.
- **A turn.** Every region fought (Auto or Thủ công, won, lost or left) is
  one world turn: a win takes the region (and clears its pressure), the
  declared push lands unless it was this region, markets restock, the
  next push is declared.
- **Campaigns.** When every region is ours, "Chiến dịch mới" starts the next
  campaign: every region the enemy's again with `cycle_pressure` more
  levels. The roster, its bonds and items stay.
- **Thủ công** is the muster and the tactics battle as before, with the
  region's pressure on the enemy (`TacticsCampaign._pressed`: its leaders
  and squads, and the waves that come later in the hold-the-city battle),
  the chosen
  items on our leaders and the hired soldiers in squads with room. Deaths
  are permanent; marks, side goals, sites and bonds count.
- **Auto** plays our mustered leaders and soldiers (the same roster people,
  resting ones left out) against the region's enemy in the auto battle.
  Each tactics unit becomes an auto unit with its own `UnitData` and a
  scaled copy of its `ClassData` (hp and attack by the unit's percents;
  counters point at the copies). A side with more units than the board
  holds (10) puts leaders first, then soldiers by turn of leader, and the
  placed units carry the hp of those left off. Melee soldiers stand in
  front, melee leaders behind, then ranged soldiers and leaders; columns
  are shuffled by the battle seed. The enemy is scaled by
  `auto_enemy_pct` and the fortune of war roll (shown on the result).
  No one dies: each of ours who fell is wounded and sits out the next
  `wound_rest_battles` battles. A win pays `auto_supplies`; there are no
  side goals, no marks and no bonds. The world moves on as for Thủ công.
  The world screen plays the battle in the result view a slice a frame
  (`FIGHT_TICKS_PER_SEC` 650, at most `FRAME_BUDGET_USEC` 4 ms of a
  frame), so the fight shows for about a second with the bars live and
  no frame freezes; nothing is applied or saved until it ends (an app
  closed mid-fight changes nothing, and the same seed gives the same
  result again). Sliced or not, the result and hash are the same.
- **Markets** sell only in regions we hold. A hire is a new roster soldier
  of that troop (`is_hired`) who joins whichever leader has room at the
  next muster; a hire is refused (`no_room`) once the hires already in the
  roster fill the most room any region we can fight next has
  (`TacticsCampaign.hire_room()`: our leaders' squad capacity past the
  scenario's soldiers, plus the squads of named soldiers who would lead),
  so no supply buys a soldier who could not fight; healing ends a soldier's rest; an item goes into the roster
  (`items`) and is chosen on a region's card before the battle, then used
  up when that region is fought. A purchase is saved at once. Healing
  treats the wounded soldier with the most marks first (then the lowest
  id): the market shows it as one row with that soldier's face.
- **Bonds (Duyên).** At the end of each of our phases in a Thủ công battle,
  every pair of our leaders within `bond_radius_cells` counts the phase
  (C++, `bond_tallies` in the battle report). Up to
  `bond_points_per_battle` of them become points in the roster
  (`TacticsRoster.bonds`, by leader id); points give the level. In battle,
  each leader of a level n bond gets n x 5 % attack while its partner is
  within the radius (C++: `get_stats_at`, so forecasts list the source
  "bond"). The muster shows each leader's bonds, the map draws a gold cord
  and rings between bonded leaders standing close (and "Duyên +x%" floats
  up when it starts), and the summary shows a level-up as a card with the
  two, the cord and one line one says to the other.

## Balance

Thủ công, `Tools/tactics_brain_probe.gd -- --battles=200 --scenario=<name>
--pressure=N [--bond-level=2 --items]`: the scripted policy's wins out of
200, plain and with every pair of leaders bonded at level 2 and both items
(a prepared player); the idle player (no commands) wins none, at pressure
0 and at pressure 3 with level 3 bonds and items.

| Battle | Pressure 0 | 1 | 2 | 3 | Bonds 2 + items: 0 | 1 | 2 | 3 | Idle |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| river_crossing | 59 % | 28 % | 17 % | 8 % | 81 % | 66 % | 33 % | 22 % | 0 % |
| night_raid | 59 % | 31 % | 17 % | 2 % | 86 % | 76 % | 45 % | 17 % | 0 % |
| city_defense | 64 % | 22 % | 5 % | 2 % | 96 % | 69 % | 45 % | 12 % | 0 % |
| supply_road | 60 % | 50 % | 28 % | 17 % | 67 % | 55 % | 34 % | 37 % | 0 % |
| broken_ring | 54 % | 43 % | 24 % | 31 % | 89 % | 91 % | 36 % | 43 % | 0 % |

The scripted policy is a weak player (it walks to the objective and hits
the weakest in reach). At the first `pressure_step_pct` of 15 the plain
policy won 0..7 % at pressure 3 and the prepared one 3..14 % on the night
raid, city and river: hopeless by hand on those maps. At 10 pressure 3 is
hard (2..31 % plain, 12..43 % prepared) but not hopeless. Bonds at level 2
alone add 0..12 points. The waves of the city defence were not pressed
before this table (they are now); its old pressure numbers were too kind.

Auto, `Tools/tactics_world_probe.gd -- --battles=100 [--veteran=3]
[--rematch]` (wins; wounded per battle about 7 fresh, 4..7 veteran):

| Region | Fresh 0 | 1 | 2 | 3 | 3 veterans + items: 0 | 1 | 2 | 3 | Veterans, rematch: 0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Bến Đò | 50 % | 37 % | 24 % | 9 % | 100 % | 95 % | 80 % | 67 % | 90 % |
| Rừng Sương | 55 % | 32 % | 19 % | 8 % | 100 % | 99 % | 91 % | 78 % | 93 % |
| Thành Cổ | 50 % | 36 % | 17 % | 7 % | 76 % | 57 % | 37 % | 27 % | 49 % |
| Trạm Ngựa | 50 % | 33 % | 20 % | 8 % | 79 % | 53 % | 39 % | 25 % | 51 % |
| Ải Vây | 52 % | 38 % | 22 % | 9 % | 77 % | 56 % | 43 % | 27 % | 55 % |

"Rematch" fights the region twice in a row and counts the second battle,
fought without whoever the first one wounded. With a fresh roster a wound
costs nothing (a new recruit fills the slot, as after a death by hand);
with veterans it costs their marks and named leaders for a battle, and
the second Auto falls back to a fresh roster's odds where they were
wounded. That is the trade: Auto never kills a veteran but benches the
ones who fell, earns no marks or bonds and pays 1 supply (2 at Ải Vây) on
a win, 0.5 a battle on average at pressure 0, against side goals worth 2
each by hand. Healing at a market (the most-marked first) buys a veteran
back early.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `TacticsWorld.get_state(id) -> StringName` | method | `home`, `ours`, `open` or `locked` |
| `TacticsWorld.can_fight(id)`, `can_shop(id)` | method | Whether the card offers a battle, a market |
| `TacticsWorld.get_threat()`, `get_threat_kind()` | method | The declared push and `threat.harden` / `threat.take` |
| `TacticsWorld.get_pressure(id)`, `get_enemy_power_pct(id)` | method | Pressure level, enemy % (100 + 10 per level) |
| `TacticsWorld.is_threat_heard` | var | Whether the horn sounded for the declared push; a new push clears it (saved) |
| `TacticsWorld.finish_region(id, is_won) -> Dictionary` | method | One turn: {region, won, taken, lost, hardened, pressure, is_complete, threat} |
| `TacticsWorld.start_new_cycle()` | method | The next campaign |
| `TacticsMarket.new(roster, region)` | constructor | |
| `TacticsMarket.get_offers()`, `refusal(index, person_id)`, `buy(index, person_id)` | method | Rows {index, kind, price, left, reason}; reasons `supplies`, `sold_out`, `no_wounded`, `no_room`, `closed`; buy returns {ok, reason, person, item} |
| `TacticsAutoResolve.resolve(campaign) -> Dictionary` | static | {is_won, winner, ticks, hash, units, counts, fortune}; deterministic |
| `TacticsAutoResolve.start(campaign)`, `advance(max_ticks) -> bool`, `get_result()` | method | The same battle a slice at a time (true when over); `get_alive_counts()`, `get_placed_counts()`, `get_fortune()` while it runs |
| `TacticsMarket.get_next_patient()` | method | The wounded soldier healing treats next, or {} |
| `TacticsCampaign.hire_room(roster, catalog, scenario) -> int` | static | Hires a muster of that scenario can place; changes nothing |
| `TacticsAutoResolve.fortune_pct(seed, limit) -> int` | static | The fortune roll |
| `TacticsCampaign.apply_auto(result, is_saved)` | method | Wounds, pay, world turn; saves |
| `TacticsBonds.set_up_battle(battle, roster, data)` | static | Gives a loaded battle the roster's bonds (called by `prepare_battle`) |
| `TacticsBonds.apply_tallies(roster, data, report)` | static | Report tallies into points; rows {a, b, points, gained, level_before, level} |
| `TacticsBonds.level_of`, `level_between`, `bonds_of` | static | Levels |
| `TacticsWorldScreen` | Control | `roster`, `changed_region` (rings once), `is_instant`; `open_region(id)`, `resolve_auto(id, items)` (the view fights, then applies), `open_market(id)`, `open_roster()`, `start_new_campaign()`, `announce_threat() -> bool` (the horn, once per push); signals `manual_requested(region_id, items)`, `back_requested` |
| `TacticsAutoResultView` | Control | `campaign`, `auto` (fights first) or `summary`; `is_fighting()`, `show_summary(summary)`; signals `fought(result)`, `continue_requested` |
| `TacticsRegionCard` | Control | Signals `manual_requested`, `auto_requested`, `market_requested`, `closed`; one request per card |

`Main.open_campaign(changed_region)` opens the world map from the title;
`Main.open_muster(region_id, items)` is Thủ công; the muster's "Về" and
the summary's "Tiếp tục" go back to the world map.

## Screens

- **World map**: title, supplies and regions held; the map (state by
  colour and symbol: gold home flag, green tick ours, red cross the
  enemy's, grey lock out of reach; a red flag and ring on the declared
  push; diamonds for pressure; a stall badge on markets); a legend; the
  push and its cost in a red panel; "Về", "Sổ quân" and, at the end,
  "Chiến dịch mới". A war horn sounds when a push is declared; the region
  just fought rings once.
- **Region card**: slides up over a shade; who holds it, its battle and
  pressure, whether the push is here; item toggles; Thủ công and Auto side
  by side, each with what it costs and pays under it; the market button.
- **Auto result**: "Giao chiến…" with a drum while the battle plays, two
  bars of who still stands that drain live (a hit sounds as units fall),
  the fortune roll; then won or lost (the title pops, the win or loss
  sound), the wounded as a row of faces under their count (named ones by
  name), supplies, "Auto leaves no marks or bonds", and what the world
  turn changed, fading in one after another, with "Sổ quân" and "Tiếp
  tục".
- **Market**: each offer with price and stock left, a "Mua" button;
  healing is one row with how many are wounded and the face and name of
  the one treated next. A purchase rings and flashes its row; a refused
  one buzzes and says why.
- A full-screen overlay (Auto, market, Sổ quân) hides the map's page
  under it once it has slid in, and shows it again when it closes.

Every change animates (slides, bar drains, pulses, staggered rows, the
bond cord) and has a sound. Idle screens draw nothing; the map redraws
only when the world changes or a pulse plays.

Cost at 360x640 (llvmpipe under xvfb, 2 s idle): world map 34 draw calls,
region card 50, Auto result 100 (7 wounded), market 57 (7 wounded), 0
frames changed while idle on each. On the web build (iPhone 13 profile,
software GL), the engine work of a tap is about 35 ms for the card and
40 ms for the market; Auto's battle runs in slices of at most 4 ms a
frame where it took one 116 ms frame.

## How to extend

- A region: a `TacticsRegionData` file under `Data/Tactics/World/Regions/`
  added to `world.tres`'s `regions`, roads in `neighbours`, a scenario,
  `auto_enemy_pct` tuned with `Tools/tactics_world_probe.gd`.
- An offer kind: add it to `TacticsMarket.KINDS` and a handler in its
  `_handlers`; `TacticsWorldData.validate()` checks offers.
- An item stat: `TacticsItemData.stat` and `TacticsCampaign._boosted`.
- `TacticsWorldData.validate()` runs when the world screen opens.

## Tests

`Tests/tactics_world_test.gd`: the world data; region states; the push
from the seed; a win opening roads; hardening and its cap; a region taken
back and defended; the next campaign; the save (world, bonds, items,
wounds, hires), a version 1 save and a broken world, a save naming
unknown regions; the horn's heard flag (new pushes, the save); pressure on
the waves; Auto deterministic, played in slices with the same result
(and one dropped mid-fight leaves nothing behind),
its fortune in bounds, no deaths, wounds for one battle, pay on a win only,
no bonds; markets (prices, stock, every refusal, no room for a hire, healing, a hire in the
next muster, items used up); bonds refused when bad, the attack bonus only
while close and in the forecast, phase tallies and the same hash on the
same seed, points capped per battle, levels, and a campaign battle set up
with the roster's bonds. `Tests/muster_test.gd` walks title, world map,
region card, Thủ công, muster, battle, summary and back.
`Tests/tactics_world_screen_test.gd`: Auto played in the view over many
frames with live bars, the same result as `resolve()`, applied and saved
once; the horn once per push and not on reopening; the market's single
heal row treating the most-marked first; the map hidden under overlays;
the Auto result and the market idle draw nothing.

## Known limits

- The auto battle has no terrain, objective or waves: `auto_enemy_pct`
  stands in for them, tuned on fresh rosters. A veteran roster (marks,
  named leaders) is stronger in both modes.
- Auto wounds about 7 of ours a battle, but the next muster fills their
  slots with new recruits (as it does after deaths by hand), so a wound
  costs the veterans' marks and named leaders for one battle, not
  numbers; a fresh roster loses nothing to it.
- The balance tables come from a scripted player, not a person; how hard
  pressure 3 is by hand is an estimate from them.
- The push is never more than one region a turn, and the home cannot be
  attacked.
