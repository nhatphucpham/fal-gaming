# Agent instructions

Read `Docs/conventions.md` before changing code and follow it. It is the
project's coding standard; the points below are the ones most often missed.

- **Layers.** Game rules live in C++ simulation code (GDExtension); bridge
  nodes expose them; scenes and GDScript handle presentation, input and
  tuning. Presentation sends commands and listens to signals; it never edits
  simulation state.
- **Data first.** New units, skills, items and similar content are `Resource`
  data under `Data/`, with stable ids like `unit.spear_guard`. Do not add `match`/`switch`
  branches per content type; use a registry.
- **Determinism.** Simulation code runs on `SimClock` ticks, uses integers or
  fixed-point, takes randomness from the seeded simulation RNG, and never
  reads the clock, input, files or network.
- **Traceable.** Fail loudly with Godot error macros, `push_error` or
  `assert`; messages start with the system name (`Combat: ...`). Event logs
  use `[<level>][<System>][t=<tick>] <event> key=value`. Never log secrets.
- **Clear.** Follow the naming table. GDScript is statically typed. Comments
  say why; function doc comments are one to three lines, class doc comments
  under about ten; no commented-out code; every `TODO` has an issue.
- **Docs in the same PR.** Every change in behavior, API, data schema, build
  or architecture updates the matching doc (`Docs/systems/<system>.md` from
  `Docs/systems/_template.md`, `Docs/architecture.md`, `Docs/build.md`).
  Changes a player or tester would notice also get a `CHANGELOG.md` entry.
  The `Docs` CI check fails code changes that touch no docs; a line starting
  with `[no-docs] <reason>` in the PR description is only for pure refactors
  and typos.
- Fill in the pull request template checklist. One concern per PR, Conventional
  Commits with the system as scope (`feat(combat): ...`).
- Keep the game light: GL Compatibility renderer, modest assets, and nothing
  that assumes a desktop-only GPU or input device. Do not add third-party
  plugins or addons without approval.
- Validate with the import and smoke test commands in the README before
  opening a PR, and report any inability to validate. If you change native
  code, also build the extension.
- Do not commit the generated `.godot/` folder or exported builds.
