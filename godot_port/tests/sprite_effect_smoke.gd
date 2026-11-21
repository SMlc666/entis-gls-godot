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
	print("PASS WaveCircle native parameters and animeEffect timing")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
