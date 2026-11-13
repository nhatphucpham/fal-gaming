# Conventions

- Keep gameplay logic in C++ and use Godot scenes for composition and tuning.
  Add a GDExtension build setup when native gameplay is introduced.
- Use tabs for C++ and GDScript indentation. Use descriptive scene and node
  names, and place assets under `Content/Falemag` by feature.
- Keep personal experiments in `Content/Falemag/_Dev` and exclude them from
  every export preset. Do not edit other developers' sandbox content.
- Commit text scenes and resources to Git; track binary media with Git LFS.
  Do not commit generated `.godot` files or exported builds.
- Use short-lived feature branches and PRs into `main`. Write Conventional
  Commits, for example `feat: add inventory` or `fix: correct movement input`.
