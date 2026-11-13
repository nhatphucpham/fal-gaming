# Conventions

- Follow Epic C++ conventions: tabs for indentation, PascalCase names and
  Unreal's `A`, `U`, `F`, `E`, `I` and `T` type prefixes. Use reflected
  properties/functions with appropriate categories; use `TObjectPtr` for
  persistent UObject member references and normal non-owning local pointers.
- Keep core gameplay logic in C++. Blueprints are for subclassing, content and
  tuning. Split public interfaces and private implementations.
- Use these asset prefixes: `BP_` Blueprint, `WBP_` widget, `M_` material,
  `MI_` material instance, `T_` texture, `SM_` static mesh, `SK_` skeletal
  mesh, `A_` animation, `NS_` Niagara system, `DA_` data asset, `IA_` input
  action, `IMC_` input mapping context.
- Put assets under `Content/Falemag` by feature. Keep personal experiments in
  `_Dev`; never ship them. Do not edit others' sandbox content.
- Track binary assets with Git LFS and lock `.uasset` and `.umap` files before
  editing. Use short-lived feature branches and PRs into `main`.
- Use Conventional Commits, for example `feat: add inventory` or
  `fix: correct movement input`.
