# Changelog

Changes a player or tester would notice, newest first. Add an entry under
`Unreleased` in the same pull request as the change (see
`Docs/conventions.md`, section 8).
Group entries under `Added`, `Changed`, `Fixed` or `Removed`.

## Unreleased

### Added

- Headless battle core for testers: six classes, 25 demo units and the
  battle rules as data under `Data/`, and `Tests/battle_test.gd`, which
  prints the length of a sample 8v8 battle. No battle screen yet.
- Coding conventions for extensible, traceable code, the system doc template,
  this changelog, a pull request checklist and a CI check that code changes
  come with docs.
