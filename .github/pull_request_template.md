## What and why

<!-- What this changes and why. Link the issue or design note. -->

## How to check

<!-- What a reviewer should run or try by hand. -->

## Checklist

- [ ] One concern; refactors and behavior changes are in separate commits.
- [ ] Follows `Docs/conventions.md`: layers, data first, naming, static
      types, determinism in simulation code.
- [ ] New content is data (`Data/`), not new code paths.
- [ ] Errors fail loudly; new log lines follow the structured format and log
      no secrets.
- [ ] Public classes and functions have short doc comments; no commented-out
      code; every `TODO` has an issue.
- [ ] Docs updated: `Docs/systems/<system>.md`, `Docs/architecture.md`,
      `Docs/build.md` as needed, and `CHANGELOG.md` under `Unreleased`.
      Or `[no-docs]` with a reason: <!-- reason -->
- [ ] Tests added or updated; import, smoke test and native build pass.
