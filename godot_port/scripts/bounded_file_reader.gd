extends RefCounted
class_name BoundedFileReader


static func read(path: String, max_bytes: int) -> Dictionary:
	if path.is_empty() or max_bytes <= 0:
		return {"ok": false, "error": "文件路径或读取上限无效。"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法打开文件: %s (%s)" % [path, error_string(FileAccess.get_open_error())]}
	var length := file.get_length()
	if length < 0 or length > max_bytes:
		file.close()
		return {"ok": false, "error": "文件长度 %d 超过读取上限 %d: %s" % [length, max_bytes, path]}
	var bytes := file.get_buffer(int(length))
	file.close()
	if bytes.size() != length:
		return {"ok": false, "error": "文件读取不完整: %s" % path}
	return {"ok": true, "data": bytes}
