# Changelog

Changes a player or tester would notice, newest first. Add an entry under
`Unreleased` in the same pull request as the change (see
`Docs/conventions.md`, section 8).
Group entries under `Added`, `Changed`, `Fixed` or `Removed`.

## Unreleased

### Changed

- Cavalry charges with sense: a rider charges only an enemy in its lane
  (its own column, else the nearest in a neighbouring column, stopping
  diagonally in front of it); with nobody in its lane it walks instead of
  running blind to the far edge. After the impact it turns to a fragile
  back-liner next to it rather than chopping at a shield. Dust bursts where
  a charge hits. Đột Trận no longer pulls the rider back when it is
  already in front of an enemy.
- Stage 1 has two enemies instead of three, and stages 5-8 are gentler:
  one 2-star enemy each, the rest 1-star.
- Saves from before this version (format 3) are not continued.

### Added

- Road encounters ("Dọc đường"): after the reward of stages 2, 4, 6, 8
  and 10 the army meets someone on a painted road (merchants, deserters,
  a wager, villagers, a stranger and more; eight in all, never one twice
  in a run) and you pick one of two cards: gold, supply, morale, a free
  unit, free shop refreshes, or a bet paid if you win the next battle. A
  card you cannot pay for is greyed out and shakes when touched. Gold won
  flies as coins to the gold chip, which counts up when they land (it
  never shows the gold early and drops back). Closing the game during an
  encounter brings it back, with a black market taken just before it.
- Win streak: from the 2nd win in a row +1 gold, from the 4th +2, shown as
  its own chip under the result with a coin sound.
- Reward "Kho báu": +5 gold. A win offers three rewards drawn from
  rest, hunt, black market and loot.
- `Tools/run_bot.gd --weak`: a new-player stand-in for balance runs.

- `Tools/build_and_test.bat` builds, imports and tests the project on
  Windows in one go, checking each step (Godot path and version, Python,
  SCons, the godot-cpp submodule, the compiler) and saying how to fix the
  first one that fails.
- `Tools/build_and_test.sh` does the same in Git Bash, MSYS2 or Linux.
- README: step-by-step Windows setup with PowerShell commands (Git,
  Python, Visual Studio Build Tools, Godot 4.7.2, clone, build, test).
- Kỳ Ngộ: every class and race family fills a Ngộ meter after each
  battle (+1 while active, +1 more after a loss, +2 for the family that
  dealt the most damage). When one is full, a cutscene plays before the
  rewards: the unit talks with the hermit Ẩn Sĩ, then you pick one of two
  cards, Hạ Mốc (the milestone needs one unit fewer) or Biến Dị (the
  milestone changes its effect). At most one per stage and four per run,
  each family once; it lasts the whole run, for your side only, and is
  saved. A family close to its Kỳ Ngộ shakes in the info row, and a changed
  milestone wears a gold seal.
- Cutscenes: painted backdrop, two figures, typed lines with a tap to
  finish or go on, "Bỏ qua" to skip (never past a choice), an ink wipe in
  and out and a gold flash on the choice. Before stage 12 Liễu Mi and Ba
  Khắc talk in their camp.
- The boss Cự Nham on stage 12, with six guards: drawn larger, with its
  name and a wide health bar at the top. Hóa Đá: the third skill your side
  casts within 3 s turns it to stone for 2 s, immune and still. From stage
  6 a "Trùm" badge opens its card with the hint "đừng tung chiêu dồn dập".
  Beating it crumbles it under confetti.
- Sound: 24 effects (taps, buying, merging, hits, skills, formations,
  Kỳ Ngộ, the boss, win and loss) and music for the preparation and the
  battle, faster with the battle speed. A mute button on the title and run
  screens; the choice is kept. On the web, sound starts after the first
  tap.
- "Cách chơi" on the title screen: four tips on buying, the board, skills
  and the boss.

- Synergies: the shape of the line-up is a weapon. Nghề (class milestones:
  2-4 different units of a class, e.g. 2 shields +20 armor, 4 shields block
  each one's first hit, 4 archers or spears pierce the enemy behind), Tộc
  (race milestones: humans raise formation levels and add damage per
  formation, wolf folk complete formations one unit short and gain Khí on
  kills; cost 4-5 count double), and twelve Trận đồ (formations) such as
  Tường Khiên, Mưa Tên (a volley every 4 s), Hộ Pháp, Mũi Giáo, Song Kiếm,
  Thương Che Cung, Phương Trận and Ngư Lân. Every milestone and formation
  is a Hợp Lực point; 3, 6, 9, 12 and 15 points give the team Khí, damage,
  max hp and attack speed. Enemies have them too.
- The info row under the board shows the Hợp Lực ring, the active
  formations and a "+N" that opens the full list (milestones like "Khiên
  2/4", formations with level and effect, formations one unit short,
  Hợp Lực tiers). Formations are outlined on the board in their colours, a
  new one runs a light around its outline and shows its name, a formation
  one unit short shows a dashed outline and a ghost marker, and the
  enemy's are outlined in red.
- Dragging a unit shows what the drop would make: outlines, chips and
  "9 → 10" on the ring. Shop cards that would reach a milestone or complete
  a formation carry a jade badge. The unit info panel lists the unit's
  milestones.
- "Ra trận" opens with a roll call (outlines flash, names stamp in); in
  battle "Chặn", "Phản", "Mất đà", "Gấp đôi" and split-hit lines show the
  procs, volleys rain arrows, and a formation that loses a member shatters.

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

- Every button keeps at least 24 px from the top and bottom of the
  screen.
- The preparation time setting reads "Xếp quân: 60 s".
- Stages 4-12 field formations and milestones you can read in the
  preparation; stages 9-12 were retuned for synergies.
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

- The web build had no sound at all: the Music and Sfx buses were added
  at run time, which is silent in the browser. They now come from
  `default_bus_layout.tres`.
- Sound on iPhone: the web build is no longer silenced by the ring/silent
  switch, and the audio is resumed on every tap.
- A hit a shield's "Chặn" blocks is no longer damage taken: the shield
  gains no Khí and no on-hit passive fires (the attacker still gains its
  Khí).
- The drag preview shows what the drop really does: a shop card that
  completes a merge previews the board after the merge (also over a taken
  cell), and a third legend previews as refused.
- With two copies of one formation, the one that loses a member is the one
  whose outline shatters.
- Formation data can no longer give max hp, front-rank range or an attack
  shape (they could not be taken back when the formation breaks), reach the
  whole side, or put two slots on one cell.

- "Ra trận" did nothing from the second stage on, on phone-sized screens:
  the hidden battle panel took the press.
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
