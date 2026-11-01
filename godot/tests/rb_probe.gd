extends Node
func _ready() -> void:
	for city in ["lusaka","nairobi","london"]:
		var d: Dictionary = CityStyles.data(city)
		var track := CityWorld.track_from(d)
		var ids := {}
		for bi in RealBuildings.plan(d, track, 2):
			var p: Dictionary = RealBuildings.plan(d, track, 2)[bi] if false else {}
		var plan := RealBuildings.plan(d, track, 2)
		for bi in plan:
			ids[plan[bi]["id"]] = int(ids.get(plan[bi]["id"], 0)) + 1
		print("RB %s %s" % [city, ids])
	get_tree().quit()
