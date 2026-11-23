extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	var host := CsxHostClass.new("")
	var vm := CsxVMReader.new(host)
	var sprite := CsxHostClass.HostSprite.new(0, host)
	var default_parameter: Variant = vm.create_object("SpriteParam")
	if default_parameter.get_field("rHorzUnit") != 1.0 or default_parameter.get_field("rCrossingAngle") != 90.0 or default_parameter.get_field("rgbLightColor") != 0xffffff or default_parameter.get_field("ptDstPos") == null:
		_fail("SpriteParam must initialize its SDK defaults and Point members")
		return
	var parameter := CsxVMReader.CsxInstance.new("SpriteParam")
	sprite.magnification = Vector2(1.5, 0.75)
	sprite.rotation_degrees = 30.0
	if not is_same(vm._dispatch_sprite_method(sprite, "GetParameter", [parameter]), parameter) or parameter.get_field("rHorzUnit") != 1.5 or parameter.get_field("rRevAngle") != 30.0:
		_fail("Sprite.GetParameter must return and populate the supplied SpriteParam")
		return
	parameter.set_field("rCrossingAngle", 67.0)
	parameter.set_field("rgbLightColor", 0x123456)
	sprite.set_parameter(parameter)
	var parameter_copy := CsxVMReader.CsxInstance.new("SpriteParam")
	sprite.get_parameter(parameter_copy)
	if parameter_copy.get_field("rCrossingAngle") != 67.0 or parameter_copy.get_field("rgbLightColor") != 0x123456:
		_fail("SpriteParam fields must survive SetParameter and GetParameter")
		return
	var window := CsxHostClass.HostWindow.new(host)
	if not is_same(vm._dispatch_window_method(window, "GetParameter", [parameter]), parameter):
		_fail("Window.GetParameter must return the supplied SpriteParam")
		return
	var source := CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
	source.image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	source.image.fill(Color.RED)
	var destination := CsxHostClass.HostSprite.new(0, host)
	destination.create_sprite(0, 8, 8)
	var draw_param: Variant = vm.create_object("SpriteParam")
	draw_param.get_field("ptDstPos").set_field("x", 2)
	draw_param.get_field("ptDstPos").set_field("y", 1)
	draw_param.set_field("rHorzUnit", 2.0)
	draw_param.set_field("rVertUnit", 2.0)
	if vm._dispatch_sprite_method(destination, "DrawImage", [source, draw_param]) != 0 or destination.image.get_pixel(5, 4).r < 0.9 or destination.image.get_pixel(6, 4).a > 0.1:
		_fail("DrawImage must scale source pixels at the requested destination")
		return
	destination.image.fill(Color.TRANSPARENT)
	source.image.set_pixel(0, 0, Color.RED)
	source.image.set_pixel(1, 0, Color.BLUE)
	draw_param.get_field("ptDstPos").set_field("x", 4)
	draw_param.set_field("rHorzUnit", -1.0)
	draw_param.set_field("rVertUnit", 1.0)
	draw_param.set_field("nTransparency", 128)
	if destination.draw_image(source, draw_param) != 1 or destination.image.get_pixel(2, 1).b < 0.9 or destination.image.get_pixel(3, 1).r < 0.9 or absf(destination.image.get_pixel(2, 1).a - 0.5) > 0.02:
		_fail("DrawImage must flip negative scale and apply transparency")
		return
	destination.image.fill(Color.TRANSPARENT)
	draw_param.get_field("ptDstPos").set_field("x", 4)
	draw_param.get_field("ptDstPos").set_field("y", 2)
	draw_param.set_field("rHorzUnit", 1.0)
	draw_param.set_field("nTransparency", 0)
	draw_param.set_field("rRevAngle", 90.0)
	if destination.draw_image(source, draw_param) != 1 or destination.image.get_pixel(3, 2).r < 0.9 or destination.image.get_pixel(3, 3).b < 0.9:
		_fail("DrawImage must rotate the source around its native destination anchor")
		return
	if vm._dispatch_sprite_method(sprite, "CreateMessage", [640, 120]) != 0:
		_fail("Sprite.CreateMessage success must return Entis Error 0")
		return
	if vm._dispatch_sprite_method(sprite, "CreateMessage", [0, 120]) != 1:
		_fail("Sprite.CreateMessage failure must return Entis Error 1")
		return
	if vm._dispatch_sprite_method(sprite, "OutputMessage", ["native message"]) != 0 or sprite.text_content != "native message":
		_fail("MessageSprite.OutputMessage must update text and return Error 0")
		return
	if vm._dispatch_sprite_method(sprite, "SetSpriteText", ["", "sprite text"]) != 0:
		_fail("Sprite.SetSpriteText success must return Entis Error 0")
		return
	if vm._dispatch_sprite_method(sprite, "SetBackColor", [0x123456, -1]) != 0 or sprite.back_color != 0x123456 or not sprite.fill_back_color:
		_fail("Sprite.SetBackColor must preserve RGB and enable flags")
		return
	if vm._dispatch_sprite_method(sprite, "SetHorzScrollRange", [400, "ID_LIST"]) != 0:
		_fail("Sprite.SetHorzScrollRange success must return Entis Error 0")
		return
	if vm._dispatch_sprite_method(sprite, "SetHorzScrollPos", [80, "ID_LIST"]) != 0 or vm._dispatch_sprite_method(sprite, "GetHorzScrollPos", ["ID_LIST"]) != 80:
		_fail("Sprite horizontal scrolling must preserve state and use Error 0")
		return
	if vm._dispatch_sprite_method(sprite, "IsMoviePlaying", []) != 0:
		_fail("MovieSprite.IsMoviePlaying false must return Entis Boolean false 0")
		return
	host.is_movie_playing = true
	if vm._dispatch_sprite_method(sprite, "IsMoviePlaying", []) != -1:
		_fail("MovieSprite.IsMoviePlaying true must return Entis Boolean true -1")
		return
	print("PASS native Sprite and MovieSprite Error/Boolean return conventions")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
