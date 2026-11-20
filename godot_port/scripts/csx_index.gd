extends RefCounted
class_name CsxIndex

const HEADER_SIZE := 64
const MAX_FUNCTIONS := 100_000
const MAX_NAME_UNITS := 65_536

var functions: Array[Dictionary] = []
var sections: Array[Dictionary] = []
var prologue_addresses: Array[int] = []
var epilogue_addresses: Array[int] = []
var global_variables: Array[Dictionary] = []
var data_variables: Array[Dictionary] = []
var last_error := ""


func inspect(path: String) -> Dictionary:
	functions.clear()
	sections.clear()
	prologue_addresses.clear()
	epilogue_addresses.clear()
	global_variables.clear()
	data_variables.clear()
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法打开 CSX：%s" % error_string(FileAccess.get_open_error()))
	file.big_endian = false
	var total_size := file.get_length()
	if total_size < HEADER_SIZE:
		return _failure("CSX 文件头不完整。")
	if file.get_buffer(8).hex_encode() != "456e7469731a0000":
		return _failure("文件头不是 Entis 格式。")
	if file.get_32() != 0xffffffff or file.get_32() != 0:
		return _failure("CSX 文件标识不匹配。")
	var marker_bytes := file.get_buffer(40)
	if marker_bytes.slice(0, 18).get_string_from_ascii() != "Cotopha Image file":
		return _failure("文件不是 Cotopha Image。")
	var declared_size := file.get_32()
	if file.get_32() != 0 or declared_size > total_size - HEADER_SIZE:
		return _failure("CSX 声明的内容长度无效。")
	var content_end := HEADER_SIZE + declared_size
	var found_function := false
	while file.get_position() < content_end:
		if content_end - file.get_position() < 16:
			return _failure("CSX section 头不完整。")
		var raw_name := file.get_buffer(8)
		var name := raw_name.get_string_from_ascii().strip_edges()
		var section_size := file.get_32()
		if file.get_32() != 0:
			return _failure("CSX section 保留字段不为零。")
		var section_start := file.get_position()
		if section_size > content_end - section_start:
			return _failure("CSX section 超出声明范围：%s" % name)
		var section_end := section_start + section_size
		sections.append({"name": name, "offset": section_start, "size": section_size})
		if name == "function":
			if found_function:
				return _failure("CSX 包含多个 function section。")
			found_function = true
			if not _read_functions(file, section_end):
				return _failure(last_error)
		elif name == "global":
			if not _read_globals(file, section_end):
				return _failure(last_error)
		elif name == "data":
			if not _read_data(file, section_end):
				return _failure(last_error)
		file.seek(section_end)
	if not found_function:
		return _failure("CSX 缺少 function section。")
	return {
		"ok": true,
		"functions": functions.size(),
		"prologues": prologue_addresses.size(),
		"epilogues": epilogue_addresses.size(),
		"globals": global_variables.size(),
		"data": data_variables.size(),
		"sections": sections.duplicate(true),
		"declared_size": declared_size,
		"trailing_bytes": total_size - content_end,
	}


func _read_functions(file: FileAccess, section_end: int) -> bool:
	if not _read_addresses(file, section_end, prologue_addresses):
		return false
	if not _read_addresses(file, section_end, epilogue_addresses):
		return false
	if section_end - file.get_position() < 4:
		last_error = "CSX 函数表缺少函数数量。"
		return false
	var count := file.get_32()
	if count > MAX_FUNCTIONS:
		last_error = "CSX 函数数量超出上限。"
		return false
	for _index in range(count):
		if section_end - file.get_position() < 8:
			last_error = "CSX 函数表不完整。"
			return false
		var address := file.get_32()
		var name_length := file.get_32()
		var name := ""
		if name_length >= 0x80000000:
			if section_end - file.get_position() < 4:
				last_error = "CSX 常量字符串引用不完整。"
				return false
			name = "[conststr #%d]" % file.get_32()
		else:
			if name_length > MAX_NAME_UNITS or name_length * 2 > section_end - file.get_position():
				last_error = "CSX 函数名长度无效。"
				return false
			var raw_name := file.get_buffer(name_length * 2)
			name = raw_name.get_string_from_utf16()
			if name_length > 0 and name.is_empty():
				last_error = "CSX 函数名不是有效 UTF-16。"
				return false
		functions.append({"name": name, "address": address})
	return true


func _read_addresses(file: FileAccess, section_end: int, target: Array[int]) -> bool:
	if section_end - file.get_position() < 4:
		last_error = "CSX 函数地址表不完整。"
		return false
	var count := file.get_32()
	if count > MAX_FUNCTIONS or count * 4 > section_end - file.get_position():
		last_error = "CSX 函数地址数量无效。"
		return false
	for _index in range(count):
		target.append(file.get_32())
	return true


func _read_string(file: FileAccess, section_end: int) -> Variant:
	if section_end - file.get_position() < 4:
		last_error = "CSX 字符串长度不完整。"
		return null
	var length := file.get_32()
	if length >= 0x80000000:
		if section_end - file.get_position() < 4:
			last_error = "CSX 常量字符串索引不完整。"
			return null
		return "[conststr #%d]" % file.get_32()
	if length * 2 > section_end - file.get_position() or length > MAX_NAME_UNITS:
		last_error = "CSX 字符串超出范围。"
		return null
	var raw := file.get_buffer(length * 2)
	return raw.get_string_from_utf16()


func _read_object_desc(file: FileAccess, section_end: int) -> Variant:
	if section_end - file.get_position() < 4:
		last_error = "CSX 对象类型头不完整。"
		return null
	var type_code := file.get_32()
	match type_code:
		0:
			var cname = _read_string(file, section_end)
			if cname == null:
				return null
			return {"type": "object", "class": cname}
		1:
			return {"type": "reference"}
		2:
			if section_end - file.get_position() < 4:
				last_error = "CSX 数组长度不完整。"
				return null
			var count := file.get_32()
			var items: Array[Dictionary] = []
			for _i in range(count):
				var item = _read_object_desc(file, section_end)
				if item == null:
					return null
				items.append(item)
			return {"type": "array", "items": items}
		3:
			return {"type": "hash"}
		4:
			if section_end - file.get_position() < 4:
				last_error = "CSX 整数值不完整。"
				return null
			return {"type": "integer", "value": file.get_32()}
		5:
			if section_end - file.get_position() < 8:
				last_error = "CSX 实数值不完整。"
				return null
			var buf := file.get_buffer(8)
			return {"type": "real", "value": buf.decode_double(0)}
		6:
			var s = _read_string(file, section_end)
			if s == null:
				return null
			return {"type": "string", "value": s}
		_:
			last_error = "CSX 未知变量类型: %d" % type_code
			return null


func _read_globals(file: FileAccess, section_end: int) -> bool:
	if section_end - file.get_position() < 4:
		last_error = "CSX global 区段缺少变量数量。"
		return false
	var count := file.get_32()
	if count > MAX_FUNCTIONS:
		last_error = "CSX global 变量数量超出上限。"
		return false
	for _i in range(count):
		var name = _read_string(file, section_end)
		if name == null:
			return false
		var obj = _read_object_desc(file, section_end)
		if obj == null:
			return false
		global_variables.append({"name": name, "value": obj})
	return true


func _read_data(file: FileAccess, section_end: int) -> bool:
	if section_end - file.get_position() < 4:
		last_error = "CSX data 区段缺少变量数量。"
		return false
	var count := file.get_32()
	if count > MAX_FUNCTIONS:
		last_error = "CSX data 变量数量超出上限。"
		return false
	for _i in range(count):
		var name = _read_string(file, section_end)
		if name == null:
			return false
		if section_end - file.get_position() < 4:
			last_error = "CSX data 变量长度不完整。"
			return false
		var dlen := file.get_32()
		if (dlen & 0x80000000) == 0:
			var fields: Array[Dictionary] = []
			for _j in range(dlen):
				var tag = _read_string(file, section_end)
				if tag == null:
					return false
				var obj = _read_object_desc(file, section_end)
				if obj == null:
					return false
				fields.append({"tag": tag, "value": obj})
			data_variables.append({"name": name, "type": "group", "fields": fields})
		else:
			var obj = _read_object_desc(file, section_end)
			if obj == null:
				return false
			data_variables.append({"name": name, "type": obj.get("type", "unknown"), "value": obj})
	return true


func _failure(message: String) -> Dictionary:
	last_error = message
	functions.clear()
	sections.clear()
	prologue_addresses.clear()
	epilogue_addresses.clear()
	global_variables.clear()
	data_variables.clear()
	return {"ok": false, "error": message}
