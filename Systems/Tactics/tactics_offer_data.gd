class_name TacticsOfferData
extends Resource
## One line of a city market (TacticsRegionData.offers): what it sells, its
## price in supplies and how many it sells between two battles. `kind` picks
## the handler (TacticsMarket): `offer.hire` a soldier of `troop`,
## `offer.heal` one wounded soldier back to the muster, `offer.item` one
## `item`. See Docs/systems/tactics_world.md.

@export var kind: StringName = &"offer.hire"
## For `offer.hire`.
@export var troop: TacticsTroopData
## For `offer.item`.
@export var item: TacticsItemData
@export_range(1, 99) var price: int = 3
## Sold at most this many times between two battles.
@export_range(1, 9) var stock: int = 1
