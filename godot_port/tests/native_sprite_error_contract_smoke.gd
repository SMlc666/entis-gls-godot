extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	var host := CsxHostClass.new("")
	var vm := CsxVMReader.new(host)
	var sprite := CsxHostClass.HostSprite.new(0, host)
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
