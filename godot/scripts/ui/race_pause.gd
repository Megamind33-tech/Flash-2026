## In-race pause menu: the Settings + Menus addon's PauseMenuUI (tree pause, focus handling, gamepad Start) with
## GRIDLINE's race actions and the dark premium theme. Resume / Restart Race / Change Camera / Options / Retire,
## plus the live Graphics, Resolution and Frame Rate rows. Restart reloads only the race scene; Retire returns to
## the menu scene; nothing reloads the game.
class_name RacePauseUI
extends PauseMenuUI

var race


func _init() -> void:
	theme_data = GridlineMenus.menu_theme()
	listen_for_pause_action = true


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	add_child(dim)
	var center := CenterContainer.new()
	center.anchor_right = 1
	center.anchor_bottom = 1
	add_child(center)
	GridlineMenus.safe_area(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", theme_data.panel_stylebox())
	_panel.custom_minimum_size = Vector2(980, 0)
	_panel.theme = GridlineMenus.ui_theme()
	center.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiStyle.label("PAUSED", UiStyle.display(), theme_data.heading_font_size + 14, GridlineMenus.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var where := UiStyle.label(str(race.track_name).to_upper() if race else "", UiStyle.cond(), 30, GridlineMenus.DIM, HORIZONTAL_ALIGNMENT_RIGHT, false)
	head.add_child(where)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	_first_button = _big(grid, "Resume", resume)
	_big(grid, "Restart Race", func():
		get_tree().paused = false
		if race:
			race.restart())
	_big(grid, "Change Camera", func():
		if race:
			race.camera.cycle())
	_big(grid, "Settings", _open_options)
	var retire := _big(col, "Retire to Menu", _main_menu)
	retire.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
	var note := UiStyle.label("Retiring forfeits the entry fee.",
		UiStyle.body(), 24, GridlineMenus.DIM, HORIZONTAL_ALIGNMENT_LEFT, false)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)


func _big(parent: Container, text: String, cb: Callable) -> Button:
	var b := _add_button(parent, text, cb)
	b.custom_minimum_size = Vector2(470, 88)
	b.add_theme_font_override("font", UiStyle.cond_bold())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _open_options() -> void:
	_panel.visible = false
	var sc := SettingsScreen.open(self, true)
	sc.closed.connect(func():
		_panel.visible = true
		if race and race.has_method("reset_dynamic_resolution"):
			race.reset_dynamic_resolution()
		_restore_focus())


func pause() -> void:
	if race and race.phase == race.Phase.RESULTS:
		return
	super.pause()


func resume() -> void:
	super.resume()
	if race and race.has_method("reset_dynamic_resolution"):
		race.reset_dynamic_resolution()


func _main_menu() -> void:
	main_menu_pressed.emit()
	if race:
		race.quit_to_menu()
