extends RefCounted

static func find(data: PackedByteArray, start: int, end: int, wanted: String) -> Dictionary:
	if start < 0 or end < start or end > data.size():
		return {"ok": false, "error": "Entis section 范围无效。"}
	var offset := start
	while offset < end:
		if end - offset < 16:
			return {"ok": false, "error": "Entis section 头不完整。"}
		var raw_name := data.slice(offset, offset + 8)
		var name_length := 0
		while name_length < raw_name.size() and raw_name[name_length] != 0 and raw_name[name_length] != 0x20:
			name_length += 1
		var name := raw_name.slice(0, name_length).get_string_from_ascii()
		var length := data.decode_u64(offset + 8)
		var content_start := offset + 16
		if length < 0 or length > end - content_start:
			return {"ok": false, "error": "Entis section 长度超出边界。"}
		var content_end := content_start + length
		if name == wanted:
			return {"ok": true, "start": content_start, "end": content_end}
		offset = content_end
	return {"ok": false, "error": "Entis 资源缺少 %s section。" % wanted}
