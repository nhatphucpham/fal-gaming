# Coding conventions

These rules apply to every change, by people and by AI agents. They serve
seven goals: code that is **easy to extend**, **easy to change**, **clear**,
**easy to understand**, **easy to track and trace**, with **short, clear
comments**, and with **documentation updated for every change in behavior**.

When a rule gets in the way of one of those goals, say so in the pull request
and change the rule in the same pull request. Do not quietly break it.

## 1. Layers

Code is split into three layers. Dependencies point downward only.

| Layer | Language and place | Owns | Must not |
| --- | --- | --- | --- |
| Presentation | Scenes, GDScript (`Scenes/`, `UI/`) | Drawing, animation, input, sound, UI | Change simulation state directly |
| Bridge | C++ `Node`/`Resource` wrappers, GDScript services (`Systems/`) | Exposing a system to Godot: properties, signals, commands | Hold game rules |
| Simulation | C++ (`Native/src/`) | Game rules: turns, combat, AI, economy | Read the clock, input, files or the network on its own; call into presentation |

- Presentation sends **commands** down (`place_unit`, `start_round`) and reads
  state or listens to **signals** coming up. It never edits simulation data
  in place.
- Simulation code that does not need Godot types stays plain C++, so it can
  be tested and replayed without the engine.
- One system per folder: `Native/src/<system>/` for C++,
  `Systems/<System>/` for GDScript. Shared engine glue (`register_types`,
  `SimClock`) stays directly in `Native/src/`. `SConstruct` must compile
  `.cpp` files in those subfolders too; the first pull request that adds one
  updates it. A system only talks to another through that system's public API
  or signals, never through its private members or child nodes.
- Autoloads are for true global services only (voice, logging, save). Each new
  autoload is listed in `Docs/architecture.md` with its reason.

## 2. Easy to extend: data first

- Game content (units, classes, skills, items, formations, enemies, dialogue)
  is **data**, not code. It lives in `Data/<Kinds>/` (PascalCase plural, such
  as `Data/Units/`) as typed `Resource` files (`.tres`) whose script defines
  the schema. Adding a unit or a skill should mean adding a data file, not
  editing a system.
- Behavior that varies by content goes through a **registry**: the system maps
  an id to a handler or a data entry. Do not grow `match`/`switch` statements
  over content types.
- Every piece of content has a stable string id of the form
  `<kind>.<snake_case_name>` (`unit.spear_guard`, `skill.shield_wall`). Ids never change once shipped;
  saves, replays, logs and network messages use ids, never array indexes or
  node paths.
- Tuning numbers (damage, cooldowns, costs, timings) live in data or in named
  constants, never as literals inside logic.
- Validate data once when it loads (missing ids, out-of-range values) and fail
  with a clear message naming the file and field. Code after loading may trust
  the data.

## 3. Easy to change

- A function does one thing and fits on one screen (about 40 lines). A file
  over about 400 lines is a hint to split the system.
- Keep state in one owner. Other code asks the owner or listens to its
  signals; it does not cache a copy that can drift.
- Prefer composition (child nodes, components, data) over inheritance deeper
  than two levels.
- Do not abstract early: write the second copy, extract on the third.
- Delete dead code and unused files in the change that makes them dead. Never
  leave code commented out; Git keeps history.
- One concern per pull request. Refactors and behavior changes go in separate
  commits so each can be reviewed and reverted alone.

## 4. Clear and easy to understand

- Names say what a thing is or does, in full words: `attack_range_cells`, not
  `ar`. Units go in the name when they are not obvious: `_usec`, `_ticks`,
  `_cells`, `_px`.
- Booleans read as questions: `is_alive`, `has_target`, `can_move`.
- Functions are verbs (`apply_damage`), signals are past-tense events
  (`unit_died`, `round_started`).
- GDScript is statically typed: every variable, parameter and return has a
  type (`var hp: int`, `func heal(amount: int) -> void`). Use `:=` only where
  the type is obvious from the right-hand side.
- Return early instead of nesting. Avoid boolean parameters that change what a
  function does; use two functions or an enum.
- Code, identifiers, comments and commit messages are in English. Text the
  player sees is in Vietnamese and goes through translation files, never
  string literals in logic.

### Naming

| Thing | C++ | GDScript |
| --- | --- | --- |
| Class / `class_name` | `PascalCase` (`SimClock`) | `PascalCase` (`VoiceService`) |
| Function, method | `snake_case` | `snake_case` |
| Variable, member | `snake_case` | `snake_case` |
| Private member | `snake_case`, private (the class default after `GDCLASS` or a `private:` section) | `_snake_case` |
| Parameter | `p_name`; output parameter `r_name` | `name` |
| Constant | `CONSTANT_CASE` (`constexpr`) | `CONSTANT_CASE` |
| Enum type / value | `PascalCase` / `CONSTANT_CASE` | `PascalCase` / `CONSTANT_CASE` |
| Signal | `snake_case`, past tense | `snake_case`, past tense |
| File | `snake_case.h` / `snake_case.cpp` | `snake_case.gd`, `snake_case.tscn` |
| Folder | `snake_case` under `Native/src/` | `PascalCase` at the top level, then `PascalCase` per feature |
| Scene node | — | `PascalCase` (`UnitSprite`, `HealthBar`) |

C++ follows godot-cpp style: classes register in `register_types.cpp`, use
`GDCLASS`, bind methods with `D_METHOD`, and pair `set_x`/`get_x` (or `is_x`)
for every exposed property.

## 5. Determinism

Battles, replays and online play depend on the simulation giving the same
result on every device from the same inputs.

- The simulation advances only on `SimClock` ticks, never on frame `delta`.
- Use integers or fixed-point for anything that affects the outcome (health,
  positions on the board, timers). Floats are for presentation only.
- All randomness comes from one seeded generator owned by the simulation and
  passed in. Never call `randi()`, `randf()`, `std::rand`, `Time`, `OS` or
  read the wall clock from simulation code.
- Iterate in a defined order. Do not iterate `std::unordered_map` or
  `std::unordered_set` when the order changes the result: their order differs
  between standard libraries (desktop vs Android). The iteration order of
  Godot's `HashMap`, `HashSet` and `Dictionary` depends only on the order of
  inserts and erases (it is not strictly insertion order after an erase), so
  it is deterministic when those are. When in doubt, sort by id.
- A battle is fully described by: data version, seed, and the list of player
  commands with their tick. Keep those three recordable (see section 6).

## 6. Easy to track and trace

### Errors

- Fail loudly at the point of the bug. In C++ use the Godot error macros
  (`ERR_FAIL_COND_V_MSG`, `ERR_FAIL_INDEX_MSG`); in GDScript use
  `push_error` for runtime problems and `assert` for programmer mistakes.
- Never swallow an error silently. If a failure is expected (the TTS server is
  offline), handle it, report it once with `push_warning` or `WARN_PRINT`, and
  keep the game running.
- Error and warning messages (`push_error`, `push_warning`, `assert`,
  `ERR_*_MSG`, `WARN_PRINT`) start with the system name and give the object id
  and the bad value: `Combat: unit.spear_guard has negative hp -3`. The
  structured format below is for event logs, not for these messages.

### Logs

Logs are structured so they can be filtered and diffed. Every line has the
same shape:

```text
[<level>][<system>][t=<tick>] <event> key=value key=value
[info][Combat][t=1284] damage_dealt src=u7 dst=u12 skill=skill.pierce amount=18 cause=e5021
```

- **Levels:** `error` (a bug or lost data), `warn` (unexpected but handled),
  `info` (major game events: round start, unit death, save), `debug`
  (developer detail), `trace` (every simulation event). `trace` and `debug`
  are off by default and switched on per system.
- **System** is the system name in `PascalCase`: the folder name for
  GDScript, the `PascalCase` form of the folder name for C++ (`combat/` is
  `Combat`).
- **Event** is a `snake_case` past-tense name; fields are `key=value` with ids,
  not display names. Add `t=<tick>` for anything inside the simulation.
- Log through the project's logging helper once it exists; until then, follow
  the same format with `print`/`push_warning`/`push_error` in GDScript and
  `UtilityFunctions::print`/`WARN_PRINT`/`ERR_PRINT` in C++.
- Do not log in per-frame or per-tick hot paths unless the line is at `trace`
  and behind a check that the level is enabled.
- Never log secrets (API keys, tokens) or personal data.

### Tracing the simulation

- Every simulation event that changes state gets an event id (`e5021`), and
  events caused by another event carry `cause=<id>`. A death can then be
  traced back through the damage, the skill and the command that started it.
- The simulation can produce a **state hash** at any tick. Tests and online
  play compare hashes to find the first tick where two runs differ.
- A bug report about a battle attaches its replay (data version, seed,
  commands). A bug that can be replayed can be fixed.

### Changes

- Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
  with the system as scope: `feat(combat): add pierce damage`,
  `fix(voice): retry after auth error`.
- A pull request links the issue or design note it implements and lists what
  a reviewer should check by hand.
- Changes a player or tester would notice are recorded in `CHANGELOG.md`
  under `Unreleased`.

## 7. Comments

Comments explain **why**, not **what**. Good names explain what.

- Every public function whose name does not say it all gets a doc comment of
  one to three lines: what it is for, units, and anything surprising (ranges,
  side effects, who owns the result).
- Every public class gets a doc comment that says what it is for and how it
  is used. Keep it under about ten lines, a short usage example included.
  - GDScript: the class doc is a `##` block right after `class_name` and
    `extends`, before any member; a member doc is `##` lines directly above
    the member. Both show in the editor help.
  - C++: `//` above the declaration in the header.
- Inside a function, comment only what the code cannot say: a reason, a
  constraint, a trade-off, a link to the rule or bug it follows.
- Keep comments short. If an explanation inside a function, or on a member,
  needs more than about five lines, it belongs in the system's doc page; link
  to it from the code.
- Write `TODO(<who>): <what> (#<issue>)`. A `TODO` without an issue is not
  allowed on `master`.
- Update or delete a comment in the same change that makes it wrong.

```gdscript
## Remaining hit points. Never below 0; reaching 0 emits [signal died].
var hp: int = 0
```

```cpp
// Damage after armor. Armor can reduce damage to 1 but never to 0, so every
// hit is visible to the player.
int apply_armor(int p_damage, int p_armor);
```

## 8. Documentation for every change

Documentation is part of the change, not a follow-up. **A pull request that
changes behavior, adds a feature, or changes a public API updates the docs in
the same pull request.** The `Docs` CI check fails a pull request that
changes code without touching `Docs/`, `README.md`, `AGENTS.md` or
`CHANGELOG.md`; see below for the exception.

What to update:

| Change | Update |
| --- | --- |
| New system | Add `Docs/systems/<system>.md` from `Docs/systems/_template.md`, and list it in `Docs/architecture.md` |
| Changed system behavior, API, signals, data schema or log events | That system's `Docs/systems/<system>.md` |
| New folder, autoload, layer or dependency | `Docs/architecture.md` |
| Build, toolchain, export or CI change | `Docs/build.md` (and `README.md` if setup steps change) |
| Anything a player or tester would notice | `CHANGELOG.md` under `Unreleased` |
| New or changed rule | This file and, if agents need it, `AGENTS.md` |

A system page says what the system is for, its data, its public API and
signals, its log events, how to extend it (add a unit, a skill), and how it is
tested. Keep it short and current; a wrong doc is worse than none.

The `CHANGELOG.md` entry is required only for changes a player or tester
would notice; the CI check does not look for it, so reviewers do.

A pull request that truly needs no doc change (a pure refactor, a typo)
starts a line of its description with `[no-docs]` followed by a one-line
reason, for example:

```text
[no-docs] rename a private helper
```

The check then passes. Changes only to `Tests/` or Markdown files never need
it.

## 9. Tests

- Each system has a test script in `Tests/` that runs headless in CI.
- Simulation tests run a short battle twice from the same seed and compare
  state hashes.
- A bug fix comes with a test that fails without the fix, when the bug can be
  reproduced in a test.

## 10. Files and formatting

- Tabs for C++ and GDScript indentation (see `.editorconfig`). UTF-8, LF,
  final newline, no trailing whitespace.
- Group assets by feature. Commit text scenes and resources; track binary
  media with Git LFS. Do not commit the generated `.godot/` folder or exported
  builds.
- Use short-lived feature branches and pull requests into `master`.
- Do not add third-party plugins or addons without approval.
