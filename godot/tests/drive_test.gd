## Headless vehicle tuning test: 0-100 km/h, top speed on the main straight, and 100-0 braking distance.
## Run: godot --headless --path godot --fixed-fps 60 res://tests/drive_test.tscn
extends Node3D

var car: RaceCarBody
var track: TrackPath
var t := 0.0
var phase := "accel"
var t100 := -1.0
var brake_start := Vector3.ZERO
var top := 0.0


func _ready() -> void:
	track = TrackPath.ashford()
	TrackBuilder.build(self)
	var args := OS.get_cmdline_user_args()
	var id := args[args.find("--car") + 1] if args.has("--car") else CarBuilder.DEFAULT_CAR
	# GR27: --weather rain|storm|after_rain [--weather-t S] measures the same run on a wet road (grip from Weather.update)
	var wk := args[args.find("--weather") + 1] if args.has("--weather") else "clear"
	Weather.configure(wk, "day", 1.0, 1)
	Weather.update(float(args[args.find("--weather-t") + 1]) if args.has("--weather-t") else 0.0)
	print("weather=%s grip=%.3f aquaplane=%.4f" % [wk, Weather.grip, Weather.aquaplane])
	car = CarBuilder.build("player_white", false, id)
	print("car=%s mass=%.0f" % [id, car.mass])
	add_child(car)
	var d := track.wrapd(-60.0)
	car.global_transform = Transform3D(Basis.looking_at(-track.tangent_at(d), Vector3.UP), track.position_at(d) + Vector3.UP * 0.35)
	car.input_enabled = true


func _physics_process(delta: float) -> void:
	t += delta
	var kmh := car.speed_kmh
	top = maxf(top, kmh)
	if phase == "accel":
		car.throttle = 1.0
		car.steer_input = clampf(-(track.project(car.global_position, [-1])[1]) * 0.15, -1, 1)
		if t100 < 0.0 and kmh >= 100.0:
			t100 = t
		if int(t * 2) != int((t - delta) * 2):
			print("t=%.1f v=%.0f km/h gear=%s rpm=%.2f" % [t, kmh, car.gear_label(), car.rpm])
		if kmh >= 110.0 or t > 14.0:
			phase = "brake"
			brake_start = car.global_position
			print("0-100 km/h: %.2fs  0-110: %.2fs" % [t100, t])
	elif phase == "brake":
		car.throttle = 0.0
		car.brake_input = 1.0
		if kmh < 1.0:
			print("braking from %.0f km/h: %.1f m" % [top, car.global_position.distance_to(brake_start)])
			get_tree().quit()
	if t > 40.0:
		get_tree().quit()
