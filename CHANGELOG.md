# Changelog

Changes a player or tester would notice, newest first. Add an entry under
`Unreleased` in the same pull request as the change (see
`Docs/conventions.md`, section 8).
Group entries under `Added`, `Changed`, `Fixed` or `Removed`.

## Unreleased

### Added

- Skills. Every unit fills a thin blue Khí bar under its health bar by
  attacking (+10) and being hit (+5); when it is full and glowing, the unit
  winds up, lights the cells it aims at in its class colour, shows the
  skill's name and casts for half a second. Shield "Trấn Thủ" taunts nearby
  enemies and takes 40% less damage, sword "Hoành Tảo" sweeps the three
  cells in front, spear "Xuyên Tâm" thrusts down the column and breaks
  armor, cavalry "Đột Trận" charges again into the most crowded column,
  archer "Tiễn Vũ" rains arrows on it and mage "Pháp Trận" blasts a cross.
  Skills grow with stars (150% at 2, 250% at 3), and at 3 stars each adds a
  Hậu chiêu: a push when the taunt ends, a second sweep, the whole column,
  a second charge, 8 arrows, a 3x3 square. Each skill has its own effect
  and the board shakes a little when it lands.
- Passives: Bàn Thạch (shield, Khí when blocking an arrow), Phản Kiếm
  (sword, strikes back every third melee hit), Nghênh Chiến (spear, hits a
  charging enemy first), Đà Ngựa (cavalry, harder charges from further),
  Ngắm Kỹ (archer, every fourth shot is a critical hit). A small icon
  blinks when one fires; critical hits show gold numbers with "!".
- Small icons beside the health bar show taunt, guard, armor break and
  stun.
- The unit info panel shows the skill and passive with a one-line
  description, and the Khí during a battle.

- A run of 12 stages, from a new title screen with "Ván mới", "Chơi tiếp"
  (when a run is saved), "Bàn thử" and the preparation time (60 s, 90 s or
  unlimited). Each stage starts with a preparation: buy units from a shop of
  five cards (higher costs glow), keep them on a bench of six, place them on
  your half of the board by tap or drag, swap, sell by dropping on the shop,
  refresh the shop, buy supply and spend it to level up for more units on
  the board. Three copies of a unit merge into 2 and then 3 stars (legends:
  two copies, at most 2 stars and two on the board), with a flight and a
  burst of confetti. The enemy line-up of the stage waits dimmed on the top
  half. "Ra trận", or the end of the timer, starts the battle on the same
  board; the banner shows the gold, supply or morale won or lost, then pick
  one of three rewards (two after a loss): rest, hunt or the black market.
  Morale at 0 ends the run; winning stage 12, "Đại Trận Lạc Hồng", wins it.
  The run is saved after every change in the preparation, at the end of
  each battle and after every reward. The end screen shows the result,
  the stages cleared and your army.
- The preparation timer pauses when the game window or browser tab is not
  in front.
- `Tools/run_bot.gd`, a balance bot that plays whole runs and prints the
  win rate of each stage.
- A first playable screen, the sandbox, laid out for a phone held upright
  (desktop windows work too): a roster of every unit, the 7 x 8 board with the
  enemy line-up shown dimmed on the top half, and the buttons "Ra trận",
  "Đổi địch" (three enemy line-ups) and "Xóa bàn". Place up to 8 units by
  tapping a card and then cells, or by dragging; tap or drag a placed unit to
  move or swap it, drag it off the board to remove it. A long press or right
  click shows a unit's stats. A second finger, or the app losing focus or
  pausing, cancels a drag and puts the unit back. Every button is at least
  88 px tall in the base size.
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

- Stages 7 to 12 each have one 2-star enemy fewer (now 1-star), to keep
  the run winnable with skills.
- The game is now portrait (720 x 1280 base size); in a landscape window the
  game column stays centred.
- The game opens on the title screen; the sandbox is reached from "Bàn thử"
  and has a "Về" button back.
- In the run, hp bars show only during a battle, not while units wait.
- During a battle the countdown badge shows the battle's time limit with a
  steel ring, a crossed-swords mark and no red pulse, so it no longer looks
  like the preparation timer.

### Fixed

- In the run, a drag that starts between two bench slots no longer picks up
  (and can no longer sell) a unit on the board.
- The sell zone and the reward cards ignore a cancelled touch, and the sell
  zone sells only when the press ends on it.
- The run save is deleted as soon as the run is won or lost, so closing the
  game at the result banner no longer lets "Chơi tiếp" replay that battle.
- A damaged or edited run save (wrong types, impossible values, two units
  on one place, too many units on the board) is ignored with one warning
  instead of loading a broken run or raising script errors.
- The run flow test no longer overwrites a run saved on the same machine.
- Closing the game after a battle that does not end the run no longer
  replays it: "Chơi tiếp" opens that battle's reward cards with its morale,
  gold and supply already counted. Refreshes, purchases, sales, moves and
  level-ups are saved at once, so reloading cannot undo a refresh. A game
  closed during a battle still resumes in that stage's preparation. Saves
  from earlier builds are no longer used.
- A press held 0.4 s or longer on a reward card or the sell zone now chooses
  or sells, and so does a finger that slides within the sell zone before
  lifting.
- A save that cannot be used is deleted when "Chơi tiếp" fails, so the title
  no longer keeps offering "Chơi tiếp" for it.
