extends SceneTree

const Index = preload("res://scripts/csx_index.gd")
const Bytecode = preload("res://scripts/csx_bytecode.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Pass a CSX path after --")
		quit(1)
		return
	var idx = Index.new()
	var path := args[0]
	var checksum := FileAccess.get_sha256(path)
	var indexed: Dictionary = idx.inspect(path)
	if not indexed.get("ok", false):
		_fail(str(indexed))
		return
	var image := {}
	for section in idx.sections:
		if section["name"] == "image":
			image = section
	if image.is_empty():
		_fail("missing image")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(image["offset"])
	var data := f.get_buffer(image["size"])
	var parser = Bytecode.new()
	var pos := 0
	var count := 0
	var boundaries := {}
	var targets: Array[int] = []
	while pos < data.size():
		var result: Dictionary = parser.decode(data, pos, 10000)
		if not result.get("ok", false):
			_fail("after %d instructions: %s" % [count + result["instructions"].size(), result["error"]])
			return
		for instruction in result["instructions"]:
			boundaries[instruction["address"]] = true
			if instruction["operands"].has("target"):
				targets.append(instruction["operands"]["target"])
		count += result["instructions"].size()
		pos = result["next_address"]
	for entry in idx.functions:
		if not boundaries.has(entry["address"]):
			_fail("function not on instruction boundary: %s %X" % [entry["name"], entry["address"]])
			return
	for address in idx.prologue_addresses:
		if not boundaries.has(address):
			_fail("prologue not on instruction boundary: %X" % address)
			return
	for target in targets:
		if not boundaries.has(target):
			_fail("branch not on instruction boundary: %X" % target)
			return
	if parser.decode(PackedByteArray([2]), 0).get("ok", false):
		_fail("truncated instruction accepted")
		return
	if parser.decode(PackedByteArray([255]), 0).get("ok", false):
		_fail("unknown opcode accepted")
		return
	if checksum != FileAccess.get_sha256(path):
		_fail("CSX changed")
		return
	print("PASS decoded %d instructions; %d functions, %d prologues and %d branch targets on boundaries" % [count, idx.functions.size(), idx.prologue_addresses.size(), targets.size()])
	quit(0)

func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
