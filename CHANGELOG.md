# Changelog

Changes a player or tester would notice, newest first. Add an entry under
`Unreleased` in the same pull request as the change (see
`Docs/conventions.md`, section 8).
Group entries under `Added`, `Changed`, `Fixed` or `Removed`.

## Unreleased

### Added

- A first playable screen, the sandbox, laid out for a phone held upright
  (desktop windows work too): a roster of every unit, the 7 x 8 board with the
  enemy line-up shown dimmed on the top half, and the buttons "Ra trận",
  "Đổi địch" (three enemy line-ups) and "Xóa bàn". Place up to 8 units by
  tapping a card and then cells, or by dragging; tap or drag a placed unit to
  move or swap it, drag it off the board to remove it. A long press or right
  click shows a unit's stats.
- The battle plays on the board: units walk, charge, swing, shoot arrows and
  cast bolts, hit units flash with damage numbers (gold for counters), the
  fallen fall over, and the winners cheer before a "Thắng trận" or
  "Thua trận" banner with "Xếp lại", which returns to setup with your
  line-up. A timer, health bars per side and a x1/x2/x4 speed button.
- Units are drawn as paper-cut figures by class and race, with cost colours.
- Vietnamese player text through `Locale/strings.csv`.
- Headless battle core for testers: six classes, 25 demo units and the
  battle rules as data under `Data/`, and `Tests/battle_test.gd`, which
  prints the length of a sample 8v8 battle.
- Coding conventions for extensible, traceable code, the system doc template,
  this changelog, a pull request checklist and a CI check that code changes
  come with docs.

### Changed

- The game is now portrait (720 x 1280 base size); in a landscape window the
  game column stays centred.
