extends RefCounted

const EXECUTE_MASK := (
	FileAccess.UNIX_EXECUTE_OWNER
	| FileAccess.UNIX_EXECUTE_GROUP
	| FileAccess.UNIX_EXECUTE_OTHER
)


static func resolve(executable_name: String, environment_variable: String) -> Dictionary:
	if OS.get_name() != "Linux":
		return {"ok": false, "error": "Linux 外部解码器只能在 Linux 上运行。"}

	var override_path := OS.get_environment(environment_variable).strip_edges()
	if not override_path.is_empty():
		if not override_path.is_absolute_path():
			return {
				"ok": false,
				"error": "%s 必须是 sidecar ELF 的绝对路径。" % environment_variable
			}
		return _validate(override_path, environment_variable)

	var candidates: Array[String] = []
	if FileAccess.file_exists("res://project.godot"):
		candidates.append(ProjectSettings.globalize_path("res://tools/bin/linux/%s" % executable_name))
	var executable_path := OS.get_executable_path()
	if not executable_path.is_empty():
		candidates.append(
			executable_path.get_base_dir().path_join("tools/bin/linux/%s" % executable_name)
		)

	var attempted_paths := PackedStringArray()
	for candidate in candidates:
		attempted_paths.append(candidate)
		if FileAccess.file_exists(candidate):
			return _validate(candidate, "")

	var attempted_text := "\n".join(attempted_paths)
	return {
		"ok": false,
		"error": (
			"找不到可执行的 Linux sidecar '%s'。res:// 资源在 PCK 中不会自动成为 OS 可执行文件。"
			+ "开发目录请先构建 Linux helper；导出应用请将它作为普通文件放在应用目录 tools/bin/linux/ 下，"
			+ "或设置 %s 为绝对路径。"
			+ ("\n已检查：\n" + attempted_text if not attempted_text.is_empty() else "")
		) % [executable_name, environment_variable]
	}


static func _validate(path: String, environment_variable: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		var source := environment_variable if not environment_variable.is_empty() else "sidecar 路径"
		return {"ok": false, "error": "%s 指向的文件不存在：%s" % [source, path]}
	var permissions := FileAccess.get_unix_permissions(path)
	if permissions < 0 or (permissions & EXECUTE_MASK) == 0:
		return {"ok": false, "error": "Linux sidecar 没有可执行权限：%s（可用 chmod +x 修复）" % path}
	return {"ok": true, "path": path}
