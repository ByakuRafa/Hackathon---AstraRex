class_name Phase2VAB
extends Control

## Phase 2: Phase A-C 3D Modular Vehicle Assembly Building (VAB).
## Renders the LanderChassis inside a gl_compatibility-safe VAB hangar alongside
## NASA reference hardware (SLS Block 1, VAB Gantry, DSN 70m Dish), with orbital
## camera controls, 7-category SI parts catalog, and live Marker3D slot inspector.

signal proceed_to_descent_requested()

const CATEGORY_ORDER: Array[Dictionary] = [
	{"id": "all", "label": "All (7)"},
	{"id": "bus", "label": "1. Bus"},
	{"id": "propulsion", "label": "2. Prop"},
	{"id": "power", "label": "3. Power"},
	{"id": "comms", "label": "4. Comms"},
	{"id": "avionics", "label": "5. Avionics"},
	{"id": "payload", "label": "6. Science"},
	{"id": "shielding", "label": "7. Shield"}
]

const CATEGORY_TITLES: Dictionary = {
	"bus": "1. STRUCTURAL BUS",
	"propulsion": "2. PROPULSION SUBSYSTEMS",
	"power": "3. ELECTRICAL POWER & STORAGE",
	"comms": "4. TELECOMMUNICATIONS (DSN)",
	"avionics": "5. AVIONICS, ADCS & TRN",
	"payload": "6. SCIENCE PAYLOADS",
	"shielding": "7. RADIATION SHIELDING"
}

const COLOR_DRAWER_BG: Color = Color(0.055, 0.078, 0.125, 0.88)
const COLOR_CARD_NORMAL: Color = Color(0.095, 0.130, 0.200, 0.94)
const COLOR_CARD_EQUIPPED: Color = Color(0.095, 0.240, 0.195, 0.96)
const COLOR_OK: Color = Color(0.24, 0.88, 0.56, 1.0)
const COLOR_WARN: Color = Color(0.98, 0.74, 0.22, 1.0)
const COLOR_CRIT: Color = Color(1.0, 0.30, 0.34, 1.0)
const COLOR_ACCENT: Color = Color(0.32, 0.74, 1.0, 1.0)
const COLOR_TEXT_MUTED: Color = Color(0.70, 0.78, 0.88, 1.0)

@onready var vab_world: Node3D = %VABWorld
@onready var camera_pivot: Node3D = %CameraPivot
@onready var vab_camera: Camera3D = %VABCamera
@onready var lander_chassis: LanderChassis = %LanderChassis
@onready var viewport_catcher: Control = %ViewportInputCatcher

@onready var left_drawer: PanelContainer = %LeftDrawer
@onready var right_drawer: PanelContainer = %RightDrawer
@onready var category_tabs: GridContainer = %CategoryTabs
@onready var catalog_vbox: VBoxContainer = %CatalogVBox

@onready var btn_reset_cam: Button = %BtnResetCam
@onready var btn_turntable: Button = %BtnTurntable
@onready var btn_proceed_sim: Button = %BtnProceedSim

@onready var slot_list_vbox: VBoxContainer = %SlotListVBox
@onready var trade_summary_label: RichTextLabel = %TradeSummaryLabel
@onready var design_code_edit: LineEdit = %DesignCodeEdit
@onready var btn_export_code: Button = %BtnExportCode
@onready var btn_import_code: Button = %BtnImportCode

var _active_category: String = "all"
var _category_buttons: Dictionary = {}
var _part_buttons: Dictionary = {}

var _cam_yaw: float = 0.65
var _cam_pitch: float = -0.34
var _cam_distance: float = 5.8
var _target_yaw: float = 0.65
var _target_pitch: float = -0.34
var _target_distance: float = 5.8
var _is_dragging: bool = false
var _auto_turntable: bool = false


func _ready() -> void:
	_style_drawers()
	_build_category_tabs()
	_rebuild_catalog_list()
	_connect_signals()
	_update_camera_transform(true)
	_refresh_equipped_states(MissionState.get_telemetry_snapshot())
	_refresh_slot_inspector(lander_chassis.get_active_slot_records())


func _process(delta: float) -> void:
	if not visible:
		return

	if _auto_turntable and not _is_dragging:
		_target_yaw += delta * 0.25

	var lerp_weight: float = clampf(delta * 10.0, 0.0, 1.0)
	_cam_yaw = lerpf(_cam_yaw, _target_yaw, lerp_weight)
	_cam_pitch = lerpf(_cam_pitch, _target_pitch, lerp_weight)
	_cam_distance = lerpf(_cam_distance, _target_distance, lerp_weight)
	_update_camera_transform(false)


func set_vab_active(active: bool) -> void:
	visible = active
	if is_instance_valid(vab_world):
		vab_world.visible = active
	if is_instance_valid(vab_camera):
		vab_camera.current = active


func _style_drawers() -> void:
	for drawer: PanelContainer in [left_drawer, right_drawer]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = COLOR_DRAWER_BG
		style.border_color = Color(0.22, 0.38, 0.60, 0.90)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		drawer.add_theme_stylebox_override("panel", style)


func _connect_signals() -> void:
	viewport_catcher.gui_input.connect(_on_viewport_gui_input)
	btn_reset_cam.pressed.connect(_on_reset_camera_pressed)
	btn_turntable.toggled.connect(_on_turntable_toggled)
	btn_proceed_sim.pressed.connect(_on_proceed_sim_pressed)
	btn_export_code.pressed.connect(_on_export_code_pressed)
	btn_import_code.pressed.connect(_on_import_code_pressed)

	if not lander_chassis.meshes_updated.is_connected(_on_chassis_meshes_updated):
		lander_chassis.meshes_updated.connect(_on_chassis_meshes_updated)
	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)


func _build_category_tabs() -> void:
	for cat_def: Dictionary in CATEGORY_ORDER:
		var cat_id: String = str(cat_def.get("id", "all"))
		var cat_label: String = str(cat_def.get("label", cat_id))
		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = cat_label
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_on_category_selected.bind(cat_id))
		category_tabs.add_child(btn)
		_category_buttons[cat_id] = btn
	_sync_category_tab_buttons()


func _on_category_selected(cat_id: String) -> void:
	_active_category = cat_id
	_sync_category_tab_buttons()
	_rebuild_catalog_list()
	_refresh_equipped_states(MissionState.get_telemetry_snapshot())


func _sync_category_tab_buttons() -> void:
	for cat_var: Variant in _category_buttons.keys():
		var cat_key: String = str(cat_var)
		var btn: Button = _category_buttons[cat_key] as Button
		btn.set_pressed_no_signal(cat_key == _active_category)


func _rebuild_catalog_list() -> void:
	for child: Node in catalog_vbox.get_children():
		child.queue_free()
	_part_buttons.clear()

	var categories_to_show: Array[String] = []
	if _active_category == "all":
		categories_to_show = ["bus", "propulsion", "power", "comms", "avionics", "payload", "shielding"]
	else:
		categories_to_show = [_active_category]

	for cat: String in categories_to_show:
		var parts: Array[Dictionary] = NasaDataLoader.get_subsystems_by_category(cat)
		if parts.is_empty():
			continue

		var header: Label = Label.new()
		header.text = str(CATEGORY_TITLES.get(cat, cat.to_upper()))
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", COLOR_ACCENT)
		catalog_vbox.add_child(header)

		for part_data: Dictionary in parts:
			var card_btn: Button = _create_part_card_button(part_data)
			catalog_vbox.add_child(card_btn)


func _create_part_card_button(part_data: Dictionary) -> Button:
	var part_id: String = str(part_data.get("id", ""))
	var part_name: String = str(part_data.get("name", part_id))
	var mass_kg: float = float(part_data.get("mass_dry_kg", 0.0))
	var mga_pct: float = float(part_data.get("mga_percent", 0.15)) * 100.0
	var power_w: float = float(part_data.get("power_w", 0.0))
	var cost_m: float = float(part_data.get("cost_m_usd", 0.0))

	var extra_si: String = _format_part_extra_si(part_data)
	var btn: Button = Button.new()
	btn.toggle_mode = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.custom_minimum_size = Vector2(0, 56)
	btn.add_theme_font_size_override("font_size", 11)
	btn.text = "%s\n%.1f kg (+%.0f%% MGA) | %+.0f W | $%.1fM%s" % [
		part_name, mass_kg, mga_pct, power_w, cost_m, extra_si
	]
	btn.tooltip_text = _build_part_tooltip(part_data)
	btn.pressed.connect(_on_part_card_pressed.bind(part_id))
	_part_buttons[part_id] = btn
	return btn


func _format_part_extra_si(part_data: Dictionary) -> String:
	var cat: String = str(part_data.get("subsystem", ""))
	match cat:
		"propulsion":
			return "\nThrust: %.2f N | Isp: %.0f s | Prop: %.0f kg" % [
				float(part_data.get("thrust_n", 0.0)),
				float(part_data.get("isp_s", 0.0)),
				float(part_data.get("propellant_capacity_kg", 0.0))
			]
		"comms":
			return " | %.1f Mbps" % float(part_data.get("data_rate_mbps", 0.0))
		"payload":
			return "\nData: %.1f GB/d | Sci: +%.0f pts" % [
				float(part_data.get("data_rate_gb_day", 0.0)),
				float(part_data.get("science_points", 0.0))
			]
		"power":
			var kwh: float = float(part_data.get("energy_capacity_kwh", 0.0))
			if kwh > 0.0:
				return " | Storage: %.0f kWh" % kwh
			var therm: float = float(part_data.get("thermal_output_w", 0.0))
			if therm > 0.0:
				return " | Heat: %.0f W" % therm
		"avionics":
			var slope: float = float(part_data.get("max_safe_slope_deg", 0.0))
			if slope > 0.0:
				return " | Max Slope: %.0f deg" % slope
			var rad_tol: float = float(part_data.get("radiation_tolerance_krad", 0.0))
			if rad_tol > 0.0:
				return " | Tol: %.0f krad" % rad_tol
		"shielding":
			return " | Areal: %.1f g/cm^2" % float(part_data.get("shielding_g_cm2", 0.0))
	return ""


func _build_part_tooltip(part_data: Dictionary) -> String:
	var name_str: String = str(part_data.get("name", ""))
	var cat: String = str(part_data.get("subsystem", "")).capitalize()
	var mass: float = float(part_data.get("mass_dry_kg", 0.0))
	var mga: float = float(part_data.get("mga_percent", 0.15)) * 100.0
	var eff_mass: float = mass * (1.0 + mga / 100.0)
	var power: float = float(part_data.get("power_w", 0.0))
	var cost: float = float(part_data.get("cost_m_usd", 0.0))
	var mount_pt: String = str(part_data.get("mount_point", ""))
	var citation: String = str(part_data.get("nasa_citation", NasaDataLoader.get_catalog_citation()))

	var tip: String = "=== %s ===\n" % name_str
	tip += "Subsystem: %s | Mount: %s\n" % [cat, mount_pt]
	tip += "Nominal Dry Mass: %.2f kg\n" % mass
	tip += "Mass Growth Allowance (MGA): +%.1f%%\n" % mga
	tip += "Effective Dry Mass: %.2f kg\n" % eff_mass
	tip += "Operating Power: %+.1f W\n" % power
	tip += "Lifecycle Cost: $%.2f M\n" % cost

	if float(part_data.get("thrust_n", 0.0)) > 0.0:
		tip += "Vacuum Thrust: %.2f N | Isp: %.1f s | Propellant: %.1f kg\n" % [
			float(part_data.get("thrust_n", 0.0)),
			float(part_data.get("isp_s", 0.0)),
			float(part_data.get("propellant_capacity_kg", 0.0))
		]
	if float(part_data.get("science_points", 0.0)) > 0.0:
		tip += "Science Return: +%.0f pts | Telemetry: %.1f GB/day\n" % [
			float(part_data.get("science_points", 0.0)),
			float(part_data.get("data_rate_gb_day", 0.0))
		]
	if float(part_data.get("data_rate_mbps", 0.0)) > 0.0:
		tip += "DSN Downlink Rate: %.1f Mbps\n" % float(part_data.get("data_rate_mbps", 0.0))
	if float(part_data.get("shielding_g_cm2", 0.0)) > 0.0:
		tip += "Shielding Density: %.1f g/cm^2\n" % float(part_data.get("shielding_g_cm2", 0.0))

	tip += "\n[Authoritative Reference]:\n%s" % citation
	return tip


func _on_part_card_pressed(part_id: String) -> void:
	if part_id == "chassis_clps":
		_refresh_equipped_states(MissionState.get_telemetry_snapshot())
		return
	MissionState.toggle_subsystem(part_id)


func _on_state_updated(snap: Dictionary) -> void:
	_refresh_equipped_states(snap)


func _on_chassis_meshes_updated(active_slots: Array[Dictionary]) -> void:
	_refresh_slot_inspector(active_slots)


func _refresh_equipped_states(snap: Dictionary) -> void:
	if snap.is_empty():
		return

	var raw_ids: Array = snap.get("subsystem_ids", []) as Array
	var equipped: Array[String] = []
	for id_var: Variant in raw_ids:
		equipped.append(str(id_var))

	for part_var: Variant in _part_buttons.keys():
		var part_id: String = str(part_var)
		var btn: Button = _part_buttons[part_id] as Button
		var is_on: bool = equipped.has(part_id)
		btn.set_pressed_no_signal(is_on)
		_apply_part_btn_style(btn, is_on)

	_update_trade_summary(snap)


func _apply_part_btn_style(btn: Button, equipped: bool) -> void:
	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = COLOR_CARD_EQUIPPED if equipped else COLOR_CARD_NORMAL
	normal_style.border_color = COLOR_OK if equipped else Color(0.22, 0.33, 0.50, 0.85)
	normal_style.set_border_width_all(1)
	if equipped:
		normal_style.border_width_left = 4
	normal_style.set_corner_radius_all(4)
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 4
	normal_style.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("pressed", normal_style)


func _refresh_slot_inspector(active_slots: Array[Dictionary]) -> void:
	for child: Node in slot_list_vbox.get_children():
		child.queue_free()

	for slot_rec: Dictionary in active_slots:
		var lbl: Label = Label.new()
		lbl.text = "• %s\n   %s" % [
			str(slot_rec.get("mount_point", "Mount")),
			str(slot_rec.get("name", ""))
		]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", COLOR_OK)
		lbl.tooltip_text = "Mounted 3D Mesh: %s" % str(slot_rec.get("model_path", ""))
		slot_list_vbox.add_child(lbl)


func _update_trade_summary(snap: Dictionary) -> void:
	var tw: float = float(snap.get("lunar_tw_ratio", 0.0))
	var dv: float = float(snap.get("delta_v_ms", 0.0))
	var req_dv: float = float(snap.get("required_dv_ms", 1750.0))
	var m0_wet: float = float(snap.get("m0_wet_kg", 0.0))
	var dry_nom: float = float(snap.get("dry_mass_nominal_kg", 0.0))
	var mga_kg: float = float(snap.get("mga_mass_kg", 0.0))
	var net_p: float = float(snap.get("net_power_w", 0.0))
	var life_d: float = float(snap.get("mission_lifetime_days", 0.0))
	var fail_code: String = str(snap.get("failure_code", "NOMINAL"))

	var tw_hex: String = "#3ee08f" if tw >= 1.0 else "#ff4d57"
	var dv_hex: String = "#3ee08f" if dv >= req_dv else "#fabb38"
	var pwr_hex: String = "#3ee08f" if net_p >= 0.0 else "#ff4d57"
	var stat_hex: String = "#3ee08f" if fail_code == "NOMINAL" else "#ff4d57"

	trade_summary_label.text = (
		"[b]REAL-TIME MGA & TRADE STUDY[/b]\n"
		+ "Dry Mass: %.1f kg (+%.1f kg MGA)\n" % [dry_nom, mga_kg]
		+ "Wet Mass (m0): %.1f kg\n" % m0_wet
		+ "Lunar T/W: [color=%s]%.3f[/color] (min 1.00)\n" % [tw_hex, tw]
		+ "Delta-V: [color=%s]%.0f / %.0f m/s[/color]\n" % [dv_hex, dv, req_dv]
		+ "Net Power: [color=%s]%+.1f W[/color]\n" % [pwr_hex, net_p]
		+ "Est. Surface Life: %.1f days\n" % life_d
		+ "Diagnostic: [color=%s]%s[/color]" % [stat_hex, fail_code]
	)


func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = clampf(_target_distance - 0.5, 2.8, 14.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = clampf(_target_distance + 0.5, 2.8, 14.0)
	elif event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_target_yaw -= mm.relative.x * 0.008
		_target_pitch = clampf(_target_pitch - mm.relative.y * 0.008, -1.25, 0.20)


func _update_camera_transform(snap_now: bool) -> void:
	if not is_instance_valid(camera_pivot) or not is_instance_valid(vab_camera):
		return
	if snap_now:
		_cam_yaw = _target_yaw
		_cam_pitch = _target_pitch
		_cam_distance = _target_distance
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	vab_camera.position = Vector3(0.0, 0.0, _cam_distance)
	vab_camera.look_at(camera_pivot.global_position, Vector3.UP)


func _on_reset_camera_pressed() -> void:
	_target_yaw = 0.65
	_target_pitch = -0.34
	_target_distance = 5.8


func _on_turntable_toggled(toggled_on: bool) -> void:
	_auto_turntable = toggled_on


func _on_proceed_sim_pressed() -> void:
	proceed_to_descent_requested.emit()


func _on_export_code_pressed() -> void:
	var code: String = MissionState.export_design_code()
	design_code_edit.text = code
	DisplayServer.clipboard_set(code)


func _on_import_code_pressed() -> void:
	var code: String = design_code_edit.text.strip_edges()
	if not code.is_empty():
		MissionState.import_design_code(code)
