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
    the auto battle.
  - `tactics_bonds.gd` (`TacticsBonds`): bond points and levels in the
    roster, set on a battle and updated from its report.
  - `TacticsCampaign` takes a plan from the world (region, enemy power,
    items), applies Auto results (`apply_auto()`) and moves the world on
    (`finish_region()`); see [Tactics roster](tactics_roster.md).
- `Scenes/Tactics/`:
  - `tactics_world_screen.gd` (`TacticsWorldScreen`): the world map screen.
  - `tactics_world_map.gd` (`TacticsWorldMap`): the region graph, drawn
    in one `TacticsMeshCanvas`.
  - `tactics_region_card.gd` (`TacticsRegionCard`): the card a region tap
    opens.
  - `tactics_auto_result_view.gd` (`TacticsAutoResultView`): after Auto.
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
| `pressure_step_pct` | 15 | Enemy hp and attack % per pressure level |
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
  pressure, so +15 % enemy hp and attack there, up to 3) or one of ours
  with a market that touches an open region (if we fight elsewhere it is
  taken back, its market closes, and it starts at pressure 1). The world
  screen shows the push and its cost all the time; the region's card says
  it too. A region of ours under threat can be fought to defend it; losing
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
  region's pressure on the enemy (`TacticsCampaign._pressed`), the chosen
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
- **Markets** sell only in regions we hold. A hire is a new roster soldier
  of that troop (`is_hired`) who joins whichever leader has room at the
  next muster; healing ends a soldier's rest; an item goes into the roster
  (`items`) and is chosen on a region's card before the battle, then used
  up when that region is fought. A purchase is saved at once.
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

Thủ công, `Tools/tactics_brain_probe.gd` (scripted policy / idle player, 60
seeds, no pressure, no bonds): river_crossing 34/60 (57 %) / 0/60,
night_raid 35/60 (58 %) / 0, city_defense 34/60 (57 %) / 0, supply_road
39/60 (65 %) / 0, broken_ring 30/60 (50 %) / 0.

Auto, `Tools/tactics_world_probe.gd -- --battles=100` (fresh rosters):

| Region | Pressure 0 | 1 | 2 | 3 |
| --- | --- | --- | --- | --- |
| Bến Đò | 50 % | 30 % | 9 % | 1 % |
| Rừng Sương | 55 % | 27 % | 8 % | 0 % |
| Thành Cổ | 50 % | 24 % | 7 % | 1 % |
| Trạm Ngựa | 50 % | 26 % | 8 % | 2 % |
| Ải Vây | 52 % | 28 % | 9 % | 1 % |

Auto is a little below the scripted Thủ công player at pressure 0, wounds
about 7 of ours a battle (won or lost) and pays 1 supply (2 at Ải Vây) on
a win, against 2 per side goal by hand. Without the fortune of war the
auto battle (no randomness) went from a coin flip to 0 % at pressure 1.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `TacticsWorld.get_state(id) -> StringName` | method | `home`, `ours`, `open` or `locked` |
| `TacticsWorld.can_fight(id)`, `can_shop(id)` | method | Whether the card offers a battle, a market |
| `TacticsWorld.get_threat()`, `get_threat_kind()` | method | The declared push and `threat.harden` / `threat.take` |
| `TacticsWorld.get_pressure(id)`, `get_enemy_power_pct(id)` | method | Pressure level, enemy % (100 + 15 per level) |
| `TacticsWorld.finish_region(id, is_won) -> Dictionary` | method | One turn: {region, won, taken, lost, hardened, pressure, is_complete, threat} |
| `TacticsWorld.start_new_cycle()` | method | The next campaign |
| `TacticsMarket.new(roster, region)` | constructor | |
| `TacticsMarket.get_offers()`, `refusal(index, person_id)`, `buy(index, person_id)` | method | Rows {index, kind, price, left, reason}; reasons `supplies`, `sold_out`, `no_wounded`, `closed`; buy returns {ok, reason, person, item} |
| `TacticsAutoResolve.resolve(campaign) -> Dictionary` | static | {is_won, winner, ticks, hash, units, counts, fortune}; deterministic |
| `TacticsAutoResolve.fortune_pct(seed, limit) -> int` | static | The fortune roll |
| `TacticsCampaign.apply_auto(result, is_saved)` | method | Wounds, pay, world turn; saves |
| `TacticsBonds.set_up_battle(battle, roster, data)` | static | Gives a loaded battle the roster's bonds (called by `prepare_battle`) |
| `TacticsBonds.apply_tallies(roster, data, report)` | static | Report tallies into points; rows {a, b, points, gained, level_before, level} |
| `TacticsBonds.level_of`, `level_between`, `bonds_of` | static | Levels |
| `TacticsWorldScreen` | Control | `roster`, `changed_region` (rings once), `is_instant`; `open_region(id)`, `resolve_auto(id, items)`, `open_market(id)`, `open_roster()`, `start_new_campaign()`; signals `manual_requested(region_id, items)`, `back_requested` |
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
- **Auto result**: won or lost, two bars that drain to what stood, the
  fortune roll, the wounded with faces, supplies, "Auto leaves no marks or
  bonds", and what the world turn changed.
- **Market**: each offer with price and stock left, a "Mua" button; healing
  lists the wounded. A purchase rings and flashes its row; a refused one
  buzzes and says why.

Every change animates (slides, bar drains, pulses, staggered rows, the
bond cord) and has a sound. Idle screens draw nothing; the map redraws
only when the world changes or a pulse plays.

Cost at 360x640 (llvmpipe under xvfb, 2 s idle): world map 34 draw calls,
region card 50, Auto result 145, market 177 (a row per wounded soldier),
0 frames changed while idle on each.

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
wounds, hires), a version 1 save and a broken world; Auto deterministic,
its fortune in bounds, no deaths, wounds for one battle, pay on a win only,
no bonds; markets (prices, stock, every refusal, healing, a hire in the
next muster, items used up); bonds refused when bad, the attack bonus only
while close and in the forecast, phase tallies and the same hash on the
same seed, points capped per battle, levels, and a campaign battle set up
with the roster's bonds. `Tests/muster_test.gd` walks title, world map,
region card, Thủ công, muster, battle, summary and back.

## Known limits

- The auto battle has no terrain, objective or waves: `auto_enemy_pct`
  stands in for them, tuned on fresh rosters. A veteran roster (marks,
  named leaders) is stronger in both modes.
- Auto wounds about 7 of ours a battle, but the next muster fills their
  slots with new recruits, so a wound costs the veterans' marks for one
  battle rather than numbers.
- The brain probe plays without bonds or pressure; bonds make Thủ công a
  little stronger than the table above.
- The push is never more than one region a turn, and the home cannot be
  attacked.
