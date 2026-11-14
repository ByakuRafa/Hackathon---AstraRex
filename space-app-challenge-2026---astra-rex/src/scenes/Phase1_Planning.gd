class_name Phase1Planning
extends Control

## Phase 1: Pre-Phase A Mission Formulation Screen.
## Configures Shackleton Crater science objectives, landing zone, 1-4 player asymmetric roles,
## launch vehicle selection, operational orbit, and live LaunchVehicleCheck diagnostics.

signal proceed_to_vab_requested()

const OBJECTIVES: Array[Dictionary] = [
	{
		"id": "obj_ice_assay",
		"title": "Polar Water-Ice Regolith Assay",
		"summary": "Subsurface volatile extraction and mass spectrometry inside Shackleton Crater.",
		"recommended_parts": "TRIDENT Ice Drill + MSolo Mass Spectrometer + MMRTG",
		"citation": "NASA CLPS PRIME-1 / VIPER Science Traceability Matrix (STM)"
	},
	{
		"id": "obj_psr_radar",
		"title": "Permanent Shadow Radar Mapping",
		"summary": "High-bandwidth L/S-band SAR backscatter mapping across permanently shadowed craters.",
		"recommended_parts": "Mini-RF SAR + Ka-Band High-Gain Dish + Rad-Hard ADCS",
		"citation": "NASA LRO Mini-RF Polar Volatiles & Artemis Exploration Strategy"
	},
	{
		"id": "obj_ridge_precursor",
		"title": "Artemis Connecting Ridge Precursor",
		"summary": "Long-duration solar/comms beacon & hazard survey on sunlit Shackleton Ridge.",
		"recommended_parts": "Articulated Vertical Solar Array + LiDAR TRN + Ka-Band HGA",
		"citation": "NASA Artemis III Candidate Landing Site Characterization (LRO LOLA)"
	}
]

const ROLE_DEFS: Array[Dictionary] = [
	{
		"role": MissionState.TeamRole.PLANNER,
		"short": "1. Mission Planner",
		"focus": "TLI Wet Mass (kg) • Budget Cap (M$) • Orbit Δv & DTE (%)"
	},
	{
		"role": MissionState.TeamRole.PROPULSION_GNC,
		"short": "2. Propulsion & GNC",
		"focus": "Lunar T/W (>= 1.0) • Tsiolkovsky Δv (m/s) • TRN Slope (<= 15°)"
	},
	{
		"role": MissionState.TeamRole.SCIENCE,
		"short": "3. Science Director",
		"focus": "Effective Science (pts) • Payload Data (GB/day) • Site Multiplier"
	},
	{
		"role": MissionState.TeamRole.COMMS_POWER,
		"short": "4. Comms & Power",
		"focus": "Net Power (W) • Battery (Wh) • DSN Link (Mbps) • Dose (mSv)"
	}
]

const COLOR_PANEL_BG: Color = Color(0.065, 0.088, 0.135, 0.96)
const COLOR_CARD_BG: Color = Color(0.095, 0.128, 0.195, 0.96)
const COLOR_CARD_SEL: Color = Color(0.11, 0.19, 0.30, 0.98)
const COLOR_OK: Color = Color(0.24, 0.88, 0.56, 1.0)
const COLOR_WARN: Color = Color(0.98, 0.74, 0.22, 1.0)
const COLOR_CRIT: Color = Color(1.0, 0.30, 0.34, 1.0)
const COLOR_ACCENT: Color = Color(0.32, 0.74, 1.0, 1.0)
const COLOR_TEXT_SUB: Color = Color(0.72, 0.80, 0.90, 1.0)

@onready var objective_list: VBoxContainer = %ObjectiveList
@onready var zone_list: VBoxContainer = %ZoneList
@onready var team_size_row: HBoxContainer = %TeamSizeRow
@onready var role_list: VBoxContainer = %RoleList
@onready var role_priority_label: Label = %RolePriorityLabel
@onready var lv_list: VBoxContainer = %LaunchVehicleList
@onready var orbit_list: VBoxContainer = %OrbitList
@onready var check_status_banner: Label = %CheckStatusBanner
@onready var check_metrics_grid: GridContainer = %CheckMetricsGrid
@onready var check_reasons_label: RichTextLabel = %CheckReasonsLabel
@onready var btn_proceed_vab: Button = %BtnProceedVAB

var _obj_buttons: Dictionary = {}
var _zone_buttons: Dictionary = {}
var _team_size_buttons: Array[Button] = []
var _role_buttons: Dictionary = {}
var _lv_buttons: Dictionary = {}
var _orbit_buttons: Dictionary = {}
var _check_labels: Dictionary = {}


func _ready() -> void:
	_style_background_panels()
	_build_objective_buttons()
	_build_landing_zone_buttons()
	_build_team_controls()
	_build_launch_vehicle_buttons()
	_build_orbit_buttons()
	_build_check_grid()

	btn_proceed_vab.pressed.connect(_on_proceed_pressed)
	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)

	_refresh_ui(MissionState.get_telemetry_snapshot())


func _style_background_panels() -> void:
	var bg_nodes: Array[Node] = find_children("*Panel", "PanelContainer", true, false)
	for n: Node in bg_nodes:
		var panel: PanelContainer = n as PanelContainer
		if panel == null:
			continue
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = COLOR_PANEL_BG
		style.border_color = Color(0.18, 0.30, 0.48, 0.85)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)


func _build_objective_buttons() -> void:
	for obj_def: Dictionary in OBJECTIVES:
		var title: String = str(obj_def.get("title", ""))
		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 46)
		btn.text = "%s\n%s" % [title, str(obj_def.get("summary", ""))]
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = "%s\nRecommended Hardware: %s\n\n[Reference]: %s" % [
			title,
			str(obj_def.get("recommended_parts", "")),
			str(obj_def.get("citation", ""))
		]
		btn.pressed.connect(_on_objective_selected.bind(title))
		objective_list.add_child(btn)
		_obj_buttons[title] = btn


func _build_landing_zone_buttons() -> void:
	var zones: Dictionary = NasaDataLoader.get_all_landing_zones()
	var terrain_meta: Dictionary = NasaDataLoader.get_terrain_metadata()
	var citation: String = str(terrain_meta.get("nasa_citation", "LRO LOLA GDR 20 m/px"))
	var zone_order: Array[String] = ["connecting_ridge_rim", "inner_wall_hazard", "crater_floor_psr"]

	for zone_id: String in zone_order:
		if not zones.has(zone_id):
			continue
		var zone: Dictionary = zones[zone_id] as Dictionary
		var label_str: String = str(zone.get("label", zone_id))
		var slope: float = float(zone.get("mean_slope_deg", 0.0))
		var solar_pct: float = float(zone.get("solar_illumination_percent", 0.0))
		var dte_pct: float = float(zone.get("dte_visibility_percent", 0.0))
		var sci_mult: float = float(zone.get("science_multiplier", 1.0))
		var elev_m: float = float(zone.get("elevation_m", 0.0))

		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 44)
		btn.text = "%s (x%.2f Sci)\nSlope %.1f° | Sun %.0f%% | DTE %.0f%% | Elev %.0f m" % [
			label_str, sci_mult, slope, solar_pct, dte_pct, elev_m
		]
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = (
			"Target Landing Site: %s\n" % label_str
			+ "Elevation (LOLA): %.1f m | Mean Slope: %.1f deg\n" % [elev_m, slope]
			+ "Solar Illumination: %.0f%% | DTE Visibility: %.0f%%\n" % [solar_pct, dte_pct]
			+ "Science Value Multiplier: x%.2f\n\n[NASA Citation]: %s" % [sci_mult, citation]
		)
		btn.pressed.connect(_on_zone_selected.bind(zone_id))
		zone_list.add_child(btn)
		_zone_buttons[zone_id] = btn


func _build_team_controls() -> void:
	for count: int in range(1, 5):
		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = "%dP" % count if count > 1 else "1P Solo"
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = "Configure team collaboration for %d mission engineer(s)." % count
		btn.pressed.connect(_on_team_size_selected.bind(count))
		team_size_row.add_child(btn)
		_team_size_buttons.append(btn)

	for r_def: Dictionary in ROLE_DEFS:
		var role_id: int = int(r_def.get("role", 0))
		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 44)
		btn.text = "%s\n%s" % [str(r_def.get("short", "")), str(r_def.get("focus", ""))]
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = "Asymmetric Team Role: %s\nPriority Metrics: %s" % [
			MissionState.get_role_label(role_id),
			str(r_def.get("focus", ""))
		]
		btn.pressed.connect(_on_role_selected.bind(role_id))
		role_list.add_child(btn)
		_role_buttons[role_id] = btn


func _build_launch_vehicle_buttons() -> void:
	var vehicles: Array[Dictionary] = NasaDataLoader.get_all_launch_vehicles()
	for lv: Dictionary in vehicles:
		var lv_id: String = str(lv.get("id", ""))
		var lv_name: String = str(lv.get("name", lv_id))
		var max_tli: float = float(lv.get("max_tli_payload_kg", 0.0))
		var cost: float = float(lv.get("cost_m_usd", 0.0))
		var fairing: float = float(lv.get("fairing_diameter_m", 5.2))
		var rel: float = float(lv.get("reliability", 0.98)) * 100.0
		var citation: String = str(lv.get("nasa_citation", ""))

		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 44)
		btn.text = "%s\nMax TLI: %.0f kg | $%.1f M | Fairing %.1f m | Rel %.0f%%" % [
			lv_name, max_tli, cost, fairing, rel
		]
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = (
			"%s\nMax Trans-Lunar Injection (TLI) Payload: %.1f kg\n" % [lv_name, max_tli]
			+ "Launch Cost: $%.1f M | Fairing Diameter: %.1f m\n" % [cost, fairing]
			+ "Reliability: %.1f%%\n\n[NASA Citation]: %s" % [rel, citation]
		)
		btn.pressed.connect(_on_launch_vehicle_selected.bind(lv_id))
		lv_list.add_child(btn)
		_lv_buttons[lv_id] = btn


func _build_orbit_buttons() -> void:
	var orbits: Array[Dictionary] = NasaDataLoader.get_all_orbits()
	for orb: Dictionary in orbits:
		var orb_id: String = str(orb.get("id", ""))
		var orb_name: String = str(orb.get("name", orb_id))
		var req_dv: float = float(orb.get("delta_v_descent_m_s", 1750.0))
		var dte_pct: float = float(orb.get("dte_visibility_percent", 50.0))
		var period_h: float = float(orb.get("orbital_period_hours", 1.97))
		var citation: String = str(orb.get("nasa_citation", ""))
		var desc: String = str(orb.get("description", ""))

		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 48)
		btn.text = "%s\nReq Δv: %.0f m/s | DTE Vis: %.0f%% | Period: %.2f h" % [
			orb_name, req_dv, dte_pct, period_h
		]
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = "%s\n%s\n\n[NASA Citation]: %s" % [orb_name, desc, citation]
		btn.pressed.connect(_on_orbit_selected.bind(orb_id))
		orbit_list.add_child(btn)
		_orbit_buttons[orb_id] = btn


func _build_check_grid() -> void:
	var rows: Array[Array] = [
		["mass", "TLI Mass Cap (m0)"],
		["dv", "Orbit Descent Δv"],
		["tw", "Lunar T/W (>= 1.0)"],
		["dte", "DTE Contact Window"],
		["cost", "Mission Cost vs Cap"]
	]
	for entry: Array in rows:
		var key: String = str(entry[0])
		var title_text: String = str(entry[1])

		var name_lbl: Label = Label.new()
		name_lbl.text = title_text
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", COLOR_TEXT_SUB)
		check_metrics_grid.add_child(name_lbl)

		var val_lbl: Label = Label.new()
		val_lbl.text = "--"
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_lbl.add_theme_font_size_override("font_size", 11)
		check_metrics_grid.add_child(val_lbl)

		_check_labels[key] = val_lbl


func _on_objective_selected(title: String) -> void:
	MissionState.selected_objective = title
	MissionState.recalculate_all_telemetry(false)


func _on_zone_selected(zone_id: String) -> void:
	MissionState.set_landing_zone(zone_id)


func _on_team_size_selected(count: int) -> void:
	MissionState.set_team_size(count)


func _on_role_selected(role_id: int) -> void:
	MissionState.set_active_role(role_id)


func _on_launch_vehicle_selected(lv_id: String) -> void:
	MissionState.set_launch_vehicle(lv_id)


func _on_orbit_selected(orbit_id: String) -> void:
	MissionState.set_orbit(orbit_id)


func _on_proceed_pressed() -> void:
	proceed_to_vab_requested.emit()


func _on_state_updated(snap: Dictionary) -> void:
	_refresh_ui(snap)


func _refresh_ui(snap: Dictionary) -> void:
	if snap.is_empty():
		return

	var sel_obj: String = str(snap.get("selected_objective", ""))
	if not _obj_buttons.has(sel_obj) and not OBJECTIVES.is_empty():
		sel_obj = str(OBJECTIVES[0].get("title", ""))
	for obj_key_var: Variant in _obj_buttons.keys():
		var obj_key: String = str(obj_key_var)
		var btn: Button = _obj_buttons[obj_key] as Button
		btn.set_pressed_no_signal(obj_key == sel_obj)

	var sel_zone: String = str(snap.get("landing_zone_id", ""))
	for z_key_var: Variant in _zone_buttons.keys():
		var z_key: String = str(z_key_var)
		var btn: Button = _zone_buttons[z_key] as Button
		btn.set_pressed_no_signal(z_key == sel_zone)

	var t_size: int = int(snap.get("team_size", 1))
	for i: int in range(_team_size_buttons.size()):
		var t_btn: Button = _team_size_buttons[i]
		t_btn.set_pressed_no_signal((i + 1) == t_size)

	var active_r: int = int(snap.get("active_role", 0))
	for r_key_var: Variant in _role_buttons.keys():
		var r_key: int = int(r_key_var)
		var r_btn: Button = _role_buttons[r_key] as Button
		r_btn.set_pressed_no_signal(r_key == active_r)
		r_btn.disabled = (r_key >= t_size)

	_update_role_priority_callout(active_r, snap)

	var sel_lv: String = str(snap.get("launch_vehicle_id", ""))
	for lv_key_var: Variant in _lv_buttons.keys():
		var lv_key: String = str(lv_key_var)
		var lv_btn: Button = _lv_buttons[lv_key] as Button
		lv_btn.set_pressed_no_signal(lv_key == sel_lv)

	var sel_orb: String = str(snap.get("orbit_id", ""))
	for orb_key_var: Variant in _orbit_buttons.keys():
		var orb_key: String = str(orb_key_var)
		var orb_btn: Button = _orbit_buttons[orb_key] as Button
		orb_btn.set_pressed_no_signal(orb_key == sel_orb)

	_update_launch_vehicle_check(snap)


func _update_role_priority_callout(active_r: int, snap: Dictionary) -> void:
	var role_title: String = MissionState.get_role_label(active_r)
	var detail: String = ""
	match active_r:
		MissionState.TeamRole.PLANNER:
			detail = "Watch: m0 = %.1f kg | Cost $%.1fM | Req Δv %.0f m/s" % [
				float(snap.get("m0_wet_kg", 0.0)),
				float(snap.get("total_cost_musd", 0.0)),
				float(snap.get("required_dv_ms", 1750.0))
			]
		MissionState.TeamRole.PROPULSION_GNC:
			detail = "Watch: Lunar T/W = %.3f | Δv = %.0f m/s | TRN LiDAR: %s" % [
				float(snap.get("lunar_tw_ratio", 0.0)),
				float(snap.get("delta_v_ms", 0.0)),
				"ACTIVE" if bool(snap.get("has_lidar_trn", false)) else "MISSING"
			]
		MissionState.TeamRole.SCIENCE:
			detail = "Watch: Eff. Sci = %.1f pts | Data = %.1f GB/d" % [
				float(snap.get("science_points_effective", 0.0)),
				float(snap.get("data_generated_gb_day", 0.0))
			]
		MissionState.TeamRole.COMMS_POWER:
			detail = "Watch: Net Pwr = %+.1f W | DSN %.1f Mbps | Dose %.1f mSv" % [
				float(snap.get("net_power_w", 0.0)),
				float(snap.get("downlink_mbps", 0.0)),
				float(snap.get("total_mission_dose_msv", 0.0))
			]
	role_priority_label.text = "Active Role: %s\n%s" % [role_title, detail]
	role_priority_label.add_theme_color_override("font_color", COLOR_ACCENT)


func _update_launch_vehicle_check(snap: Dictionary) -> void:
	var check: Dictionary = MissionState.validate_launch_compatibility()
	var compat: bool = bool(check.get("compatible", false))
	var mass_ok: bool = bool(check.get("mass_ok", false))
	var dv_ok: bool = bool(check.get("dv_ok", false))
	var tw_ok: bool = bool(check.get("tw_ok", false))
	var budget_ok: bool = bool(check.get("budget_ok", false))

	var m0_wet: float = float(check.get("m0_wet_kg", 0.0))
	var max_tli: float = float(check.get("max_tli_mass_kg", 0.0))
	var dv: float = float(check.get("delta_v_ms", 0.0))
	var req_dv: float = float(check.get("required_dv_ms", 1750.0))
	var tw: float = float(check.get("lunar_tw_ratio", 0.0))
	var dte_pct: float = float(snap.get("dte_visibility_pct", 0.0))
	var cost: float = float(check.get("total_cost_musd", 0.0))
	var cap: float = float(check.get("budget_cap_musd", 350.0))

	if compat:
		check_status_banner.text = "LaunchVehicleCheck: PASS — READY FOR TLI"
		check_status_banner.add_theme_color_override("font_color", COLOR_OK)
	else:
		check_status_banner.text = "LaunchVehicleCheck: FAIL — VIOLATIONS DETECTED"
		check_status_banner.add_theme_color_override("font_color", COLOR_CRIT)

	check_status_banner.tooltip_text = "Launch Compatibility Audit\n[Reference]: %s" % str(check.get("citation", ""))

	var lbl_mass: Label = _check_labels["mass"] as Label
	lbl_mass.text = "%.1f / %.0f kg [%s]" % [m0_wet, max_tli, "PASS" if mass_ok else "FAIL"]
	lbl_mass.add_theme_color_override("font_color", COLOR_OK if mass_ok else COLOR_CRIT)

	var lbl_dv: Label = _check_labels["dv"] as Label
	lbl_dv.text = "%.0f / %.0f m/s [%s]" % [dv, req_dv, "PASS" if dv_ok else "FAIL"]
	lbl_dv.add_theme_color_override("font_color", COLOR_OK if dv_ok else COLOR_WARN)

	var lbl_tw: Label = _check_labels["tw"] as Label
	lbl_tw.text = "%.3f [%s]" % [tw, "PASS" if tw_ok else "LOCKOUT"]
	lbl_tw.add_theme_color_override("font_color", COLOR_OK if tw_ok else COLOR_CRIT)

	var lbl_dte: Label = _check_labels["dte"] as Label
	lbl_dte.text = "%.0f%% Direct-to-Earth" % dte_pct
	lbl_dte.add_theme_color_override("font_color", COLOR_OK if dte_pct >= 35.0 else COLOR_WARN)

	var lbl_cost: Label = _check_labels["cost"] as Label
	lbl_cost.text = "$%.1fM / $%.0fM [%s]" % [cost, cap, "PASS" if budget_ok else "OVER"]
	lbl_cost.add_theme_color_override("font_color", COLOR_OK if budget_ok else COLOR_CRIT)

	var reasons_raw: Array = check.get("reasons", []) as Array
	var lines: Array[String] = []
	for r_var: Variant in reasons_raw:
		lines.append("• " + str(r_var))
	check_reasons_label.text = "\n".join(lines)
