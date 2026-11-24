extends RefCounted
class_name NoaArchive

const ErisanDecoder = preload("res://scripts/erisan_decoder.gd")
const Cp932Decoder = preload("res://scripts/cp932_decoder.gd")

const HEADER_PREFIX_HEX := "456e7469731a0000"
const HEADER_FILE_ID := 0x02000400
const HEADER_MARKER := "ERISA-Archive file"
const HEADER_SIZE := 0x40
const MAX_ENTRY_COUNT := 1_000_000
const MAX_VARIABLE_FIELD_SIZE := 1_048_576
const MAX_ENTRY_READ_SIZE := 128 * 1024 * 1024

var archive_path := ""
var archive_size := 0
var entries: Array[Dictionary] = []
var section_names: Array[String] = []
var last_error := ""
var _index_ready := false


func inspect(path: String) -> Dictionary:
	archive_path = path
	archive_size = 0
	entries.clear()
	section_names.clear()
	last_error = ""
	_index_ready = false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法打开文件：%s" % error_string(FileAccess.get_open_error()))
	file.big_endian = false
	archive_size = file.get_length()
	if archive_size < HEADER_SIZE:
		return _failure("文件短于 NOA 头部。")

	if file.get_buffer(8).hex_encode() != HEADER_PREFIX_HEX:
		return _failure("文件头不是 Entis NOA。")
	var file_id := file.get_32()
	file.get_32() # reserved
	var marker_bytes := file.get_buffer(40)
	if marker_bytes.size() != 40:
		return _failure("NOA 头部不完整。")
	var marker_length := 0
	while marker_length < marker_bytes.size() and marker_bytes[marker_length] != 0:
		marker_length += 1
	var marker := marker_bytes.slice(0, marker_length).get_string_from_ascii()
	if file_id != HEADER_FILE_ID or not marker.begins_with(HEADER_MARKER):
		return _failure("Entis 头部标识不匹配。")

	file.seek(HEADER_SIZE)
	while file.get_position() < archive_size:
		var section_base := file.get_position()
		if archive_size - section_base < 16:
			return _failure("归档末尾有不完整的 section 头。")

		var section_name_bytes := file.get_buffer(8)
		var section_name := _decode_section_name(section_name_bytes)
		var section_size := file.get_64()
		var section_data_offset := file.get_position()
		if section_size < 0 or section_size > archive_size - section_data_offset:
			return _failure("section '%s' 的长度越过文件末尾。" % section_name)
		var section_end := section_data_offset + section_size
		section_names.append(section_name)

		if section_name == "DirEntry":
			if not _read_directory_section(file, section_base, section_data_offset, section_end):
				return _failure(last_error)

		file.seek(section_end)

	_index_ready = true
	return {
		"ok": true,
		"entry_count": entries.size(),
		"section_count": section_names.size(),
		"sections": section_names.duplicate(),
		"archive_size": archive_size,
	}


func read_payload_header(entry_index: int) -> Dictionary:
	if not _index_ready:
		return {"ok": false, "error": "请先成功读取归档索引。"}
	if entry_index < 0 or entry_index >= entries.size():
		return {"ok": false, "error": "条目索引超出范围。"}
	var entry: Dictionary = entries[entry_index]
	if entry.get("kind", "") != "file":
		return {"ok": false, "error": "所选条目不是普通文件。"}
	var offset: int = entry.get("payload_offset", -1)
	if offset < 0 or offset > archive_size - 16:
		return {"ok": false, "error": "条目数据偏移越过文件末尾。"}

	var file := FileAccess.open(archive_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法重新打开归档文件。"}
	if file.get_length() != archive_size:
		return {"ok": false, "error": "归档大小已变化，请重新读取索引。"}
	file.big_endian = false
	file.seek(offset)
	var magic := file.get_buffer(8).get_string_from_ascii()
	var stored_size := file.get_64()
	if stored_size < 0 or stored_size > archive_size - offset - 16:
		return {"ok": false, "error": "条目数据长度超出归档范围。"}
	return {
		"ok": true,
		"magic": magic,
		"stored_size": stored_size,
		"matches_filedata": magic == "filedata",
	}


func read_entry(entry_index: int, max_bytes: int = MAX_ENTRY_READ_SIZE) -> Dictionary:
	if not _index_ready:
		return {"ok": false, "error": "请先成功读取归档索引。"}
	if entry_index < 0 or entry_index >= entries.size():
		return {"ok": false, "error": "条目索引超出范围。"}
	var entry: Dictionary = entries[entry_index]
	if entry.get("kind", "") != "file":
		return {"ok": false, "error": "所选条目不是普通文件。"}
	var encoding: int = entry.get("encoding_flags", 0)
	if encoding != 0 and encoding != 0x80000010:
		return {"ok": false, "error": "此条目使用了尚未支持的 NOA 压缩或加密（0x%08X）。" % encoding}
	var size: int = entry.get("unpacked_size", -1)
	if max_bytes < 0 or size < 0 or size > max_bytes or size > MAX_ENTRY_READ_SIZE:
		return {"ok": false, "error": "条目大小超出读取上限。"}
	var header := read_payload_header(entry_index)
	if not header.get("ok", false):
		return header
	if not header.get("matches_filedata", false):
		return {"ok": false, "error": "条目缺少 filedata 标记。"}
	var stored_size: int = header["stored_size"]
	if encoding == 0 and stored_size < size:
		return {"ok": false, "error": "条目数据比索引中声明的长度短。"}
	if stored_size > MAX_ENTRY_READ_SIZE:
		return {"ok": false, "error": "条目存储大小超出读取上限。"}
	var file := FileAccess.open(archive_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法重新打开归档文件。"}
	if file.get_length() != archive_size:
		return {"ok": false, "error": "归档大小已变化，请重新读取索引。"}
	file.seek(int(entry["payload_offset"]) + 16)
	var read_size := size if encoding == 0 else stored_size
	var data := file.get_buffer(read_size)
	if data.size() != read_size:
		return {"ok": false, "error": "条目数据读取不完整。"}
	if encoding == 0x80000010:
		return ErisanDecoder.decode(data, size)
	return {"ok": true, "data": data}


func _read_directory_section(file: FileAccess, section_base: int, data_offset: int, section_end: int) -> bool:
	file.seek(data_offset)
	if section_end - file.get_position() < 4:
		last_error = "DirEntry section 缺少条目数量。"
		return false

	var entry_count := file.get_32()
	if entry_count < 0 or entry_count > MAX_ENTRY_COUNT:
		last_error = "DirEntry 条目数量不合理：%d" % entry_count
		return false

	for _index in range(entry_count):
		if section_end - file.get_position() < 40:
			last_error = "DirEntry 条目超出 section 边界。"
			return false

		var unpacked_size := file.get_64()
		var flags := file.get_32()
		var encoding_flags := file.get_32()
		var relative_offset := file.get_64()
		file.get_buffer(8) # timestamp/reserved fields
		var extra_size := file.get_32()

		if extra_size < 0 or extra_size > MAX_VARIABLE_FIELD_SIZE:
			last_error = "DirEntry 扩展字段长度不合理：%d" % extra_size
			return false
		if (flags & 0x70) != 0:
			if extra_size > section_end - file.get_position():
				last_error = "DirEntry 扩展字段越过 section 边界。"
				return false
			file.seek(file.get_position() + extra_size)

		if section_end - file.get_position() < 4:
			last_error = "DirEntry 缺少文件名长度。"
			return false
		var name_size := file.get_32()
		if name_size < 0 or name_size > MAX_VARIABLE_FIELD_SIZE:
			last_error = "DirEntry 文件名长度不合理：%d" % name_size
			return false
		if name_size > section_end - file.get_position():
			last_error = "DirEntry 文件名越过 section 边界。"
			return false

		var raw_name := file.get_buffer(name_size)
		var nul_index := raw_name.find(0)
		if nul_index >= 0:
			raw_name = raw_name.slice(0, nul_index)
		var name := _decode_entry_name(raw_name)
		var kind := _entry_kind(flags)
		if kind == "file" or kind == "directory":
			entries.append({
				"name": name,
				"kind": kind,
				"flags": flags,
				"encoding_flags": encoding_flags,
				"unpacked_size": unpacked_size,
				"payload_offset": section_base + relative_offset,
			})

	return true


func _entry_kind(flags: int) -> String:
	if flags == 0x10:
		return "directory"
	if flags == 0x20 or flags == 0x40:
		return "control"
	return "file"


func _decode_section_name(raw: PackedByteArray) -> String:
	var name_length := 0
	while name_length < raw.size() and raw[name_length] != 0 and raw[name_length] != 0x20:
		name_length += 1
	return raw.slice(0, name_length).get_string_from_ascii()


func _decode_entry_name(raw: PackedByteArray) -> String:
	var decoded: Dictionary = Cp932Decoder.decode_to_utf8(raw)
	if decoded.get("ok", false):
		return str(decoded.get("text", ""))
	return "[Invalid CP932: %s]" % raw.hex_encode()


func _failure(message: String) -> Dictionary:
	last_error = message
	_index_ready = false
	entries.clear()
	section_names.clear()
	return {"ok": false, "error": message}
