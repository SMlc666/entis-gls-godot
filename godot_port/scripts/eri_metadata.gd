extends RefCounted

const EntisSections = preload("res://scripts/entis_sections.gd")
const PREFIX_HEX := "456e7469731a0000"
const ERI_FILE_ID := 0x03000100
const HEADER_SIZE := 64
const IMAGE_INFO_MIN_SIZE := 68


static func inspect(data: PackedByteArray) -> Dictionary:
	if data.size() < HEADER_SIZE or data.slice(0, 8).hex_encode() != PREFIX_HEX:
		return {"ok": false, "error": "不是有效的 Entis 图片头。"}
	if data.decode_u32(8) != ERI_FILE_ID:
		return {"ok": false, "error": "不是 ERI 图片。"}

	var header := EntisSections.find(data, HEADER_SIZE, data.size(), "Header")
	if not header.get("ok", false):
		return header
	var info := EntisSections.find(data, header["start"], header["end"], "ImageInf")
	if not info.get("ok", false):
		return info
	var offset: int = info["start"]
	if int(info["end"]) - offset < IMAGE_INFO_MIN_SIZE:
		return {"ok": false, "error": "ERI ImageInf 信息不完整。"}

	var raw_width := data.decode_u32(offset + 16)
	var raw_height := data.decode_u32(offset + 20)
	var width := raw_width if raw_width < 0x80000000 else raw_width - 0x100000000
	var height := raw_height if raw_height < 0x80000000 else raw_height - 0x100000000
	if width == 0 or height == 0:
		return {"ok": false, "error": "ERI 图片尺寸无效。"}
	var has_reference := false
	var description := EntisSections.find(data, header["start"], header["end"], "descript")
	if description.get("ok", false):
		if int(description["end"]) - int(description["start"]) > 1024 * 1024:
			return {"ok": false, "error": "ERI 描述信息过大。"}
		var description_bytes := data.slice(description["start"], description["end"])
		var marker := "#reference-file".to_utf8_buffer()
		var utf16_marker := PackedByteArray()
		for byte in marker:
			utf16_marker.append(byte)
			utf16_marker.append(0)
		has_reference = _contains_bytes(description_bytes, marker) or _contains_bytes(description_bytes, utf16_marker)
	var frame_count := 0
	var stream := EntisSections.find(data, HEADER_SIZE, data.size(), "Stream")
	if stream.get("ok", false):
		var frame_scan := int(stream.start)
		while frame_scan + 16 <= int(stream.end):
			var raw_name := data.slice(frame_scan, frame_scan + 8)
			var name_length := 0
			while name_length < raw_name.size() and raw_name[name_length] != 0 and raw_name[name_length] != 0x20:
				name_length += 1
			var section_name := raw_name.slice(0, name_length).get_string_from_ascii()
			var section_size := data.decode_u64(frame_scan + 8)
			if section_size < 0 or section_size > int(stream.end) - frame_scan - 16:
				return {"ok": false, "error": "ERI Stream section 长度无效。"}
			if section_name == "ImageFrm":
				frame_count += 1
				if frame_count > 4096:
					return {"ok": false, "error": "ERI 帧数超过支持上限。"}
			frame_scan += 16 + int(section_size)
	if frame_count < 1:
		return {"ok": false, "error": "ERI 图片缺少图像帧。"}
	var total_time_ms := 0
	var sequence: Array[int] = []
	var file_header := EntisSections.find(data, header["start"], header["end"], "FileHdr")
	if file_header.get("ok", false) and int(file_header.end) - int(file_header.start) >= 20:
		total_time_ms = int(data.decode_u32(int(file_header.start) + 16))
	var sequence_section := EntisSections.find(data, stream["start"], stream["end"], "Sequence")
	if sequence_section.get("ok", false):
		var sequence_bytes := int(sequence_section.end) - int(sequence_section.start)
		if sequence_bytes % 8 != 0 or sequence_bytes > 8 * 100000:
			return {"ok": false, "error": "ERI Sequence table 长度无效。"}
		for sequence_offset in range(int(sequence_section.start), int(sequence_section.end), 8):
			var frame_index := int(data.decode_u32(sequence_offset))
			var duration := int(data.decode_u32(sequence_offset + 4))
			if frame_index >= frame_count or duration > 100000:
				return {"ok": false, "error": "ERI Sequence table 内容无效。"}
			if sequence.size() + duration > 1000000:
				return {"ok": false, "error": "ERI Sequence 展开长度超过支持上限。"}
			for _step in duration:
				sequence.append(frame_index)
	else:
		for frame_index in frame_count:
			sequence.append(frame_index)
	if sequence.is_empty():
		for frame_index in frame_count:
			sequence.append(frame_index)
	return {
		"ok": true,
		"version": data.decode_u32(offset),
		"transformation": data.decode_u32(offset + 4),
		"architecture": data.decode_u32(offset + 8),
		"format": data.decode_u32(offset + 12),
		"width": absi(width),
		"height": absi(height),
		"frame_count": frame_count,
		"frame_sequence": sequence,
		"total_time_ms": total_time_ms,
		"bottom_up": height > 0,
		"bit_depth": data.decode_u32(offset + 24),
		"blocking_degree": data.decode_u32(offset + 52),
		"has_reference": has_reference,
	}


static func _contains_bytes(data: PackedByteArray, pattern: PackedByteArray) -> bool:
	if pattern.is_empty() or pattern.size() > data.size():
		return false
	for start in range(data.size() - pattern.size() + 1):
		var matches := true
		for index in range(pattern.size()):
			if data[start + index] != pattern[index]:
				matches = false
				break
		if matches:
			return true
	return false
