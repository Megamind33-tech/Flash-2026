## Where advertising creatives come from. GRIDLINE ships with LocalAdProvider (fictional sponsors baked into the
## atlas) and an optional campaign file. A future sponsor backend or ad network plugs in by subclassing
## AdProvider. Placement logic never talks to a network directly. No third-party SDK is integrated.
class_name AdProvider
extends RefCounted


## Creatives for a placement: Array of {"id", "sponsor", "region": Rect2 in atlas UV, "campaign"}.
func creatives_for(_placement: Dictionary) -> Array:
	return []


## Receives measured viewability (never "loaded" counts). Default: keep locally.
func report(_summary: Dictionary) -> void:
	pass
