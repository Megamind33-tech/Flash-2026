## Voice chat for online matches (autoload "Voice"). Transport: Net.send_voice / Net.voice_packet (unreliable,
## ordered, channel 2, relayed by the server to everyone or to the speaker's team only).
##
## Capture: AudioStreamMicrophone on a muted "Mic" bus with an AudioEffectCapture. Frames of 40 ms are reduced to
## 16 kHz mono (box filter) and mu-law coded to 8 bits: 640 bytes per frame, ~128 kbit/s - fine on LAN and broadband;
## swap in an Opus GDExtension later for mobile data. Playback: one AudioStreamGenerator per remote speaker.
## Modes: push-to-talk (talk(true/false), e.g. the HUD's mic button) or open mic with a level gate; team-only channel;
## per-player mute. Needs project setting audio/driver/enable_input and, on Android, the RECORD_AUDIO permission
## (requested the first time voice is enabled).
extends Node

signal speaking_changed(peer: int, speaking: bool)

const RATE := 16000
const FRAME := 640                 # 40 ms at 16 kHz
const GATE := 0.02                 # open-mic RMS threshold

var enabled := false
var push_to_talk := true
var team_only := true
var muted := {}                    # peer -> true
var _talking := false
var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _acc := PackedFloat32Array()
var _players := {}                 # peer -> [AudioStreamPlayer, AudioStreamGeneratorPlayback, last_heard]


func _ready() -> void:
	Net.voice_packet.connect(_on_packet)


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		if OS.get_name() == "Android" and not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
			OS.request_permissions()
		_start_capture()
	else:
		_stop_capture()


func talk(on: bool) -> void:
	_talking = on


func toggle_mute(peer: int) -> void:
	muted[peer] = not muted.get(peer, false)


func _start_capture() -> void:
	var bus := AudioServer.get_bus_index("Mic")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Mic")
		AudioServer.set_bus_mute(bus, true)   # never play your own voice back
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	_mic.play()


func _stop_capture() -> void:
	if _mic:
		_mic.stop()
		_mic.queue_free()
		_mic = null
	_acc.clear()


func _process(_delta: float) -> void:
	if enabled and _capture and Net.is_online():
		_pump_capture()
	for peer in _players.keys():   # speaking indicators fade 0.3 s after the last packet
		var e: Array = _players[peer]
		if e[2] > 0.0 and Time.get_ticks_msec() / 1000.0 - e[2] > 0.3:
			e[2] = 0.0
			speaking_changed.emit(peer, false)


func _pump_capture() -> void:
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	var frames := _capture.get_buffer(avail)
	var step := AudioServer.get_mix_rate() / RATE
	var pos := 0.0
	while pos + step <= frames.size():   # box-filter resample to 16 kHz mono
		var s := 0.0
		var n := 0
		for i in range(int(pos), int(pos + step)):
			s += (frames[i].x + frames[i].y) * 0.5
			n += 1
		_acc.append(s / maxi(n, 1))
		pos += step
	while _acc.size() >= FRAME:
		var chunk := _acc.slice(0, FRAME)
		_acc = _acc.slice(FRAME)
		var send := _talking if push_to_talk else _rms(chunk) > GATE
		if send:
			Net.send_voice(encode(chunk), team_only)


static func _rms(x: PackedFloat32Array) -> float:
	var s := 0.0
	for v in x:
		s += v * v
	return sqrt(s / maxi(x.size(), 1))


## G.711-style mu-law, 8 bits per sample.
static func encode(pcm: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(pcm.size())
	for i in pcm.size():
		var x := clampf(pcm[i], -1.0, 1.0)
		var y := signf(x) * log(1.0 + 255.0 * absf(x)) / log(256.0)
		out[i] = int(round((y + 1.0) * 127.5))
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		var y := float(data[i]) / 127.5 - 1.0
		out[i] = signf(y) * (pow(256.0, absf(y)) - 1.0) / 255.0
	return out


func _on_packet(peer: int, data: PackedByteArray) -> void:
	if muted.get(peer, false):
		return
	if not _players.has(peer):
		var p := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.5
		p.stream = gen
		add_child(p)
		p.play()
		_players[peer] = [p, p.get_stream_playback(), 0.0]
	var e: Array = _players[peer]
	var pb := e[1] as AudioStreamGeneratorPlayback
	var pcm := decode(data)
	if pb.get_frames_available() >= pcm.size():
		for v in pcm:
			pb.push_frame(Vector2(v, v))
	if e[2] == 0.0:
		speaking_changed.emit(peer, true)
	e[2] = Time.get_ticks_msec() / 1000.0


func speaking(peer: int) -> bool:
	return _players.has(peer) and float(_players[peer][2]) > 0.0
