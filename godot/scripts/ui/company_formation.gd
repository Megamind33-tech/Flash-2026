## Team Owner onboarding: found the racing company in two focused steps.
##   1. IDENTITY - company name (live validation, character count), team colour, what the company does;
##      a live identity card on the right (monogram, name, owner, founding week) and the starting budget.
##   2. CONFIRM  - summary of exactly what will be saved, EDIT or FOUND COMPANY.
## Founding goes through TeamOwner.found(), which validates again and refuses a second founding; the button locks on
## the first press so a double tap cannot submit twice. The 3D garage ring follows the chosen colour live.
## Layout: containers inside a panel anchored to the safe area, so it holds on 16:9, 20:9 and 4:3.
class_name CompanyFormation
extends Control

signal founded(name: String)

const COLORS := ["#E0B040", "#B3261E", "#1F4E8C", "#2E7D32", "#7B3FB0", "#E8E8E8", "#F07A1A", "#00A3A3"]
const COLOR_NAMES := {"#E0B040": "Gold", "#B3261E": "Racing red", "#1F4E8C": "Deep blue", "#2E7D32": "Green",
	"#7B3FB0": "Purple", "#E8E8E8": "White", "#F07A1A": "Orange", "#00A3A3": "Teal"}

var studio          # GarageStudio of the menu (optional): its ring takes the team colour
var company := ""
var color := "#E0B040"
var step := 1
var _busy := false

var _content: VBoxContainer
var _name_edit: LineEdit
var _hint: Label
var _count: Label
var _chips: Array = []
var _continue: Button
var _card_band: ColorRect
var _mono_tile: PanelContainer
var _mono: Label
var _card_name: Label
var _card_color: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if company == "":
		company = "%s Racing" % str(Game.save["career"].get("driverName", "Rookie")).split(" ")[-1]
	var args := OS.get_cmdline_user_args()   # evidence: --formation-name <text> --formation-color <hex> --formation-step 2
	if args.has("--formation-name"):
		company = args[args.find("--formation-name") + 1].replace("_", " ")
	if args.has("--formation-color"):
		color = "#" + args[args.find("--formation-color") + 1]
	if args.has("--formation-step"):
		step = int(args[args.find("--formation-step") + 1])
	var safe := UiStyle.safe_margins(get_viewport())
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.CHARCOAL, 0.97), 1, UiStyle.LINE, 12))
	frame.anchor_left = 0.08
	frame.anchor_right = 0.92
	frame.anchor_top = 0.13
	frame.anchor_bottom = 0.94
	frame.offset_left = safe.x
	frame.offset_right = -safe.z
	frame.offset_top = safe.y
	frame.offset_bottom = -safe.w
	add_child(frame)
	var pad := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(k, 32)
	frame.add_child(pad)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 18)
	pad.add_child(_content)
	_build()
	_apply_color()


func _build() -> void:
	for c in _content.get_children():
		c.queue_free()
	_chips.clear()
	_hint = null
	_count = null
	_continue = null
	var head := HBoxContainer.new()
	_content.add_child(head)
	var title := UiStyle.label("FOUND YOUR RACING COMPANY", UiStyle.display(), 60, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_steps())
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 36)
	_content.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	if step == 1:
		_identity(left)
	else:
		_confirm(left)
	_preview(right)
	_update_name(company)


func _steps() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for i in 2:
		var on := step == i + 1
		var l := UiStyle.label("  %d  %s  " % [i + 1, ["IDENTITY", "CONFIRM"][i]], UiStyle.cond_bold(), 26,
			UiStyle.INK if on else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, false)
		l.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.ACCENT if on else UiStyle.GRAPHITE, 0, Color.TRANSPARENT, 6))
		l.custom_minimum_size = Vector2(0, 48)
		h.add_child(l)
	return h


func _heading(parent: Control, text: String) -> void:
	parent.add_child(UiStyle.label(text, UiStyle.cond_bold(), 26, UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false))


# ------------------------------------------------------------------ step 1

func _identity(left: VBoxContainer) -> void:
	_heading(left, "COMPANY NAME")
	_name_edit = LineEdit.new()
	_name_edit.text = company
	_name_edit.placeholder_text = "e.g. Kafue Motorsport"
	_name_edit.max_length = TeamOwner.NAME_MAX + 4   # room to type; validation reports the limit
	_name_edit.custom_minimum_size = Vector2(0, 76)
	_name_edit.add_theme_font_override("font", UiStyle.cond_bold())
	_name_edit.add_theme_font_size_override("font_size", 38)
	_name_edit.add_theme_stylebox_override("normal", UiStyle.box(Color(1, 1, 1, 0.07), 2, Color(1, 1, 1, 0.25), 8))
	_name_edit.add_theme_stylebox_override("focus", UiStyle.box(Color(1, 1, 1, 0.1), 2, UiStyle.ACCENT, 8))
	_name_edit.text_changed.connect(_update_name)
	_name_edit.text_submitted.connect(func(_t): _next())
	left.add_child(_name_edit)
	var hint_row := HBoxContainer.new()
	left.add_child(hint_row)
	_hint = UiStyle.label("", UiStyle.body(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_row.add_child(_hint)
	_count = UiStyle.label("", UiStyle.cond(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
	hint_row.add_child(_count)
	_heading(left, "TEAM COLOUR")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 12)
	chips.add_theme_constant_override("v_separation", 12)
	left.add_child(chips)
	for c in COLORS:
		var cc: String = c
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(72, 72)
		b.tooltip_text = COLOR_NAMES[cc]
		b.pressed.connect(func(): color = cc; _apply_color())
		b.set_meta("color", cc)
		chips.add_child(b)
		_chips.append(b)
	_heading(left, "WHAT YOUR COMPANY DOES")
	for line in ["Scout and sign drivers, then train them between race weeks.",
			"Buy team cars and assign one to each driver.",
			"Sign partners who pay every week you race.",
			"Enter competitions from Local up to International."]:
		var l := UiStyle.label("•  " + line, UiStyle.body(), 26, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	_continue = UiStyle.primary_button("CONTINUE", Vector2(320, 84), 44)
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_continue.pressed.connect(_next)
	left.add_child(_continue)


func _update_name(t: String) -> void:
	company = t
	var problem := TeamOwner.name_problem(t)
	var clean := TeamOwner.clean_name(t)
	if _hint and _count and step == 1:
		_hint.text = problem if problem != "" else "Available."
		_hint.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if problem != "" else UiStyle.MONEY)
		_count.text = "%d / %d" % [clean.length(), TeamOwner.NAME_MAX]
		_count.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if clean.length() > TeamOwner.NAME_MAX else UiStyle.MUTED)
	if _continue:
		_continue.disabled = problem != ""
		_continue.modulate.a = 0.4 if problem != "" else 1.0
	if _card_name:
		_card_name.text = clean.to_upper() if clean != "" else "YOUR COMPANY"
		_mono.text = monogram(clean)


## Two-letter badge from the company name: first letters of the first two words, else the first two letters.
static func monogram(n: String) -> String:
	var words := Array(n.strip_edges().split(" ", false)).filter(func(w): return w != "&" and w != "-")
	if words.is_empty():
		return "?"
	if words.size() == 1:
		return str(words[0]).substr(0, 2).to_upper()
	return (str(words[0])[0] + str(words[1])[0]).to_upper()


func _next() -> void:
	if TeamOwner.name_problem(company) != "":
		return
	step = 2
	_build()
	_apply_color()


# ------------------------------------------------------------------ step 2

func _confirm(left: VBoxContainer) -> void:
	_heading(left, "CHECK BEFORE YOU FOUND")
	var rows := [["Company", TeamOwner.clean_name(company)], ["Colour", COLOR_NAMES.get(color, color)],
		["Owner", str(Game.save["career"].get("driverName", "You"))],
		["Starts in", "Week %d · Local competitions" % int(TeamOwner.state().get("week", 1))],
		["Budget", "$%s from your wallet" % RaceHud._thousands(TeamOwner.money())]]
	for r in rows:
		var h := HBoxContainer.new()
		h.custom_minimum_size = Vector2(0, 64)
		var k := UiStyle.label(str(r[0]).to_upper(), UiStyle.cond_bold(), 26, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		k.custom_minimum_size = Vector2(220, 0)
		h.add_child(k)
		var v := UiStyle.label(str(r[1]), UiStyle.cond_bold(), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.clip_text = true
		h.add_child(v)
		left.add_child(h)
	var note := UiStyle.label("The name and colour are saved with your career and are used across your team HQ and team cars. The company cannot be renamed later.",
		UiStyle.body(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	_hint = UiStyle.label("", UiStyle.body(), 24, Color(1, 0.55, 0.5), HORIZONTAL_ALIGNMENT_LEFT, false)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_hint)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	left.add_child(btns)
	var edit := Button.new()
	edit.text = "‹  EDIT"
	edit.focus_mode = Control.FOCUS_NONE
	edit.custom_minimum_size = Vector2(220, 84)
	edit.add_theme_font_override("font", UiStyle.display())
	edit.add_theme_font_size_override("font_size", 40)
	edit.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.GRAPHITE, 1, UiStyle.LINE, 8))
	edit.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.GRAPHITE.lightened(0.1), 1, UiStyle.LINE, 8))
	edit.pressed.connect(func():
		if _busy:
			return
		step = 1
		_build()
		_apply_color())
	btns.add_child(edit)
	var go := UiStyle.primary_button("FOUND COMPANY", Vector2(400, 84), 44)
	go.name = "FoundButton"
	go.pressed.connect(func(): submit(go))
	btns.add_child(go)
	_hint.text = ""


## Founds the company. Locks on the first press (no duplicate submissions); on a refusal shows why and unlocks.
func submit(button: Button = null) -> String:
	if _busy:
		return "busy"
	_busy = true
	if button:
		button.disabled = true
		button.text = "FOUNDING…"
	var err := TeamOwner.found(company, color)
	if err != "":
		_busy = false
		if button:
			button.disabled = false
			button.text = "FOUND COMPANY"
		if _hint:
			_hint.text = err
		return err
	Game.add_xp(50)
	founded.emit(str(TeamOwner.state()["name"]))
	return ""


# ------------------------------------------------------------------ preview

func _preview(right: VBoxContainer) -> void:
	_heading(right, "IDENTITY PREVIEW")
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.105, 0.115, 1), 1, UiStyle.LINE, 10))
	right.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	card.add_child(cv)
	_card_band = ColorRect.new()
	_card_band.custom_minimum_size = Vector2(0, 14)
	cv.add_child(_card_band)
	var cm := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		cm.add_theme_constant_override(k, 22)
	cv.add_child(cm)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 20)
	cm.add_child(ch)
	_mono_tile = PanelContainer.new()
	_mono_tile.custom_minimum_size = Vector2(120, 120)
	ch.add_child(_mono_tile)
	_mono = UiStyle.label("", UiStyle.display(), 72, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	_mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mono_tile.add_child(_mono)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_child(info)
	_card_name = UiStyle.label("", UiStyle.display(), 46, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	_card_name.clip_text = true
	_card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_card_name)
	info.add_child(UiStyle.label("OWNER  %s" % str(Game.save["career"].get("driverName", "You")).to_upper(), UiStyle.cond_bold(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false))
	_card_color = UiStyle.label("", UiStyle.cond_bold(), 24, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	info.add_child(_card_color)
	_heading(right, "STARTING BUDGET")
	var bud := PanelContainer.new()
	bud.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.GRAPHITE, 1, UiStyle.LINE, 10))
	right.add_child(bud)
	var bm := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		bm.add_theme_constant_override(k, 20)
	bud.add_child(bm)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bm.add_child(bv)
	bv.add_child(UiStyle.label("$%s" % RaceHud._thousands(TeamOwner.money()), UiStyle.display(), 64, UiStyle.MONEY, HORIZONTAL_ALIGNMENT_LEFT, false))
	for line in ["Your wallet funds the team (shared with your driver career).",
			"Registration is free. Weekly costs start when you sign drivers.",
			"Driver signing from $%s · training $%s a session." % [RaceHud._thousands(_cheapest_scout()), RaceHud._thousands(TeamOwner.TRAIN_COST)]]:
		var l := UiStyle.label(line, UiStyle.body(), 22, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bv.add_child(l)


static func _cheapest_scout() -> int:
	var best := 0
	for sc in TeamOwner.scouts():
		var fee := int((sc as Dictionary).get("fee", 0))
		if fee > 0 and (best == 0 or fee < best):
			best = fee
	return best


func _apply_color() -> void:
	var c := Color(color)
	for b in _chips:
		var bc: String = b.get_meta("color")
		var on := bc == color
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(bc), 5 if on else 0, Color.WHITE, 10))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color(bc), 4, Color(1, 1, 1, 0.6), 10))
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(bc), 5, Color.WHITE, 10))
	if _card_band:
		_card_band.color = c
		_mono_tile.add_theme_stylebox_override("panel", UiStyle.box(c, 0, Color.TRANSPARENT, 10))
		_mono.add_theme_color_override("font_color", UiStyle.INK if c.get_luminance() > 0.55 else Color.WHITE)
		_card_color.text = "COLOUR  %s" % str(COLOR_NAMES.get(color, color)).to_upper()
		_update_name(company)
	if studio and studio.has_method("set_accent"):
		studio.set_accent(c)
