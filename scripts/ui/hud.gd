extends CanvasLayer
## HUD — all in-game UI, built in code (robust, anchor-based = mobile-ready).
## Panels: hotbar, vitals, warning banner, challenge, toasts, inventory,
## crafting, furniture palette, design bar, pause menu, tutorial hints.

var game_active := false
var player: Node
var structural: Node
var challenges: Node
var furniture: Node
var villager: Node

var _hotbar_slots: Array = []
var _inv_slots: Array = []
var _icons: Texture2D = null
var _inv_cursor := {}

var _mode_label: Label
var _coords_label: Label
var _clock_label: Label
var _coins_label: Label
var _health_bar: ProgressBar
var _hunger_bar: ProgressBar
var _warning_panel: PanelContainer
var _warning_label: Label
var _challenge_label: Label
var _quest_label: Label
var _toast_label: Label
var _dialogue_label: Label
var _hint_label: Label
var _info_state_label: Label

var _inv_panel: PanelContainer
var _inv_grid: GridContainer
var _cursor_label: Label
var _craft_panel: PanelContainer
var _craft_box: VBoxContainer
var _palette_panel: PanelContainer
var _palette_box: HBoxContainer
var _design_panel: PanelContainer
var _pause_panel: PanelContainer
var _tut_panel: PanelContainer

var _toast_queue: Array = []
var _toast_t := -1.0
var _dialogue_t := 0.0
var _poll_t := 0.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_icons = load("res://assets/generated/icons.png") if ResourceLoader.exists("res://assets/generated/icons.png") else null
	_build()
	Game.slot_changed.connect(_refresh_hotbar)
	Game.toast_requested.connect(_on_toast)
	Game.mode_changed.connect(func(_m): _refresh_all())
	Game.coins_changed.connect(func(_c): _refresh_top())
	Game.dialogue_requested.connect(_on_dialogue)

func attach(p: Node, st: Node, ch: Node, fu: Node, vl: Node) -> void:
	player = p
	structural = st
	challenges = ch
	furniture = fu
	villager = vl
	if player != null:
		player.inventory.changed.connect(_refresh_hotbar)
	if structural != null:
		structural.instability_changed.connect(_on_instability)
		structural.info_toggled.connect(func(_e): _refresh_hint())
	if challenges != null:
		challenges.challenge_updated.connect(_on_challenge)
	if furniture != null:
		furniture.mode_changed.connect(_on_furniture_mode)
	_refresh_all()

func _refresh_all() -> void:
	_refresh_hotbar()
	_refresh_top()
	_refresh_hint()
	_refresh_furniture_panels()
	_refresh_inv()

# --- construction --------------------------------------------------------------

func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# crosshair
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH
	cross.position = Vector2(-5, -11)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)

	# top-left vitals
	var tl := VBoxContainer.new()
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.position = Vector2(14, 10)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_label = _label(tl, "Creative")
	_mode_label.add_theme_font_size_override("font_size", 15)
	_coords_label = _label(tl, "")
	_clock_label = _label(tl, "")
	_coins_label = _label(tl, "")
	_health_bar = _bar(tl, Color(0.85, 0.25, 0.2))
	_hunger_bar = _bar(tl, Color(0.9, 0.65, 0.25))
	root.add_child(tl)

	# top-center warning banner
	_warning_panel = PanelContainer.new()
	_warning_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.45, 0.05, 0.02, 0.85), Color(1, 0.3, 0.1)))
	_warning_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning_panel.position = Vector2(-160, 12)
	_warning_panel.custom_minimum_size = Vector2(320, 0)
	_warning_label = Label.new()
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 15)
	_warning_label.add_theme_color_override("font_color", Color(1, 0.85, 0.75))
	_warning_panel.add_child(_warning_label)
	_warning_panel.visible = false
	root.add_child(_warning_panel)

	# top-right: challenge + quest
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-330, 10)
	tr.custom_minimum_size = Vector2(316, 0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_challenge_label = _label(tr, "")
	_challenge_label.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	_challenge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_label = _label(tr, "")
	_quest_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1))
	_quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(tr)

	# bottom: hotbar
	var hotbar := HBoxContainer.new()
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar.position = Vector2(-180, -78)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 9:
		var slot := _slot_control(i)
		_hotbar_slots.append(slot)
		hotbar.add_child(slot)
	root.add_child(hotbar)

	# bottom-left hints
	_hint_label = _label(root, "")
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.position = Vector2(14, -34)
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))

	# info-mode state (bottom-right)
	_info_state_label = _label(root, "")
	_info_state_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_info_state_label.position = Vector2(-420, -34)
	_info_state_label.add_theme_font_size_override("font_size", 12)
	_info_state_label.add_theme_color_override("font_color", Color(0.6, 1, 0.7))

	# toast
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 15)
	_toast_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_label.position = Vector2(-300, -140)
	_toast_label.custom_minimum_size = Vector2(600, 0)
	_toast_label.modulate.a = 0.0
	root.add_child(_toast_label)

	# dialogue
	_dialogue_label = Label.new()
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialogue_label.add_theme_font_size_override("font_size", 14)
	_dialogue_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	_dialogue_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue_label.position = Vector2(-350, -108)
	_dialogue_label.custom_minimum_size = Vector2(700, 0)
	_dialogue_label.modulate.a = 0.0
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_dialogue_label)

	_build_inventory(root)
	_build_crafting(root)
	_build_palette(root)
	_build_design(root)
	_build_pause(root)
	_build_tutorial(root)

func _build_inventory(root: Control) -> void:
	_inv_panel = PanelContainer.new()
	_inv_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.1, 0.14, 0.92), Color(0.4, 0.5, 0.7)))
	_inv_panel.set_anchors_preset(Control.PRESET_CENTER)
	_inv_panel.position = Vector2(-260, -210)
	var vb := VBoxContainer.new()
	_inv_panel.add_child(vb)
	var title := Label.new()
	title.text = "Inventory    (Tab to close)"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 9
	for i in 36:
		var s := _slot_control(i, true)
		_inv_slots.append(s)
		s.pressed.connect(_on_inv_slot_clicked.bind(i))
		_inv_grid.add_child(s)
	vb.add_child(_inv_grid)
	_cursor_label = Label.new()
	_cursor_label.add_theme_font_size_override("font_size", 13)
	vb.add_child(_cursor_label)
	root.add_child(_inv_panel)
	_inv_panel.visible = false

func _build_crafting(root: Control) -> void:
	_craft_panel = PanelContainer.new()
	_craft_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.08, 0.05, 0.92), Color(0.7, 0.5, 0.3)))
	_craft_panel.set_anchors_preset(Control.PRESET_CENTER)
	_craft_panel.position = Vector2(-230, -230)
	var vb := VBoxContainer.new()
	_craft_panel.add_child(vb)
	var title := Label.new()
	title.text = "Crafting    (C to close)"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)
	_craft_box = VBoxContainer.new()
	vb.add_child(_craft_box)
	root.add_child(_craft_panel)
	_craft_panel.visible = false

func _build_palette(root: Control) -> void:
	_palette_panel = PanelContainer.new()
	_palette_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.1, 0.08, 0.92), Color(0.3, 0.7, 0.4)))
	_palette_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_palette_panel.position = Vector2(-330, -150)
	var vb := VBoxContainer.new()
	_palette_panel.add_child(vb)
	var title := Label.new()
	title.text = "Furniture    (LMB place · R rotate · G snap · RMB cancel)"
	title.add_theme_font_size_override("font_size", 14)
	vb.add_child(title)
	_palette_box = HBoxContainer.new()
	vb.add_child(_palette_box)
	root.add_child(_palette_panel)
	_palette_panel.visible = false

func _build_design(root: Control) -> void:
	_design_panel = PanelContainer.new()
	_design_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.07, 0.12, 0.92), Color(0.5, 0.4, 0.8)))
	_design_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_design_panel.position = Vector2(-300, -150)
	var vb := VBoxContainer.new()
	_design_panel.add_child(vb)
	var title := Label.new()
	title.text = "Design Mode    (LMB select · X color · M measure · Del remove)"
	title.add_theme_font_size_override("font_size", 14)
	vb.add_child(title)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	for txt in ["Measure (M)", "Save (Ctrl+K)", "Load (Ctrl+L)"]:
		var b := Button.new()
		b.text = txt
		hb.add_child(b)
	root.add_child(_design_panel)
	_design_panel.visible = false

func _build_pause(root: Control) -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.1, 0.95), Color(0.5, 0.5, 0.7)))
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	var vb := VBoxContainer.new()
	_pause_panel.add_child(vb)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	for txt in ["Resume", "Save Game", "Toggle Mode (Creative/Survival)", "Quit to Menu"]:
		var b := Button.new()
		b.text = txt
		b.pressed.connect(_on_pause_button.bind(txt))
		vb.add_child(b)
	root.add_child(_pause_panel)
	_pause_panel.visible = false

func _build_tutorial(root: Control) -> void:
	_tut_panel = PanelContainer.new()
	_tut_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.09, 0.13, 0.9), Color(0.4, 0.6, 0.9)))
	_tut_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_tut_panel.position = Vector2(14, -290)
	var vb := VBoxContainer.new()
	_tut_panel.add_child(vb)
	_label(vb, "📘 How building works")
	for line in [
		"· Blocks need SUPPORT: connected to the ground (or a Foundation).",
		"· Wood cantilevers 2, stone 1, reinforced 5 blocks.",
		"· Ghost preview: green = ok, yellow = at limit, red = will fail.",
		"· Red flashing = UNSTABLE: add support before the timer ends!",
		"· V = structural info  ·  B = furniture  ·  T = design mode",
		"· Survival: mine first, build second. Fly (F) is Creative-only.",
	]:
		_label(vb, line)
	var b := Button.new()
	b.text = "Got it"
	b.pressed.connect(func():
		Game.settings["tut_seen"] = true
		var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(Game.settings))
		_tut_panel.visible = false
	)
	vb.add_child(b)
	root.add_child(_tut_panel)
	_tut_panel.visible = not Game.settings.get("tut_seen", false)

func _label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _bar(parent: Node, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(150, 14)
	b.show_percentage = false
	b.max_value = 100.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.4)
	b.add_theme_stylebox_override("background", sb)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b

func _slot_control(index: int, interactive: bool = false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(52, 52)
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.75)
	sb.border_color = Color(0.35, 0.4, 0.5)
	sb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sel := sb.duplicate()
	sel.border_color = Color(1, 1, 0.4)
	b.add_theme_stylebox_override("hover", sel)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("focus", sb)
	b.tooltip_text = str(index + 1)
	if interactive:
		pass
	return b

func _icon_for(id: int) -> Texture2D:
	if _icons == null:
		return null
	if Blocks.is_weapon(id):
		return null  # weapons render their real 3D model in the hand
	var cell := id - 1  # icon grid mirrors the atlas cell order
	if id >= 100:
		cell = 16 if id == 101 else 17
	if cell < 0 or cell > 17:
		return null
	var at := AtlasTexture.new()
	at.atlas = _icons
	at.region = Rect2i((cell % 4) * 16, (cell / 4) * 16, 16, 16)
	return at

# --- updates -------------------------------------------------------------------

func _process(dt: float) -> void:
	# toast queue
	if _toast_t >= 0.0:
		_toast_t += dt
		var fade := 1.0 - _toast_t / 3.0
		_toast_label.modulate.a = clampf(fade * 2.0, 0.0, 1.0)
		if _toast_t > 3.0:
			_toast_t = -1.0
			if _toast_queue.size() > 0:
				_toast_label.text = str(_toast_queue.pop_front())
				_toast_t = 0.0
				_toast_label.modulate.a = 1.0
	# dialogue fade
	if _dialogue_t > 0.0:
		_dialogue_t -= dt
		_dialogue_label.modulate.a = clampf(_dialogue_t, 0.0, 1.0)
	# polls
	_poll_t += dt
	if _poll_t > 0.15:
		_poll_t = 0.0
		_poll_dynamic()

func _unhandled_input(event: InputEvent) -> void:
	if not game_active:
		return
	# pause panel (HUD is ALWAYS so this works while the tree is paused)
	if _pause_panel.visible:
		if event.is_action_pressed("pause"):
			_resume()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		_open_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		_inv_panel.visible = not _inv_panel.visible
		if _inv_panel.visible:
			_craft_panel.visible = false
			_refresh_inv()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("crafting"):
		_craft_panel.visible = not _craft_panel.visible
		if _craft_panel.visible:
			_inv_panel.visible = false
			_refresh_crafting()
		get_viewport().set_input_as_handled()
		return
	# hotbar selection: number keys + mouse wheel
	for i in 9:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			Game.select_slot(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("wheel_up"):
		Game.select_slot((Game.selected_slot + 8) % 9)
	elif event.is_action_pressed("wheel_down"):
		Game.select_slot((Game.selected_slot + 1) % 9)

func _poll_dynamic() -> void:
	if player == null:
		return
	_refresh_top()
	if structural != null:
		_info_state_label.text = "V: Structural Info: %s" % ("ON" if structural.info_mode else "off")
	if villager != null:
		if not villager.active.is_empty() and villager.active.get("status", "") == "open":
			_quest_label.text = "Karim: %s (%d/%d)" % [str(villager.active["text"]), int(villager.active["progress"]), int(villager.active["n"])]
		else:
			_quest_label.text = ""
	if furniture != null:
		_refresh_furniture_panels()

func _refresh_top() -> void:
	if player == null:
		return
	_mode_label.text = "Creative (Fly: %s)" % ("on" if _flying(player) else "off") if Game.is_creative() else "Survival"
	var p: Vector3 = player.global_position
	_coords_label.text = "x %d  y %d  z %d" % [int(p.x), int(p.y), int(p.z)]
	if _clock_label != null:
		var dn: Node = get_tree().get_first_node_in_group("day_night")
		_clock_label.text = ("🌙 " if (dn != null and dn.is_night()) else "☀ ") + (dn.clock_text() if dn != null else "")
	_coins_label.text = "🪙 %d" % Game.coins
	var surv := Game.mode == Game.Mode.SURVIVAL
	_health_bar.visible = surv
	_hunger_bar.visible = surv
	_health_bar.value = player.health
	_hunger_bar.value = player.hunger
	_refresh_hotbar()

func _flying(p: Node) -> bool:
	return bool(p._flying) if p != null and "_flying" in p else false

func _refresh_hotbar() -> void:
	if player == null:
		return
	for i in 9:
		var slot: Button = _hotbar_slots[i]
		var id := -1
		var count := 0
		if Game.is_creative():
			var list := _creative_list()
			id = int(list[i]) if i < list.size() else -1
			count = -1
		else:
			var s: Dictionary = player.inventory.get_slot(i)
			id = int(s.get("id", 0))
			count = int(s.get("count", 0))
		var txt := ""
		if id > 0:
			txt = Blocks.item_name(id) + ("\n∞" if count == -1 else "\n%d" % count)
		else:
			txt = ""
		slot.text = txt
		slot.icon = _icon_for(id)
		var sb: StyleBoxFlat = slot.get_theme_stylebox("normal")
		if sb != null:
			sb.border_color = Color(1, 1, 0.4) if i == Game.selected_slot else Color(0.35, 0.4, 0.5)
		# number keys + wheel handled in _unhandled? do it here:
	# wheel & number keys:
	# (handled in _unhandled_input)

func _creative_list() -> Array:
	var out: Array = []
	for i in range(1, 100):
		var m: BlockMaterial = Blocks.mat(i)
		if m != null and not m.is_terrain and not m.unbreakable:
			out.append(i)
	return out

func _refresh_hint() -> void:
	var lines := ["Tab Inventory · C Craft · B Furniture · T Design · V Info"]
	if furniture != null:
		if furniture.palette_open:
			lines = ["Palette: LMB place · R 15° · Ctrl+R 90° · G snap · RMB cancel"]
		elif furniture.design_open:
			lines = ["Design: LMB select · X color · M measure · Del remove · Ctrl+K save"]
	_hint_label.text = "  |  ".join(lines)

func _refresh_furniture_panels() -> void:
	if furniture == null:
		return
	_palette_panel.visible = furniture.palette_open
	if furniture.palette_open:
		_refresh_palette()
	_design_panel.visible = furniture.design_open

func _refresh_palette() -> void:
	for c in _palette_box.get_children():
		c.queue_free()
	var items := FurnitureCatalog.list()
	for i in items.size():
		var it: Dictionary = items[i]
		var b := Button.new()
		b.text = str(i + 1) + ". " + str(it["name"])
		b.toggle_mode = true
		b.button_pressed = i == furniture.selected_palette_index
		b.pressed.connect(func():
			furniture.selected_palette_index = i
			_refresh_palette()
		)
		_palette_box.add_child(b)

func _refresh_inv() -> void:
	for i in 36:
		var slot: Button = _inv_slots[i]
		if player == null:
			return
		var s: Dictionary = player.inventory.get_slot(i)
		var id := int(s.get("id", 0))
		slot.icon = _icon_for(id) if id > 0 else null
		slot.text = ("%d" % int(s["count"])) if id > 0 else ""
	_refresh_inv_cursor()

func _refresh_inv_cursor() -> void:
	if _inv_cursor.is_empty():
		_cursor_label.text = ""
	else:
		_cursor_label.text = "Cursor: %s ×%d" % [Blocks.item_name(int(_inv_cursor["id"])), int(_inv_cursor["count"])]

func _on_inv_slot_clicked(i: int) -> void:
	if player == null:
		return
	var s: Dictionary = player.inventory.get_slot(i)
	var sid := int(s.get("id", 0))
	var scount := int(s.get("count", 0))
	if _inv_cursor.is_empty():
		if sid > 0:
			_inv_cursor = {"id": sid, "count": scount}
			player.inventory.set_slot(i, 0, 0)
	else:
		if sid == 0:
			player.inventory.set_slot(i, int(_inv_cursor["id"]), int(_inv_cursor["count"]))
			_inv_cursor = {}
		elif sid == int(_inv_cursor["id"]):
			player.inventory.set_slot(i, sid, mini(64, scount + int(_inv_cursor["count"])))
			_inv_cursor = {}
		else:
			var tmp := {"id": sid, "count": scount}
			player.inventory.set_slot(i, int(_inv_cursor["id"]), int(_inv_cursor["count"]))
			_inv_cursor = tmp
	_refresh_inv()

func _refresh_crafting() -> void:
	for c in _craft_box.get_children():
		c.queue_free()
	for r in Crafting.recipes:
		var b := Button.new()
		var ins := []
		for id in r.inputs:
			ins.append("%d×%s" % [int(r.inputs[id]), Blocks.item_name(int(id))])
		b.text = "%s:  %s  →  %d× %s" % [str(r.name), " + ".join(ins), r.output_count, Blocks.item_name(r.output)]
		b.disabled = player != null and not Crafting.can_craft(player.inventory, r)
		b.pressed.connect(func():
			if player != null and Crafting.craft(player.inventory, r):
				Game.toast("Crafted %d× %s" % [r.output_count, Blocks.item_name(r.output)])
		)
		_craft_box.add_child(b)

func _on_challenge(text: String, progress: int, target: int) -> void:
	_challenge_label.text = "⭐ %s\nProgress: %d/%d" % [text, progress, target]

func _on_instability(count: int, remaining: float) -> void:
	if count > 0:
		_warning_panel.visible = true
		_warning_label.text = "⚠ STRUCTURE UNSTABLE — %d block(s) — collapses in %.1fs — add support!" % [count, remaining]
	else:
		_warning_panel.visible = false

func _on_toast(text: String) -> void:
	if _toast_t < 0.0:
		_toast_label.text = str(text)
		_toast_t = 0.0
		_toast_label.modulate.a = 1.0
	else:
		_toast_queue.append(text)

func _on_dialogue(text: String) -> void:
	_dialogue_label.text = str(text)
	_dialogue_t = 6.0
	_dialogue_label.modulate.a = 1.0

func _on_furniture_mode(palette: bool, design: bool) -> void:
	_refresh_furniture_panels()

# --- pause -----------------------------------------------------------------------

func _open_pause() -> void:
	_pause_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume() -> void:
	_pause_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_pause_button(txt: String) -> void:
	match txt:
		"Resume":
			_resume()
		"Save Game":
			var ok := Saves.save_game()
			Game.toast("Game saved." if ok else "Save failed.")
		"Toggle Mode (Creative/Survival)":
			Game.set_mode(Game.Mode.SURVIVAL if Game.is_creative() else Game.Mode.CREATIVE)
			_resume()
		"Quit to Menu":
			if Net.is_offline() and game_active:
				Saves.save_game()
			get_tree().paused = false
			_pause_panel.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			var main: Node = get_tree().get_first_node_in_group("main_scene")
			if main != null and main.has_method("show_main_menu"):
				main.show_main_menu()
