## Wet-road reflections for the Mobile renderer (no screen-space reflections): three box-projected reflection probes
## leapfrog along the circuit ahead of the player, so wet asphalt and standing water mirror the actual street
## (buildings, barriers, ad boards, lights) instead of only the sky. A probe re-captures only when it is moved to
## the next slot - one capture per SPACING metres driven, spread over the following frames - never every frame.
## Cars are excluded from the capture (they move; the paint has its own reflections).
## Only in wet conditions (film or standing water) and from the effects level 1 (Balanced) up; Low keeps sky
## reflections. Godot's probes need no extra shader work: the road's PBR (roughness/specular) picks them up.
class_name WetReflections
extends Node3D

const SPACING := 45.0
const COUNT := 3
const HEIGHT := 1.6           # capture point: about driver eye height, so near-road parallax is right

var track: TrackPath
var target: Node3D
var probes: Array[ReflectionProbe] = []
var slots: Array[int] = []
var captures := 0             # how many re-captures happened (perf log)


static func build(root: Node3D, p_track: TrackPath, p_target: Node3D) -> WetReflections:
	var st := Weather.state_at(Weather.kind, 0.0)
	var wet := st.y > 0.08 or st.z > 0.3
	var lvl := VisualsManager.level("effects")
	var args := OS.get_cmdline_user_args()
	if args.has("--no-wet-reflections") or not wet or lvl < 1:
		return null
	var w := WetReflections.new()
	w.name = "WetReflections"
	w.track = p_track
	w.target = p_target
	root.add_child(w)
	for i in COUNT:
		w.probes.append(null)
		w.slots.append(-999)
	w._place(true)
	return w


func _process(_delta: float) -> void:
	_place(false)


func _slot_pos(slot: int) -> Transform3D:
	var d := track.wrapd(slot * SPACING)
	var fwd := track.tangent_at(d)
	var p := track.position_at(d) + Vector3.UP * 6.0
	return Transform3D(Basis.looking_at(-fwd, Vector3.UP), p)


func _make_probe(slot: int) -> ReflectionProbe:
	var p := ReflectionProbe.new()
	p.update_mode = ReflectionProbe.UPDATE_ONCE   # a new probe captures once, over the next frames
	p.box_projection = true
	p.size = Vector3(track.half_width * 2.0 + 34.0, 28.0, SPACING + 14.0)
	p.origin_offset = Vector3(0, HEIGHT - 6.0, 0)   # box centred above the road, capture near eye height
	p.max_distance = 180.0
	p.cull_mask = 0xFFFFF & ~CarBuilder.CAR_LAYER   # no cars in the capture
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED   # keep the sky's ambient light; only reflections change
	p.blend_distance = 6.0
	add_child(p)
	p.global_transform = _slot_pos(slot)
	captures += 1
	return p


var _hint := [-1]


## Keep probes on the player's slot and the next two; one that falls behind is replaced at the free slot ahead.
func _place(_force: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	var d := float(track.project(target.global_position, _hint)[0])
	var base := int(floor(d / SPACING))
	var want := []
	for k in COUNT:
		want.append(base + k)
	for i in COUNT:
		if slots[i] in want:
			continue
		for s in want:
			if not (s in slots):
				if probes[i]:
					probes[i].queue_free()
				probes[i] = _make_probe(s)
				slots[i] = s
				break
