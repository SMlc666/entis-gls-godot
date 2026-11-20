extends RefCounted

const LinuxSidecar = preload("res://scripts/linux_sidecar.gd")
const MAX_OUTPUT_SIZE := 128 * 1024 * 1024


static func convert(data: PackedByteArray, decoder: String, input_ext: String, output_ext: String) -> Dictionary:
	if OS.get_name() != "Linux":
		return {"ok": false, "error": "当前预览解码器仅支持 Linux。"}
	var sidecar := LinuxSidecar.resolve("arc_unpacker", "YOSUGA_ARC_UNPACKER")
	if not sidecar.get("ok", false):
		return {"ok": false, "error": str(sidecar.get("error", "Linux 资源解码器不可用。"))}
	var executable := str(sidecar.get("path", ""))

	var work_dir := ProjectSettings.globalize_path("user://codec_preview/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var mkdir_error := DirAccess.make_dir_recursive_absolute(work_dir)
	if mkdir_error != OK:
		return {"ok": false, "error": "无法创建预览临时目录：%s" % error_string(mkdir_error)}
	var input_path := work_dir.path_join("input." + input_ext)
	var output_path := work_dir.path_join("input." + output_ext)
	var input := FileAccess.open(input_path, FileAccess.WRITE)
	if input == null:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "无法创建临时资源文件。"}
	input.store_buffer(data)
	var write_error := input.get_error()
	input.close()
	if write_error != OK:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "无法写入临时资源：%s" % error_string(write_error)}

	var output: Array = []
	var exit_code := OS.execute(executable, PackedStringArray([
		"--dec=" + decoder, "--threads=1", "--no-color", "--no-vfs", "--out=" + work_dir, input_path,
	]), output, true)
	if exit_code < 0:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "OS.execute 无法启动 Linux sidecar：%s" % executable}
	if exit_code != 0 or not FileAccess.file_exists(output_path):
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "资源解码失败（退出码 %d）。%s" % [exit_code, "\n".join(PackedStringArray(output))]}
	var output_file := FileAccess.open(output_path, FileAccess.READ)
	if output_file == null:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "无法读取解码后的资源。"}
	var output_size := output_file.get_length()
	if output_size <= 0 or output_size > MAX_OUTPUT_SIZE:
		output_file.close()
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "解码后的资源大小超出预览上限。"}
	var converted := output_file.get_buffer(output_size)
	output_file.close()
	_cleanup(work_dir, input_path, output_path)
	if converted.size() != output_size:
		return {"ok": false, "error": "解码后的资源读取不完整。"}
	return {"ok": true, "data": converted}


static func _cleanup(work_dir: String, input_path: String, output_path: String) -> void:
	if FileAccess.file_exists(input_path):
		DirAccess.remove_absolute(input_path)
	if FileAccess.file_exists(output_path):
		DirAccess.remove_absolute(output_path)
	DirAccess.remove_absolute(work_dir)
