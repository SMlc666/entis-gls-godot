extends RefCounted

const ExternalCodec = preload("res://scripts/external_codec.gd")
const EriMetadata = preload("res://scripts/eri_metadata.gd")
const MAX_IMAGE_PIXELS := 64 * 1024 * 1024


static func decode(data: PackedByteArray) -> Dictionary:
	var metadata := EriMetadata.inspect(data)
	if not metadata.get("ok", false):
		return metadata
	if metadata["has_reference"]:
		return {"ok": false, "error": "图片引用了底图，暂不支持合成预览。"}
	if int(metadata["width"]) > 32768 or int(metadata["height"]) > 32768 or int(metadata["width"]) * int(metadata["height"]) > MAX_IMAGE_PIXELS:
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
				if width != int(metadata["width"]) or height != int(metadata["height"]):
					return {"ok": false, "error": "原生 ERI 解码器返回的图片尺寸与头部不一致。"}
				var expected_bytes := int(metadata["width"]) * int(metadata["height"]) * 4
				if not pixels is PackedByteArray or pixels.size() != expected_bytes:
					return {"ok": false, "error": "原生 ERI 解码器返回了长度错误的 RGBA 数据。"}
				var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
				if image == null or image.is_empty():
					return {"ok": false, "error": "无法从原生解码结果创建 ERI 图片。"}
				return {"ok": true, "image": image}
			if native_result is Dictionary:
				native_error = str(native_result.get("error", "原生 ERI 解码失败。"))
	if OS.get_name() != "Linux":
		return {
			"ok": false,
			"error": native_error if not native_error.is_empty() else "此平台未加载进程内 ERI 解码扩展。"
		}
	var result := ExternalCodec.convert(data, "entis/eri", "eri", "png")
	if not result.get("ok", false):
		return result
	var image := Image.new()
	var load_error := image.load_png_from_buffer(result["data"])
	if load_error != OK or image.is_empty():
		return {"ok": false, "error": "无法读取解码后的图片：%s" % error_string(load_error)}
	return {"ok": true, "image": image}
