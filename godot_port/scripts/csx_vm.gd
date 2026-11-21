extends RefCounted
class_name CsxVM

const CsxIndexReader = preload("res://scripts/csx_index.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxBytecodeReader = preload("res://scripts/csx_bytecode.gd")

const MAX_CONSTSTR_ENTRIES := 1000000
const MAX_CONSTSTR_SECTION_BYTES := 67108864
const MAX_VM_EVAL_STACK := 65536
const MAX_VM_CALL_ARGUMENTS := 4096
const MAX_VM_CALL_DEPTH := 1000
const MAX_VM_LOCALS := 65536
const MAX_VM_BLOCK_DEPTH := 4096
const MAX_VM_OBJECT_FIELDS := 65536
const MAX_VM_ARRAY_ENTRIES := 65536
const MAX_SYNC_STEPS := 10000000

const OPCODES := ["new", "free", "load", "store", "enter", "leave", "jump", "cjump", "call", "return", "element", "element_indirect", "operate", "unary", "compare"]
const TYPES := ["object", "reference", "array", "hash", "integer", "real", "string"]


class CsxRef extends RefCounted:
	const MAX_ARRAY_INDEX := 65535
	const MAX_FIELD_INDEX := 65535
	const MAX_DICTIONARY_ENTRIES := 65536
	var container: Variant
	var key: Variant
	var is_declaration: bool = false

	func _init(p_container: Variant = null, p_key: Variant = null, p_is_decl: bool = false) -> void:
		container = p_container
		key = p_key
		is_declaration = p_is_decl

	func get_value() -> Variant:
		if container == null:
			return null
		if container is Dictionary:
			return container.get(key, null)
		elif container is Array:
			var idx := int(key)
			if idx >= 0 and idx < container.size():
				return container[idx]
			return null
		elif container is CsxInstance:
			var inst := container as CsxInstance
			if key is int:
				return inst.get_field_by_index(int(key))
			return inst.get_field(str(key))
		elif container is CsxHostClass.HostResourceManager:
			var r: Variant = (container as CsxHostClass.HostResourceManager).get_resource(str(key))
			if r != null:
				return r
			return (container as CsxHostClass.HostResourceManager).fields.get(key, null)
		elif container is CsxHostClass.HostSprite:
			return (container as CsxHostClass.HostSprite).fields.get(key, null)
		elif container is CsxHostClass.HostWindow:
			return (container as CsxHostClass.HostWindow).fields.get(key, null)
		return null

	func set_value(val: Variant) -> bool:
		if container == null:
			return false
		if container is Dictionary:
			if not container.has(key) and container.size() >= MAX_DICTIONARY_ENTRIES:
				return false
			container[key] = val
		elif container is Array:
			var idx := int(key)
			if idx < 0 or (idx >= container.size() and idx > MAX_ARRAY_INDEX):
				return false
			if idx >= 0:
				while container.size() <= idx:
					container.append(null)
				container[idx] = val
		elif container is CsxInstance:
			var inst := container as CsxInstance
			if key is int:
				return inst.set_field_by_index(int(key), val)
			else:
				inst.set_field(str(key), val)
		elif container is CsxHostClass.HostResourceManager:
			var manager_fields := (container as CsxHostClass.HostResourceManager).fields
			if not _set_dictionary_value(manager_fields, key, val): return false
		elif container is CsxHostClass.HostSprite:
			var sprite_fields := (container as CsxHostClass.HostSprite).fields
			if not _set_dictionary_value(sprite_fields, key, val): return false
		elif container is CsxHostClass.HostWindow:
			var window_fields := (container as CsxHostClass.HostWindow).fields
			if not _set_dictionary_value(window_fields, key, val): return false
		return true

	func _set_dictionary_value(target: Dictionary, field_key: Variant, value: Variant) -> bool:
		if not target.has(field_key) and target.size() >= MAX_DICTIONARY_ENTRIES:
			return false
		target[field_key] = value
		return true


class CsxInstance extends RefCounted:
	const MAX_FIELD_INDEX := 65535
	const MAX_FIELDS := 65536
	var type_name: String
	var fields: Dictionary = {}
	var field_names: Array[String] = []

	func _init(p_type_name: String) -> void:
		type_name = p_type_name

	func get_field(name: String) -> Variant:
		return fields.get(name, null)

	func get_field_by_index(idx: int) -> Variant:
		if idx >= 0 and idx < field_names.size():
			return fields.get(field_names[idx], null)
		return null

	func set_field(name: String, val: Variant) -> bool:
		if not fields.has(name):
			if fields.size() >= MAX_FIELDS:
				return false
			field_names.append(name)
		fields[name] = val
		return true

	func set_field_by_index(idx: int, val: Variant) -> bool:
		if idx < 0 or idx > MAX_FIELD_INDEX:
			return false
		if idx >= 0 and idx < field_names.size():
			fields[field_names[idx]] = val
		else:
			while field_names.size() <= idx:
				field_names.append("__f_%d" % field_names.size())
			fields[field_names[idx]] = val
		return true

	func has_field(name: String) -> bool:
		return fields.has(name)


class StackFrame extends RefCounted:
	const MAX_LOCALS := 65536
	var name: String
	var return_ip: int = -1
	var locals: Dictionary = {}
	var local_order: Array[String] = []
	var this_obj: Variant = null
	var catch_target: int = -1
	var block_depth: int = 0
	var block_locals: Array[int] = []
	var last_new_var_name: String = ""
	var last_new_stack_size: int = -1

	func _init(p_name: String, p_return_ip: int = -1, p_this: Variant = null) -> void:
		name = p_name
		return_ip = p_return_ip
		this_obj = p_this

	func add_local(var_name: String, val: Variant) -> bool:
		if local_order.size() >= MAX_LOCALS:
			return false
		locals[var_name] = val
		local_order.append(var_name)
		return true

	func set_local(var_name: String, val: Variant) -> void:
		locals[var_name] = val

	func get_local(var_name: String) -> Variant:
		return locals.get(var_name, null)

	func get_local_by_index(idx: int) -> Variant:
		if idx >= 0 and idx < local_order.size():
			return locals.get(local_order[idx], null)
		return null


static func is_truthy(val: Variant) -> bool:
	if val == null:
		return false
	if val is bool:
		return val
	if val is int or val is float:
		return val != 0
	if val is String:
		return not val.is_empty()
	if val is Array or val is Dictionary:
		return not val.is_empty()
	return true


var _image := PackedByteArray()
var image: PackedByteArray:
	get:
		return _image
	set(value):
		_image = value
		instruction_starts = PackedInt32Array()
		_image_validation_attempted = false
		_image_validation_error = ""
var const_strings: Array[String] = []
var instruction_starts := PackedInt32Array()
var bytecode_decoder := CsxBytecodeReader.new()
var _image_validation_attempted: bool = false
var _image_validation_error: String = ""
var functions: Dictionary = {} # name -> int (address)
var functions_lower: Dictionary = {} # lowercase name -> int (address)
var prologues: Array[int] = []
var global_vars: Array[Dictionary] = [] # index -> { "name": ..., "value": ... }
var globals_by_name: Dictionary = {} # name -> value
var data_vars: Array[Dictionary] = [] # index -> { "name": ..., "value": ... }
var data_by_name: Dictionary = {} # name -> value

var ip: int = 0
var eval_stack: Array = []
var call_stack: Array[StackFrame] = []
var pending_call_args: Array = []
var pending_return_ip: int = -1
var is_halted: bool = true
var is_synchronous_call: bool = false
var last_return_value: Variant = null
var last_error := ""
var executed_instructions: int = 0
var max_call_depth: int = 1000

var host: CsxHostClass


func _init(p_host: CsxHostClass = null) -> void:
	if p_host != null:
		host = p_host
	else:
		host = CsxHostClass.new()


func load_csx(path: String) -> Dictionary:
	last_error = ""
	image = PackedByteArray()
	const_strings.clear()
	instruction_starts = PackedInt32Array()
	functions.clear()
	functions_lower.clear()
	prologues.clear()
	global_vars.clear()
	globals_by_name.clear()
	data_vars.clear()
	data_by_name.clear()
	var idx := CsxIndexReader.new()
	var inspected: Dictionary = idx.inspect(path)
	if not inspected.get("ok", false):
		last_error = inspected.get("error", "无法读取 CSX 索引。")
		return {"ok": false, "error": last_error}

	var image_section: Dictionary = {}
	for sec in idx.sections:
		if sec["name"] == "image":
			image_section = sec
			break
	if image_section.is_empty():
		last_error = "CSX 缺少 image 区段。"
		return {"ok": false, "error": last_error}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法读取 CSX 内容: %s" % error_string(FileAccess.get_open_error())
		return {"ok": false, "error": last_error}
	file.seek(image_section["offset"])
	image = file.get_buffer(image_section["size"])
	if image.size() != int(image_section["size"]):
		last_error = "CSX image 区段读取不完整。"
		return {"ok": false, "error": last_error}
	var conststr_section: Dictionary = {}
	for sec in idx.sections:
		if sec["name"] == "conststr":
			conststr_section = sec
			break
	if not conststr_section.is_empty():
		var conststr_size := int(conststr_section["size"])
		if conststr_size < 4 or conststr_size > MAX_CONSTSTR_SECTION_BYTES:
			last_error = "CSX conststr 区段为空、不完整或超过大小上限。"
			return {"ok": false, "error": last_error}
		file.seek(int(conststr_section["offset"]))
		var conststr_bytes := file.get_buffer(conststr_size)
		var conststr_result := _decode_conststr_section(conststr_bytes)
		if not conststr_result.get("ok", false):
			last_error = str(conststr_result.get("error", "CSX conststr 区段无效。"))
			return {"ok": false, "error": last_error}
		const_strings = conststr_result["strings"]

	var validation: Dictionary = bytecode_decoder.validate_image(image, const_strings.size())
	if not validation.get("ok", false):
		last_error = "CSX image 验证失败：%s" % validation.get("error", "未知错误")
		_image_validation_attempted = true
		_image_validation_error = last_error
		return {"ok": false, "error": last_error}
	instruction_starts = validation["instruction_starts"]
	_image_validation_attempted = true
	_image_validation_error = ""

	functions.clear()
	functions_lower.clear()
	for fn in idx.functions:
		var fname: String = fn["name"]
		var faddr: int = fn["address"]
		if not _is_instruction_boundary(faddr):
			last_error = "函数入口不是有效指令边界：%s @ 0x%X" % [fname, faddr]
			return {"ok": false, "error": last_error}
		functions[fname] = faddr
		functions_lower[fname.to_lower()] = faddr

	prologues = idx.prologue_addresses.duplicate()
	for address in prologues:
		if not _is_instruction_boundary(address):
			last_error = "初始化入口不是有效指令边界：0x%X" % address
			return {"ok": false, "error": last_error}

	_init_storage(idx.global_variables, idx.data_variables)
	return {"ok": true, "functions": functions.size(), "prologues": prologues.size(), "globals": global_vars.size(), "data": data_vars.size()}


func _decode_conststr_section(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4:
		return {"ok": false, "error": "conststr 区段缺少字符串数量。"}
	var count := int(bytes.decode_u32(0))
	if count > MAX_CONSTSTR_ENTRIES or count > (bytes.size() - 4) / 8:
		return {"ok": false, "error": "conststr 字符串数量无效。"}
	var strings: Array[String] = []
	strings.resize(count)
	var offset := 4
	for index in range(count):
		if bytes.size() - offset < 4:
			return {"ok": false, "error": "conststr[%d] 长度不完整。" % index}
		var char_count := int(bytes.decode_u32(offset))
		offset += 4
		if char_count > CsxBytecodeReader.MAX_STRING_UNITS:
			return {"ok": false, "error": "conststr[%d] 字符串过长。" % index}
		var string_bytes := char_count * 2
		if string_bytes > bytes.size() - offset - 4:
			return {"ok": false, "error": "conststr[%d] 字符串数据不完整。" % index}
		strings[index] = bytes.slice(offset, offset + string_bytes).get_string_from_utf16()
		offset += string_bytes
		var dword_count := int(bytes.decode_u32(offset))
		offset += 4
		if dword_count > (bytes.size() - offset) / 4:
			return {"ok": false, "error": "conststr[%d] DWORD 数组不完整。" % index}
		offset += dword_count * 4
	if offset != bytes.size():
		return {"ok": false, "error": "conststr 区段包含无法识别的尾随数据。"}
	return {"ok": true, "strings": strings}


func _is_instruction_boundary(address: int) -> bool:
	var low := 0
	var high := instruction_starts.size() - 1
	while low <= high:
		var middle := (low + high) >> 1
		var candidate := instruction_starts[middle]
		if candidate == address:
			return true
		if candidate < address:
			low = middle + 1
		else:
			high = middle - 1
	return false


func _set_member_field(target: Variant, field_name: String, value: Variant) -> bool:
	if target is CsxInstance:
		return (target as CsxInstance).set_field(field_name, value)
	if target is CsxHostClass.HostSprite:
		return _set_dictionary_entry((target as CsxHostClass.HostSprite).fields, field_name, value)
	if target is CsxHostClass.HostResourceManager:
		return _set_dictionary_entry((target as CsxHostClass.HostResourceManager).fields, field_name, value)
	if target is CsxHostClass.HostWindow:
		return _set_dictionary_entry((target as CsxHostClass.HostWindow).fields, field_name, value)
	return true


func _set_dictionary_entry(target: Dictionary, key: Variant, value: Variant) -> bool:
	if not target.has(key) and target.size() >= MAX_VM_OBJECT_FIELDS:
		return false
	target[key] = value
	return true


func has_function(p_name: String) -> bool:
	return functions.has(p_name) or functions_lower.has(p_name.to_lower())


func get_function_address(p_name: String) -> int:
	if functions.has(p_name):
		return functions[p_name]
	var lk := p_name.to_lower()
	if functions_lower.has(lk):
		return functions_lower[lk]
	return -1



func _init_storage(raw_globals: Array[Dictionary], raw_data: Array[Dictionary]) -> void:
	global_vars.clear()
	globals_by_name.clear()
	data_vars.clear()
	data_by_name.clear()

	for g in raw_globals:
		var name: String = g["name"]
		var desc: Dictionary = g["value"]
		var val = _instantiate_storage_object(desc)
		var entry := {"name": name, "value": val}
		global_vars.append(entry)
		globals_by_name[name] = val

	for d in raw_data:
		var name: String = d["name"]
		var val: Variant = null
		if d.get("type", "") == "group":
			var group_dict := {}
			for field in d.get("fields", []):
				var tag: String = field.get("tag", "")
				var fdesc: Dictionary = field.get("value", {})
				group_dict[tag] = _instantiate_storage_object(fdesc)
			val = group_dict
		else:
			val = _instantiate_storage_object(d.get("value", {}))
		var entry := {"name": name, "value": val}
		data_vars.append(entry)
		data_by_name[name] = val


func _instantiate_storage_object(desc: Dictionary) -> Variant:
	var type_str: String = desc.get("type", "")
	match type_str:
		"integer":
			return int(desc.get("value", 0))
		"real":
			return float(desc.get("value", 0.0))
		"string":
			return str(desc.get("value", ""))
		"array":
			var arr: Array = []
			for item in desc.get("items", []):
				arr.append(_instantiate_storage_object(item))
			return arr
		"hash":
			return {}
		"reference":
			return null
		"object":
			var cname: String = desc.get("class", "")
			return create_object(cname)
		_:
			return null


func create_object(target_class: String) -> Variant:
	match target_class:
		"ResourceManager":
			return CsxHostClass.HostResourceManager.new(host)
		"Sprite", "SuperSprite", "MessageSprite", "MovieSprite":
			return CsxHostClass.HostSprite.new(0, host)
		"Window", "WndSpriteCmd":
			return CsxHostClass.HostWindow.new(host)
		"InputFilter":
			return CsxHostClass.HostInputFilter.new(host)
		"ToneFilter":
			return CsxHostClass.HostToneFilter.new(host)
		"Resource":
			return CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
		"File":
			return CsxHostClass.HostFile.new(host)
		"Time":
			var t := CsxInstance.new("Time")
			t.set_field("nYear", 0)
			t.set_field("nMonth", 0)
			t.set_field("nDay", 0)
			t.set_field("nWeek", 0)
			t.set_field("nHour", 0)
			t.set_field("nMinute", 0)
			t.set_field("nSecond", 0)
			t.set_field("nMilliSecond", 0)
			t.set_field("nDayOfWeek", 0)
			return t
		"Size":
			var s := CsxInstance.new("Size")
			s.set_field("w", 0)
			s.set_field("h", 0)
			return s
		"Point":
			var p := CsxInstance.new("Point")
			p.set_field("x", 0)
			p.set_field("y", 0)
			return p
		"Rect":
			var r := CsxInstance.new("Rect")
			r.set_field("left", 0)
			r.set_field("top", 0)
			r.set_field("right", 0)
			r.set_field("bottom", 0)
			return r
		_:
			var inst := CsxInstance.new(target_class)
			var ctor_name := "%s::%s" % [target_class, target_class]
			if functions.has(ctor_name):
				call_function_sync(ctor_name, [inst])
			return inst


func execute_prologues() -> Dictionary:
	var count := 0
	for addr in prologues:
		var res := call_address_sync(addr, [])
		if not res.get("ok", false):
			last_error = "初始化 prologue 失败 @ 0x%X: %s" % [addr, res.get("error", "未知错误")]
			return {"ok": false, "error": last_error, "executed": count}
		count += 1
	return {"ok": true, "executed": count}


func call_function_sync(func_name: String, args: Array, max_steps: int = 1_000_000) -> Dictionary:
	var addr := get_function_address(func_name)
	if addr < 0:
		last_error = "函数不存在: %s" % func_name
		return {"ok": false, "error": last_error}
	return call_address_sync(addr, args, max_steps)


func call_address_sync(address: int, args: Array, max_steps: int = 1_000_000) -> Dictionary:
	last_error = ""
	if args.size() > MAX_VM_CALL_ARGUMENTS:
		last_error = "同步调用参数超过上限 (%d)。" % MAX_VM_CALL_ARGUMENTS
		return {"ok": false, "error": last_error}
	if max_steps < 1 or max_steps > MAX_SYNC_STEPS:
		last_error = "同步调用预算无效（允许 1..%d 步）。" % MAX_SYNC_STEPS
		return {"ok": false, "error": last_error}
	if not _ensure_image_validated():
		return {"ok": false, "error": last_error}
	if not _is_instruction_boundary(address):
		last_error = "同步调用入口不是有效指令边界：0x%X" % address
		return {"ok": false, "error": last_error}
	var saved_ip := ip
	var saved_halted := is_halted
	var saved_pending_args := pending_call_args.duplicate()
	var saved_pending_ret := pending_return_ip
	var saved_call_stack := call_stack.duplicate()
	var saved_eval_stack := eval_stack.duplicate()

	ip = address
	is_halted = false
	pending_call_args = args.duplicate()
	pending_return_ip = -1
	call_stack.clear()
	eval_stack.clear()

	var was_synchronous := is_synchronous_call
	is_synchronous_call = true
	var steps := 0
	while not is_halted and steps < max_steps:
		if not step():
			is_halted = true
			var err = last_error
			var fail_ip := ip
			var st := call_stack.duplicate()
			ip = saved_ip
			is_halted = saved_halted
			pending_call_args = saved_pending_args
			pending_return_ip = saved_pending_ret
			call_stack = saved_call_stack
			eval_stack = saved_eval_stack
			is_synchronous_call = was_synchronous
			return {"ok": false, "error": err, "ip": fail_ip, "steps": steps, "stack": st}
		steps += 1

	var timed_out := not is_halted and steps >= max_steps
	var ret = last_return_value
	var timeout_ip := ip
	var timeout_stack := call_stack.duplicate()
	ip = saved_ip
	is_halted = saved_halted
	pending_call_args = saved_pending_args
	pending_return_ip = saved_pending_ret
	call_stack = saved_call_stack
	eval_stack = saved_eval_stack
	is_synchronous_call = was_synchronous
	if timed_out:
		last_error = "同步调用超过步数上限 (%d) @ 0x%X" % [max_steps, timeout_ip]
		return {"ok": false, "timeout": true, "error": last_error, "ip": timeout_ip, "steps": steps, "stack": timeout_stack}
	return {"ok": true, "result": ret, "steps": steps}


func step() -> bool:
	if not _ensure_image_validated():
		return false
	if ip < 0 or ip >= image.size():
		last_error = "指令指针超出范围: 0x%X" % ip
		return false
	if eval_stack.size() > MAX_VM_EVAL_STACK:
		last_error = "求值栈超过上限 (%d)。" % MAX_VM_EVAL_STACK
		return false
	if not instruction_starts.is_empty():
		if not _is_instruction_boundary(ip):
			last_error = "指令指针不在已验证的指令边界：0x%X" % ip
			return false
	else:
		var decoded := bytecode_decoder.decode(image, ip, 1)
		if not decoded.get("ok", false):
			last_error = "指令解码失败 @ 0x%X：%s" % [ip, decoded.get("error", "未知错误")]
			return false

	var start_ip := ip
	var code := image[ip]
	ip += 1
	executed_instructions += 1

	match code:
		0: # new
			var mode := _read_u8()
			var type_code := _read_u8()
			var target_class := ""
			if type_code == 0:
				target_class = _read_string()
			var var_name := _read_string()
			if not last_error.is_empty():
				return false
			var new_val: Variant = null
			if type_code == 0:
				new_val = create_object(target_class)
			elif type_code == 1:
				new_val = null
			elif type_code == 2:
				new_val = []
			elif type_code == 3:
				new_val = {}
			elif type_code == 4:
				new_val = 0
			elif type_code == 5:
				new_val = 0.0
			elif type_code == 6:
				new_val = ""

			if mode == 1: # stack local
				if call_stack.is_empty():
					last_error = "在全局作用域尝试创建本地变量 %s" % var_name
					return false
				var cur_frame: StackFrame = call_stack.back()
				if not cur_frame.add_local(var_name, new_val):
					last_error = "函数局部变量数量超过上限 (%d)。" % MAX_VM_LOCALS
					return false
				cur_frame.last_new_var_name = var_name
				cur_frame.last_new_stack_size = eval_stack.size()
			elif mode == 2: # this member
				var cur_this = _get_current_this()
				if not _set_member_field(cur_this, var_name, new_val):
					last_error = "对象成员数量超过上限 (%d)。" % MAX_VM_OBJECT_FIELDS
					return false

		1: # free
			if not eval_stack.is_empty():
				eval_stack.pop_back()

		2: # load
			var mode := _read_u8()
			var type_code := _read_u8()
			if mode == 0: # immediate
				match type_code:
					0:
						var cname := _read_string()
						if not last_error.is_empty(): return false
						eval_stack.append(create_object(cname))
					1:
						eval_stack.append(null)
					2:
						eval_stack.append([])
					3:
						eval_stack.append({})
					4:
						var ival := _read_s32()
						eval_stack.append(ival)
					5:
						var rval := _read_double()
						eval_stack.append(rval)
					6:
						var sval := _read_string()
						if not last_error.is_empty(): return false
						eval_stack.append(sval)
					_:
						last_error = "未知的即值类型: %d" % type_code
						return false
			elif mode == 1: # stack local
				var key: Variant = null
				if type_code == 4:
					key = _read_s32()
				elif type_code == 6:
					key = _read_string()
				if not last_error.is_empty(): return false
				var frame: StackFrame = call_stack.back() if not call_stack.is_empty() else null
				if frame == null:
					last_error = "无法读取栈变量，栈帧为空。"
					return false
				if key is int:
					if key < 0 or key >= frame.local_order.size():
						last_error = "局部变量索引超出范围：%d" % key
						return false
					var var_name: String = frame.local_order[key]
					var local_value: Variant = frame.locals.get(var_name)
					eval_stack.append(local_value if local_value is CsxRef else CsxRef.new(frame.locals, var_name))
				else:
					var local_value: Variant = frame.locals.get(str(key))
					eval_stack.append(local_value if local_value is CsxRef else CsxRef.new(frame.locals, str(key)))
			elif mode == 2: # this member
				var cur_this = _get_current_this()
				if type_code == 1:
					eval_stack.append(cur_this)
				else:
					var key: Variant = null
					if type_code == 4:
						key = _read_s32()
					elif type_code == 6:
						key = _read_string()
					if not last_error.is_empty(): return false
					eval_stack.append(CsxRef.new(cur_this, key))
			elif mode == 3: # global
				var key: Variant = null
				if type_code == 4:
					key = _read_s32()
				elif type_code == 6:
					key = _read_string()
				if not last_error.is_empty(): return false
				if key is int:
					if key < 0 or key >= global_vars.size():
						last_error = "全局变量索引超出范围：%d" % key
						return false
					var g_name: String = global_vars[key]["name"]
					eval_stack.append(CsxRef.new(globals_by_name, g_name))
				else:
					eval_stack.append(CsxRef.new(globals_by_name, str(key)))
			elif mode == 4: # data
				var key: Variant = null
				if type_code == 4:
					key = _read_s32()
				elif type_code == 6:
					key = _read_string()
				if not last_error.is_empty(): return false
				if key is int:
					if key < 0 or key >= data_vars.size():
						last_error = "数据变量索引超出范围：%d" % key
						return false
					var d_name: String = data_vars[key]["name"]
					eval_stack.append(CsxRef.new(data_by_name, d_name))
				else:
					eval_stack.append(CsxRef.new(data_by_name, str(key)))

		3: # store
			var kind := _read_u8()
			var cur_frame: StackFrame = call_stack.back() if not call_stack.is_empty() else null
			var is_decl_init: bool = false
			if cur_frame != null and not cur_frame.last_new_var_name.is_empty() and eval_stack.size() == cur_frame.last_new_stack_size + 1:
				is_decl_init = true

			if is_decl_init:
				if not _require_eval_stack(1, "store"):
					return false
				var rhs: Variant = resolve_value(eval_stack.pop_back())
				var var_name: String = cur_frame.last_new_var_name
				cur_frame.last_new_var_name = ""
				cur_frame.last_new_stack_size = -1
				if kind == 255:
					cur_frame.set_local(var_name, rhs)
				else:
					var current_val = cur_frame.get_local(var_name)
					var res_val = _apply_operate(kind, current_val, rhs)
					cur_frame.set_local(var_name, res_val)
			else:
				if eval_stack.size() < 2:
					last_error = "store 指令栈元素不足（需要至少2个，实际 %d）" % eval_stack.size()
					return false
				var rhs: Variant = resolve_value(eval_stack.pop_back())
				var lhs: Variant = eval_stack.back()
				# A scalar store can coerce an intermediate initializer result.
				# Keep the pending declaration until its final store consumes it.
				if cur_frame != null and (lhs is CsxRef or eval_stack.size() != cur_frame.last_new_stack_size + 1):
					cur_frame.last_new_var_name = ""
					cur_frame.last_new_stack_size = -1
				var res_val: Variant = rhs
				if lhs is CsxRef:
					var ref := lhs as CsxRef
					if kind == 255:
						if not ref.set_value(rhs):
							last_error = "store 数组/字段索引超过上限。"
							return false
						res_val = rhs
					else:
						var current_val = ref.get_value()
						res_val = _apply_operate(kind, current_val, rhs)
						if not ref.set_value(res_val):
							last_error = "store 数组/字段索引超过上限。"
							return false
				elif lhs is String:
					res_val = "" if rhs == null else str(rhs)
				elif lhs is int:
					res_val = _to_int(rhs)
				elif lhs is float:
					res_val = _to_float(rhs)
				else:
					res_val = rhs

				eval_stack[eval_stack.size() - 1] = res_val

		4: # enter
			var func_name := _read_string()
			var count := _read_s32()
			if not last_error.is_empty():
				return false
			if count == -1: # @TRY block
				var _marker := _read_u8()
				var rel := _read_s32()
				var catch_addr := ip + rel
				if not _is_valid_instruction_target(catch_addr):
					last_error = "异常处理目标不是有效指令边界：0x%X" % catch_addr
					return false
				if not call_stack.is_empty():
					call_stack.back().catch_target = catch_addr
			else:
				var formal_args: Array[Dictionary] = []
				for _a in range(count):
					var ty := _read_u8()
					var cls := ""
					if ty == 0:
						cls = _read_string()
					var aname := _read_string()
					formal_args.append({"type": ty, "class": cls, "name": aname})
					if not last_error.is_empty():
						return false
				var is_inner_block: bool = (pending_return_ip < 0 and not call_stack.is_empty() and func_name.is_empty())
				if is_inner_block:
					var cur_frame: StackFrame = call_stack.back()
					if cur_frame.block_depth >= MAX_VM_BLOCK_DEPTH or cur_frame.local_order.size() + count > MAX_VM_LOCALS:
						last_error = "函数作用域或局部变量数量超过上限。"
						return false
					cur_frame.block_locals.append(cur_frame.local_order.size())
					cur_frame.block_depth += 1
					for i in range(count):
						var p_info: Dictionary = formal_args[i]
						var p_val: Variant = _default_for_type(p_info["type"])
						cur_frame.add_local(p_info["name"], p_val)
				else:
					var call_depth_limit := mini(max_call_depth, MAX_VM_CALL_DEPTH)
					if call_depth_limit < 1 or call_stack.size() >= call_depth_limit:
						last_error = "调用深度超过上限 (%d)。" % call_depth_limit
						return false
					var this_for_frame: Variant = null
					if pending_call_args.size() > 0 and formal_args.size() > 0 and formal_args[0]["name"] == "this":
						this_for_frame = pending_call_args[0]
					var frame := StackFrame.new(func_name, pending_return_ip, this_for_frame)
					pending_return_ip = -1
					for i in range(count):
						var p_info: Dictionary = formal_args[i]
						var p_val: Variant = null
						if i < pending_call_args.size():
							p_val = pending_call_args[i]
							var resolved: Variant = resolve_value(p_val)
							if int(p_info["type"]) != 1 or p_info["name"] == "this" or resolved is RefCounted:
								p_val = resolved
						else:
							p_val = _default_for_type(p_info["type"])
						frame.add_local(p_info["name"], p_val)
					pending_call_args.clear()
					call_stack.append(frame)

		5: # leave
			if not call_stack.is_empty():
				var cur_frame: StackFrame = call_stack.back()
				if cur_frame.block_depth > 0:
					cur_frame.block_depth -= 1
					var prev_count: int = cur_frame.block_locals.pop_back() if not cur_frame.block_locals.is_empty() else 0
					while cur_frame.local_order.size() > prev_count:
						var rname: String = cur_frame.local_order.pop_back()
						cur_frame.locals.erase(rname)
				else:
					call_stack.pop_back()

		6: # jump
			var rel := _read_s32()
			var target := ip + rel
			if not _is_valid_instruction_target(target):
				last_error = "jump 目标不是有效指令边界：0x%X" % target
				return false
			ip = target

		7: # cjump
			var cond := _read_u8()
			var rel := _read_s32()
			var target := ip + rel
			if not _is_valid_instruction_target(target):
				last_error = "cjump 目标不是有效指令边界：0x%X" % target
				return false
			if not _require_eval_stack(1, "cjump"):
				return false
			var val = resolve_value(eval_stack.pop_back())
			var is_true: bool = is_truthy(val)
			var jump_if_true := (cond & 1) != 0
			var push_cond := (cond & 2) != 0
			if is_true == jump_if_true:
				ip = target
				if push_cond:
					eval_stack.append(-1 if is_true else 0)

		8: # call
			var mode := _read_u8()
			var argc := _read_s32()
			var func_name := _read_string()
			if mode == 0:
				_read_u16() # throw marker
			if not last_error.is_empty():
				return false
			if argc < 0 or argc > MAX_VM_CALL_ARGUMENTS:
				last_error = "call 参数数量无效：%d" % argc
				return false
			if not _require_eval_stack(argc, "call %s" % func_name):
				return false

			var args: Array = []
			for _i in range(argc):
				args.push_front(eval_stack.pop_back())

			if mode == 2: # member call: receiver is args[0]
				if args.is_empty():
					last_error = "Member call 缺少 receiver 参数: %s" % func_name
					return false
				var receiver = resolve_value(args[0])
				var method_args: Array = []
				for k in range(1, args.size()):
					method_args.append(resolve_value(args[k]))
				# Cotopha keeps reference output parameters on the eval stack while
				# argc counts only the receiver for these host calls.
				if func_name in ["GetCursorPos", "GetRectangle"] and not eval_stack.is_empty():
					var output_value: Variant = resolve_value(eval_stack.back())
					if output_value is CsxInstance:
						method_args.append(output_value)

				if func_name == "GetType":
					if receiver == null:
						eval_stack.append("")
					elif receiver is CsxInstance:
						eval_stack.append((receiver as CsxInstance).type_name)
					elif receiver is CsxHostClass.HostResource:
						eval_stack.append("Resource")
					elif receiver is CsxHostClass.HostFile:
						eval_stack.append("File")
					elif receiver is CsxHostClass.HostSprite:
						eval_stack.append("Sprite")
					elif receiver is CsxHostClass.HostWindow:
						eval_stack.append("Window")
					elif receiver is CsxHostClass.HostInputFilter:
						eval_stack.append("InputFilter")
					elif receiver is CsxHostClass.HostToneFilter:
						eval_stack.append("ToneFilter")
					elif receiver is String:
						eval_stack.append("String")
					elif receiver is int:
						eval_stack.append("Integer")
					elif receiver is float:
						eval_stack.append("Real")
					elif receiver is Array:
						eval_stack.append("Array")
					elif receiver is Dictionary:
						eval_stack.append("Hash")
					else:
						eval_stack.append("")
					return true

				if receiver is CsxInstance:
					var inst := receiver as CsxInstance
					var full_name := "%s::%s" % [inst.type_name, func_name]
					if func_name == "hitret" or full_name == "AdvScreen::hitret":
						var msg_info = inst.get_field("msgInfo")
						if msg_info is CsxInstance:
							var spk: String = str(msg_info.get_field("name"))
							var txt: String = str(msg_info.get_field("message"))
							var voc: String = str(msg_info.get_field("voice"))
							if not txt.is_empty():
								host.record_dialogue(spk, txt, voc)
					if func_name == "startSelect" or full_name == "AdvScreen::startSelect":
						var items = inst.get_field("selectItem")
						if items is Array and host.current_choices.is_empty():
							host.record_choices(items)
						if host.auto_advance:
							inst.set_field("selectResult", 1)
							eval_stack.append(1)
							return true
						if host.selected_choice > 0:
							var choice: int = host.selected_choice
							host.selected_choice = -1
							host.is_waiting_choice = false
							host.current_choices.clear()
							inst.set_field("selectResult", choice)
							if items is Array:
								(items as Array).clear()
							eval_stack.append(choice)
							return true
						for arg in args:
							eval_stack.append(arg)
						ip = start_ip
						host.is_waiting_choice = true
						return true
					if has_function(full_name):
						pending_return_ip = ip
						ip = get_function_address(full_name)
						pending_call_args = [inst] + args.slice(1)
						return true
					elif inst.type_name == "InputFilter":
						var f_dummy := CsxHostClass.HostInputFilter.new(host)
						var fres = _dispatch_input_filter_method(f_dummy, func_name, method_args)
						eval_stack.append(fres)
						return true
					elif inst.type_name == "Resource":
						var r_dummy := CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
						var rres = _dispatch_resource_method(r_dummy, func_name, method_args)
						eval_stack.append(rres)
						return true
					elif inst.type_name == "ToneFilter":
						eval_stack.append(0)
						return true
					elif inst.type_name == "File":
						var f_dummy := CsxHostClass.HostFile.new(host)
						var fres = _dispatch_file_method(f_dummy, func_name, method_args)
						eval_stack.append(fres)
						return true

					else:
						last_error = "脚本类 %s 缺少方法 %s" % [inst.type_name, func_name]
						return false
				elif receiver is String:
					if func_name == "MakeUpper":
						var upp: String = (receiver as String).to_upper()
						if args[0] is CsxRef:
							if not (args[0] as CsxRef).set_value(upp):
								last_error = "MakeUpper 数组/字段索引超过上限。"
								return false
						eval_stack.append(upp)
						return true
					elif func_name == "MakeLower":
						var low: String = (receiver as String).to_lower()
						if args[0] is CsxRef:
							if not (args[0] as CsxRef).set_value(low):
								last_error = "MakeLower 数组/字段索引超过上限。"
								return false
						eval_stack.append(low)
						return true
					elif func_name == "Call":
						var str_fn: String = receiver as String
						var target_addr := get_function_address(str_fn)
						if target_addr >= 0:
							pending_return_ip = ip
							ip = target_addr
							pending_call_args = method_args
							return true
						else:
							last_error = "未找到函数: %s" % str_fn
							return false
					var res = _dispatch_string_method(receiver as String, func_name, method_args)
					if not last_error.is_empty(): return false
					eval_stack.append(res)
					return true
				elif receiver is int or receiver is bool:
					var int_val: int = -1 if (receiver is bool and receiver) else (0 if receiver is bool else receiver as int)
					var res = _dispatch_int_method(args[0], int_val, func_name, method_args)
					if not last_error.is_empty(): return false
					eval_stack.append(res)
					return true
				elif receiver is float:
					var res = _dispatch_real_method(args[0], receiver as float, func_name, method_args)
					eval_stack.append(res)
					return true
				elif receiver is CsxHostClass.HostInputFilter:
					var res = _dispatch_input_filter_method(receiver as CsxHostClass.HostInputFilter, func_name, method_args)
					eval_stack.append(res)
					return true
				elif receiver is CsxHostClass.HostResource:
					var resource_args := args.slice(1) if func_name == "GetVolume" else method_args
					var res = _dispatch_resource_method(receiver as CsxHostClass.HostResource, func_name, resource_args)
					eval_stack.append(res)
					return true
				elif receiver is CsxHostClass.HostToneFilter:
					var tf := receiver as CsxHostClass.HostToneFilter
					var tres = _dispatch_tone_filter_method(tf, func_name, method_args)
					eval_stack.append(tres)
					return true
				elif receiver is CsxHostClass.HostResourceManager:
					var hrm := receiver as CsxHostClass.HostResourceManager
					if func_name == "LoadResource":
						var archive_name: String = str(method_args[0]) if method_args.size() > 0 else ""
						var res_code := hrm.load_resource(archive_name)
						eval_stack.append(res_code)
						return true
					elif func_name == "CreateFormPage":
						var parent_spr = method_args[0] if method_args.size() > 0 else null
						var page_id: String = str(method_args[1]) if method_args.size() > 1 else ""
						var form_code := 0
						if parent_spr is CsxHostClass.HostSprite:
							form_code = hrm.create_form_page(parent_spr, page_id)
						eval_stack.append(form_code)
						return true
					else:
						eval_stack.append(0)
						return true
				elif receiver is CsxHostClass.HostFile:
					var file := receiver as CsxHostClass.HostFile
					var fres = _dispatch_file_method(file, func_name, method_args)
					eval_stack.append(fres)
					return true
				elif receiver is CsxHostClass.HostSprite:
					var spr := receiver as CsxHostClass.HostSprite
					var sres = _dispatch_sprite_method(spr, func_name, method_args)
					eval_stack.append(sres)
					return true
				elif receiver is CsxHostClass.HostWindow:
					var win := receiver as CsxHostClass.HostWindow
					var wres = _dispatch_window_method(win, func_name, method_args)
					eval_stack.append(wres)
					return true
				elif receiver is Array:
					var res = _dispatch_array_method(receiver as Array, func_name, method_args)
					if not last_error.is_empty(): return false
					eval_stack.append(res)
					return true
				elif receiver is Dictionary:
					var res = _dispatch_hash_method(receiver as Dictionary, func_name, method_args)
					eval_stack.append(res)
					return true
				elif receiver == null:
					match func_name:
						"IsExisting":
							var h_res := host.call_host_function("IsExisting", method_args, self)
							eval_stack.append(h_res.get("result", 0))
							return true
						"IsEmpty":
							eval_stack.append(-1)
							return true
						"GetInfo", "GetImageInfo":
							var info := CsxInstance.new("ImageInfo")
							var bpos := CsxInstance.new("Point")
							bpos.set_field("x", 0)
							bpos.set_field("y", 0)
							var lpos := CsxInstance.new("Point")
							lpos.set_field("x", 0)
							lpos.set_field("y", 0)
							info.set_field("basePosition", bpos)
							info.set_field("localPosition", lpos)
							info.set_field("width", 800)
							info.set_field("height", 600)
							eval_stack.append(info)
							return true
						"Release", "Stop", "Clear", "IsActivation", "IsVisible", "IsPlaying", "GetLength":
							eval_stack.append(0)
							return true
						"Middle", "Left", "Right", "Replace", "MakeUpper", "MakeLower", "Trim":
							var res = _dispatch_string_method("", func_name, method_args)
							eval_stack.append(res)
							return true
						"Find":
							eval_stack.append(-1)
							return true
						"Char":
							eval_stack.append(0)
							return true
						_:
							last_error = "未知 receiver 类型 (<null>) 调用方法 %s" % func_name
							return false
				else:
					last_error = "未知 receiver 类型 (%s) 调用方法 %s" % [str(receiver), func_name]
					return false

			elif mode == 3 or mode == 5:
				var resolved_args: Array = []
				for a in args:
					resolved_args.append(resolve_value(a))

				if mode == 5:
					var cur_this = _get_current_this()
					if cur_this is CsxInstance:
						var inst := cur_this as CsxInstance
						var full_name := "%s::%s" % [inst.type_name, func_name]
						if func_name == "hitret" or full_name == "AdvScreen::hitret":
							var msg_info = inst.get_field("msgInfo")
							if msg_info is CsxInstance:
								var spk: String = str(msg_info.get_field("name"))
								var txt: String = str(msg_info.get_field("message"))
								var voc: String = str(msg_info.get_field("voice"))
								if not txt.is_empty():
									host.record_dialogue(spk, txt, voc)
						if functions.has(full_name):
							pending_return_ip = ip
							ip = functions[full_name]
							pending_call_args = [inst] + args
							return true

				if has_function(func_name):
					pending_return_ip = ip
					ip = get_function_address(func_name)
					pending_call_args = args
					return true

				var host_res := host.call_host_function(func_name, resolved_args, self)
				if host_res.get("handled", false):
					var res_val = host_res.get("result", null)
					if res_val != null:
						eval_stack.append(res_val)
					return true

				last_error = "未实现的全局函数: %s (mode=%d, argc=%d)" % [func_name, mode, argc]
				return false

		9: # return
			var kind := _read_u8()
			var ret_val: Variant = 0
			if kind != 1 and not eval_stack.is_empty():
				ret_val = resolve_value(eval_stack.pop_back())

			if call_stack.is_empty():
				is_halted = true
				last_return_value = ret_val
				return true

			var frame: StackFrame = call_stack.pop_back()
			if frame.return_ip <= 0:
				is_halted = true
				last_return_value = ret_val
				return true

			ip = frame.return_ip
			if kind != 1:
				eval_stack.append(ret_val)

		10: # element
			var type_code := _read_u8()
			var key: Variant = null
			if type_code == 4:
				key = _read_s32()
			elif type_code == 6:
				key = _read_string()
			if not last_error.is_empty() or not _require_eval_stack(1, "element"):
				return false
			var obj = resolve_value(eval_stack.pop_back())
			eval_stack.append(CsxRef.new(obj, key))

		11: # element_indirect
			if not _require_eval_stack(2, "element_indirect"):
				return false
			var idx = resolve_value(eval_stack.pop_back())
			var obj = resolve_value(eval_stack.pop_back())
			eval_stack.append(CsxRef.new(obj, idx))

		12: # operate
			var op := _read_u8()
			if not _require_eval_stack(2, "operate"):
				return false
			var rhs = resolve_value(eval_stack.pop_back())
			var lhs = resolve_value(eval_stack.pop_back())
			eval_stack.append(_apply_operate(op, lhs, rhs))

		13: # unary
			var uop := _read_u8()
			if not _require_eval_stack(1, "unary"):
				return false
			var val = resolve_value(eval_stack.pop_back())
			eval_stack.append(_apply_unary(uop, val))

		14: # compare
			var cmp := _read_u8()
			if not _require_eval_stack(2, "compare"):
				return false
			var rhs = resolve_value(eval_stack.pop_back())
			var lhs = resolve_value(eval_stack.pop_back())
			eval_stack.append(_apply_compare(cmp, lhs, rhs))

		_:
			last_error = "未实现的指令: 0x%02X @ 0x%X" % [code, start_ip]
			return false

	if not last_error.is_empty():
		return false
	if eval_stack.size() > MAX_VM_EVAL_STACK:
		last_error = "求值栈超过上限 (%d)。" % MAX_VM_EVAL_STACK
		return false
	return true


func _get_current_this() -> Variant:
	for i in range(call_stack.size() - 1, -1, -1):
		if call_stack[i].this_obj != null:
			return call_stack[i].this_obj
	return null


func _dispatch_string_method(s: String, method: String, args: Array) -> Variant:
	match method:
		"IsMatchUsage":
			var usage: String = str(args[0]) if args.size() > 0 else ""
			var captures: Variant = args[1] if args.size() > 1 else null
			return _is_match_usage(s, usage, captures)
		"MakeUpper":
			return s.to_upper()
		"MakeLower":
			return s.to_lower()
		"GetLength":
			return s.length()
		"Find":
			var sub: String = str(args[0]) if args.size() > 0 else ""
			return s.find(sub)
		"Replace":
			var target_str: String = str(args[0]) if args.size() > 0 else ""
			var replacement: String = str(args[1]) if args.size() > 1 else ""
			return s.replace(target_str, replacement)
		"Middle":
			var start_idx: int = int(args[0]) if args.size() > 0 else 0
			var count: int = int(args[1]) if args.size() > 1 else -1
			return s.substr(start_idx, count)
		"Left":
			var count: int = int(args[0]) if args.size() > 0 else 0
			return s.left(count)
		"Right":
			var count: int = int(args[0]) if args.size() > 0 else 0
			return s.right(count)
		"Char":
			var idx: int = int(args[0]) if args.size() > 0 else 0
			return s.unicode_at(idx)
		"Call":
			if functions.has(s):
				pending_return_ip = ip
				ip = functions[s]
				pending_call_args = args.duplicate()
			return 0
		_:
			return 0


func _is_match_usage(value: String, usage: String, captures: Variant) -> String:
	var regex_source := "^"
	var cursor := 0
	var capture_count := 0
	var digit_capture := "(<0-9>*)"
	while cursor < usage.length():
		if usage.substr(cursor, digit_capture.length()) == digit_capture:
			regex_source += "([0-9]*)"
			capture_count += 1
			cursor += digit_capture.length()
		elif usage.substr(cursor, 1) == "&":
			var close_at := usage.find("&", cursor + 1)
			if close_at < 0:
				regex_source += _escape_regex_literal("&")
				cursor += 1
			else:
				var literal := usage.substr(cursor + 1, close_at - cursor - 1)
				regex_source += _escape_regex_literal(literal)
				cursor = close_at + 1
		else:
			regex_source += _escape_regex_literal(usage.substr(cursor, 1))
			cursor += 1
	regex_source += "$"

	var regex := RegEx.new()
	if regex.compile(regex_source) != OK:
		return "!"
	var result := regex.search(value)
	if result == null:
		return "!"
	if captures is Array:
		captures.clear()
		for index in range(capture_count):
			var group_value := result.get_string(index + 1)
			captures.append(int(group_value) if group_value.is_valid_int() else 0)
	# CSX callers use `IsMatchUsage(...) == ""` as their match test.
	return ""


func _escape_regex_literal(value: String) -> String:
	var escaped := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if "\\.^$|?*+()[]{}".contains(character):
			escaped += "\\"
		escaped += character
	return escaped


func _dispatch_array_method(arr: Array, method: String, args: Array) -> Variant:
	match method:
		"IsButtonChecked":
			var button_id := str(args[0]) if args.size() > 0 else ""
			for item in arr:
				if item is CsxHostClass.HostSprite and _sprite_has_checked_button(item, button_id):
					return -1
			return 0
		"GetLength":
			return arr.size()
		"IsEmpty":
			if args.size() > 0:
				var idx: int = int(args[0])
				return -1 if (idx < 0 or idx >= arr.size() or arr[idx] == null) else 0
			return -1 if arr.is_empty() else 0
		"Find":
			var target = args[0] if args.size() > 0 else null
			var start_idx: int = clampi(int(args[1]) if args.size() > 1 else 0, 0, arr.size())
			for i in range(start_idx, arr.size()):
				if arr[i] == target:
					return i
			return -1
		"Push":
			if args.size() > 0:
				if arr.size() >= MAX_VM_ARRAY_ENTRIES:
					last_error = "数组长度超过上限 (%d)。" % MAX_VM_ARRAY_ENTRIES
					return 0
				arr.append(args[0])
			return 0
		"Pop":
			if not arr.is_empty():
				return arr.pop_back()
			return null
		"Insert":
			if args.size() >= 2:
				if arr.size() >= MAX_VM_ARRAY_ENTRIES:
					last_error = "数组长度超过上限 (%d)。" % MAX_VM_ARRAY_ENTRIES
					return 0
				var idx: int = clampi(int(args[0]), 0, arr.size())
				arr.insert(idx, args[1])
			return 0
		"Remove", "RemoveAll":
			if args.is_empty():
				arr.clear()
			elif args.size() == 1:
				var idx: int = int(args[0])
				if idx >= 0 and idx < arr.size():
					arr.remove_at(idx)
			elif args.size() >= 2:
				var idx: int = int(args[0])
				if idx < 0 or idx >= arr.size():
					return 0
				var count: int = int(args[1])
				if count < 0:
					count = arr.size() - idx
				else:
					count = mini(count, arr.size() - idx)
				for _k in range(count):
					arr.remove_at(idx)
			return 0
		"Swap":
			if args.size() >= 2:
				var i: int = int(args[0])
				var j: int = int(args[1])
				if i >= 0 and i < arr.size() and j >= 0 and j < arr.size():
					var tmp = arr[i]
					arr[i] = arr[j]
					arr[j] = tmp
			return 0
		"Clear":
			arr.clear()
			return 0
		_:
			return 0


func _dispatch_hash_method(h: Dictionary, method: String, args: Array) -> Variant:
	match method:
		"GetLength":
			return h.size()
		"IsEmpty":
			return -1 if h.is_empty() else 0
		"Remove":
			if args.size() > 0:
				h.erase(args[0])
			return 0
		"RemoveAll", "Clear":
			h.clear()
			return 0
		_:
			return 0


func _dispatch_sprite_method(spr: CsxHostClass.HostSprite, method: String, args: Array) -> Variant:
	match method:
		"AttachImage":
			if args.size() > 0:
				spr.attach_image(args[0])
			return 0
		"AttachToneFilter":
			var filter: Variant = args[0] if not args.is_empty() else null
			return spr.attach_tone_filter(filter as CsxHostClass.HostToneFilter) if filter is CsxHostClass.HostToneFilter else -1
		"BeginAnimation":
			return spr.begin_animation(
				_to_int(args[0]) if args.size() > 0 else 1,
				_to_int(args[1]) if args.size() > 1 else 0,
				_to_int(args[2]) if args.size() > 2 else -1,
				_to_int(args[3]) if args.size() > 3 else 0,
				_to_int(args[4]) if args.size() > 4 else -1
			)
		"EndAnimation":
			return spr.end_animation()
		"SetVisible":
			if args.size() > 0:
				spr.set_visible(_to_int(args[0]))
			return 0
		"SetTransparency":
			if not args.is_empty():
				var item := spr.find_form_item(str(args[1])) if args.size() > 1 else spr
				if item != null:
					item.set_transparency(_to_int(args[0]))
			return 0
		"CheckButton":
			if args.size() >= 2:
				var button := spr.find_form_item(str(args[0]))
				if button != null and button.is_button:
					button.fields["checked"] = is_truthy(args[1])
					button.set_button_state("pushed" if button.fields["checked"] else "normal")
			return 0
		"SetSpriteImage":
			if args.size() >= 2:
				return 1 if spr.set_form_image(str(args[0]), str(args[1])) else 0
			return 0
		"SetBezierCurve":
			spr.activation_curves = [[], [], []]
			for index in mini(args.size(), 3):
				var curve = args[index]
				if not curve is CsxInstance:
					continue
				var source = curve.get_field("parent")
				if not source is Array or source.size() != 4:
					continue
				var points: Array[Vector2] = []
				for point in source:
					if point is CsxInstance:
						points.append(Vector2(_to_float(point.get_field("x")), _to_float(point.get_field("y"))))
				if points.size() == 4:
					spr.activation_curves[index] = points
			return 0
		"SetBlendingEnvelope":
			if args.size() > 0:
				spr.set_blending_envelope(_to_int(args[0]))
			return 0
		"SetBlendDegree":
			spr.blending = _to_int(args[0]) if not args.is_empty() else 0
			return 0
		"SetEffectParameter":
			return spr.set_effect_parameter(args[0] if not args.is_empty() else null, args[1] if args.size() > 1 else null)
		"ModifyAnimationFlags":
			var add_flags := _to_int(args[0]) if not args.is_empty() else 0
			var remove_flags := _to_int(args[1]) if args.size() > 1 else 0
			return spr.modify_animation_flags(add_flags, remove_flags)
		"GetAnimationFlags":
			return host.sprite_animation_flags if host != null else 0
		"BeginActivation":
			if args.size() > 0:
				# Blocking entry points cannot present intermediate frames.
				spr.begin_activation(0 if is_synchronous_call else _to_int(args[0]))
			return 0
		"FlushActivation":
			spr.flush_activation()
			return 0
		"IsActivation":
			if is_synchronous_call and spr.is_activating:
				spr.flush_activation()
			return spr.is_activation()
		"IsVisible":
			return -1 if spr.is_visible else 0
		"IsButtonChecked":
			var button_id := str(args[0]) if args.size() > 0 else ""
			return -1 if _sprite_has_checked_button(spr, button_id) else 0
		"GetTransparency":
			return spr.transparency
		"MovePosition", "SetPos", "SetPosition":
			if args.size() >= 2:
				spr.move_position(_to_int(args[0]), _to_int(args[1]))
			return 0
		"AddSprite":
			if args.size() >= 2:
				spr.add_sprite(_to_int(args[0]), args[1])
			return 0
		"DetachSprite":
			if args.size() > 0:
				spr.detach_sprite(args[0])
			return 0
		"DetachAllSprite":
			spr.detach_all_sprites()
			return 0
		"Release":
			return spr.release()
		"CreateSprite":
			var fmt := _to_int(args[0]) if args.size() > 0 else 0
			var w := _to_int(args[1]) if args.size() > 1 else 0
			var h := _to_int(args[2]) if args.size() > 2 else 0
			return spr.create_sprite(fmt, w, h)
		"CreateMessage":
			var message_width := _to_int(args[0]) if args.size() > 0 else 0
			var message_height := _to_int(args[1]) if args.size() > 1 else 0
			return spr.create_message(message_width, message_height)
		"SetBackColor":
			var rgb := _to_int(args[0]) if args.size() > 0 else 0
			var en := is_truthy(args[1]) if args.size() > 1 else false
			return spr.set_back_color(rgb, en)
		"SetAlphaImage":
			var a_res = args[0] if args.size() > 0 else null
			var rng := _to_int(args[1]) if args.size() > 1 else 0
			return spr.set_alpha_image(a_res, rng)
		"FillRect":
			var rect = args[0] if args.size() > 0 else null
			var col: int = _to_int(args[1]) if args.size() > 1 else 0
			var trans: int = _to_int(args[2]) if args.size() > 2 else 0
			var flags: int = _to_int(args[3]) if args.size() > 3 else 0
			return spr.fill_rect(rect, col, trans, flags)
		"LoadImage":
			var fname := str(args[0]) if args.size() > 0 else ""
			return spr.load_image(fname)
		"OpenMovie":
			var mov_path := str(args[0]) if args.size() > 0 else ""
			return spr.open_movie(mov_path)
		"PlayMovie":
			var mode := _to_int(args[0]) if args.size() > 0 else 0
			return spr.play_movie(mode)
		"IsMoviePlaying":
			return spr.is_movie_playing()
		"StopMovie":
			return spr.stop_movie()
		"CloseMovie":
			return spr.close_movie()
		"SetParameter":
			var param = args[0] if args.size() > 0 else null
			return spr.set_parameter(param)
		"Lock", "Unlock":
			return 0
		"GetParameter":
			var param = args[0] if args.size() > 0 else null
			return spr.get_parameter(param)
		"DrawImage":
			var src = args[0] if args.size() > 0 else null
			var param = args[1] if args.size() > 1 else null
			return spr.draw_image(src, param)
		"GetInfo", "GetImageInfo":
			var info: CsxInstance = args[0] if (args.size() > 0 and args[0] is CsxInstance) else CsxInstance.new("ImageInfo")
			var bpos := CsxInstance.new("Point")
			bpos.set_field("x", spr.position.x)
			bpos.set_field("y", spr.position.y)
			var lpos := CsxInstance.new("Point")
			lpos.set_field("x", 0)
			lpos.set_field("y", 0)
			info.set_field("basePosition", bpos)
			info.set_field("localPosition", lpos)
			var w := spr.size.x if spr.size.x > 0 else 800
			var h := spr.size.y if spr.size.y > 0 else 600
			info.set_field("width", w)
			info.set_field("height", h)
			info.set_field("nImageWidth", w)
			info.set_field("nImageHeight", h)
			return info
		"SetSpriteText":
			var item_id := str(args[0]) if args.size() > 0 else ""
			var text_value := str(args[1]) if args.size() > 1 else ""
			return spr.set_sprite_text(item_id, text_value)
		"GetSpriteText":
			return spr.get_sprite_text(str(args[0]) if not args.is_empty() else "")
		"GetHorzScrollPos":
			return spr.get_scroll_position(str(args[0]) if not args.is_empty() else "", "horz")
		"SetHorzScrollPos":
			var position := _to_int(args[0]) if args.size() > 0 else 0
			var item_id := str(args[1]) if args.size() > 1 else ""
			return spr.set_scroll_position(position, item_id, "horz")
		"SetHorzScrollRange":
			var range_value := _to_int(args[0]) if args.size() > 0 else 0
			var item_id := str(args[1]) if args.size() > 1 else ""
			return spr.set_scroll_range(range_value, item_id, "horz")
		"GetVertScrollPos":
			return spr.get_scroll_position(str(args[0]) if not args.is_empty() else "", "vert")
		"SetVertScrollPos":
			var position := _to_int(args[0]) if args.size() > 0 else 0
			var item_id := str(args[1]) if args.size() > 1 else ""
			return spr.set_scroll_position(position, item_id, "vert")
		"SetVertScrollRange":
			var range_value := _to_int(args[0]) if args.size() > 0 else 0
			var item_id := str(args[1]) if args.size() > 1 else ""
			return spr.set_scroll_range(range_value, item_id, "vert")
		"GetRectangle":
			var rect: Variant = args[0] if not args.is_empty() else null
			if rect is CsxInstance and rect.type_name == "Rect":
				var bounds := spr.get_sprite_rect()
				(rect as CsxInstance).set_field("left", floori(bounds.position.x))
				(rect as CsxInstance).set_field("top", floori(bounds.position.y))
				(rect as CsxInstance).set_field("right", ceili(bounds.end.x))
				(rect as CsxInstance).set_field("bottom", ceili(bounds.end.y))
			return rect
		"GetCursorPos":
			var point: Variant = args[0] if not args.is_empty() else null
			_write_cursor_point(point, host.get_cursor_position() if host != null else Vector2i.ZERO)
			return point if point is CsxInstance else 0
		"AttachMessageStyle":
			var res_mgr = args[0] if args.size() > 0 else null
			var style_id: String = str(args[1]) if args.size() > 1 else ""
			return spr.attach_message_style(res_mgr, style_id)
		"SetDefaultMsgSpeed":
			return spr.set_default_message_speed(_to_int(args[0]) if args.size() > 0 else 0, _to_int(args[1]) if args.size() > 1 else 0, _to_int(args[2], 256) if args.size() > 2 else 256)
		"IsMessagePending":
			return -1 if spr.message_pending else 0
		"FlushMessage":
			return spr.flush_message()
		"ClearMessage":
			return spr.clear_message()
		"OutputMessage":
			var msg: String = str(args[0]) if args.size() > 0 else ""
			return spr.output_message(msg)
		_:
			return 0


func _sprite_has_checked_button(sprite: CsxHostClass.HostSprite, button_id: String) -> bool:
	if sprite.btn_id == button_id and (sprite.btn_state == "pushed" or bool(sprite.fields.get("checked", false))):
		return true
	for child in sprite.children:
		if _sprite_has_checked_button(child, button_id):
			return true
	return false


func _is_polling_sprite_activation() -> bool:
	return not call_stack.is_empty() and call_stack.back().name == "WaitUntilSpriteActive"


func _dispatch_input_filter_method(flt: CsxHostClass.HostInputFilter, method: String, args: Array) -> Variant:
	match method:
		"LoadInputFilter":
			var fname := str(args[0]) if args.size() > 0 else ""
			return flt.load_input_filter(fname)
		"DeleteInputFilter":
			return flt.delete_input_filter()
		"OpenFilter":
			var mode := int(args[0]) if args.size() > 0 else 0
			var win = args[1] if args.size() > 1 else null
			return flt.open_filter(mode, win)
		"CloseFilter":
			return flt.close_filter()
		"FlushInputQueue":
			var limit := int(args[0]) if args.size() > 0 else 0
			return flt.flush_input_queue(limit)
		"GetCapturedJoyStick":
			return flt.get_captured_joy_stick()
		"IsJoyButtonPushing":
			var key := int(args[0]) if args.size() > 0 else 0
			var dev := int(args[1]) if args.size() > 1 else 0
			return flt.is_joy_button_pushing(key, dev)
		"GetJoyButtonPushed":
			var key := int(args[0]) if args.size() > 0 else 0
			var dev := int(args[1]) if args.size() > 1 else 0
			return flt.get_joy_button_pushed(key, dev, _is_polling_sprite_activation())
		"FlushJoyButtonPushed":
			var dev := int(args[0]) if args.size() > 0 else 0
			var key := int(args[1]) if args.size() > 1 else -1
			return flt.flush_joy_button_pushed(dev, key)
		"ResetJoyButtonPushing":
			var dev := int(args[0]) if args.size() > 0 else 0
			var key := int(args[1]) if args.size() > 1 else -1
			return flt.reset_joy_button_pushing(dev, key)
		"GetCursorPos":
			var point: Variant = args[0] if not args.is_empty() else null
			_write_cursor_point(point, flt.get_cursor_pos())
			return point if point is CsxInstance else 0
		"MoveCursorPos":
			var x := int(args[0]) if args.size() > 0 else 0
			var y := int(args[1]) if args.size() > 1 else 0
			return flt.move_cursor_pos(x, y)
		"GetInputEvent":
			var ev_ref = args[0] if args.size() > 0 else null
			var timeout := int(args[1]) if args.size() > 1 else 0
			return flt.get_input_event(ev_ref, timeout)
		_:
			return 0


func _dispatch_tone_filter_method(tf: CsxHostClass.HostToneFilter, method: String, args: Array) -> Variant:
	match method:
		"GetType":
			return tf.get_type()
		"SetType":
			if args.size() > 0:
				tf.set_type(str(args[0]))
			return 0
		"SetTone":
			if args.size() >= 3:
				tf.set_tone(float(args[0]), float(args[1]), float(args[2]))
			return 0
		"SetGeneralTone":
			if args.size() >= 8:
				return tf.set_general_tone(
					_to_int(args[0]), _to_int(args[1]), _to_int(args[2]), _to_int(args[3]),
					_to_int(args[4]), _to_int(args[5]), _to_int(args[6]), _to_int(args[7]),
					_to_int(args[8]) if args.size() > 8 else 0
				)
			return -1
		"GetTone":
			return tf.get_tone()
		"CreateToneFilter":
			return 0
		"DeleteToneFilter":
			return tf.delete_tone_filter()
		_:
			return 0


func _dispatch_resource_method(res: CsxHostClass.HostResource, method: String, args: Array) -> Variant:
	match method:
		"LoadSound":
			if args.size() > 0:
				return res.load_sound(str(args[0]), int(args[1]) if args.size() > 1 else -1)
			return 0
		"LoadImage":
			if args.size() > 0:
				return res.load_image(str(args[0]))
			return 0
		"Play":
			var intro := int(args[0]) if args.size() > 0 else -1
			var flag := int(args[1]) if args.size() > 1 else 0
			return res.play(intro, flag)
		"PlayFrom":
			var s_pos := int(args[0]) if args.size() > 0 else 0
			var e_pos := int(args[1]) if args.size() > 1 else -1
			var rep := bool(args[2]) if args.size() > 2 else false
			var r_pos := int(args[3]) if args.size() > 3 else -1
			var flag := int(args[4]) if args.size() > 4 else 0
			return res.play_from(s_pos, e_pos, rep, r_pos, flag)
		"SetRewindingPortion":
			var rewind := _to_int(args[0]) if args.size() > 0 else -1
			var end := _to_int(args[1]) if args.size() > 1 else -1
			var repeat := _to_int(args[2]) != 0 if args.size() > 2 else false
			return res.set_rewinding_portion(rewind, end, repeat)
		"Stop":
			return res.stop()
		"Pause":
			return res.pause()
		"Restart":
			return res.restart()
		"Release":
			return res.release()
		"SetVolume":
			var vl := float(args[0]) if args.size() > 0 else 1.0
			var vr := float(args[1]) if args.size() > 1 else 1.0
			return res.set_volume(vl, vr)
		"SetTotalVolume":
			var flag := int(args[0]) if args.size() > 0 else 0
			var vol := float(args[1]) if args.size() > 1 else 1.0
			return res.set_total_volume(flag, vol)
		"GetTotalVolume":
			var flag := int(args[0]) if args.size() > 0 else 0
			return res.get_total_volume(flag)
		"GetVolume":
			return res.get_volume(args[0] if args.size() > 0 else null, args[1] if args.size() > 1 else null)
		"SetVolumeEnvelope":
			return res.set_volume_envelope(args[0] if args.size() > 0 else null, int(args[1]) if args.size() > 1 else 0)
		"CancelVolumeEnvelope":
			return res.cancel_volume_envelope()
		"IsPendingEnvelope":
			return res.is_volume_envelope_pending()
		"IsPlaying":
			return -1 if res.is_playing else 0
		"GetPlayingPosition":
			return res.get_playing_position()
		"GetPixel":
			return res.get_pixel(_to_int(args[0]) if args.size() > 0 else 0, _to_int(args[1]) if args.size() > 1 else 0)
		"GetPixelRect":
			var get_pixels: Variant = args[0] if args.size() > 0 else null
			if not get_pixels is Array:
				if res.host != null:
					res.host.report_unsupported("HostResource.GetPixelRect Pointer buffer")
				return -1
			return res.get_pixel_rect(get_pixels, _to_int(args[1]) if args.size() > 1 else 0, _to_int(args[2]) if args.size() > 2 else 0, _to_int(args[3]) if args.size() > 3 else 0, _to_int(args[4]) if args.size() > 4 else 0)
		"SetPixelRect":
			var set_pixels: Variant = args[0] if args.size() > 0 else null
			if not set_pixels is Array:
				if res.host != null:
					res.host.report_unsupported("HostResource.SetPixelRect Pointer buffer")
				return -1
			return res.set_pixel_rect(set_pixels, _to_int(args[1]) if args.size() > 1 else 0, _to_int(args[2]) if args.size() > 2 else 0, _to_int(args[3]) if args.size() > 3 else 0, _to_int(args[4]) if args.size() > 4 else 0)
		"GetSoundInfo":
			if res.audio_stream == null:
				return null
			var sound_info := CsxInstance.new("SoundInfo")
			var stream := res.audio_stream
			var channels := 2 if stream.stereo else 1
			var bits_per_sample := 8 if stream.format == AudioStreamWAV.FORMAT_8_BITS else 16
			var bytes_per_frame := channels * bits_per_sample / 8
			@warning_ignore("integer_division")
			var samples := int(stream.data.size() / bytes_per_frame) if bytes_per_frame > 0 else 0
			sound_info.set_field("nSamplesPerSec", stream.mix_rate)
			sound_info.set_field("nChannelCount", channels)
			sound_info.set_field("nBitsPerSample", bits_per_sample)
			sound_info.set_field("nResourceBytes", stream.data.size())
			sound_info.set_field("nSampleCount", samples)
			sound_info.set_field("nRewoundPosition", res.playback_rewind_frame if res.playback_rewind_frame >= 0 else 0)
			return sound_info
		"GetInfo", "GetImageInfo":
			if res.image == null:
				return null
			var image_info := CsxInstance.new("ImageInfo")
			var base_position := CsxInstance.new("Point")
			base_position.set_field("x", 0)
			base_position.set_field("y", 0)
			var local_position := CsxInstance.new("Point")
			local_position.set_field("x", 0)
			local_position.set_field("y", 0)
			image_info.set_field("basePosition", base_position)
			image_info.set_field("localPosition", local_position)
			image_info.set_field("width", res.image.get_width())
			image_info.set_field("height", res.image.get_height())
			image_info.set_field("nImageWidth", res.image.get_width())
			image_info.set_field("nImageHeight", res.image.get_height())
			return image_info
		_:
			if res.host != null:
				res.host.report_unsupported("HostResource.%s" % method)
			return 0


func _to_int(v: Variant, default_val: int = 0) -> int:
	if v is int:
		return v
	if v is float or v is bool:
		return int(v)
	if v is String:
		return (v as String).to_int()
	return default_val


func _to_float(v: Variant, default_val: float = 0.0) -> float:
	if v is float:
		return v
	if v is int or v is bool:
		return float(v)
	if v is String:
		return (v as String).to_float()
	if v is CsxInstance:
		var inst := v as CsxInstance
		if inst.fields.has("x"):
			return _to_float(inst.fields["x"])
		if inst.fields.has("value"):
			return _to_float(inst.fields["value"])
	return default_val


func _dispatch_int_method(target_ref: Variant, val: int, method: String, args: Array) -> Variant:
	match method:
		"TestBit":
			var bit: int = _to_int(args[0]) if args.size() > 0 else 0
			if bit < 0 or bit >= 64:
				return 0
			return -1 if ((val >> bit) & 1) != 0 else 0
		"SetBit":
			var bit: int = _to_int(args[0]) if args.size() > 0 else 0
			if bit < 0 or bit >= 64:
				last_error = "SetBit 位索引超出范围：%d" % bit
				return 0
			var new_val: int = val | (1 << bit)
			if target_ref is CsxRef:
				if not (target_ref as CsxRef).set_value(new_val):
					last_error = "SetBit 数组/字段索引超过上限。"
			return new_val
		"ResetBit":
			var bit: int = _to_int(args[0]) if args.size() > 0 else 0
			if bit < 0 or bit >= 64:
				last_error = "ResetBit 位索引超出范围：%d" % bit
				return 0
			var new_val: int = val & ~(1 << bit)
			if target_ref is CsxRef:
				if not (target_ref as CsxRef).set_value(new_val):
					last_error = "ResetBit 数组/字段索引超过上限。"
			return new_val
		"Abs":
			return absi(val)
		"Char":
			return String.chr(val)
		"Format":
			return str(val)
		"RotateLeft":
			var bit: int = _to_int(args[0]) if args.size() > 0 else 0
			var new_val: int = (val << (bit & 31)) | (val >> (32 - (bit & 31)))
			if target_ref is CsxRef:
				if not (target_ref as CsxRef).set_value(new_val):
					last_error = "RotateLeft 数组/字段索引超过上限。"
			return new_val
		"RotateRight":
			var bit: int = _to_int(args[0]) if args.size() > 0 else 0
			var new_val: int = (val >> (bit & 31)) | (val << (32 - (bit & 31)))
			if target_ref is CsxRef:
				if not (target_ref as CsxRef).set_value(new_val):
					last_error = "RotateRight 数组/字段索引超过上限。"
			return new_val
		_:
			return 0


func _dispatch_real_method(_target_ref: Variant, val: float, method: String, args: Array) -> Variant:
	match method:
		"Abs":
			return absf(val)
		"Sqrt":
			return sqrt(val) if val >= 0 else 0.0
		"Sin":
			return sin(val)
		"Cos":
			return cos(val)
		"Tan":
			return tan(val)
		"ASin":
			return asin(val)
		"ACos":
			return acos(val)
		"ATan":
			return atan(val)
		"Round":
			return roundi(val)
		"Floor":
			return floori(val)
		"Log":
			return log(val) if val > 0 else 0.0
		"Power":
			var p: float = _to_float(args[0]) if args.size() > 0 else 1.0
			return pow(val, p)
		"Pi":
			return PI
		_:
			return 0.0


func _dispatch_file_method(file: CsxHostClass.HostFile, method: String, args: Array) -> Variant:
	match method:
		"Open":
			var path := str(args[0]) if args.size() > 0 else ""
			var mode := _to_int(args[1]) if args.size() > 1 else 2
			return file.open(path, mode)
		"Close":
			return file.close()
		"SaveObject":
			var obj = args[0] if args.size() > 0 else null
			return file.save_object(obj)
		"LoadObject":
			var obj = args[0] if args.size() > 0 else null
			return file.load_object(obj)
		"SaveThumbnailImage":
			var spr = args[0] if args.size() > 0 else null
			var w := _to_int(args[1]) if args.size() > 1 else 120
			var h := _to_int(args[2]) if args.size() > 2 else 90
			return file.save_thumbnail_image(spr, w, h)
		"IsExisting":
			var path := str(args[0]) if args.size() > 0 else ""
			return file.is_existing(path)
		"DumpContext":
			var path := str(args[0]) if args.size() > 0 else ""
			return file.dump_context(path)
		"OutputLogText":
			var path := str(args[0]) if args.size() > 0 else ""
			var text := str(args[1]) if args.size() > 1 else ""
			return file.output_log_text(path, text)
		_:
			print("[CSX VM] Unhandled File method: ", method)
			return 0


func _dispatch_window_method(win: CsxHostClass.HostWindow, method: String, args: Array) -> Variant:
	match method:
		"AddSprite":
			if args.size() >= 2:
				win.add_sprite(_to_int(args[0]), args[1])
			return 0
		"DetachSprite":
			if args.size() > 0:
				win.detach_sprite(args[0])
			return 0
		"DetachAllSprite":
			win.detach_all_sprites()
			return 0
		"GetDisplaySize":
			return win.get_display_size()
		"ShowCursor":
			return win.show_cursor(_to_int(args[0]) if args.size() > 0 else 0)
		"SetOptionalFuncFlag":
			return win.set_optional_func_flag(_to_int(args[0]) if args.size() > 0 else 0)
		"Lock":
			return win.lock()
		"Unlock":
			return win.unlock()
		"UpdateWindow":
			return 0
		"CreateDisplay":
			var m = _to_int(args[0]) if args.size() > 0 else 0
			var d = _to_int(args[1]) if args.size() > 1 else 0
			var w = _to_int(args[2]) if args.size() > 2 else 800
			var h = _to_int(args[3]) if args.size() > 3 else 600
			return win.create_display(m, d, w, h)
		"ChangeDisplay":
			return win.change_display(_to_int(args[0]) if args.size() > 0 else 0)
		"GetJoyButtonPushed":
			var key := _to_int(args[0]) if args.size() > 0 else 0
			var dev := _to_int(args[1]) if args.size() > 1 else 0
			return win.get_joy_button_pushed(key, dev, _is_polling_sprite_activation())
		"IsJoyButtonPushing":
			var key := _to_int(args[0]) if args.size() > 0 else 0
			var dev := _to_int(args[1]) if args.size() > 1 else 0
			return win.is_joy_button_pushing(key, dev)
		"FlushJoyButtonPushed":
			return win.flush_joy_button_pushed()
		"UpdateRect":
			return win.update_rect()
		"GetCommand":
			return win.get_command(args[0] if args.size() > 0 else null)
		"FlushCommandQueue":
			var flg: int = _to_int(args[0]) if args.size() > 0 else -1
			return win.flush_command_queue(flg)
		"GetCursorPos":
			var point: Variant = args[0] if not args.is_empty() else null
			_write_cursor_point(point, win.host.get_cursor_position() if win.host != null else Vector2i.ZERO)
			return point if point is CsxInstance else 0
		_:
			return 0


func _apply_operate(op: int, a: Variant, b: Variant) -> Variant:
	if a is CsxInstance and a.type_name == "Vector2D" and op in [0, 1, 2, 3]:
		var result := CsxInstance.new("Vector2D")
		for field in ["x", "y"]:
			var right: Variant = b.get_field(field) if b is CsxInstance and b.type_name == "Vector2D" else b
			result.set_field(field, _apply_operate(op, a.get_field(field), right))
		return result
	match op:
		0: # Add
			if a is Array:
				var appended_count := (b as Array).size() if b is Array else 1
				if (a as Array).size() + appended_count > MAX_VM_ARRAY_ENTRIES:
					last_error = "数组拼接结果超过上限 (%d)。" % MAX_VM_ARRAY_ENTRIES
					return []
				var res := (a as Array).duplicate()
				if b is Array:
					res.append_array(b as Array)
				else:
					res.append(b)
				return res
			if a is String or b is String:
				return ("" if a == null else str(a)) + ("" if b == null else str(b))
			if a is int and b is int:
				return int(a) + int(b)
			return _to_float(a) + _to_float(b)
		1: # Sub
			if a is int and b is int:
				return int(a) - int(b)
			return _to_float(a) - _to_float(b)
		2: # Mul
			if a is int and b is int:
				return int(a) * int(b)
			return _to_float(a) * _to_float(b)
		3: # Div
			if a is int and b is int:
				var ib := int(b)
				return (int(a) / ib) if ib != 0 else 0
			var fb := _to_float(b)
			return (_to_float(a) / fb) if fb != 0.0 else 0.0
		4: # Mod
			var ia := _to_int(a)
			var ib := _to_int(b)
			return (ia % ib) if ib != 0 else 0
		5: # And
			return _to_int(a) & _to_int(b)
		6: # Or
			return _to_int(a) | _to_int(b)
		7: # Xor
			return _to_int(a) ^ _to_int(b)
		8: # LogicalAnd
			return -1 if (is_truthy(a) and is_truthy(b)) else 0
		9: # LogicalOr
			return -1 if (is_truthy(a) or is_truthy(b)) else 0
		10: # ShiftRight
			return _to_int(a) >> _to_int(b)
		11: # ShiftLeft
			return _to_int(a) << _to_int(b)
		_:
			return 0


func _apply_unary(uop: int, a: Variant) -> Variant:
	match uop:
		0: # Plus
			return a if a != null else 0
		1: # Negate
			if a == null: return 0
			return -int(a) if a is int else -_to_float(a)
		2: # BitNot
			return ~_to_int(a)
		3: # LogicalNot
			return 0 if is_truthy(a) else -1
		_:
			return a


func _apply_compare(cmp: int, a: Variant, b: Variant) -> int:
	if a == null and b == null:
		match cmp:
			1, 3, 5: return -1
			_: return 0
	if a == null:
		a = 0 if (b is int or b is float) else ""
	if b == null:
		b = 0 if (a is int or a is float) else ""

	match cmp:
		0: # NotEqual
			if typeof(a) != typeof(b):
				if (a is int or a is float) and (b is int or b is float):
					return -1 if _to_float(a) != _to_float(b) else 0
				return -1
			return -1 if a != b else 0
		1: # Equal
			if typeof(a) != typeof(b):
				if (a is int or a is float) and (b is int or b is float):
					return -1 if _to_float(a) == _to_float(b) else 0
				return 0
			return -1 if a == b else 0
		2: # LessThan
			if (a is int or a is float) and (b is int or b is float):
				return -1 if _to_float(a) < _to_float(b) else 0
			return -1 if str(a) < str(b) else 0
		3: # LessEqual
			if (a is int or a is float) and (b is int or b is float):
				return -1 if _to_float(a) <= _to_float(b) else 0
			return -1 if str(a) <= str(b) else 0
		4: # GreaterThan
			if (a is int or a is float) and (b is int or b is float):
				return -1 if _to_float(a) > _to_float(b) else 0
			return -1 if str(a) > str(b) else 0
		5: # GreaterEqual
			if (a is int or a is float) and (b is int or b is float):
				return -1 if _to_float(a) >= _to_float(b) else 0
			return -1 if str(a) >= str(b) else 0
		_:
			return 0


func _default_for_type(type_code: int) -> Variant:
	match type_code:
		0: return null
		1: return null
		2: return []
		3: return {}
		4: return 0
		5: return 0.0
		6: return ""
		_: return null


func _read_string() -> String:
	var length := _read_s32()
	if not last_error.is_empty():
		return ""
	if length == -2147483648:
		var index := _read_s32()
		if not last_error.is_empty():
			return ""
		if index < 0 or index >= const_strings.size():
			last_error = "conststr 索引超出范围：%d" % index
			return ""
		return const_strings[index]
	if length < 0:
		last_error = "字符串长度标记无效：%d" % length
		return ""
	if length > CsxBytecodeReader.MAX_STRING_UNITS or length * 2 > image.size() - ip:
		last_error = "字符串长度超出 image 区段范围：%d" % length
		return ""
	var raw := image.slice(ip, ip + length * 2)
	ip += length * 2
	return raw.get_string_from_utf16()


func _read_u8() -> int:
	if ip < 0 or ip >= image.size():
		last_error = "指令缺少 1 字节操作数 @ 0x%X" % ip
		return 0
	var value := image[ip]
	ip += 1
	return value


func _read_u16() -> int:
	if ip < 0 or image.size() - ip < 2:
		last_error = "指令缺少 2 字节操作数 @ 0x%X" % ip
		return 0
	var value := image.decode_u16(ip)
	ip += 2
	return value


func _read_s32() -> int:
	if ip < 0 or image.size() - ip < 4:
		last_error = "指令缺少 4 字节操作数 @ 0x%X" % ip
		return 0
	var value := image.decode_s32(ip)
	ip += 4
	return value


func _read_double() -> float:
	if ip < 0 or image.size() - ip < 8:
		last_error = "指令缺少 8 字节实数操作数 @ 0x%X" % ip
		return 0.0
	var value := image.decode_double(ip)
	ip += 8
	return value


func _require_eval_stack(count: int, operation: String) -> bool:
	if count < 0 or eval_stack.size() < count:
		last_error = "%s 指令求值栈不足（需要 %d，实际 %d）。" % [operation, count, eval_stack.size()]
		return false
	return true


func _is_valid_instruction_target(target: int) -> bool:
	if not _ensure_image_validated():
		return false
	if target < 0 or target >= image.size():
		return false
	return _is_instruction_boundary(target)


func _ensure_image_validated() -> bool:
	if _image_validation_attempted:
		if not _image_validation_error.is_empty():
			last_error = _image_validation_error
			return false
		return true
	_image_validation_attempted = true
	var validation: Dictionary = bytecode_decoder.validate_image(image, const_strings.size())
	if not validation.get("ok", false):
		_image_validation_error = str(validation.get("error", "image 指令无效。"))
		last_error = "CSX image 验证失败：%s" % _image_validation_error
		return false
	instruction_starts = validation["instruction_starts"]
	_image_validation_error = ""
	return true


func resolve_value(v: Variant) -> Variant:
	if v is CsxRef:
		return (v as CsxRef).get_value()
	return v


func _write_cursor_point(point: Variant, position: Vector2i) -> void:
	if point is CsxInstance:
		(point as CsxInstance).set_field("x", position.x)
		(point as CsxInstance).set_field("y", position.y)
