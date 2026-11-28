extends RefCounted

const EntisSections = preload("res://scripts/entis_sections.gd")
const MAX_OUTPUT_SIZE := 128 * 1024 * 1024


static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < 64 or data.slice(0, 8).hex_encode() != "456e7469731a0000" or data.decode_u32(8) != 0x03000100:
		return {"ok": false, "error": "不是有效的 Entis 音频头。"}
	if data.slice(16, 48).get_string_from_ascii() != "Music Interleaved and Orthogonal":
		return {"ok": false, "error": "不是 MIO 音频。"}
	var header := EntisSections.find(data, 64, data.size(), "Header")
	if not header.get("ok", false):
		return header
	var sound_info := EntisSections.find(data, header["start"], header["end"], "SoundInf")
	if not sound_info.get("ok", false):
		return sound_info
	var offset: int = sound_info["start"]
	if int(sound_info["end"]) - offset < 40:
		return {"ok": false, "error": "MIO 音频信息不完整。"}
	var channels := data.decode_u32(offset + 12)
	var rate := data.decode_u32(offset + 16)
	var samples := data.decode_u32(offset + 28)
	var bits := data.decode_u32(offset + 36)
	if channels < 1 or channels > 2 or rate < 1 or rate > 384000 or samples < 1 or bits not in [8, 16, 24, 32]:
		return {"ok": false, "error": "MIO 音频参数不受支持。"}
	if samples * channels * (bits >> 3) > MAX_OUTPUT_SIZE:
		return {"ok": false, "error": "MIO 解码结果预计超过预览上限。"}
	var native_error := ""
	if ClassDB.class_exists("YzkCodec"):
		var codec: Object = ClassDB.instantiate("YzkCodec")
		if codec != null and codec.has_method("decode_mio"):
			var native_result: Variant = codec.call("decode_mio", data)
			if native_result is Dictionary and native_result.get("ok", false):
				var native_channels := int(native_result.get("channels", 0))
				var native_rate := int(native_result.get("sample_rate", 0))
				var native_bits := int(native_result.get("bits_per_sample", 0))
				var pcm: Variant = native_result.get("data", PackedByteArray())
				var frame_bytes := channels * (bits >> 3)
				if native_channels != channels or native_rate != rate or native_bits != bits:
					return {"ok": false, "error": "原生 MIO 解码器返回的音频格式与头部不一致。"}
				if bits not in [8, 16]:
					native_error = "Godot AudioStreamWAV 当前只支持本接口的 8 位或 16 位 PCM。"
				elif not pcm is PackedByteArray or pcm.is_empty() or pcm.size() > MAX_OUTPUT_SIZE or pcm.size() % frame_bytes != 0:
					return {"ok": false, "error": "原生 MIO 解码器返回了长度错误的 PCM 数据。"}
				else:
					var stream := AudioStreamWAV.new()
					stream.format = AudioStreamWAV.FORMAT_8_BITS if bits == 8 else AudioStreamWAV.FORMAT_16_BITS
					stream.mix_rate = rate
					stream.stereo = channels == 2
					stream.data = pcm
					return {"ok": true, "stream": stream}
			if native_result is Dictionary and not native_result.get("ok", false):
				native_error = str(native_result.get("error", "原生 MIO 解码失败。"))
	return {
		"ok": false,
		"error": native_error if not native_error.is_empty() else "未加载进程内 MIO 解码扩展。"
	}
