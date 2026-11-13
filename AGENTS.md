# Agent instructions

- Put gameplay logic in C++; use Godot scenes for composition and tuning. Do
  not add third-party plugins without approval.
- Do not edit or generate `.uasset` or `.umap` files. Describe required asset
  changes in an **Editor tasks** checklist in the PR.
- Validate the Godot project and smoke test before opening a PR. Report any
  inability to validate. If changing native gameplay, also build its extension.
- Do not modify generated `Binaries`, `Intermediate`, or `Saved` folders, or
  other developers' sandbox content under `Content/Falemag/_Dev`.
- Do not commit generated `.godot` files or exported builds.
- Follow `Docs/conventions.md` and keep changes focused.
