extends SceneTree

# Usage: godot --headless --path godot_port --script res://tools/audit_native_api.gd -- GAME_DIR

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")

const AUDITED_METHODS := [
	"LoadSound", "AttachSound", "LoadImage", "Play", "PlayFrom", "SetRewindingPortion",
	"Stop", "Pause", "Restart", "Release", "SetVolume", "SetVolumeEnvelope",
	"CancelVolumeEnvelope", "GetSoundInfo", "GetWaveData", "LoadMidi", "SaveImage",
	"GetPixel", "GetPixelRect", "SetPixelRect", "GetInfo", "GetImageInfo",
	"SetEffectParameter", "SetMeshWarpEffect", "OpenMovie", "PlayMovie",
	"IsMoviePlaying", "StopMovie", "CloseMovie",
]

const EFFECT_TYPES := [
	"TileImage", "FilterWhite", "FilterLight", "FilterBlack", "FilterDark",
	"RasterScroll", "WaveCircle", "Shimmer", "MeshWarp", "ShadingOff", "ShadingLight",
	"SmashParticle2D", "SmashParticle3D",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass game directory after --")
		quit(2)
		return
	var vm := CsxVMReader.new(CsxHostClass.new(args[0]))
	var loaded: Dictionary = vm.load_csx(args[0].path_join("system/yosuga.csx"))
	if not loaded.get("ok", false):
		push_error("Could not load yosuga.csx: %s" % loaded.get("error", "unknown"))
		quit(1)
		return

	var calls: Dictionary = {}
	var callsites: Dictionary = {}
	var volume_callsites: Dictionary = {}
	var movie_callsites: Dictionary = {}
	var effect_literals: Dictionary = {}
	var cursor := 0
	while cursor < vm.image.size():
		var batch: Dictionary = vm.bytecode_decoder.decode(vm.image, cursor, 10000)
		if not batch.get("ok", false):
			push_error("CSX decode failed: %s" % batch.get("error", "unknown"))
			quit(1)
			return
		for instruction: Dictionary in batch["instructions"]:
			var operands: Dictionary = instruction["operands"]
			var literal: Variant = operands.get("value", {})
			if literal is Dictionary and int(literal.get("type", -1)) == 6:
				var literal_value := str(literal.get("value", ""))
				if EFFECT_TYPES.has(literal_value):
					effect_literals[literal_value] = int(effect_literals.get(literal_value, 0)) + 1
			if int(instruction["opcode"]) != 8:
				continue
			var method_name := str(operands.get("name", ""))
			if not AUDITED_METHODS.has(method_name):
				continue
			var mode := int(operands.get("mode", -1))
			var key := "%s mode=%d" % [method_name, mode]
			calls[key] = int(calls.get(key, 0)) + 1
			if method_name == "SetEffectParameter":
				callsites[int(instruction["address"])] = _function_owner(vm.functions, int(instruction["address"]))
			if method_name in ["SetVolume", "SetVolumeEnvelope", "GetVolume", "SetRewindingPortion"]:
				volume_callsites[int(instruction["address"])] = "%s %s mode=%d" % [method_name, _function_owner(vm.functions, int(instruction["address"])), mode]
			if method_name in ["OpenMovie", "PlayMovie", "IsMoviePlaying", "StopMovie", "CloseMovie"]:
				movie_callsites[int(instruction["address"])] = "%s mode=%d" % [_function_owner(vm.functions, int(instruction["address"])), mode]
		cursor = int(batch.get("next_address", cursor))
		if cursor <= 0:
			push_error("CSX decoder failed to advance")
			quit(1)
			return

	print("CSX instructions=%d functions=%d conststr=%d" % [vm.instruction_starts.size(), vm.functions.size(), vm.const_strings.size()])
	var call_keys: Array = calls.keys()
	call_keys.sort()
	print("Observed native API callsites:")
	for key in call_keys:
		print("  %s count=%d" % [key, calls[key]])
	var site_addresses: Array = callsites.keys()
	site_addresses.sort()
	print("SetEffectParameter callsites:")
	for address in site_addresses:
		print("  0x%X %s" % [address, callsites[address]])
	var volume_addresses: Array = volume_callsites.keys()
	volume_addresses.sort()
	print("Audio parameter callsites:")
	for address in volume_addresses:
		print("  0x%X %s" % [address, volume_callsites[address]])
	var literal_names: Array = effect_literals.keys()
	literal_names.sort()
	print("Effect type literals:")
	for effect_type in literal_names:
		print("  %s count=%d" % [effect_type, effect_literals[effect_type]])
	var movie_addresses: Array = movie_callsites.keys()
	movie_addresses.sort()
	print("Movie callsites:")
	for address in movie_addresses:
		print("  0x%X %s" % [address, movie_callsites[address]])
	quit(0)


func _function_owner(functions: Dictionary, address: int) -> String:
	var owner := "<unknown>"
	var owner_address := -1
	for name: String in functions:
		var function_address := int(functions[name])
		if function_address <= address and function_address > owner_address:
			owner = name
			owner_address = function_address
	return "%s@0x%X" % [owner, owner_address]
