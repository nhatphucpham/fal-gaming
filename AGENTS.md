# Agent instructions

- Do not edit or generate `.uasset` or `.umap` files. Describe required asset
  changes in an **Editor tasks** checklist in the PR.
- Put gameplay logic in C++; Blueprints subclass and tune C++ classes.
- Compile the editor target with `Scripts/build-editor.bat` (or `.sh` on the
  corresponding host) before opening a PR. Report any inability to compile.
- Do not modify generated `Binaries`, `Intermediate`, or `Saved` folders, or
  other developers' sandbox content under `Content/Falemag/_Dev`.
- Asset prefixes: `BP_` Blueprint, `WBP_` widget, `M_` material, `MI_` material
  instance, `T_` texture, `SM_` static mesh, `SK_` skeletal mesh, `A_` animation,
  `NS_` Niagara system, `DA_` data asset, `IA_` input action, `IMC_` input
  mapping context.
- Follow `Docs/conventions.md` and keep changes focused.
