extends RefCounted

const LinuxSidecar = preload("res://scripts/linux_sidecar.gd")
const MAX_INPUT_SIZE := 128 * 1024 * 1024
const MAX_OUTPUT_SIZE := 128 * 1024 * 1024
static var last_native_error := ""

static func decode(data: PackedByteArray, unpacked_size: int) -> Dictionary:
	if data.size() < 4 or data.size() > MAX_INPUT_SIZE:
		return {"ok": false, "error": "ERISAN 压缩数据长度超出支持范围。"}
	if unpacked_size <= 0 or unpacked_size > MAX_OUTPUT_SIZE:
		return {"ok": false, "error": "ERISAN 解压大小超出支持范围。"}
	last_native_error = ""
	if ClassDB.class_exists("YzkCodec"):
		var native_codec: Object = ClassDB.instantiate("YzkCodec")
		if native_codec != null and native_codec.has_method("decode_erisan"):
			var native_result: Variant = native_codec.call("decode_erisan", data, unpacked_size)
			if native_result is Dictionary and native_result.get("ok", false):
				var native_data: Variant = native_result.get("data", PackedByteArray())
				if native_data is PackedByteArray and native_data.size() == unpacked_size:
					return {"ok": true, "data": native_data}
				return {"ok": false, "error": "原生 ERISAN 解码器返回了长度错误的数据。"}
			if native_result is Dictionary:
				last_native_error = str(native_result.get("error", "原生 ERISAN 解码失败。"))
	if OS.get_name() != "Linux":
		var error_message := str(last_native_error)
		if error_message.is_empty():
			error_message = "此平台未加载进程内 ERISAN 解码扩展。"
		return {"ok": false, "error": error_message}
	var sidecar := LinuxSidecar.resolve("erisan_decode", "YOSUGA_ERISAN_DECODER")
	if not sidecar.get("ok", false):
		return {"ok": false, "error": str(sidecar.get("error", "Linux ERISAN 解码器不可用。"))}
	var executable := str(sidecar.get("path", ""))

	var work_dir := ProjectSettings.globalize_path("user://erisan_decode/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var mkdir_error := DirAccess.make_dir_recursive_absolute(work_dir)
	if mkdir_error != OK:
		return {"ok": false, "error": "无法创建临时目录：%s" % error_string(mkdir_error)}
	var input_path := work_dir.path_join("input.bin")
	var output_path := work_dir.path_join("output.bin")
	var input := FileAccess.open(input_path, FileAccess.WRITE)
	if input == null:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "无法创建临时压缩数据文件。"}
	input.store_buffer(data)
	var write_error := input.get_error()
	input.close()
	if write_error != OK:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "无法写入临时压缩数据：%s" % error_string(write_error)}

	var output: Array = []
	var exit_code := OS.execute(executable, PackedStringArray([input_path, output_path, str(unpacked_size)]), output, true)
	if exit_code < 0:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "OS.execute 无法启动 Linux sidecar：%s" % executable}
	if exit_code != 0 or not FileAccess.file_exists(output_path):
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "ERISAN 解码失败（退出码 %d）。%s" % [exit_code, "\n".join(PackedStringArray(output))]}
	var decoded_file := FileAccess.open(output_path, FileAccess.READ)
	if decoded_file == null or decoded_file.get_length() != unpacked_size:
		_cleanup(work_dir, input_path, output_path)
		return {"ok": false, "error": "ERISAN 输出长度不匹配。"}
	var decoded := decoded_file.get_buffer(unpacked_size)
	decoded_file.close()
	_cleanup(work_dir, input_path, output_path)
	if decoded.size() != unpacked_size:
		return {"ok": false, "error": "ERISAN 输出读取不完整。"}
	return {"ok": true, "data": decoded}


static func _cleanup(work_dir: String, input_path: String, output_path: String) -> void:
	if FileAccess.file_exists(input_path):
		DirAccess.remove_absolute(input_path)
	if FileAccess.file_exists(output_path):
		DirAccess.remove_absolute(output_path)
	DirAccess.remove_absolute(work_dir)
