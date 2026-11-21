extends RichTextEffect

var bbcode := "native_fade"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var fade_ms := maxf(0.0, float(char_fx.env.get("fade_ms", 0.0)))
	if fade_ms <= 0.0:
		return true
	var interval_ms := maxf(0.0, float(char_fx.env.get("interval_ms", 0.0)))
	var char_start_ms := float(char_fx.relative_index) * interval_ms
	var char_elapsed_ms := char_fx.elapsed_time * 1000.0 - char_start_ms
	char_fx.color.a *= clampf(char_elapsed_ms / fade_ms, 0.0, 1.0)
	return true
