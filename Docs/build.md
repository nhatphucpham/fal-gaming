# Build and test

Use the standard Godot 4.7.2 editor. Open `project.godot` in the project
manager or follow the command-line instructions in the README. Godot imports
assets into `.godot/`, which is generated locally and ignored by Git.

To validate without a graphical display, run the editor import and the
`Tests/smoke_test.gd` command shown in the README. CI also starts the project
headlessly. These checks do not replace testing an exported Windows build.

Install matching export templates in the Godot editor and use the Windows
Desktop preset to export. The README gives a command-line example. A C++
GDExtension toolchain is not needed for this empty starter; it must be set up
when native gameplay code is added.
