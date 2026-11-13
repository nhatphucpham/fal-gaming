# Conventions

- Keep gameplay logic in C++ (GDExtension) and use scenes for composition and
  tuning.
- Use tabs for C++ and GDScript indentation, and descriptive scene and node
  names. Group assets by feature.
- Commit text scenes and resources to Git; track binary media with Git LFS.
  Do not commit the generated `.godot/` folder or exported builds.
- Use short-lived feature branches and pull requests into `master`. Write
  Conventional Commits, for example `feat: add turn order` or
  `fix: correct unit selection`.
