class_name Phase2VAB
extends Control

## Phase 2: Phase A-C 3D Modular Vehicle Assembly Building (VAB).
## Allocates >= 65% of screen width to the interactive 3D spacecraft viewport,
## with a clean scrollable subsystem drawer, concise SI part cards, and tooltip citations.

signal proceed_to_descent_requested()

const CATEGORY_ORDER: Array[Dictionary] = [
	{"id": "all", "label": "All"},
	{"id": "bus", "label": "Bus"},
	{"id": "propulsion", "label": "Prop"},
	{"id": "power", "label": "Power"},
	{"id": "comms", "label": "Comms"},
	{"id": "avionics", "label": "Avionics"},
	{"id": "payload", "label": "Science"},
	{"id": "shielding", "label": "Shield"}
]

const CATEGORY_TITLES: Dictionary = {
	"bus": "STRUCTURAL BUS",
	"propulsion": "PROPULSION",
	"power": "POWER & STORAGE",
	"comms": "TELECOMMUNICATIONS",
	"avionics": "AVIONICS & TRN",
	"payload": "SCIENCE PAYLOADS",
	"shielding": "RADIATION SHIELDING"
}

const PART_SHORT_NAMES: Dictionary = {
	"chassis_clps": "CLPS Lander Bus",
	"prop_chem_biprop": "Biprop Descent Engine",
	"prop_ion_sep": "Xenon Hall Thruster",
	"pwr_solar_lro": "Vertical Solar Array",
	"pwr_rtg_mmrtg": "MMRTG (Pu-238)",
	"pwr_batt_liion": "Cryo Li-Ion Battery",
	"comm_hga_ka": "Ka-Band HGA Dish",
	"comm_uga_s": "S-Band Omni Antenna",
	"obc_adcs_radhard": "Rad-Hard OBC & ADCS",
	"obc_adcs_cots": "COTS OBC & Sensor",
	"avionics_lidar_trn": "Hazard LiDAR & TRN",
	"pay_drill_trident": "TRIDENT Ice Drill",
	"pay_spec_msolo": "MSolo Mass Spec",
	"pay_sar_lband": "Mini-RF L-Band SAR",
	"shield_heavy": "Poly-Al Rad Shield"
}

const COLOR_DRAWER_BG: Color = Color(0.055, 0.082, 0.145, 0.94)
const COLOR_CARD_NORMAL: Color = Color(0.086, 0.125, 0.204, 0.96)
const COLOR_CARD_EQUIPPED: Color = Color(0.067, 0.220, 0.173, 0.96)
const COLOR_OK: Color = Color(0.063, 0.725, 0.506, 1.0)       # #10B981
const COLOR_WARN: Color = Color(0.961, 0.620, 0.043, 1.0)     # #F59E0B
const COLOR_CRIT: Color = Color(0.937, 0.267, 0.267, 1.0)     # #EF4444
const COLOR_ACCENT: Color = Color(0.220, 0.741, 0.973, 1.0)   # #38BDF8
const COLOR_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)          # #FFFFFF
const COLOR_MUTED: Color = Color(0.580, 0.639, 0.722, 1.0)    # #94A3B8

@onready var vab_world: Node3D = %VABWorld
@onready var camera_pivot: Node3D = %CameraPivot
@onready var vab_camera: Camera3D = %VABCamera
@onready var lander_chassis: LanderChassis = %LanderChassis
@onready var viewport_catcher: Control = %ViewportInputCatcher

@onready var left_drawer: PanelContainer = %LeftDrawer
@onready var bottom_bar: PanelContainer = %BottomBar
@onready var category_tabs: GridContainer = %CategoryTabs
@onready var catalog_vbox: VBoxContainer = %CatalogVBox

@onready var btn_reset_cam: Button = %BtnResetCam
@onready var btn_turntable: Button = %BtnTurntable
@onready var btn_proceed_sim: Button = %BtnProceedSim

@onready var trade_summary_label: Label = %TradeSummaryLabel
@onready var design_code_edit: LineEdit = %DesignCodeEdit
@onready var btn_export_code: Button = %BtnExportCode
@onready var btn_import_code: Button = %BtnImportCode

var _active_category: String = "all"
var _category_buttons: Dictionary = {}
var _part_buttons: Dictionary = {}
var _latest_slots: Array[Dictionary] = []

var _cam_yaw: float = 0.65
var _cam_pitch: float = -0.34
var _cam_distance: float = 5.8
var _target_yaw: float = 0.65
var _target_pitch: float = -0.34
var _target_distance: float = 5.8
var _is_dragging: bool = false
var _auto_turntable: bool = false


func _ready() -> void:
	_style_panels()
	_style_cta_button()
	_build_category_tabs()
	_rebuild_catalog_list()
	_connect_signals()
	_update_camera_transform(true)

	_latest_slots = lander_chassis.get_active_slot_records()
	_refresh_equipped_states(MissionState.get_telemetry_snapshot())


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


func _style_panels() -> void:
	for panel: PanelContainer in [left_drawer, bottom_bar]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = COLOR_DRAWER_BG
		style.border_color = Color(0.18, 0.29, 0.45, 0.90)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 12 if panel == left_drawer else 8
		style.content_margin_bottom = 12 if panel == left_drawer else 8
		panel.add_theme_stylebox_override("panel", style)


func _style_cta_button() -> void:
	var normal_sb: StyleBoxFlat = StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.06, 0.28, 0.44, 0.98)
	normal_sb.border_color = COLOR_ACCENT
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(5)
	normal_sb.content_margin_left = 14
	normal_sb.content_margin_right = 14
	normal_sb.content_margin_top = 8
	normal_sb.content_margin_bottom = 8

	var hover_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.08, 0.36, 0.56, 1.0)
	btn_proceed_sim.add_theme_stylebox_override("normal", normal_sb)
	btn_proceed_sim.add_theme_stylebox_override("hover", hover_sb)
	btn_proceed_sim.add_theme_color_override("font_color", COLOR_WHITE)


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
		btn.add_theme_font_size_override("font_size", 12)
		var tab_style: StyleBoxFlat = StyleBoxFlat.new()
		tab_style.bg_color = COLOR_CARD_NORMAL
		tab_style.border_color = Color(0.20, 0.31, 0.48, 0.85)
		tab_style.set_border_width_all(1)
		tab_style.set_corner_radius_all(4)
		tab_style.content_margin_left = 6
		tab_style.content_margin_right = 6
		tab_style.content_margin_top = 4
		tab_style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", tab_style)
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
		header.add_theme_font_size_override("font_size", 12)
		header.add_theme_color_override("font_color", COLOR_MUTED)
		catalog_vbox.add_child(header)

		for part_data: Dictionary in parts:
			var card_btn: Button = _create_part_card_button(part_data)
			catalog_vbox.add_child(card_btn)


func _create_part_card_button(part_data: Dictionary) -> Button:
	var part_id: String = str(part_data.get("id", ""))
	var short_name: String = str(PART_SHORT_NAMES.get(part_id, part_data.get("name", part_id)))
	var stat_line: String = _format_compact_stat_line(part_data)

	var btn: Button = Button.new()
	btn.toggle_mode = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 56)
	btn.add_theme_font_size_override("font_size", 14)
	btn.text = "%s\n%s" % [short_name, stat_line]
	btn.tooltip_text = _build_part_tooltip(part_data)
	btn.pressed.connect(_on_part_card_pressed.bind(part_id))
	_part_buttons[part_id] = btn
	return btn


func _format_compact_stat_line(part_data: Dictionary) -> String:
	var mass_kg: float = float(part_data.get("mass_dry_kg", 0.0))
	var cost_m: float = float(part_data.get("cost_m_usd", 0.0))
	var cat: String = str(part_data.get("subsystem", ""))

	match cat:
		"propulsion":
			var thrust_n: float = float(part_data.get("thrust_n", 0.0))
			var thrust_str: String = ("%.1f kN" % (thrust_n / 1000.0)) if thrust_n >= 100.0 else ("%.2f N" % thrust_n)
			return "%.0f kg  •  %s  •  $%.1fM" % [mass_kg, thrust_str, cost_m]
		"power":
			var kwh: float = float(part_data.get("energy_capacity_kwh", 0.0))
			if kwh > 0.0:
				return "%.0f kg  •  %.0f kWh  •  $%.1fM" % [mass_kg, kwh, cost_m]
			return "%.0f kg  •  %+.0f W  •  $%.1fM" % [mass_kg, float(part_data.get("power_w", 0.0)), cost_m]
		"comms":
			return "%.1f kg  •  %.1f Mbps  •  $%.1fM" % [mass_kg, float(part_data.get("data_rate_mbps", 0.0)), cost_m]
		"avionics":
			var slope: float = float(part_data.get("max_safe_slope_deg", 0.0))
			if slope > 0.0:
				return "%.1f kg  •  %.0f° Slope  •  $%.1fM" % [mass_kg, slope, cost_m]
			return "%.1f kg  •  %.0f krad  •  $%.1fM" % [mass_kg, float(part_data.get("radiation_tolerance_krad", 0.0)), cost_m]
		"payload":
			return "%.0f kg  •  +%.0f Sci  •  $%.1fM" % [mass_kg, float(part_data.get("science_points", 0.0)), cost_m]
		"shielding":
			return "%.0f kg  •  %.0f g/cm²  •  $%.1fM" % [mass_kg, float(part_data.get("shielding_g_cm2", 0.0)), cost_m]

	return "%.0f kg  •  %+.0f W  •  $%.1fM" % [mass_kg, float(part_data.get("power_w", 0.0)), cost_m]


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

	var tip: String = "%s\n" % name_str
	tip += "Subsystem: %s | Mount: %s\n" % [cat, mount_pt]
	tip += "Nominal Dry Mass: %.2f kg (+%.1f%% MGA -> %.2f kg)\n" % [mass, mga, eff_mass]
	tip += "Operating Power: %+.1f W | Cost: $%.2f M\n" % [power, cost]

	if float(part_data.get("thrust_n", 0.0)) > 0.0:
		tip += "Thrust: %.2f N | Isp: %.1f s | Propellant: %.1f kg\n" % [
			float(part_data.get("thrust_n", 0.0)),
			float(part_data.get("isp_s", 0.0)),
			float(part_data.get("propellant_capacity_kg", 0.0))
		]
	if float(part_data.get("thermal_output_w", 0.0)) > 0.0:
		tip += "Thermal Output: %.0f W\n" % float(part_data.get("thermal_output_w", 0.0))
	if float(part_data.get("science_points", 0.0)) > 0.0:
		tip += "Science Return: +%.0f pts | Telemetry: %.1f GB/day\n" % [
			float(part_data.get("science_points", 0.0)),
			float(part_data.get("data_rate_gb_day", 0.0))
		]
	if float(part_data.get("data_rate_mbps", 0.0)) > 0.0:
		tip += "DSN Downlink Rate: %.1f Mbps\n" % float(part_data.get("data_rate_mbps", 0.0))
	if float(part_data.get("shielding_g_cm2", 0.0)) > 0.0:
		tip += "Shielding Density: %.1f g/cm^2\n" % float(part_data.get("shielding_g_cm2", 0.0))

	tip += "\n[NASA Citation]\n%s" % citation
	return tip


func _on_part_card_pressed(part_id: String) -> void:
	if part_id == "chassis_clps":
		_refresh_equipped_states(MissionState.get_telemetry_snapshot())
		return
	MissionState.toggle_subsystem(part_id)


func _on_state_updated(snap: Dictionary) -> void:
	_refresh_equipped_states(snap)


func _on_chassis_meshes_updated(active_slots: Array[Dictionary]) -> void:
	_latest_slots = active_slots
	_update_trade_summary(MissionState.get_telemetry_snapshot())


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
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_CARD_EQUIPPED if equipped else COLOR_CARD_NORMAL
	style.border_color = COLOR_OK if equipped else Color(0.20, 0.31, 0.48, 0.85)
	style.set_border_width_all(1)
	if equipped:
		style.border_width_left = 4
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("pressed", style)


func _update_trade_summary(snap: Dictionary) -> void:
	if snap.is_empty():
		return

	var tw: float = float(snap.get("lunar_tw_ratio", 0.0))
	var dv: float = float(snap.get("delta_v_ms", 0.0))
	var req_dv: float = float(snap.get("required_dv_ms", 1750.0))
	var m0_wet: float = float(snap.get("m0_wet_kg", 0.0))
	var dry_nom: float = float(snap.get("dry_mass_nominal_kg", 0.0))
	var mga_kg: float = float(snap.get("mga_mass_kg", 0.0))
	var net_p: float = float(snap.get("net_power_w", 0.0))
	var life_d: float = float(snap.get("mission_lifetime_days", 0.0))
	var fail_code: String = str(snap.get("failure_code", "NOMINAL"))

	var status_color: Color = COLOR_OK if fail_code == "NOMINAL" else (COLOR_WARN if fail_code == "DSN_DOWNLINK_BOTTLENECK" else COLOR_CRIT)
	trade_summary_label.text = "%d Mounted  •  T/W %.2f  •  Δv %.0f/%.0f m/s  •  %s" % [
		_latest_slots.size(), tw, dv, req_dv, fail_code
	]
	trade_summary_label.add_theme_color_override("font_color", status_color)

	var slot_lines: Array[String] = []
	for slot_rec: Dictionary in _latest_slots:
		slot_lines.append("• %s -> %s (%s)" % [
			str(slot_rec.get("mount_point", "Mount")),
			str(slot_rec.get("name", "")),
			str(slot_rec.get("model_path", "")).get_file()
		])

	trade_summary_label.tooltip_text = (
		"Real-Time MGA & Trade Study\n"
		+ "Dry Mass: %.1f kg (+%.1f kg MGA) | Wet Mass (m0): %.1f kg\n" % [dry_nom, mga_kg, m0_wet]
		+ "Lunar T/W: %.3f | Delta-V: %.0f / %.0f m/s | Net Power: %+.1f W\n" % [tw, dv, req_dv, net_p]
		+ "Surface Lifetime: %.1f days | Status: %s\n\n" % [life_d, fail_code]
		+ "Mounted 3D Slots (%d):\n%s" % [_latest_slots.size(), "\n".join(slot_lines)]
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
