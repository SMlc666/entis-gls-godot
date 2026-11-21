extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	var host := CsxHostClass.new()
	var sprite := CsxHostClass.HostSprite.new(0, host)
	var effect := CsxVMClass.CsxInstance.new("EffectParam")
	effect.set_field("strType", "WaveCircle")
	effect.set_field("nShakingWidth", 7)
	effect.set_field("nMeshSize", 12)
	effect.set_field("nFrequency", 24)
	effect.set_field("nInterval", 100)
	effect.set_field("nDegreeStep", 32)
	effect.set_field("nFlags", 4)
	if sprite.set_effect_parameter(effect) != 0:
		_fail("WaveCircle effect parameters must be accepted")
		return
	if sprite.fields.get("effect_mesh_size") != 12 or sprite.fields.get("effect_shaking_width") != 7 or sprite.fields.get("effect_frequency") != 24:
		_fail("WaveCircle must preserve the original mesh and radial wave parameters")
		return
	if not host.active_effect_sprites.has(sprite.get_instance_id()):
		_fail("Animated WaveCircle must register for host advancement")
		return
	host.advance_sprite_animations(0.1)
	if sprite.blending != 32:
		_fail("WaveCircle degree must advance by nDegreeStep each nInterval")
		return
	host.sprite_animation_flags &= ~4
	host.advance_sprite_animations(0.1)
	if sprite.blending != 0:
		_fail("WaveCircle degree must return to zero when animeEffect is disabled")
		return
	var tile_effect := CsxVMClass.CsxInstance.new("EffectParam")
	var view_size := CsxVMClass.CsxInstance.new("ISize")
	view_size.set_field("w", 800)
	view_size.set_field("h", 600)
	var tile_speed := CsxVMClass.CsxInstance.new("IPoint")
	tile_speed.set_field("x", 1)
	tile_speed.set_field("y", 0)
	tile_effect.set_field("strType", "TileImage")
	tile_effect.set_field("sizeView", view_size)
	tile_effect.set_field("ptSpeed", tile_speed)
	tile_effect.set_field("nInterval", 100)
	tile_effect.set_field("nDegreeStep", 0)
	sprite.size = Vector2i(800, 600)
	if sprite.set_effect_parameter(tile_effect) != 0:
		_fail("Original TileImage parameters must be accepted")
		return
	if sprite.fields.get("effect_size") != Vector2i(800, 600) or sprite.fields.get("effect_scroll_speed") != Vector2i(1, 0):
		_fail("TileImage must preserve the original view size and pixel speed")
		return
	host.sprite_animation_flags |= 4
	host.advance_sprite_animations(0.099)
	if sprite.fields.get("effect_scroll") != Vector2i.ZERO:
		_fail("TileImage must wait for nInterval before scrolling")
		return
	host.advance_sprite_animations(0.001)
	if sprite.fields.get("effect_scroll") != Vector2i(-799, 0):
		_fail("TileImage must advance one pixel and wrap at the 800-pixel view boundary")
		return
	var vm := CsxVMClass.new(host)
	var mesh_values: Array = [
		0.0, 0.0, 64.0, 0.0, 0.0, 64.0, 64.0, 64.0,
		0.0, 0.0, 64.0, 10.0, 10.0, 64.0, 64.0, 64.0,
	]
	var mesh_result: Variant = vm._dispatch_sprite_method(sprite, "SetMeshWarpEffect", [mesh_values, 2, 1, 1])
	if mesh_result != 0 or sprite.fields.get("effect_type") != "MeshWarp":
		_fail("SetMeshWarpEffect must accept native flattened mesh arrays")
		return
	if sprite.fields["effect_mesh_frames"].size() != 2 or sprite.fields["effect_mesh_base"].size() != 4:
		_fail("SetMeshWarpEffect must retain all morph frames and its generated base mesh")
		return
	if vm._dispatch_sprite_method(sprite, "SetMeshWarpEffect", [[], 0, 0, 0]) != -1:
		_fail("SetMeshWarpEffect must reject invalid mesh dimensions")
		return
	print("PASS WaveCircle and TileImage native parameters and animeEffect timing")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
