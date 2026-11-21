extends SceneTree

func _initialize() -> void:
	var codec: Object = ClassDB.instantiate("YzkCodec")
	if codec == null or not codec.has_method("build_shading_levels"):
		push_error("FAIL native shading filter API is unavailable")
		quit(1)
		return

	var solid := PackedByteArray()
	solid.resize(3 * 3 * 4)
	for i in range(0, solid.size(), 4):
		solid[i] = 32
		solid[i + 1] = 96
		solid[i + 2] = 160
		solid[i + 3] = 255
	var solid_levels: Array = codec.call("build_shading_levels", solid, 3, 3)
	if solid_levels.size() != 5:
		push_error("FAIL shading filter must return source plus four levels")
		quit(1)
		return
	for level: PackedByteArray in solid_levels:
		if level != solid:
			push_error("FAIL shading filter changed a constant image")
			quit(1)
			return

	var impulse := PackedByteArray()
	impulse.resize(3 * 3 * 4)
	impulse.fill(0)
	for channel in range(4):
		impulse[16 + channel] = 255
	var impulse_levels: Array = codec.call("build_shading_levels", impulse, 3, 3)
	var blurred: PackedByteArray = impulse_levels[1]
	if blurred[16] >= 255 or blurred[0] != 0 or blurred.size() != impulse.size():
		push_error("FAIL native 4:2:1 filter did not soften the impulse while retaining boundaries")
		quit(1)
		return
	print("PASS native shading filter levels=5 constant=preserved impulse_center=%d" % blurred[16])
	quit(0)
