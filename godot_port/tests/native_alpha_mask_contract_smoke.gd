extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	var host := CsxHostClass.new("")
	var vm := CsxVMClass.new(host)
	var sprite := CsxHostClass.HostSprite.new(0, host)
	sprite.image = Image.create(2, 1, false, Image.FORMAT_RGBA8)
	sprite.image.fill(Color(1, 0.5, 0.25, 1))
	sprite.texture = ImageTexture.create_from_image(sprite.image)
	sprite.size = Vector2i(2, 1)
	var alpha_resource := CsxHostClass.HostResource.new("alpha", "", -1, 0, 0, host)
	alpha_resource.image = Image.create(2, 1, false, Image.FORMAT_RGBA8)
	alpha_resource.image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
	alpha_resource.image.set_pixel(1, 0, Color(1.0, 1.0, 1.0, 1.0))
	if vm._dispatch_sprite_method(sprite, "SetAlphaImage", [alpha_resource, 128]) != 0:
		_fail("SetAlphaImage must return Entis Error 0")
		return
	if sprite.alpha_resource != alpha_resource or sprite.alpha_texture == null or sprite.alpha_range != 128:
		_fail("SetAlphaImage must retain the resource, 8-bit mask texture and range")
		return
	sprite.set_transparency(64)
	sprite.set_blend_degree(192)
	if sprite.transparency != 64 or vm._dispatch_sprite_method(sprite, "GetBlendDegree", []) != 192:
		_fail("SetBlendDegree with an active alpha mask must preserve transparency independently")
		return
	var mask := sprite.alpha_texture.get_image()
	if mask.get_pixel(0, 0).r > 0.01 or mask.get_pixel(1, 0).r < 0.99:
		_fail("SetAlphaImage must preserve mask intensity in the red channel")
		return
	sprite.set_alpha_image(null, 256)
	if sprite.alpha_resource != null or sprite.alpha_texture != null or sprite.alpha_range != 256:
		_fail("SetAlphaImage null must clear the current alpha mask")
		return
	sprite.set_blend_degree(80)
	if sprite.transparency != 80 or vm._dispatch_sprite_method(sprite, "GetBlendDegree", []) != 80:
		_fail("SetBlendDegree without an alpha mask must also update transparency")
		return
	sprite.set_alpha_image(alpha_resource, 300)
	if sprite.alpha_resource != alpha_resource or sprite.alpha_texture != null:
		_fail("Alpha ranges at or above 256 must retain the resource but bypass mask compositing")
		return
	print("PASS native Sprite.SetAlphaImage resource, range and mask contract")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
