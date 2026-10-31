## Per-competitor race state: identity, lap tracking, track limits and recovery (port of Gridline.Race.RaceCar).
class_name Racer
extends RefCounted

signal notice(message: String)

var id: String
var display_name: String
var is_player := false
var grid_slot := 0
var driver := {}
var car: RaceCarBody
var laps: LapTracker
var track: TrackPath
var distance := 0.0
var lateral := 0.0
var position := 0
var penalty := 0.0
var warnings := 0
var recoveries := 0
var eliminated := false
var elim_order := 0
var _hint := [-1]
var _stuck := 0.0
var _rolled := 0.0
var _off := false
var _off_start := 0.0


func setup(p_track: TrackPath, total_laps: int) -> void:
	track = p_track
	laps = LapTracker.new(track.length, total_laps)
	_project()
	laps.initialise(distance)


func _project() -> void:
	var r := track.project(car.global_position, _hint)
	distance = r[0]
	lateral = r[1]


func physics_update(delta: float, clock_running: bool, race_time: float) -> void:
	_project()
	if not clock_running or laps.finished:
		return
	laps.update(distance, race_time)
	if laps.finished:
		return
	_track_limits()
	_recovery(delta)


func _track_limits() -> void:
	var outside := absf(lateral) > track.half_width + 1.5
	if outside and not _off:
		_off = true
		_off_start = laps.progress
	elif not outside and _off:
		_off = false
		if laps.progress - _off_start > 25.0:
			warnings += 1
			if warnings >= 3:
				warnings = 0
				penalty += 5.0
				notice.emit("+5s PENALTY - TRACK LIMITS")
			else:
				notice.emit("TRACK LIMITS WARNING %d/3" % warnings)


func _recovery(delta: float) -> void:
	_rolled = _rolled + delta if car.global_basis.y.y < 0.3 else 0.0
	# Stuck: stopped, or pinned sideways/backwards against a rail or another car while still sliding along it (a pile
	# against the Giza guardrail crawled for minutes at 5 m/s with no forward speed).
	var heading := car.global_basis.z.dot(track.tangent_at(distance))
	var fwd_speed := car.linear_velocity.dot(car.global_basis.z)
	var pinned := heading < 0.55 and fwd_speed < 3.0
	_stuck = _stuck + delta if car.linear_velocity.length() < 1.5 or pinned else 0.0
	var lost := absf(lateral) > 40.0 or car.global_position.y < track.position_at(distance).y - 15.0
	if _rolled > 3.0 or lost or _stuck > (8.0 if is_player else 5.0):
		recover()


func recover() -> void:
	var d := track.wrapd(distance - 8.0)
	var pos := track.position_at(d) + Vector3.UP * 0.6
	car.place(Transform3D(Basis.looking_at(-track.tangent_at(d), Vector3.UP), pos))
	_hint[0] = -1
	_project()
	laps.relocate(distance)
	_stuck = 0.0
	_rolled = 0.0
	_off = false
	recoveries += 1
	if is_player:
		notice.emit("CAR RECOVERED")


func snapshot() -> Dictionary:
	return {"id": id, "name": display_name, "player": is_player, "finished": laps.finished, "finish_time": laps.finish_time,
		"penalty": penalty, "progress": laps.progress, "laps": laps.laps_completed, "best": laps.best_lap_ms, "grid": grid_slot}


static func classify(snaps: Array) -> Array:
	var list := snaps.duplicate()
	list.sort_custom(func(a, b):
		if a["finished"] != b["finished"]:
			return a["finished"]
		if a["finished"]:
			var ta: float = a["finish_time"] + a["penalty"]
			var tb: float = b["finish_time"] + b["penalty"]
			if ta != tb:
				return ta < tb
		elif a["progress"] != b["progress"]:
			return a["progress"] > b["progress"]
		return a["grid"] < b["grid"])
	return list


static func format_ms(ms: int) -> String:
	if ms <= 0:
		return "--:--.---"
	return "%d:%02d.%03d" % [ms / 60000, ms / 1000 % 60, ms % 1000]
