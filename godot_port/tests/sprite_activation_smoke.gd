extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")


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
	print("PASS Sprite activation")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
