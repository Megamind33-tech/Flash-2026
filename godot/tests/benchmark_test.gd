## The on-device benchmark runs end to end (short run): loads through the briefing without a tap, races on
## autopilot, writes a report with every field, and does not touch the career.
##   BENCH_SECONDS=10 godot --headless --path . -s res://tests/benchmark_test.gd
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var g = root.get_node("/root/Game")
	var money_before := int(g.save["career"]["money"])
	var races_before := int(g.save["career"]["racesEntered"])
	g.start_benchmark()
	var t0 := Time.get_ticks_msec()
	var bm: Node = null
	while Time.get_ticks_msec() - t0 < 240000:
		await process_frame
		if current_scene and bm == null:
			for c in current_scene.get_children():
				if c.get_script() and str(c.get_script().resource_path).ends_with("benchmark.gd"):
					bm = c
		if bm and not bm.report.is_empty():
			break
	var fails := 0
	var r: Dictionary = bm.report if bm else {}
	for k in ["avg_fps", "low1_fps", "p50_ms", "p95_ms", "p99_ms", "worst_ms", "draw_calls", "triangles", "video_mem_mb", "ram_mb", "device", "renderer", "preset", "temp_start"]:
		if not r.has(k):
			fails += 1
			print("BENCH FAIL missing ", k)
	if not r.is_empty():
		print("BENCH report ", JSON.stringify(r))
		print("BENCH text\n", bm.text())
		if float(r["low1_fps"]) > float(r["avg_fps"]) + 0.01 or int(r["frames"]) < 30:
			fails += 1
			print("BENCH FAIL implausible numbers")
	if int(g.save["career"]["money"]) != money_before or int(g.save["career"]["racesEntered"]) != races_before:
		fails += 1
		print("BENCH FAIL the benchmark changed the career")
	print("BENCHMARK %s failures=%d" % ["PASS" if fails == 0 and not r.is_empty() else "FAIL", fails if not r.is_empty() else fails + 1])
	quit(0 if fails == 0 and not r.is_empty() else 1)
