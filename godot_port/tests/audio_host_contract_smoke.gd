extends "res://tests/smoke_test_base.gd"

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host = CsxHostClass.new("")
	host.bgm_player = _new_player("BGM")
	host.env_se_player = _new_player("EnvSE")
	host.se_player = _new_player("SE")
	host.voice_player = _new_player("Voice")
	host.system_player = _new_player("System")
	for channel in ["bgm", "env_se", "se", "voice", "system"]:
		host.audio_right_players[channel] = _new_player("%sRight" % channel)

	var bgm: Variant = _resource(host, "BGM07.mio", "bgm")
	var se: Variant = _resource(host, "SE001.mio", "se")
	var env_se: Variant = _resource(host, "SE270.mio", "env_se")
	var voice: Variant = _resource(host, "SR000001.mio", "voice")
	expect(bgm.play() == 1 and host.bgm_player.playing, "HostResource.play must start the selected BGM player")
	expect(se.play() == 1 and host.se_player.playing, "HostResource.play must start the selected SE player")
	expect(se.play(-2, 1) == 1 and se.current_position == 0, "Native Play sentinel -2 and flag 1 must start at the beginning")
	expect(env_se.play(0, 1) == 1 and host.env_se_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Native environment sound Play must retain the channel loop policy")
	expect(voice.play(-2, 2) == 1 and host.voice_player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Native voice Play flag 2 must keep one-shot playback")
	expect(se.play(-2, 3) == 1 and se.play_type == CsxHostClass.AUDIO_PLAY_TYPE_SYSTEM, "Native Play must accept the SDK System category flag")
	expect(se.play(-2, 4) == -1 and host.last_error.contains("flag=4"), "Unknown native Play flags must be reported instead of ignored")
	expect(se.play(20, 1) == 1 and se.current_position == 20, "Native Play start positions must use PCM frames")
	se.stop()
	env_se.stop()
	voice.stop()
	expect(host.bgm_player.stream != bgm.audio_stream, "Playback must use a duplicate of the cached stream")
	expect(host.bgm_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGM playback must retain the host's looping policy")
	expect(bgm.audio_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "BGM playback must not mutate the shared source stream")
	expect(host.se_player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "SE must not loop by default")
	expect(host.se_player.stream.data == se.audio_stream.data, "The stream supplied to HostResource must be the stream actually played")

	expect(bgm.set_volume(0.4, 0.4) == 1, "HostResource.set_volume must report success for an initialized channel")
	expect(is_equal_approx(host.get_audio_channel_volume("bgm"), 0.4), "HostResource.set_volume must update the matching Godot player")
	expect(bgm.set_total_volume(CsxHostClass.AUDIO_PLAY_TYPE_MUSIC, 0.5) == 1, "SetTotalVolume must update the SDK Music master volume")
	expect(is_equal_approx(bgm.get_total_volume(CsxHostClass.AUDIO_PLAY_TYPE_MUSIC), 0.5), "GetTotalVolume must return the selected SDK category master volume")
	expect(is_equal_approx(host.get_audio_channel_volume("bgm"), 0.2), "Changing a category master must scale currently playing resources of that category")
	bgm.set_total_volume(CsxHostClass.AUDIO_PLAY_TYPE_MUSIC, 1.0)
	var volume_out := {"left": 0.0, "right": 0.0}
	var vm = CsxVMClass.new(host)
	var volume_result: int = vm._dispatch_resource_method(
		bgm,
		"GetVolume",
		[CsxVMClass.CsxRef.new(volume_out, "left"), CsxVMClass.CsxRef.new(volume_out, "right")]
	)
	expect(volume_result == 0 and is_equal_approx(volume_out.left, 0.4) and is_equal_approx(volume_out.right, 0.4), "GetVolume must return Entis success code 0 and write both native output references")
	var sound_info: Variant = vm._dispatch_resource_method(bgm, "GetSoundInfo", [])
	expect(sound_info is CsxVMClass.CsxInstance and sound_info.get_field("nSamplesPerSec") == 22050 and sound_info.get_field("nChannelCount") == 2, "GetSoundInfo must expose native PCM format metadata")
	expect(sound_info.get_field("nSampleCount") == 22050 and sound_info.get_field("nResourceBytes") == bgm.audio_stream.data.size(), "GetSoundInfo must report PCM sample and byte counts")
	var resource_info: Variant = vm._dispatch_resource_method(bgm, "GetInfo", [])
	expect(resource_info is CsxVMClass.CsxInstance and resource_info.type_name == "SoundInfo" and resource_info.get_field("nSampleCount") == 22050, "Resource.GetInfo must return SoundInfo when the resource owns audio")
	var pixel_resource: Variant = _resource(host, "pixel-test.eri", "")
	pixel_resource.audio_stream = null
	pixel_resource.image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pixel_resource.image_frames.append(pixel_resource.image)
	var image_info: Variant = vm._dispatch_resource_method(pixel_resource, "GetInfo", [])
	expect(image_info is CsxVMClass.CsxInstance and image_info.type_name == "ImageInfo" and image_info.get_field("nImageWidth") == 2 and image_info.get_field("nImageHeight") == 2, "Resource.GetInfo must return complete image dimensions")
	expect(image_info.get_field("nFormatType") == 0x04000001 and image_info.get_field("nBitsPerPixel") == 32 and image_info.get_field("nFrameCount") == 1 and image_info.get_field("nResourceBytes") == 16, "Resource.GetInfo must report native ARGB frame storage metadata")
	var info_sprite: Variant = CsxHostClass.HostSprite.new(0, host)
	info_sprite.image = pixel_resource.image
	info_sprite.animation_frames.append(pixel_resource.image)
	info_sprite.size = Vector2i(2, 2)
	var sprite_info: Variant = vm._dispatch_sprite_method(info_sprite, "GetInfo", [])
	expect(sprite_info is CsxVMClass.CsxInstance and sprite_info.type_name == "ImageInfo" and sprite_info.get_field("nFormatType") == 0x04000001 and sprite_info.get_field("nBitsPerPixel") == 32 and sprite_info.get_field("nFrameCount") == 1 and sprite_info.get_field("nResourceBytes") == 16, "Sprite.GetInfo must expose native image storage metadata")
	pixel_resource.image.set_pixel(0, 0, Color8(0x12, 0x34, 0x56, 0x78))
	pixel_resource.image.set_pixel(1, 0, Color8(0x9a, 0xbc, 0xde, 0xf0))
	expect(vm._dispatch_resource_method(pixel_resource, "GetPixel", [0, 0]) == 0x78123456, "GetPixel must expose native 0xAARRGGBB values")
	var pixel_rect: Array = []
	expect(vm._dispatch_resource_method(pixel_resource, "GetPixelRect", [pixel_rect, 0, 0, 2, 1]) == 0, "GetPixelRect must return Entis success code 0 and fill CSX arrays")
	expect(pixel_rect == [0x78123456, 0xf09abcde], "GetPixelRect must preserve native pixel order and channel packing")
	expect(vm._dispatch_resource_method(pixel_resource, "SetPixelRect", [[0x80402010, 0xffabcdef], 0, 1, 2, 1]) == 0, "SetPixelRect must return Entis success code 0 and write native packed colors into images")
	expect(vm._dispatch_resource_method(pixel_resource, "GetPixel", [0, 1]) == 0x80402010 and vm._dispatch_resource_method(pixel_resource, "GetPixel", [1, 1]) == 0xffabcdef, "SetPixelRect writes must round-trip through GetPixel")
	expect(bgm.pause() == 1 and host.bgm_player.stream_paused, "HostResource.pause must pause the matching player")
	expect(bgm.restart() == 1 and not host.bgm_player.stream_paused, "HostResource.restart must resume a paused player")
	expect(se.play_from(0, -1, true) == 1, "HostResource.play_from must start and accept the repeat option")
	expect(host.se_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "HostResource.play_from repeat must enable playback looping")
	expect(se.audio_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "HostResource.play_from must not mutate the shared source stream")
	expect(se.is_repeating, "HostResource must retain the active repeat state for restart")

	se.stop()
	expect(se.play_from(20, 100, false) == 1, "PlayFrom must start a bounded one-shot")
	expect(host.se_player.stream.data.size() == 100 * 4, "One-shot playback must end after frame 100")
	expect(se.audio_stream.data.size() == 22050 * 4, "Truncating playback must preserve the source PCM")
	expect(se.play_from(10, 100, true, 20) == 1, "PlayFrom must support a loop with a distinct intro and rewind point")
	expect(host.se_player.stream.loop_begin == 20 and host.se_player.stream.loop_end == 100, "WAV loop points must use PCM frames")
	expect(host.se_player.stream.data.size() == se.audio_stream.data.size(), "Loop playback must keep the full source PCM")
	expect(se.pause() == 1 and se.restart() == 1, "Pause and resume must keep the custom loop")
	expect(host.se_player.stream.loop_begin == 20 and host.se_player.stream.loop_end == 100, "Resuming must preserve the loop bounds")
	expect(se.play_from(100, 100, true, 20) == 0, "An empty playback range must be rejected")
	expect(host.se_player.stream.loop_begin == 20 and host.se_player.stream.loop_end == 100, "An invalid request must preserve the active loop")
	expect(se.play_from(0, 100, true, 100) == 0, "Rewind at the end frame must be rejected")
	se.stop()
	expect(vm._dispatch_resource_method(se, "SetRewindingPortion", [20, 100, -1]) == 0, "SetRewindingPortion must return Entis success code 0 for valid SDK frame bounds")
	expect(se.play(-2, 1) == 1, "Play must apply a configured rewinding portion")
	expect(host.se_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and host.se_player.stream.loop_begin == 20 and host.se_player.stream.loop_end == 100, "Configured rewinding bounds must drive native Play looping")
	se.stop()
	expect(vm._dispatch_resource_method(se, "SetRewindingPortion", [100, 100, 1]) == 1, "SetRewindingPortion must return Entis failure code 1 and reject an empty range")
	expect(host.bgm_player.stream.loop_begin == 0 and host.bgm_player.stream.loop_end == 22050, "Default loop must cover the whole track")
	se.stop()
	expect(se.play_from(0, -1, false, -1, 1) == 1 and se.play_type == CsxHostClass.AUDIO_PLAY_TYPE_SOUND, "PlayFrom must accept the SDK Sound category flag")
	expect(se.play_from(0, -1, false, -1, 4) == -1, "Unknown PlayFrom category flags must be reported and rejected")
	var volume_curve: Variant = _linear_volume_curve(0.0, 0.8)
	expect(se.set_volume_envelope(volume_curve, 1000) == 1, "SetVolumeEnvelope must accept a native Bezier2D curve")
	expect(se.is_volume_envelope_pending() == -1, "A timed volume envelope must report as pending")
	host.advance_audio_envelopes(0.5)
	expect(is_equal_approx(host.get_audio_channel_volume("se"), 0.4), "The native Bezier volume envelope must interpolate over elapsed time")
	expect(se.cancel_volume_envelope() == 0 and se.is_volume_envelope_pending() == 0, "CancelVolumeEnvelope must stop the active envelope")
	expect(is_equal_approx(host.get_audio_channel_volume("se"), 0.4), "CancelVolumeEnvelope must hold the current volume")
	expect(se.set_volume_envelope(volume_curve, 100) == 1, "A new envelope must replace the cancelled envelope")
	host.advance_audio_envelopes(0.1)
	expect(se.is_volume_envelope_pending() == 0 and is_equal_approx(host.get_audio_channel_volume("se"), 0.8), "A completed envelope must reach its endpoint and clear its pending state")

	expect(se.set_volume(0.2, 0.8) == 1, "SetVolume must preserve independent left and right channel values")
	var se_right_player: AudioStreamPlayer = host.audio_right_players["se"]
	expect(bool(host.se_player.get_meta("csx_dual_channel", false)) and se_right_player.stream is AudioStreamWAV, "Asymmetric playback must split and route both output channels")
	expect(host.se_player.stream.data.slice(0, 4) == PackedByteArray([0x34, 0x12, 0, 0]), "The left playback lane must preserve left PCM and silence its right lane")
	expect(se_right_player.stream.data.slice(0, 4) == PackedByteArray([0, 0, 0xcc, 0xed]), "The right playback lane must preserve right PCM and silence its left lane")
	var pcm8 := AudioStreamWAV.new()
	pcm8.format = AudioStreamWAV.FORMAT_8_BITS
	pcm8.mix_rate = 22050
	pcm8.stereo = true
	pcm8.data = PackedByteArray([10, 20, 30, 40])
	var left8: AudioStreamWAV = host._make_audio_lane_stream(pcm8, 0)
	var right8: AudioStreamWAV = host._make_audio_lane_stream(pcm8, 1)
	expect(left8.data == PackedByteArray([10, 128, 30, 128]) and right8.data == PackedByteArray([128, 20, 128, 40]), "8-bit PCM splitting must use unsigned silence and retain channel samples")
	expect(is_equal_approx(host.get_audio_channel_volume("se"), 0.2), "SetVolume must apply the left channel gain")
	expect(is_equal_approx(db_to_linear(se_right_player.volume_db), 0.8), "SetVolume must apply the right channel gain independently")
	var asymmetric_curve: Variant = _volume_curve(0.2, 0.8, 0.4, 0.6)
	expect(se.set_volume_envelope(asymmetric_curve, 1000) == 1, "SetVolumeEnvelope must preserve separate channel curves")
	host.advance_audio_envelopes(0.5)
	expect(is_equal_approx(host.get_audio_channel_volume("se"), 0.3), "The left volume envelope must interpolate independently")
	expect(is_equal_approx(db_to_linear(se_right_player.volume_db), 0.7), "The right volume envelope must interpolate independently")
	expect(se.pause() == 1 and se_right_player.stream_paused, "Pausing an asymmetric stream must pause both channel players")
	expect(se.restart() == 1 and not se_right_player.stream_paused, "Resuming an asymmetric stream must resume both channel players")

	expect(host.resolve_audio_channel("BGM01.mio") == "bgm", "BGM filename classification must remain supported")
	expect(host.resolve_audio_channel("SE270.mio") == "env_se", "Environment SE filename classification must remain supported")
	expect(host.resolve_audio_channel("SE001.mio") == "se", "SE filename classification must remain supported")
	expect(host.resolve_audio_channel("SR000001.mio") == "voice", "Voice filename classification must remain supported")
	expect(host.resolve_audio_channel("other.mio", "voice.noa") == "voice", "Voice archive classification must remain supported")
	expect(host.resolve_audio_channel("untyped.mio", "sound.noa").is_empty(), "Unknown audio type must not be guessed")
	expect(not host.play_audio_stream(_silence_stream(), "untyped.mio"), "Unknown audio type must fail instead of claiming playback")
	expect(host.last_error.contains("声道"), "Unknown audio type failure must be visible")
	expect(se.play() == 1 and host.se_player.playing, "SE playback must remain available after a rejected unsupported request")
	expect(bgm.play_from(0, -1, false) == 1, "BGM PlayFrom must honor an explicit non-repeat request")
	expect(host.bgm_player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "PlayFrom repeat=false must disable the BGM channel default loop")

	expect(bgm.stop() == 1, "HostResource.stop must report that its selected channel stopped")
	expect(not host.bgm_player.playing, "HostResource.stop must stop BGM")
	expect(host.se_player.playing, "Stopping BGM must not stop the SE player")
	expect(se.stop() == 1 and not host.se_player.playing, "HostResource.stop must stop the selected SE player")

	expect(se.play_from(2205, 4410, false) == 1, "A one-shot must play from a nonzero frame")
	await create_timer(0.35).timeout
	expect(not host.se_player.playing, "A bounded one-shot must finish before the original file ends")
	expect(se.play_from(0, 2205, true, 1102) == 1, "A short intro and loop must play")
	await create_timer(0.35).timeout
	expect(host.se_player.playing, "Repeating playback must continue past its first end frame")
	var playback_frame: int = se.get_playing_position()
	expect(playback_frame >= 1102 and playback_frame <= 2205, "The mixer must wrap to the rewind frame, not the intro")
	se.stop()
	var attached_resource = CsxHostClass.HostResource.new("attached-se", "sound.noa", -1, 0, 0, host)
	expect(vm._dispatch_resource_method(attached_resource, "AttachSound", [se]) == 0, "AttachSound must return Entis success code 0 and bind a loaded waveform resource")
	var attached_stream: AudioStreamWAV = attached_resource.audio_stream
	se.release()
	expect(attached_resource.audio_stream == attached_stream and attached_resource.play() == 1, "Attached audio must remain playable after its source Resource is released")
	expect(attached_resource.stop() == 1, "An attached sound Resource must stop its selected audio channel")

	var test_players: Array[AudioStreamPlayer] = []
	for player_value: Variant in [host.bgm_player, host.env_se_player, host.se_player, host.voice_player, host.system_player] + host.audio_players.values() + host.audio_right_players.values():
		if player_value is AudioStreamPlayer and not test_players.has(player_value):
			test_players.append(player_value)
	host.shutdown_runtime()
	for player: AudioStreamPlayer in test_players:
		if is_instance_valid(player):
			player.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	finish_success("PASS HostResource audio routing, PCM playback ranges, pause/resume, volume, and stop contract")


func _new_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	root.add_child(player)
	return player


func _resource(host: Variant, resource_name: String, channel: String) -> Variant:
	var resource = CsxHostClass.HostResource.new(resource_name, "sound.noa", 0, 0, 0, host)
	resource.audio_channel = channel
	resource.audio_stream = _silence_stream()
	return resource


func _silence_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = true
	var silence := PackedByteArray()
	silence.resize(22050 * 2 * 2)
	silence[0] = 0x34
	silence[1] = 0x12
	silence[2] = 0xcc
	silence[3] = 0xed
	stream.data = silence
	return stream


func _linear_volume_curve(start_volume: float, end_volume: float) -> Variant:
	return _volume_curve(start_volume, start_volume, end_volume, end_volume)


func _volume_curve(start_left: float, start_right: float, end_left: float, end_right: float) -> Variant:
	var curve = CsxVMClass.CsxInstance.new("Bezier2D")
	var points: Array = []
	for step in range(4):
		var point = CsxVMClass.CsxInstance.new("Point")
		var t := float(step) / 3.0
		point.set_field("x", lerpf(start_left, end_left, t))
		point.set_field("y", lerpf(start_right, end_right, t))
		points.append(point)
	curve.set_field("parent", points)
	return curve
