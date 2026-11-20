extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var game_dir := args[0] if not args.is_empty() else OS.get_environment("YOSUGA_GAME_DIR")
	if game_dir.is_empty():
		game_dir = ProjectSettings.globalize_path("res://assets")
	if game_dir.ends_with(".csx"):
		game_dir = game_dir.get_base_dir()
		if game_dir.get_file() == "system":
			game_dir = game_dir.get_base_dir()
	var csx_path := game_dir.path_join("system/yosuga.csx")
	if not FileAccess.file_exists(csx_path):
		printerr("Usage: set YOSUGA_GAME_DIR or pass the game directory after --")
		quit(2)
		return
	var host := CsxHostClass.new(game_dir)
	var vm := CsxVMReader.new(host)
	vm.load_csx(csx_path)

	print("Matching functions:")
	for fn in vm.functions.keys():
		var l: String = fn.to_lower()
		for kw in ["title", "start", "main", "entry", "menu", "select", "init", "boot", "loop"]:
			if kw in l:
				print("  %-35s @ 0x%06X" % [fn, vm.functions[fn]])
				break
	quit(0)
