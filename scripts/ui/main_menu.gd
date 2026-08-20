extends CanvasLayer
## MainMenu — new world / continue / host / join / skins / mods / settings.

signal start_requested(seed: int, mode: int)
signal continue_requested
signal host_requested
signal join_requested(ip: String)

var main: Node
var _status_label: Label
var _seed_edit: LineEdit
var _mode_option: OptionButton
var _ip_edit: LineEdit
var _join_btn: Button
var _continue_btn: Button
var _skin_box: HBoxContainer
var _skin_buttons: Array = []
var _selected_skin := "default"
var _trust_check: CheckBox
var _sens_slider: HSlider
var _sound_check: CheckBox
var _snap_check: CheckBox
var _mods_label: Label
var _file_dialog: FileDialog
var _visible := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func show_menu(seed: int) -> void:
	_visible = true
	visible = true
	_seed_edit.text = str(seed)
	_continue_btn.disabled = not Saves.has_save(seed)
	_refresh_skins()
	_refresh_mods()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_menu() -> void:
	_visible = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func show_status(t: String) -> void:
	_status_label.text = t

func get_selected_skin() -> String:
	return _selected_skin

# --- construction ---------------------------------------------------------------

func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	return sb

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.1, 0.16, 0.96), Color(0.45, 0.6, 0.85)))
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(620, 0)
	card.add_child(vb)

	var title := Label.new()
	title.text = "VOXEL FORGE"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 0.5))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Voxel building with real structural logic — Kenney & KayKit style (Godot 4.4 prototype)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vb.add_child(sub)

	# world
	var world_hb := HBoxContainer.new()
	vb.add_child(world_hb)
	world_hb.add_child(_mk_label("Seed"))
	_seed_edit = LineEdit.new()
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.placeholder_text = "random"
	world_hb.add_child(_seed_edit)
	world_hb.add_child(_mk_label("Mode"))
	_mode_option = OptionButton.new()
	_mode_option.add_item("Creative (build + fly)", 0)
	_mode_option.add_item("Survival", 1)
	_mode_option.selected = 0
	world_hb.add_child(_mode_option)

	var start_btn := Button.new()
	start_btn.text = "▶  New World"
	start_btn.custom_minimum_size = Vector2(0, 44)
	start_btn.pressed.connect(_on_start)
	vb.add_child(start_btn)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue (load last save for this seed)"
	_continue_btn.pressed.connect(func(): emit_signal("continue_requested"))
	vb.add_child(_continue_btn)

	# online
	var online_hb := HBoxContainer.new()
	vb.add_child(online_hb)
	var host_btn := Button.new()
	host_btn.text = "Host World (listen server)"
	host_btn.custom_minimum_size = Vector2(230, 0)
	host_btn.pressed.connect(func(): emit_signal("host_requested"))
	online_hb.add_child(host_btn)
	online_hb.add_child(_mk_label("Join IP:"))
	_ip_edit = LineEdit.new()
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.placeholder_text = "e.g. 192.168.1.20"
	online_hb.add_child(_ip_edit)
	_join_btn = Button.new()
	_join_btn.text = "Join"
	_join_btn.pressed.connect(func(): emit_signal("join_requested", _ip_edit.text.strip_edges()))
	online_hb.add_child(_join_btn)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1))
	vb.add_child(_status_label)

	# skins
	var skins_title := _mk_label("Skin (syncs online · import custom 192×128 PNG)")
	skins_title.add_theme_font_size_override("font_size", 13)
	vb.add_child(skins_title)
	var skins_hb := HBoxContainer.new()
	vb.add_child(skins_hb)
	_skin_box = HBoxContainer.new()
	_skin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skins_hb.add_child(_skin_box)
	var import_btn := Button.new()
	import_btn.text = "Import PNG…"
	import_btn.pressed.connect(_open_import)
	skins_hb.add_child(import_btn)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.size = Vector2i(720, 480)
	var fl := AcceptDialog.new()
	_file_dialog.add_filter("*.png ; PNG images")
	_file_dialog.file_selected.connect(_on_skin_imported)
	add_child(_file_dialog)

	# mods
	_mods_label = Label.new()
	_mods_label.add_theme_font_size_override("font_size", 12)
	_mods_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.7))
	_mods_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_mods_label)
	_trust_check = CheckBox.new()
	_trust_check.text = "Trust mod scripts (security risk — enables mod GDScript hooks)"
	_trust_check.toggled.connect(func(on: bool):
		Game.settings["trust_mod_scripts"] = on
		Game.toast("Mod scripts %s — restart to apply" % ("enabled" if on else "disabled"))
	)
	vb.add_child(_trust_check)

	# settings
	var set_hb := HBoxContainer.new()
	vb.add_child(set_hb)
	set_hb.add_child(_mk_label("Sensitivity"))
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.3
	_sens_slider.max_value = 3.0
	_sens_slider.step = 0.1
	_sens_slider.value = float(Game.settings.get("sensitivity", 1.0))
	_sens_slider.custom_minimum_size = Vector2(160, 0)
	_sens_slider.value_changed.connect(func(v: float): Game.settings["sensitivity"] = v)
	set_hb.add_child(_sens_slider)
	_sound_check = CheckBox.new()
	_sound_check.text = "Sound"
	_sound_check.button_pressed = bool(Game.settings.get("sound", true))
	_sound_check.toggled.connect(func(on: bool): Game.settings["sound"] = on)
	set_hb.add_child(_sound_check)
	_snap_check = CheckBox.new()
	_snap_check.text = "Grid snap"
	_snap_check.button_pressed = bool(Game.settings.get("snap_grid", true))
	_snap_check.toggled.connect(func(on: bool): Game.settings["snap_grid"] = on)
	set_hb.add_child(_snap_check)

	var about := Label.new()
	about.text = "Controls: WASD move · LMB break · RMB place · F fly (creative) · Tab inventory · C craft · B furniture · T design · V structural info · E interact · Q eat"
	about.add_theme_font_size_override("font_size", 11)
	about.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(about)

func _mk_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 13)
	return l

# --- actions ---------------------------------------------------------------------

func _on_start() -> void:
	var seed := 1
	if _seed_edit.text.strip_edges().is_valid_int():
		seed = int(_seed_edit.text.strip_edges())
	else:
		seed = randi() % 100000
	var mode := Game.Mode.CREATIVE if _mode_option.selected == 0 else Game.Mode.SURVIVAL
	emit_signal("start_requested", seed, mode)

func _refresh_skins() -> void:
	for b in _skin_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_skin_buttons.clear()
	var skins: Array = SkinManager.list_skins()
	if skins.is_empty():
		skins = ["default"]
	for s in skins:
		var b := Button.new()
		b.text = str(s)
		b.toggle_mode = true
		b.button_pressed = s == _selected_skin
		b.pressed.connect(func():
			_selected_skin = s
			for o in _skin_buttons:
				if is_instance_valid(o):
					o.button_pressed = (o == b)
		)
		_skin_box.add_child(b)
		_skin_buttons.append(b)

func _open_import() -> void:
	_file_dialog.popup_centered()

func _on_skin_imported(path: String) -> void:
	var name := path.get_file().get_basename()
	if SkinManager.import_skin(path, name):
		Game.toast("Skin imported: %s" % name)
		_refresh_skins()
	else:
		Game.toast("Import failed")

func _refresh_mods() -> void:
	if Mods.loaded.is_empty():
		_mods_label.text = "Mods: none loaded (see mods/ folder for the example template)"
	else:
		var parts := []
		for m in Mods.loaded:
			parts.append("• %s v%s (%d materials, %d recipes, %d scripts)" % [str(m["name"]), str(m["version"]), int(m["materials"]), int(m["recipes"]), int(m["scripts"])])
		_mods_label.text = "Mods:\n" + "\n".join(parts)
	_trust_check.button_pressed = bool(Game.settings.get("trust_mod_scripts", false))
