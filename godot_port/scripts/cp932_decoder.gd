extends RefCounted
class_name Cp932Decoder

const TABLE_PATH := "res://assets/codepages/cp932.tbl"
const LEAD_BLOCKS := [[0x81, 0x9F], [0xE0, 0xFC]]
const TRAIL_COUNT := 188
const TABLE_BYTES := 60 * TRAIL_COUNT * 2
static var _table: PackedByteArray = PackedByteArray()


static func decode_to_utf8(input: PackedByteArray) -> Dictionary:
	if input.is_empty():
		return {"ok": true, "text": ""}
	if _table.is_empty():
		_table = FileAccess.get_file_as_bytes(TABLE_PATH)
	if _table.size() != TABLE_BYTES:
		return {"ok": false, "error": "CP932 字符映射表缺失或长度错误。"}

	var output := PackedByteArray()
	var offset := 0
	while offset < input.size():
		var first := int(input[offset])
		if first <= 0x7F:
			output.append(first)
			offset += 1
			continue
		if first >= 0xA1 and first <= 0xDF:
			var halfwidth_codepoint := 0xFF61 + first - 0xA1
			output.append_array(String.chr(halfwidth_codepoint).to_utf8_buffer())
			offset += 1
			continue
		if first == 0x80 or first == 0xA0 or first >= 0xFD:
			var extension_codepoint := _decode_cp932_single_extension(first)
			if extension_codepoint == 0:
				return {"ok": false, "error": "CP932 含未映射的单字节 0x%02X (offset %d)。" % [first, offset]}
			output.append_array(String.chr(extension_codepoint).to_utf8_buffer())
			offset += 1
			continue

		if offset + 1 >= input.size():
			return {"ok": false, "error": "CP932 末尾有不完整的双字节字符。"}
		var table_index := _table_index(first, int(input[offset + 1]))
		if table_index < 0:
			return {"ok": false, "error": "CP932 字节序列无效: 0x%02X 0x%02X (offset %d)。" % [first, input[offset + 1], offset]}
		var mapping_offset := table_index * 2
		var codepoint := int(_table[mapping_offset]) | (int(_table[mapping_offset + 1]) << 8)
		if codepoint == 0:
			return {"ok": false, "error": "CP932 码位未映射: 0x%02X 0x%02X (offset %d)。" % [first, input[offset + 1], offset]}
		output.append_array(String.chr(codepoint).to_utf8_buffer())
		offset += 2

	return {"ok": true, "text": output.get_string_from_utf8()}


static func _table_index(lead: int, trail: int) -> int:
	if not ((lead >= 0x81 and lead <= 0x9F) or (lead >= 0xE0 and lead <= 0xFC)):
		return -1
	if trail < 0x40 or trail > 0xFC or trail == 0x7F:
		return -1
	var lead_index := lead - 0x81 if lead <= 0x9F else 31 + lead - 0xE0
	var trail_index := trail - 0x40 if trail <= 0x7E else 63 + trail - 0x80
	return lead_index * TRAIL_COUNT + trail_index


static func _decode_cp932_single_extension(value: int) -> int:
	match value:
		0x80: return 0x0080
		0xA0: return 0xF8F0
		0xFD: return 0xF8F1
		0xFE: return 0xF8F2
		0xFF: return 0xF8F3
		_: return 0
