## On-device benchmark (Settings > Display > Run benchmark): a fixed 90 s Lusaka race, five cars on autopilot, chase
## camera, at the player's current graphics settings. Records every frame's real (wall-clock) time and the renderer
## counters, then shows and saves a report that can be copied and sent:
##   average FPS, 1 % low FPS (average of the slowest 1 % of frames), p50 / p95 / p99 / worst frame time,
##   frames over 33.3 ms, draw calls, triangles, video memory, RAM, battery / CPU temperature at start and end
##   (where Android lets an app read them), device, renderer, preset, render scale, resolution, frame cap.
## Measures the frame as the device presents it, independent of any screen recorder.
class_name RaceBenchmark
extends Node

const WARMUP := 8.0      # seconds after the start before sampling (shader warm-up, grid launch)
const DURATION := 90.0

var race: Node
var _t := 0.0
var _last_us := 0
var _frames := PackedFloat32Array()
var _draws := 0.0
var _prims := 0.0
var _samples := 0
var _cpu_ms := 0.0      # render-thread CPU time per frame (RenderingServer measurement)
var _gpu_ms := 0.0      # GPU time per frame, where the driver reports it
var _phys_ms := 0.0     # physics step (all _physics_process + the physics server), per frame
var _proc_ms := 0.0     # game logic (_process), per frame
var _temp_start := {}
var _done := false
var report := {}


var duration := DURATION


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if OS.has_environment("BENCH_SECONDS"):   # tests: a short run
		duration = float(OS.get_environment("BENCH_SECONDS"))
	_temp_start = temperatures()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(_delta: float) -> void:
	if _done or race == null or race.phase != race.Phase.RACING and race.phase != race.Phase.FINISHING:
		return
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	_t += _delta
	if _t < WARMUP or dt <= 0.0:
		return
	_frames.append(dt)
	_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var vrid := get_viewport().get_viewport_rid()
	_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu()
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
	_phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_samples += 1
	if _t >= WARMUP + duration:
		_finish()


## Battery and CPU temperatures (degrees C) from the files Android exposes, where the app may read them.
static func temperatures() -> Dictionary:
	var out := {}
	var b := _read_num("/sys/class/power_supply/battery/temp")
	if b > 0.0:
		out["battery"] = b / 10.0 if b > 200.0 else b
	var hottest := -1.0
	for i in 40:
		var v := _read_num("/sys/class/thermal/thermal_zone%d/temp" % i)
		if v > 0.0:
			var c := v / 1000.0 if v > 1000.0 else v
			if c > 10.0 and c < 130.0:
				hottest = maxf(hottest, c)
	if hottest > 0.0:
		out["hottest_zone"] = hottest
	return out


static func _read_num(path: String) -> float:
	if not FileAccess.file_exists(path):
		return -1.0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1.0
	var s := f.get_as_text().strip_edges()
	return float(s) if s.is_valid_float() or s.is_valid_int() else -1.0


func _finish() -> void:
	_done = true
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for v in _frames:
		total += v
	var worst1 := 0.0
	var k := maxi(1, n / 100)
	for i in range(n - k, n):
		worst1 += sorted[i]
	worst1 /= k
	var over := 0
	for v in _frames:
		over += 1 if v > 33.4 else 0
	var pct := func(p: float) -> float: return sorted[clampi(int(n * p), 0, n - 1)]
	var temp_end := temperatures()
	var vp := race.get_viewport()
	report = {
		"device": OS.get_model_name(), "os": OS.get_name() + " " + OS.get_version(),
		"renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(),
		"preset": Game.PRESETS[clampi(Game.quality(), 0, 3)]["name"], "custom_options": Game.preset_index() < 0,
		"resolution": "%dx%d" % [int(vp.get_visible_rect().size.x), int(vp.get_visible_rect().size.y)],
		"window": "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"render_scale": "auto" if Game.auto_resolution() else "%d%%" % roundi(Game.base_render_scale() * 100),
		"frame_cap": Engine.max_fps, "display_hz": Game.display_hz(),
		"seconds": snappedf(total / 1000.0, 0.1), "frames": n,
		"avg_fps": snappedf(1000.0 * n / maxf(total, 0.001), 0.1),
		"low1_fps": snappedf(1000.0 / maxf(worst1, 0.001), 0.1),
		"p50_ms": snappedf(pct.call(0.5), 0.1), "p95_ms": snappedf(pct.call(0.95), 0.1), "p99_ms": snappedf(pct.call(0.99), 0.1),
		"worst_ms": snappedf(sorted[n - 1], 0.1), "frames_over_33ms": over,
		"render_cpu_ms": snappedf(_cpu_ms / maxf(_samples, 1), 0.01), "gpu_ms": snappedf(_gpu_ms / maxf(_samples, 1), 0.01),
		"physics_ms": snappedf(_phys_ms / maxf(_samples, 1), 0.01), "logic_ms": snappedf(_proc_ms / maxf(_samples, 1), 0.01),
		"draw_calls": roundi(_draws / maxf(_samples, 1)), "triangles": roundi(_prims / maxf(_samples, 1)),
		"video_mem_mb": roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"ram_mb": roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"temp_start": _temp_start, "temp_end": temp_end,
	}
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open("user://benchmark_%s.json" % stamp, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
	print("[GRIDLINE] BENCHMARK ", JSON.stringify(report))
	_show()


func text() -> String:
	var r := report
	var t0: Dictionary = r["temp_start"]
	var t1: Dictionary = r["temp_end"]
	var temp := "not readable on this device"
	if t1.has("battery") or t1.has("hottest_zone"):
		temp = "battery %s -> %s C, hottest sensor %s -> %s C" % [str(t0.get("battery", "?")), str(t1.get("battery", "?")), str(t0.get("hottest_zone", "?")), str(t1.get("hottest_zone", "?"))]
	return "GRIDLINE benchmark (Lusaka, 5 cars, %ss)\nDevice: %s (%s)\nGPU: %s, renderer %s\nPreset: %s%s, 3D res %s, cap %d fps, display %d Hz, %s\n\nAverage FPS: %s\n1%% low FPS: %s\nFrame time p50 / p95 / p99 / worst: %s / %s / %s / %s ms\nFrames over 33 ms: %d of %d\nCPU render %s ms, GPU %s ms, physics %s ms, game logic %s ms per frame\nDraw calls: %d   Triangles: %d\nVideo memory: %d MB   RAM: %d MB\nTemperature: %s" % [
		r["seconds"], r["device"], r["os"], r["gpu"], r["renderer"], r["preset"], " (custom options)" if r["custom_options"] else "",
		r["render_scale"], r["frame_cap"], r["display_hz"], r["window"], r["avg_fps"], r["low1_fps"], r["p50_ms"], r["p95_ms"], r["p99_ms"],
		r["worst_ms"], r["frames_over_33ms"], r["frames"], r["render_cpu_ms"], "n/a" if float(r["gpu_ms"]) <= 0.0 else str(r["gpu_ms"]), r["physics_ms"], r["logic_ms"], r["draw_calls"], r["triangles"], r["video_mem_mb"], r["ram_mb"], temp]


func _show() -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.072, 0.08, 0.98), 1, UiStyle.LINE, 12))
	cc.add_child(p)
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 32)
	p.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	v.add_child(UiStyle.label("BENCHMARK RESULT", UiStyle.display(), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	var big := HBoxContainer.new()
	big.add_theme_constant_override("separation", 40)
	v.add_child(big)
	for f in [["AVERAGE FPS", str(report["avg_fps"])], ["1% LOW FPS", str(report["low1_fps"])], ["P95 FRAME", "%s ms" % report["p95_ms"]]]:
		var fv := VBoxContainer.new()
		fv.add_child(UiStyle.label(f[0], UiStyle.cond_bold(), 22, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
		fv.add_child(UiStyle.label(f[1], UiStyle.display(), 64, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))
		big.add_child(fv)
	var body := UiStyle.label(text(), UiStyle.body(), 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
	body.custom_minimum_size = Vector2(980, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var copy := UiStyle.primary_button("COPY RESULTS", Vector2(340, 80), 36)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(text())
		copy.text = "COPIED")
	row.add_child(copy)
	var back := UiStyle.primary_button("BACK TO MENU", Vector2(340, 80), 36)
	back.pressed.connect(func():
		get_tree().paused = false
		Game.session.erase("benchmark")
		race.quit_to_menu())
	row.add_child(back)
