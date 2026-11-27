extends RefCounted

const EriMetadata = preload("res://scripts/eri_metadata.gd")
const MAX_IMAGE_PIXELS := 64 * 1024 * 1024


static func decode(data: PackedByteArray) -> Dictionary:
	var metadata := EriMetadata.inspect(data)
	if not metadata.get("ok", false):
		return metadata
	if metadata["has_reference"]:
		return {"ok": false, "error": "图片引用了底图，暂不支持合成预览。"}
	var frame_count := int(metadata.get("frame_count", 1))
	if int(metadata["width"]) > 32768 or int(metadata["height"]) > 32768 or int(metadata["width"]) * int(metadata["height"]) * frame_count > MAX_IMAGE_PIXELS:
		return {"ok": false, "error": "ERI 图片尺寸超出预览上限。"}
	var native_error := ""
	if ClassDB.class_exists("YzkCodec"):
		var codec: Object = ClassDB.instantiate("YzkCodec")
		if codec != null and codec.has_method("decode_eri"):
			var native_result: Variant = codec.call("decode_eri", data)
			if native_result is Dictionary and native_result.get("ok", false):
				var width := int(native_result.get("width", 0))
				var height := int(native_result.get("height", 0))
				var pixels: Variant = native_result.get("data", PackedByteArray())
				var stacked_height := int(metadata["height"]) * frame_count
				if width != int(metadata["width"]) or height != stacked_height:
					return {"ok": false, "error": "原生 ERI 解码器返回的帧图集尺寸与头部不一致。"}
				var expected_bytes := int(metadata["width"]) * stacked_height * 4
				if not pixels is PackedByteArray or pixels.size() != expected_bytes:
					return {"ok": false, "error": "原生 ERI 解码器返回了长度错误的 RGBA 数据。"}
				var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
				if image == null or image.is_empty():
					return {"ok": false, "error": "无法从原生解码结果创建 ERI 图片。"}
				return _split_frames(image, metadata)
			if native_result is Dictionary:
				native_error = str(native_result.get("error", "原生 ERI 解码失败。"))
	return {
		"ok": false,
		"error": native_error if not native_error.is_empty() else "未加载进程内 ERI 解码扩展。"
	}


static func _split_frames(stacked_image: Image, metadata: Dictionary) -> Dictionary:
	var width := int(metadata["width"])
	var frame_height := int(metadata["height"])
	var frame_count := int(metadata.get("frame_count", 1))
	if stacked_image.get_width() != width or stacked_image.get_height() != frame_height * frame_count:
		return {"ok": false, "error": "ERI 解码帧图集尺寸与帧索引不匹配。"}
	var frames: Array[Image] = []
	for frame_index in frame_count:
		frames.append(stacked_image.get_region(Rect2i(0, frame_index * frame_height, width, frame_height)))
	if frames.is_empty():
		return {"ok": false, "error": "ERI 解码结果没有可用帧。"}
	return {
		"ok": true,
		"image": frames[0],
		"frames": frames,
		"frame_sequence": metadata.get("frame_sequence", []),
		"total_time_ms": int(metadata.get("total_time_ms", 0)),
	}
