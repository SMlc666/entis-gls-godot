extends RefCounted
class_name CsxBytecode

# Cotopha image instruction encoding; offsets are relative to the image section.
const OPCODES := ["new", "free", "load", "store", "enter", "leave", "jump", "cjump", "call", "return", "element", "element_indirect", "operate", "unary", "compare"]
const TYPES := ["object", "reference", "array", "hash", "integer", "real", "string"]
const MAX_STRING_UNITS := 65536
const MAX_ARGUMENTS := 4096
const MAX_IMAGE_SIZE := 67108864
const MAX_IMAGE_INSTRUCTIONS := 10000000
const MAX_INSTRUCTIONS_PER_BATCH := 10000

var _data := PackedByteArray()
var _pos := 0
var _error := ""
var _conststr_references: Array[int] = []


func decode(data: PackedByteArray, address: int, limit: int = 32) -> Dictionary:
	_data = data
	_pos = address
	_error = ""
	_conststr_references.clear()
	var instructions: Array[Dictionary] = []
	if address < 0 or address >= data.size() or limit < 1 or limit > 10000:
		return {"ok": false, "error": "指令地址或数量无效。", "instructions": instructions}
	for _i in range(limit):
		if _pos >= _data.size():
			break
		var start := _pos
		var code := _u8()
		if code >= OPCODES.size():
			_error = "未知指令 0x%02X" % code
		else:
			var operands: Dictionary = {}
			match code:
				0:
					operands["mode"] = _u8()
					operands["type"] = _type()
					if int(operands["mode"]) > 2:
						_error = "new 指令的存储模式无效。"
					operands["class"] = _class_name(operands["type"])
					operands["name"] = _string()
				2:
					operands["mode"] = _u8()
					if int(operands["mode"]) > 4:
						_error = "load 指令的存储模式无效。"
					operands["value"] = _immediate()
				3, 9, 12, 13, 14:
					operands["kind"] = _u8()
				4:
					operands["name"] = _string()
					var count := _i32()
					if count == -1:
						operands["exception_marker"] = _u8()
						operands["relative"] = _i32()
						operands["target"] = _pos + int(operands["relative"])
					elif count < 0 or count > MAX_ARGUMENTS:
						_error = "参数数量无效。"
					else:
						var args: Array[Dictionary] = []
						for _arg in range(count):
							var type := _type()
							args.append({"type": type, "class": _class_name(type), "name": _string()})
							if not _error.is_empty():
								break
						operands["args"] = args
				6, 7:
					if code == 7:
						operands["condition"] = _u8()
					operands["relative"] = _i32()
					operands["target"] = _pos + int(operands["relative"])
				8:
					operands["mode"] = _u8()
					operands["argc"] = _i32()
					if int(operands["mode"]) > 5:
						_error = "call 指令的调用模式无效。"
					if (int(operands["argc"]) < 0 or
					int(operands["argc"]) > MAX_ARGUMENTS):
						_error = "call 指令的参数数量无效。"
					operands["name"] = _string()
					if operands["mode"] == 0:
						operands["throw_marker"] = _u16()
				10:
					operands["value"] = _immediate()
			if _error.is_empty():
				instructions.append({"address": start, "size": _pos - start, "opcode": code, "name": OPCODES[code], "operands": operands})
		if not _error.is_empty():
			return {"ok": false, "error": "%s（image + 0x%X）" % [_error, start], "instructions": instructions, "conststr_references": _conststr_references.duplicate()}
	return {"ok": true, "instructions": instructions, "next_address": _pos, "conststr_references": _conststr_references.duplicate()}


func validate_image(data: PackedByteArray, conststr_count: int = -1) -> Dictionary:
	if data.is_empty() or data.size() > MAX_IMAGE_SIZE:
		return {"ok": false, "error": "image 区段为空或超过大小上限。"}

	var starts := PackedInt32Array()
	var branch_targets := PackedInt32Array()
	var conststr_references: Array[int] = []
	var address := 0
	while address < data.size():
		var decoded := decode(data, address, MAX_INSTRUCTIONS_PER_BATCH)
		if not decoded.get("ok", false):
			return {"ok": false, "error": decoded.get("error", "image 指令无效。")}
		var instructions: Array = decoded.get("instructions", [])
		if instructions.is_empty():
			return {"ok": false, "error": "image 校验未取得进展（image + 0x%X）。" % address}
		for instruction in instructions:
			starts.append(int(instruction["address"]))
			if starts.size() > MAX_IMAGE_INSTRUCTIONS:
				return {"ok": false, "error": "image 指令数量超过上限。"}
			var operands: Dictionary = instruction["operands"]
			if operands.has("target"):
				branch_targets.append(int(operands["target"]))
		conststr_references.append_array(decoded.get("conststr_references", []))
		var next_address := int(decoded.get("next_address", address))
		if next_address <= address or next_address > data.size():
			return {"ok": false, "error": "image 指令边界无效（image + 0x%X）。" % address}
		address = next_address

	for target in branch_targets:
		if target < 0 or target >= data.size() or not _contains_address(starts, target):
			return {"ok": false, "error": "分支目标不是有效指令边界（image + 0x%X）。" % target}
	if conststr_count >= 0:
		for index in conststr_references:
			if index < 0 or index >= conststr_count:
				return {"ok": false, "error": "conststr 索引超出范围：%d（共 %d 项）。" % [index, conststr_count]}
	return {"ok": true, "instruction_starts": starts, "conststr_references": conststr_references}


func _contains_address(addresses: PackedInt32Array, target: int) -> bool:
	var low := 0
	var high := addresses.size() - 1
	while low <= high:
		var middle := (low + high) >> 1
		var candidate := addresses[middle]
		if candidate == target:
			return true
		if candidate < target:
			low = middle + 1
		else:
			high = middle - 1
	return false


func _take(size: int) -> PackedByteArray:
	if size < 0 or _pos < 0 or size > _data.size() - _pos:
		_error = "指令数据不完整。"
		return PackedByteArray()
	var bytes := _data.slice(_pos, _pos + size)
	_pos += size
	return bytes


func _u8() -> int:
	var b := _take(1)
	return b[0] if b.size() == 1 else 0


func _u16() -> int:
	var b := _take(2)
	return b.decode_u16(0) if b.size() == 2 else 0


func _i32() -> int:
	var b := _take(4)
	return b.decode_s32(0) if b.size() == 4 else 0


func _type() -> int:
	var value := _u8()
	if value >= TYPES.size() and _error.is_empty():
		_error = "未知数据类型 %d。" % value
	return value


func _string() -> Variant:
	var count := _i32()
	if count == -2147483648:
		var index := _i32()
		if index < 0:
			_error = "conststr 索引无效。"
		else:
			_conststr_references.append(index)
		return {"reference_marker": count, "index": index}
	if count < 0:
		_error = "字符串长度标记无效。"
		return ""
	if count > MAX_STRING_UNITS:
		_error = "字符串过长。"
		return ""
	var bytes := _take(count * 2)
	return bytes.get_string_from_utf16() if bytes.size() == count * 2 else ""


func _class_name(type: int) -> Variant:
	if type == 0:
		return _string()
	return TYPES[type] if type >= 0 and type < TYPES.size() else "?"


func _immediate() -> Dictionary:
	var type := _type()
	var result := {"type": type}
	match type:
		4:
			result["value"] = _i32()
		5:
			var bytes := _take(8)
			result["value"] = bytes.decode_double(0) if bytes.size() == 8 else 0.0
		6:
			result["value"] = _string()
		_:
			result["class"] = _class_name(type)
	return result
