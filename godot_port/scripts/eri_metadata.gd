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
	return {
		"ok": true,
		"version": data.decode_u32(offset),
		"transformation": data.decode_u32(offset + 4),
		"architecture": data.decode_u32(offset + 8),
		"format": data.decode_u32(offset + 12),
		"width": absi(width),
		"height": absi(height),
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
