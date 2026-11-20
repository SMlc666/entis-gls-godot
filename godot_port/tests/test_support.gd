extends RefCounted
class_name GodotPortTestSupport

const SAVE_ROOT := "user://test_saves"


static func new_save_dir(suite_name: String) -> String:
	var run_id := "%s_%d_%d" % [suite_name, OS.get_process_id(), Time.get_ticks_usec()]
	return SAVE_ROOT.path_join(run_id)


static func configure_player_saves(player: Variant, suite_name: String) -> String:
	var test_dir := new_save_dir(suite_name)
	player.save_dir_override = test_dir
	return test_dir


static func resolve_game_dir(args: PackedStringArray) -> String:
	var game_dir := ""
	for argument in args:
		if not argument.begins_with("--"):
			game_dir = argument
			break
	if game_dir.is_empty():
		game_dir = OS.get_environment("YOSUGA_GAME_DIR")
	if game_dir.is_empty():
		game_dir = ProjectSettings.globalize_path("res://assets")
	if game_dir.ends_with(".csx"):
		game_dir = game_dir.get_base_dir()
		if game_dir.get_file() == "system":
			game_dir = game_dir.get_base_dir()
	return game_dir.simplify_path() if _has_game_files(game_dir) else ""


static func _has_game_files(game_dir: String) -> bool:
	return (
		not game_dir.is_empty()
		and FileAccess.file_exists(game_dir.path_join("system/yosuga.csx"))
		and FileAccess.file_exists(game_dir.path_join("data1.noa"))
	)


static func uses_isolated_saves(host: Variant, test_dir: String) -> bool:
	return host != null and host.save_dir == test_dir and test_dir.begins_with(SAVE_ROOT + "/")


static func remove_test_saves(test_dir: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(test_dir)
	_remove_tree_contents(absolute_path)
	DirAccess.remove_absolute(absolute_path)


static func _remove_tree_contents(absolute_path: String) -> void:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	for child_dir in directory.get_directories():
		var child_path := absolute_path.path_join(child_dir)
		_remove_tree_contents(child_path)
		DirAccess.remove_absolute(child_path)
	for file_name in directory.get_files():
		DirAccess.remove_absolute(absolute_path.path_join(file_name))
