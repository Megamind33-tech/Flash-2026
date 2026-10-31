## Default provider: the 16 fictional sponsors in assets/ads/ads_atlas.png (tools/scenic/make_ads.py), with
## optional per-placement campaigns from res://data/ads/campaigns.json. No real brands are included.
class_name LocalAdProvider
extends AdProvider

const SPONSORS := ["Kafue Cola", "Copperline Tyres", "Nile Energy", "Zedbank", "Savanna Air", "GRIDLINE",
	"Skyline Mobile", "Harmattan Oil", "Rift Coffee", "Kiln Cement", "Baobab Freight", "Nordwerk",
	"Thames & Co", "Sahel Solar", "Volt Rush", "Arden Motors"]

var _campaigns: Array = []


func _init() -> void:
	var f := FileAccess.open("res://data/ads/campaigns.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_campaigns = d.get("campaigns", [])


static func creative(i: int, campaign := "house") -> Dictionary:
	i = posmod(i, 16)
	return {"id": "acg_%02d" % i, "sponsor": SPONSORS[i], "region": Rect2((i % 4) * 0.25, (i / 4) * 0.25, 0.25, 0.25), "campaign": campaign}


func creatives_for(placement: Dictionary) -> Array:
	for c in _campaigns:   # campaign file: {"id", "placements": ["lusaka_led_*", ...], "creatives": [atlas indices]}
		for pat in c.get("placements", []):
			if str(placement["id"]).match(str(pat)):
				return c["creatives"].map(func(i): return creative(int(i), str(c["id"])))
	var seed := hash(str(placement["id"]))
	var out := []
	for k in int(placement.get("slots", 1)):
		out.append(creative(seed + k * 5))
	return out


func report(summary: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://ads")
	var f := FileAccess.open("user://ads/impressions.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(summary, "  "))
