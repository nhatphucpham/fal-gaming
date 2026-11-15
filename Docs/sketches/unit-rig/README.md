# Unit rig sketch

`rig2.js` is the approved reference for how units look and move: the bone
rig, the pieces of each class, the key-pose clips and the run cycle that
the owner signed off. It is the script of a prototype page (it expects the
page's canvases and buttons) and is kept as written, for reference only;
nothing in the game loads it.

The Godot port lives in `Scenes/Board/`: `unit_pose.gd` (the pose fields
and `P()`), `rig_solver.gd` (`solve`), `rig_clips.gd` (the generic clips
and run), `rig_body.gd`, `rig_torso.gd`, `rig_heads.gd`,
`rig_weapons.gd`, `rig_bow.gd` and `rig_horse.gd` (the pieces),
`kit_*.gd` (`defClass` per class), `rig_painter.gd` (`drawFigure`) and
`pose_animator.gd` (the actor's `play` and `update`). The numbers are the
sketch's; see [Board](../../systems/board.md) for what differs and why.
