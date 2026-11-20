extends RefCounted

const DEFAULT_STATE: Dictionary = {
	"bgm_volume": 0.8,
	"se_volume": 0.8,
	"system_volume": 0.8,
	"voice_volume": 1.0,
	"message_speed": 3000,
	"auto_delay_seconds": 2.0,
	"bgm_muted": false,
	"se_muted": false,
	"system_muted": false,
	"voice_muted": false,
}

var _values: Dictionary = DEFAULT_STATE.duplicate()


func reset_defaults() -> void:
	_values = DEFAULT_STATE.duplicate()


func set_audio_volume(channel: String, value: float) -> void:
	var key := "%s_volume" % channel.to_lower()
	if _values.has(key):
		_values[key] = clampf(value, 0.0, 1.0)


func audio_volume(channel: String) -> float:
	var key := "%s_volume" % channel.to_lower()
	return float(_values.get(key, 1.0))


func set_muted(channel: String, muted: bool) -> void:
	var key := "%s_muted" % channel.to_lower()
	if _values.has(key):
		_values[key] = muted


func is_muted(channel: String) -> bool:
	var key := "%s_muted" % channel.to_lower()
	return bool(_values.get(key, false))


func set_message_speed(value: int) -> void:
	_values["message_speed"] = clampi(value, 500, 10000)


func message_speed() -> int:
	return int(_values.get("message_speed", 3000))


func set_auto_delay_seconds(value: float) -> void:
	_values["auto_delay_seconds"] = clampf(value, 1.0, 5.0)


func auto_delay_seconds() -> float:
	return float(_values.get("auto_delay_seconds", 2.0))


func to_dictionary() -> Dictionary:
	return _values.duplicate()


func restore(values: Dictionary) -> void:
	for channel in ["bgm", "se", "system", "voice"]:
		var volume: Variant = values.get(channel + "_volume")
		if (volume is int or volume is float) and is_finite(float(volume)):
			set_audio_volume(channel, float(volume))
		var muted: Variant = values.get(channel + "_muted")
		if muted is bool:
			set_muted(channel, muted)
	var speed: Variant = values.get("message_speed")
	if (speed is int or speed is float) and is_finite(float(speed)):
		set_message_speed(int(clampf(float(speed), 500.0, 10000.0)))
	var delay: Variant = values.get("auto_delay_seconds")
	if (delay is int or delay is float) and is_finite(float(delay)):
		set_auto_delay_seconds(float(delay))
