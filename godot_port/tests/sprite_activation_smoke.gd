extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	var host := CsxHostClass.new()
	var sprite := CsxHostClass.HostSprite.new(0, host)
	sprite.set_transparency(256)
	sprite.set_blending_envelope(0)
	sprite.begin_activation(500)
	host.advance_sprite_animations(0.125)
	if sprite.transparency != 192 or sprite.is_activation() != -1:
		_fail("Fade must interpolate before its deadline")
		return
	host.advance_sprite_animations(0.375)
	if sprite.transparency != 0 or sprite.is_activation() != 0 or not host.active_sprites.is_empty():
		_fail("Fade must finish at its target and unregister")
		return
	sprite.set_blending_envelope(256)
	sprite.begin_activation(200)
	host.advance_sprite_animations(0.1)
	sprite.set_blending_envelope(64)
	sprite.begin_activation(0)
	if sprite.transparency != 64 or sprite.is_activation() != 0 or not host.active_sprites.is_empty():
		_fail("A zero-duration activation must immediately replace an active fade")
		return
	sprite.set_blending_envelope(256)
	sprite.begin_activation(200)
	sprite.flush_activation()
	if sprite.transparency != 256 or sprite.is_activation() != 0 or not host.active_sprites.is_empty():
		_fail("Flushing must finish an activation without waiting for another frame")
		return
	var mask := CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
	mask.image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	sprite.set_alpha_image(mask, 8)
	sprite.set_transparency(32)
	sprite.set_blend_degree(0)
	sprite.set_blending_envelope(256)
	sprite.begin_activation(200)
	host.advance_sprite_animations(0.1)
	if sprite.blending != 128 or sprite.transparency != 32:
		_fail("Masked fading must animate blend degree without changing sprite transparency")
		return
	sprite.flush_activation()
	if sprite.blending != 256 or sprite.transparency != 32:
		_fail("Flushing a masked fade must preserve independent transparency")
		return
	var vm := CsxVMClass.new(host)
	vm._dispatch_sprite_method(sprite, "SetBezierCurve", [null, [0.0, 30.0, 60.0, 90.0]])
	sprite.begin_activation(200)
	host.advance_sprite_animations(0.1)
	if not is_equal_approx(sprite.rotation_degrees, 45.0):
		_fail("Sprite rotation must follow the native scalar Bezier curve")
		return
	sprite.flush_activation()
	vm._dispatch_sprite_method(sprite, "SetBezierCurve", [null, [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0]])
	sprite.begin_activation(200)
	host.advance_sprite_animations(0.15)
	if not is_equal_approx(sprite.rotation_degrees, 45.0):
		_fail("Sprite rotation must evaluate the second segment of a native Bezier curve")
		return
	vm._dispatch_sprite_method(sprite, "SetBezierCurve", [null, []])
	if not sprite.activation_curves[1].is_empty():
		_fail("An empty native Bezier array must clear the corresponding curve")
		return
	sprite.flush_activation()
	print("PASS Sprite activation")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
