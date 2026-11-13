# Agent instructions

- Follow `Docs/conventions.md` and keep changes focused.
- Put gameplay logic in C++ (GDExtension); use Godot scenes for composition
  and tuning. Do not add third-party plugins or addons without approval.
- Keep the game light: GL Compatibility renderer, modest assets, and nothing
  that assumes a desktop-only GPU or input device.
- Validate the project with the import and smoke test commands in the README
  before opening a PR, and report any inability to validate. If you change
  native code, also build the extension.
- Do not commit the generated `.godot/` folder or exported builds.
