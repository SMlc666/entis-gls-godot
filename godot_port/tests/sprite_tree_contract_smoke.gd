extends SceneTree

const HostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	var parent_a := HostClass.HostSprite.new(1)
	var parent_b := HostClass.HostSprite.new(2)
	var parent_c := HostClass.HostSprite.new(3)
	var child := HostClass.HostSprite.new(4)
	parent_a.add_sprite(0, child)
	if child.parent_sprite != parent_a or not parent_a.children.has(child):
		_fail("Adding a child must record its unique parent")
		return
	child.add_sprite(0, parent_a)
	if parent_a.parent_sprite != null or child.children.has(parent_a):
		_fail("A child-parent cycle must be rejected")
		return
	parent_c.add_sprite(0, child)
	if parent_a.children.has(child) or child.parent_sprite != parent_c or not parent_c.children.has(child):
		_fail("Reparenting must detach the old parent before adding the new one")
		return
	var first_window := HostClass.HostWindow.new(null)
	var second_window := HostClass.HostWindow.new(null)
	first_window.add_sprite(0, parent_c)
	second_window.add_sprite(1, parent_c)
	if first_window.root_sprites.has(parent_c) or not second_window.root_sprites.has(parent_c) or parent_c.root_window != second_window:
		_fail("A sprite mounted in a second window must detach from its previous root")
		return
	second_window.add_sprite(2, child)
	if parent_c.children.has(child) or child.parent_sprite != null or child.root_window != second_window:
		_fail("Mounting a child as a window root must detach the previous parent")
		return
	second_window.detach_all_sprites()
	if parent_c.root_window != null or child.root_window != null:
		_fail("Detaching all window sprites must clear root ownership")
		return
	parent_c.add_sprite(0, child)
	parent_c.detach_all_sprites()
	if child.parent_sprite != null:
		_fail("Detaching all children must clear their parent references")
		return
	print("PASS sprite tree single-parent and cycle contract")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
