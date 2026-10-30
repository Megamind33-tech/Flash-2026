## Lap, sector and progress bookkeeping for one competitor (port of Gridline.Core.LapTracker, tested in C#).
## Progress is continuous: negative on the grid, 0 at the line, L after one lap.
class_name LapTracker
extends RefCounted

signal lap_completed(lap: int, lap_ms: int)
signal sector_completed(sector: int, sector_ms: int)
signal finished_race

var track_length: float
var total_laps: int
var sector_count: int
var max_step_distance := 60.0

var progress := 0.0
var max_progress := 0.0
var laps_completed := 0
var finished := false
var finish_time := 0.0
var best_lap_ms := 0
var last_lap_ms := 0
var lap_times: Array[int] = []
var rejected_steps := 0

var _last_distance := 0.0
var _lap_start := 0.0
var _sector_start := 0.0
var _sectors_total := 0
var _initialised := false


func _init(length: float, laps: int, sectors: int = 3) -> void:
	track_length = length
	total_laps = maxi(1, laps)
	sector_count = maxi(1, sectors)


func initialise(distance: float) -> void:
	_last_distance = _wrap(distance)
	progress = _last_distance - track_length if _last_distance > track_length * 0.5 else _last_distance
	max_progress = progress
	_initialised = true


func start_clock(time: float) -> void:
	_lap_start = time
	_sector_start = time


func relocate(distance: float) -> void:
	var d := _wrap(distance)
	progress = minf(progress + _signed_delta(_last_distance, d), max_progress)
	_last_distance = d


func update(distance: float, time: float) -> void:
	if not _initialised:
		initialise(distance)
	if finished:
		return
	var d := _wrap(distance)
	var delta := _signed_delta(_last_distance, d)
	_last_distance = d
	if absf(delta) > max_step_distance:
		rejected_steps += 1
		return
	progress += delta
	if progress <= max_progress:
		return
	max_progress = progress
	var sector_len := track_length / sector_count
	var sectors_now := floori(max_progress / sector_len)
	while _sectors_total < sectors_now:
		_sectors_total += 1
		var sector := (_sectors_total - 1) % sector_count
		var sector_ms := roundi((time - _sector_start) * 1000.0)
		_sector_start = time
		sector_completed.emit(sector, sector_ms)
		if sector == sector_count - 1:
			laps_completed += 1
			var lap_ms := roundi((time - _lap_start) * 1000.0)
			_lap_start = time
			last_lap_ms = lap_ms
			lap_times.append(lap_ms)
			if best_lap_ms == 0 or lap_ms < best_lap_ms:
				best_lap_ms = lap_ms
			lap_completed.emit(laps_completed, lap_ms)
			if laps_completed >= total_laps:
				finished = true
				finish_time = time
				finished_race.emit()
				return


func current_lap() -> int:
	return mini(total_laps, laps_completed + 1)


func current_lap_elapsed(time: float) -> float:
	return 0.0 if finished else time - _lap_start


func _wrap(d: float) -> float:
	return fposmod(d, track_length)


func _signed_delta(from: float, to: float) -> float:
	var delta := to - from
	if delta > track_length * 0.5:
		delta -= track_length
	elif delta < -track_length * 0.5:
		delta += track_length
	return delta
