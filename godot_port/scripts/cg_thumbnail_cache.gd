extends RefCounted

const MAX_DIMENSION := 360
const MAX_BYTES := 12 * 1024 * 1024

var _entries: Dictionary = {}
var _lru: Array[String] = []
var _bytes_used := 0


func get_texture(key: String) -> Texture2D:
	if not _entries.has(key):
		return null
	_lru.erase(key)
	_lru.append(key)
	return _entries[key]["texture"] as Texture2D


func cache_image(key: String, source: Image) -> Texture2D:
	if source == null or source.is_empty():
		return null
	var thumbnail := source.duplicate()
	var source_size: Vector2i = thumbnail.get_size()
	var scale_factor: float = minf(1.0, float(MAX_DIMENSION) / float(maxi(source_size.x, source_size.y)))
	if scale_factor < 1.0:
		thumbnail.resize(
			maxi(1, int(round(float(source_size.x) * scale_factor))),
			maxi(1, int(round(float(source_size.y) * scale_factor))),
			Image.INTERPOLATE_LANCZOS
		)
	var texture := ImageTexture.create_from_image(thumbnail)
	var size_bytes: int = thumbnail.get_data().size()
	if size_bytes <= 0 or size_bytes > MAX_BYTES:
		return texture
	_remove(key)
	_evict_for(size_bytes)
	_entries[key] = {"texture": texture, "bytes": size_bytes}
	_lru.append(key)
	_bytes_used += size_bytes
	return texture


func clear() -> void:
	_entries.clear()
	_lru.clear()
	_bytes_used = 0


func cached_bytes() -> int:
	return _bytes_used


func _evict_for(required_bytes: int) -> void:
	while not _lru.is_empty() and _bytes_used + required_bytes > MAX_BYTES:
		_remove(_lru[0])


func _remove(key: String) -> void:
	if not _entries.has(key):
		_lru.erase(key)
		return
	_bytes_used -= int(_entries[key].get("bytes", 0))
	_entries.erase(key)
	_lru.erase(key)
