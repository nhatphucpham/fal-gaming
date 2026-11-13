# Build and test

Use the standard Godot 4.7.2 editor and open `project.godot`, or follow the
command-line steps in the README. Godot imports assets into `.godot/`, which is
generated locally and ignored by Git.

To validate without a display, run the editor import and
`Tests/smoke_test.gd` as shown in the README. CI does the same and also starts
the project headlessly. These checks do not replace testing an exported build
on the target device.

A C++ toolchain is not needed yet. It will be required, and documented here,
when the GDExtension is added.
