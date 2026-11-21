extends SceneTree


func _initialize() -> void:
	if not ClassDB.class_exists("YzkCodec"):
		printerr("FAIL native GDExtension must register YzkCodec")
		quit(1)
		return
	var codec: Object = ClassDB.instantiate("YzkCodec")
	if codec == null or not codec.has_method("decode_erisan"):
		printerr("FAIL YzkCodec must expose decode_erisan to GDScript")
		quit(1)
		return
	var result: Variant = codec.call("decode_erisan", PackedByteArray(), 1)
	if not result is Dictionary or result.get("ok", true) or int(result.get("code", 0)) != -1:
		printerr("FAIL native codec must reject empty input before decoding")
		quit(1)
		return
	for method_name: String in ["decode_eri", "decode_mio", "decode_mei"]:
		if not codec.has_method(method_name):
			printerr("FAIL YzkCodec must expose %s to GDScript" % method_name)
			quit(1)
			return
		var decode_result: Variant = codec.call(method_name, PackedByteArray())
		if not decode_result is Dictionary or decode_result.get("ok", true):
			printerr("FAIL native %s must reject empty input before decoding" % method_name)
			quit(1)
			return
	print("PASS GDExtension ERISAN/ERI/MIO method binding and input bounds")
	quit(0)
