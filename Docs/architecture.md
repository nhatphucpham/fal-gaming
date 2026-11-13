# Architecture

`Source/Falemag` is the runtime module. Public headers are in `Public`;
implementation and automation tests are in `Private`. The two target files
define the game and editor builds. Add small gameplay systems to the runtime
module by feature; extract an independent, reusable system into a plugin only
when its boundaries warrant it.

`UFalemagGameInstance` lives for the lifetime of the game and is the place for
cross-level state. `AFalemagGameMode` selects the pawn and controller for a
game world. `AFalemagPlayerController` installs the local player's input mapping
context; `AFalemagCharacter` binds move, look and jump actions and owns the
camera. The default C++ classes are configured in `DefaultEngine.ini`.

Input assets and a playable map are intentionally not checked in. Follow the
editor steps in the README to create and wire Blueprint subclasses and assets.
New content belongs under `Content/Falemag` in the relevant feature folder;
`_Dev` is for experiments and excluded from cooking.
