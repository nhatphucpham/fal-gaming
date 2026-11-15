class_name KitSword
extends RefCounted
## Kiếm (class.sword): the sketch's base figure. Plumed helmet, plate over
## the tunic, scabbard strap and red scarf, a sword; every clip and rest
## pose is the generic one from RigClips.


static func build() -> RigKit:
	var kit := RigKit.new()
	kit.pieces = RigBody.base_pieces()
	return kit
