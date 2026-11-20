extends "res://tests/smoke_test_base.gd"

const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host = CsxHostClass.new("")
	host.bgm_player = _new_player("BGM")
	host.env_se_player = _new_player("EnvSE")
	host.se_player = _new_player("SE")
	host.voice_player = _new_player("Voice")
	host.system_player = _new_player("System")

	var bgm: Variant = _resource(host, "BGM07.mio", "bgm")
	var se: Variant = _resource(host, "SE001.mio", "se")
	expect(bgm.play() == 1 and host.bgm_player.playing, "HostResource.play must start the selected BGM player")
	expect(se.play() == 1 and host.se_player.playing, "HostResource.play must start the selected SE player")
	expect(host.bgm_player.stream != bgm.audio_stream, "Playback must use a duplicate of the cached stream")
	expect(host.bgm_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGM playback must retain the host's looping policy")
	expect(bgm.audio_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "BGM playback must not mutate the shared source stream")
	expect(host.se_player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "SE must not loop by default")
	expect(host.se_player.stream.data == se.audio_stream.data, "The stream supplied to HostResource must be the stream actually played")

	expect(bgm.set_volume(0.4, 0.4) == 1, "HostResource.set_volume must report success for an initialized channel")
	expect(is_equal_approx(host.get_audio_channel_volume("bgm"), 0.4), "HostResource.set_volume must update the matching Godot player")
	expect(bgm.pause() == 1 and host.bgm_player.stream_paused, "HostResource.pause must pause the matching player")
	expect(bgm.restart() == 1 and not host.bgm_player.stream_paused, "HostResource.restart must resume a paused player")
	expect(se.play_from(0, -1, true) == 1, "HostResource.play_from must start and accept the repeat option")
	expect(host.se_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "HostResource.play_from repeat must enable playback looping")
	expect(se.audio_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "HostResource.play_from must not mutate the shared source stream")
	expect(se.is_repeating, "HostResource must retain the active repeat state for restart")

	se.stop()
	expect(se.play_from(0, 100, false) == -1, "Unsupported PlayFrom end_pos must be reported and rejected")
	expect(not host.se_player.playing and host.last_error.contains("未实现"), "Unsupported end_pos must not silently start playback")
	expect(se.play_from(0, -1, false, 100) == -1, "Unsupported PlayFrom rewind_pos must be reported and rejected")
	expect(not host.se_player.playing, "Unsupported rewind_pos must not silently start playback")
	expect(se.play_from(0, -1, false, -1, 1) == -1, "Unsupported PlayFrom flags must be reported and rejected")
	expect(se.cancel_volume_envelope() == -1 and host.last_error.contains("未实现"), "CancelVolumeEnvelope must not pretend to be implemented")

	var volume_before_asymmetric_request := host.get_audio_channel_volume("se")
	expect(se.set_volume(0.2, 0.8) == -1, "Asymmetric stereo volume must be explicitly unsupported")
	expect(is_equal_approx(host.get_audio_channel_volume("se"), volume_before_asymmetric_request), "Unsupported stereo volume must not be averaged into a false result")

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

	print("PASS HostResource audio routing, play_from limits, pause/resume, volume, and stop contract")
	quit(0)


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
	stream.data = silence
	return stream
