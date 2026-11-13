# Build and test

Install Unreal Engine 5.5 and set `UE_ROOT` to its root, not its `Engine`
subdirectory. On Windows, use the commands in the README. On Linux/macOS,
export `UE_ROOT` and run the `.sh` equivalents with Bash; those scripts target
the host platform, which has not been validated as a shipping target.

- `Scripts/build-editor.bat` / `.sh`: compile the editor target.
- `Scripts/build-game.bat` / `.sh`: compile the development game target.
- `Scripts/cook.bat` / `.sh`: cook project content for the host platform.
- `Scripts/package.bat` / `.sh`: build, cook, stage and archive to `Packaged`.
- `Scripts/clean.bat` / `.sh`: **delete** project `Binaries`, `Intermediate`,
  `Saved` (including local saves and logs), and `DerivedDataCache`.

The editor build uses UnrealBuildTool through the engine's build script;
game build, cook and package use Unreal Automation Tool's `BuildCookRun`.
All four forward extra command-line arguments. Build the editor and create and
configure the default map before cooking or packaging. These scripts require
the appropriate engine platform support and native toolchain.

The Windows test command is in the README. On Linux/macOS, substitute the
corresponding `UnrealEditor-Cmd` executable in
`$UE_ROOT/Engine/Binaries/Linux/` or `.../Mac/`, and pass
`-ExecCmds="Automation RunTests Falemag"` and
`-TestExit="Automation Test Queue Empty"`. Check the log for failures.
