class_name MainHUD
extends PanelContainer

## Persistent NASA Mission Control Top HUD Bar (<= 88px height).
## Hosts 1-Click Judge Presets, Student/Engineer Toggle, 4 Phase Tabs,
## and 6 Compact SI Resource Gauges with progressive-disclosure NASA citations in tooltips.

signal phase_requested(phase_index: int)

const COLOR_BG_BAR: Color = Color(0.043, 0.067, 0.125, 0.98)
const COLOR_CARD_BG: Color = Color(0.075, 0.110, 0.184, 0.96)
const COLOR_CARD_WARN_BG: Color = Color(0.180, 0.129, 0.043, 0.96)
const COLOR_CARD_ERR_BG: Color = Color(0.200, 0.055, 0.071, 0.96)

const COLOR_OK: Color = Color(0.063, 0.725, 0.506, 1.0)       # #10B981
const COLOR_WARN: Color = Color(0.961, 0.620, 0.043, 1.0)     # #F59E0B
const COLOR_CRIT: Color = Color(0.937, 0.267, 0.267, 1.0)     # #EF4444
const COLOR_ACCENT: Color = Color(0.220, 0.741, 0.973, 1.0)   # #38BDF8
const COLOR_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)          # #FFFFFF
const COLOR_HEADER: Color = Color(0.902, 0.945, 1.0, 1.0)     # #E6F1FF
const COLOR_MUTED: Color = Color(0.580, 0.639, 0.722, 1.0)    # #94A3B8

@onready var status_badge_label: Label = %StatusBadgeLabel
@onready var btn_preset_1: Button = %BtnPreset1
@onready var btn_preset_2: Button = %BtnPreset2
@onready var btn_preset_3: Button = %BtnPreset3
@onready var btn_mode_toggle: Button = %BtnModeToggle

@onready var btn_phase_1: Button = %BtnPhase1
@onready var btn_phase_2: Button = %BtnPhase2
@onready var btn_phase_3: Button = %BtnPhase3
@onready var btn_phase_4: Button = %BtnPhase4

@onready var card_mass: PanelContainer = %CardMass
@onready var mass_value_label: Label = %MassValueLabel
@onready var mass_sub_label: Label = %MassSubLabel

@onready var card_propulsion: PanelContainer = %CardPropulsion
@onready var prop_value_label: Label = %PropValueLabel
@onready var prop_sub_label: Label = %PropSubLabel

@onready var card_power: PanelContainer = %CardPower
@onready var power_value_label: Label = %PowerValueLabel
@onready var power_sub_label: Label = %PowerSubLabel

@onready var card_budget: PanelContainer = %CardBudget
@onready var budget_value_label: Label = %BudgetValueLabel
@onready var budget_sub_label: Label = %BudgetSubLabel

@onready var card_comms: PanelContainer = %CardComms
@onready var comms_value_label: Label = %CommsValueLabel
@onready var comms_sub_label: Label = %CommsSubLabel

@onready var card_radiation: PanelContainer = %CardRadiation
@onready var rad_value_label: Label = %RadValueLabel
@onready var rad_sub_label: Label = %RadSubLabel

var _active_phase_index: int = 0
var _phase_buttons: Array[Button] = []
var _preset_buttons: Array[Button] = []


func _ready() -> void:
	_phase_buttons = [btn_phase_1, btn_phase_2, btn_phase_3, btn_phase_4]
	_preset_buttons = [btn_preset_1, btn_preset_2, btn_preset_3]

	_apply_bar_style()
	_apply_compact_hud_buttons()
	_connect_ui_signals()
	_connect_state_signals()

	set_active_phase(0)
	_sync_controls_from_state()
	refresh_telemetry(MissionState.get_telemetry_snapshot())


func _apply_bar_style() -> void:
	var bar_style: StyleBoxFlat = StyleBoxFlat.new()
	bar_style.bg_color = COLOR_BG_BAR
	bar_style.border_color = Color(0.18, 0.29, 0.45, 0.90)
	bar_style.border_width_bottom = 2
	bar_style.content_margin_left = 12
	bar_style.content_margin_right = 12
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", bar_style)


func _apply_compact_hud_buttons() -> void:
	var all_hud_btns: Array[Button] = []
	all_hud_btns.append_array(_preset_buttons)
	all_hud_btns.append(btn_mode_toggle)
	all_hud_btns.append_array(_phase_buttons)

	for btn: Button in all_hud_btns:
		var normal_sb: StyleBoxFlat = _make_hud_btn_style(
			Color(0.086, 0.125, 0.204, 0.96),
			Color(0.20, 0.31, 0.48, 0.85),
			false
		)
		var hover_sb: StyleBoxFlat = _make_hud_btn_style(
			Color(0.122, 0.180, 0.294, 0.98),
			COLOR_ACCENT,
			false
		)
		var pressed_sb: StyleBoxFlat = _make_hud_btn_style(
			Color(0.094, 0.212, 0.341, 0.98),
			COLOR_ACCENT,
			true
		)
		btn.add_theme_stylebox_override("normal", normal_sb)
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.add_theme_stylebox_override("pressed", pressed_sb)
		btn.add_theme_stylebox_override("focus", hover_sb)


func _make_hud_btn_style(bg: Color, border: Color, active: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	if active:
		sb.border_width_bottom = 2
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _connect_ui_signals() -> void:
	btn_preset_1.pressed.connect(_on_preset_pressed.bind(1))
	btn_preset_2.pressed.connect(_on_preset_pressed.bind(2))
	btn_preset_3.pressed.connect(_on_preset_pressed.bind(3))
	btn_mode_toggle.toggled.connect(_on_mode_toggled)

	for idx: int in range(_phase_buttons.size()):
		var btn: Button = _phase_buttons[idx]
		btn.pressed.connect(_on_phase_button_pressed.bind(idx))


func _connect_state_signals() -> void:
	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)
	if not MissionState.preset_loaded.is_connected(_on_preset_loaded):
		MissionState.preset_loaded.connect(_on_preset_loaded)
	if not MissionState.simulation_alert.is_connected(_on_simulation_alert):
		MissionState.simulation_alert.connect(_on_simulation_alert)


func set_active_phase(phase_index: int) -> void:
	_active_phase_index = clampi(phase_index, 0, _phase_buttons.size() - 1)
	for idx: int in range(_phase_buttons.size()):
		var btn: Button = _phase_buttons[idx]
		var is_active: bool = (idx == _active_phase_index)
		btn.set_pressed_no_signal(is_active)
		if is_active:
			btn.add_theme_color_override("font_color", COLOR_HEADER)
		else:
			btn.remove_theme_color_override("font_color")


func _on_phase_button_pressed(phase_index: int) -> void:
	set_active_phase(phase_index)
	phase_requested.emit(phase_index)


func _on_preset_pressed(preset_index: int) -> void:
	MissionState.apply_preset(preset_index)


func _on_mode_toggled(toggled_on: bool) -> void:
	MissionState.set_engineer_mode(toggled_on)
	_sync_controls_from_state()


func _on_preset_loaded(_preset_index: int, _preset_name: String) -> void:
	_sync_controls_from_state()


func _on_state_updated(snap: Dictionary) -> void:
	_sync_controls_from_state()
	refresh_telemetry(snap)


func _on_simulation_alert(alert_code: String, message: String, citation: String) -> void:
	var pill_color: Color = COLOR_WARN if alert_code == "DSN_DOWNLINK_BOTTLENECK" else COLOR_CRIT
	_apply_status_pill(alert_code, pill_color)
	status_badge_label.tooltip_text = "%s\n\n[NASA Reference]\n%s" % [message, citation]


func _sync_controls_from_state() -> void:
	_ensure_compact_hud_styles()
	var eng: bool = MissionState.engineer_mode
	if btn_mode_toggle.button_pressed != eng:
		btn_mode_toggle.set_pressed_no_signal(eng)
	btn_mode_toggle.text = "ENGINEER (SI)" if eng else "STUDENT"
	btn_mode_toggle.tooltip_text = (
		"Dual-Scale Interface Mode\n"
		+ "Student: Guided PASS/FAIL indicators.\n"
		+ "Engineer: Full SI precision, MGA margins, and NASA citations.\n\n"
		+ "[NASA Reference]\n%s" % NasaDataLoader.get_catalog_citation()
	)

	btn_preset_1.tooltip_text = "Load Preset 1: Optimal Artemis CLPS (all constraints nominal)."
	btn_preset_2.tooltip_text = "Load Preset 2: Critical Thrust & PSR Power Failure demonstration."
	btn_preset_3.tooltip_text = "Load Preset 3: Free Sandbox on SLS Block 1 ($5,000M cap)."

	for idx: int in range(_preset_buttons.size()):
		var p_btn: Button = _preset_buttons[idx]
		var is_selected: bool = (idx + 1 == MissionState.current_preset_index)
		p_btn.set_pressed_no_signal(is_selected)


func _ensure_compact_hud_styles() -> void:
	if has_meta("_compact_hud_applied"):
		return
	set_meta("_compact_hud_applied", true)
	var base_panel: StyleBox = get_theme_stylebox("panel")
	if base_panel is StyleBoxFlat:
		var hud_sb: StyleBoxFlat = (base_panel as StyleBoxFlat).duplicate() as StyleBoxFlat
		hud_sb.content_margin_left = 10.0
		hud_sb.content_margin_right = 10.0
		hud_sb.content_margin_top = 4.0
		hud_sb.content_margin_bottom = 4.0
		add_theme_stylebox_override("panel", hud_sb)
	var top_buttons: Array[Button] = []
	for b: Button in _preset_buttons:
		top_buttons.append(b)
	for b: Button in _phase_buttons:
		top_buttons.append(b)
	top_buttons.append(btn_mode_toggle)
	for b: Button in top_buttons:
		for state_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb: StyleBox = b.get_theme_stylebox(state_name)
			if sb is StyleBoxFlat:
				var c_sb: StyleBoxFlat = (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
				c_sb.content_margin_top = 2.0
				c_sb.content_margin_bottom = 2.0
				c_sb.content_margin_left = 8.0
				c_sb.content_margin_right = 8.0
				b.add_theme_stylebox_override(state_name, c_sb)


func refresh_telemetry(snap: Dictionary) -> void:
	if snap.is_empty():
		return

	var eng: bool = bool(snap.get("engineer_mode", false))
	var lv_id: String = str(snap.get("launch_vehicle_id", "falcon_9_clps"))
	var orbit_id: String = str(snap.get("orbit_id", "orbit_llo_polar"))
	var zone_id: String = str(snap.get("landing_zone_id", "connecting_ridge_rim"))
	var lv: Dictionary = NasaDataLoader.get_launch_vehicle(lv_id)
	var orbit: Dictionary = NasaDataLoader.get_orbit(orbit_id)
	var zone: Dictionary = NasaDataLoader.get_landing_zone(zone_id)
	var failure_code: String = str(snap.get("failure_code", "NOMINAL"))

	_update_status_badge(failure_code, eng, snap)
	_update_mass_card(snap, lv, eng)
	_update_propulsion_card(snap, orbit, eng)
	_update_power_card(snap, zone, eng)
	_update_budget_card(snap, lv, eng)
	_update_comms_card(snap, orbit, zone, eng)
	_update_radiation_card(snap, eng)


func _update_status_badge(failure_code: String, eng: bool, snap: Dictionary) -> void:
	if failure_code == "NOMINAL":
		var label_str: String = "NOMINAL" if eng else "PASS  •  READY"
		_apply_status_pill(label_str, COLOR_OK)
		status_badge_label.tooltip_text = (
			"Mission Status: NOMINAL (PASS)\n"
			+ "Wet Mass m0: %.1f kg | Lunar T/W: %.2f | Net Power: %+.1f W\n\n"
			% [float(snap.get("m0_wet_kg", 0.0)), float(snap.get("lunar_tw_ratio", 0.0)), float(snap.get("net_power_w", 0.0))]
			+ "[NASA Reference]\nNASA SP-2016-6105 Rev2 Systems Engineering Constraints"
		)
	elif failure_code == "DSN_DOWNLINK_BOTTLENECK":
		_apply_status_pill("WARN  •  COMMS", COLOR_WARN)
	else:
		var short_code: String = _abbreviate_failure(failure_code)
		_apply_status_pill("FAIL  •  %s" % short_code, COLOR_CRIT)


func _abbreviate_failure(code: String) -> String:
	match code:
		"CRITICAL_THRUST_DEFICIT":
			return "T/W < 1"
		"PROPELLANT_DV_SHORTFALL":
			return "LOW Δv"
		"LAUNCH_VEHICLE_OVERWEIGHT":
			return "OVERMASS"
		"PSR_POWER_BLACKOUT":
			return "NO PWR"
		"SLOPE_TIPOVER_HAZARD":
			return "SLOPE"
		"RADIATION_SEU_RISK":
			return "RAD SEU"
		"NO_PROPULSION_MODULE":
			return "NO ENGINE"
	return code


func _apply_status_pill(text_val: String, pill_color: Color) -> void:
	status_badge_label.text = text_val
	status_badge_label.add_theme_color_override("font_color", COLOR_WHITE)
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = Color(pill_color.r * 0.35, pill_color.g * 0.35, pill_color.b * 0.35, 0.95)
	pill.border_color = pill_color
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(10)
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	pill.content_margin_top = 2
	pill.content_margin_bottom = 2
	status_badge_label.add_theme_stylebox_override("normal", pill)


func _update_mass_card(snap: Dictionary, lv: Dictionary, eng: bool) -> void:
	var m0_wet: float = float(snap.get("m0_wet_kg", 0.0))
	var dry_nom: float = float(snap.get("dry_mass_nominal_kg", 0.0))
	var mga_kg: float = float(snap.get("mga_mass_kg", 0.0))
	var mf_dry: float = float(snap.get("mf_dry_kg", 0.0))
	var prop_kg: float = float(snap.get("propellant_mass_kg", 0.0))
	var max_tli: float = float(lv.get("max_tli_payload_kg", 4000.0))
	var mga_pct: float = (mga_kg / dry_nom * 100.0) if dry_nom > 0.0 else 0.0

	var mass_ok: bool = (m0_wet <= max_tli) and (max_tli > 0.0)
	var border_col: Color = COLOR_OK if mass_ok else COLOR_CRIT
	var bg_col: Color = COLOR_CARD_BG if mass_ok else COLOR_CARD_ERR_BG

	if eng:
		mass_value_label.text = "%.0f / %.0f kg" % [m0_wet, max_tli]
		mass_sub_label.text = "Dry %.0f kg  •  +%.0f%% MGA" % [mf_dry, mga_pct]
	else:
		mass_value_label.text = "%.0f kg" % m0_wet
		mass_sub_label.text = "%s  •  %.0f kg" % ["SAFE MARGIN" if mass_ok else "OVERLOAD", max_tli]

	mass_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mass_sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mass_value_label.add_theme_color_override("font_color", COLOR_WHITE if mass_ok else COLOR_CRIT)
	_apply_card_style(card_mass, border_col, bg_col)

	var citation: String = str(lv.get("nasa_citation", NasaDataLoader.get_catalog_citation()))
	card_mass.tooltip_text = (
		"Launch Mass & Mass Growth Allowance (MGA)\n"
		+ "Nominal Dry Mass: %.2f kg\n" % dry_nom
		+ "MGA Reserve: +%.2f kg (+%.1f%%)\n" % [mga_kg, mga_pct]
		+ "Effective Dry Mass (mf): %.2f kg\n" % mf_dry
		+ "Propellant Load: %.1f kg\n" % prop_kg
		+ "Total Wet Mass (m0): %.2f kg / %.1f kg TLI Cap\n\n" % [m0_wet, max_tli]
		+ "[NASA Citation]\n%s\nNASA SP-2016-6105 Rev2 Sec 4.3 & Appendix G (MGA)" % citation
	)


func _update_propulsion_card(snap: Dictionary, orbit: Dictionary, eng: bool) -> void:
	var dv: float = float(snap.get("delta_v_ms", 0.0))
	var req_dv: float = float(snap.get("required_dv_ms", 1750.0))
	var tw: float = float(snap.get("lunar_tw_ratio", 0.0))
	var thrust_n: float = float(snap.get("total_thrust_n", 0.0))
	var isp_s: float = float(snap.get("effective_isp_s", 0.0))

	var tw_ok: bool = tw >= 1.0
	var dv_ok: bool = dv >= req_dv
	var all_ok: bool = tw_ok and dv_ok

	var border_col: Color = COLOR_OK if all_ok else (COLOR_CRIT if not tw_ok else COLOR_WARN)
	var bg_col: Color = COLOR_CARD_BG if all_ok else (COLOR_CARD_ERR_BG if not tw_ok else COLOR_CARD_WARN_BG)

	if not tw_ok:
		prop_value_label.text = "T/W %.2f (<1)" % tw
		prop_sub_label.text = ("LOCKOUT  •  %.0f m/s" % dv) if eng else "THRUST DEFICIT"
		prop_value_label.add_theme_color_override("font_color", COLOR_CRIT)
	elif not dv_ok:
		prop_value_label.text = "%.0f / %.0f m/s" % [dv, req_dv]
		prop_sub_label.text = ("DV LOW  •  T/W %.2f" % tw) if eng else ("Δv DEFICIT  •  %.2f" % tw)
		prop_value_label.add_theme_color_override("font_color", COLOR_WARN)
	else:
		if eng:
			prop_value_label.text = "%.0f m/s" % dv
			prop_sub_label.text = "T/W %.2f  •  %.1f kN" % [tw, thrust_n / 1000.0]
		else:
			prop_value_label.text = "%.0f m/s" % dv
			prop_sub_label.text = "SAFE LANDING T/W  •  %.2f" % tw
		prop_value_label.add_theme_color_override("font_color", COLOR_WHITE)

	prop_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	prop_sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_card_style(card_propulsion, border_col, bg_col)

	var orb_citation: String = str(orbit.get("nasa_citation", "NASA SP-2016-6105 Rev2 Sec 4.4"))
	card_propulsion.tooltip_text = (
		"Propulsion & Lunar Terminal Descent Lockout\n"
		+ "Tsiolkovsky Equation: dV = Isp * 9.80665 * ln(m0 / mf)\n"
		+ "Available Delta-V: %.2f m/s (Required: %.1f m/s)\n" % [dv, req_dv]
		+ "Lunar T/W Ratio: %.4f (Thrust %.2f N / Weight %.1f N)\n" % [tw, thrust_n, float(snap.get("lunar_weight_n", 0.0))]
		+ "Effective Isp: %.1f s\n" % isp_s
		+ "Rule: T/W >= 1.0 mandatory against g_moon = 1.625 m/s^2\n\n"
		+ "[NASA Citation]\n%s\nNASA SP-2016-6105 Rev2 Sec 4.4 & 6.1" % orb_citation
	)


func _update_power_card(snap: Dictionary, zone: Dictionary, eng: bool) -> void:
	var p_gen: float = float(snap.get("power_generated_w", 0.0))
	var p_use: float = float(snap.get("power_consumed_w", 0.0))
	var net_p: float = float(snap.get("net_power_w", 0.0))
	var batt_wh: float = float(snap.get("battery_wh", 0.0))
	var thermal_w: float = float(snap.get("thermal_output_w", 0.0))
	var night_ok: bool = bool(snap.get("can_survive_lunar_night", false))

	var power_ok: bool = net_p >= 0.0
	var border_col: Color = COLOR_OK if (power_ok and night_ok) else (COLOR_CRIT if not power_ok else COLOR_WARN)
	var bg_col: Color = COLOR_CARD_BG if power_ok else COLOR_CARD_ERR_BG

	if eng:
		power_value_label.text = "%+.0f W" % net_p
		power_sub_label.text = "%.0f/%.0f W  •  %.1f kWh" % [p_gen, p_use, batt_wh / 1000.0]
	else:
		var p_state: String = "POWER POSITIVE" if (power_ok and night_ok) else ("SOLAR BLACKOUT" if not power_ok else "NIGHT DRAIN")
		power_value_label.text = "%+.0f W" % net_p
		power_sub_label.text = "%s  •  %.0f kWh" % [p_state, batt_wh / 1000.0]

	power_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	power_sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	power_value_label.add_theme_color_override("font_color", COLOR_WHITE if power_ok else COLOR_CRIT)
	_apply_card_style(card_power, border_col, bg_col)

	card_power.tooltip_text = (
		"Electrical Power & Thermal Balance (SI)\n"
		+ "Equation: P = P0 * cos(theta_incidence) * (1 - shadow_occlusion)\n"
		+ "Generated Power: %.2f W | Duty Load: %.2f W\n" % [p_gen, p_use]
		+ "Net Margin: %+.2f W (Peak Load: %.1f W)\n" % [net_p, float(snap.get("power_peak_consumed_w", 0.0))]
		+ "Energy Storage: %.0f Wh | RTG Thermal: %.0f W\n" % [batt_wh, thermal_w]
		+ "Zone: %s (Solar %.0f%%)\n\n" % [str(zone.get("label", "Shackleton")), float(zone.get("solar_illumination_percent", 0.0))]
		+ "[NASA Citation]\nLRO / CLPS South Pole Illumination Constraint & NASA SP-2016-6105 Rev2"
	)


func _update_budget_card(snap: Dictionary, lv: Dictionary, eng: bool) -> void:
	var total_cost: float = float(snap.get("total_cost_musd", 0.0))
	var cap_musd: float = float(snap.get("budget_cap_musd", 350.0))
	var lv_cost: float = float(snap.get("launch_vehicle_cost_musd", 0.0))
	var sub_cost: float = float(snap.get("subsystems_cost_musd", 0.0))
	var is_sandbox: bool = bool(snap.get("sandbox_mode", false))

	var budget_ok: bool = (total_cost <= cap_musd) or is_sandbox
	var border_col: Color = COLOR_OK if budget_ok else COLOR_CRIT
	var bg_col: Color = COLOR_CARD_BG if budget_ok else COLOR_CARD_ERR_BG

	if eng:
		budget_value_label.text = "$%.0fM / $%.0fM" % [total_cost, cap_musd]
		budget_sub_label.text = "LV $%.0fM  •  Sub $%.0fM" % [lv_cost, sub_cost]
	else:
		var badge: String = "SANDBOX CAP" if is_sandbox else ("WITHIN CAP" if budget_ok else "OVER BUDGET")
		budget_value_label.text = "$%.0fM" % total_cost
		budget_sub_label.text = "%s  •  $%.0fM" % [badge, cap_musd]

	budget_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	budget_sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	budget_value_label.add_theme_color_override("font_color", COLOR_WHITE if budget_ok else COLOR_CRIT)
	_apply_card_style(card_budget, border_col, bg_col)

	card_budget.tooltip_text = (
		"Lifecycle Mission Cost Cap (M$ USD)\n"
		+ "Launch Vehicle (%s): $%.2f M\n" % [str(lv.get("name", "")), lv_cost]
		+ "Spacecraft Subsystems: $%.2f M\n" % sub_cost
		+ "Total Mission Cost: $%.2f M / Cap: $%.1f M\n\n" % [total_cost, cap_musd]
		+ "[NASA Citation]\n%s" % str(lv.get("nasa_citation", NasaDataLoader.get_catalog_citation()))
	)


func _update_comms_card(snap: Dictionary, orbit: Dictionary, zone: Dictionary, eng: bool) -> void:
	var data_gen: float = float(snap.get("data_generated_gb_day", 0.0))
	var dl_cap: float = float(snap.get("downlink_capacity_gb_day", 0.0))
	var dl_mbps: float = float(snap.get("downlink_mbps", 0.0))
	var dte_pct: float = float(snap.get("dte_visibility_pct", 0.0))
	var backlog: float = float(snap.get("data_backlog_gb_day", 0.0))
	var sci_eff: float = float(snap.get("science_points_effective", 0.0))

	var comms_ok: bool = (backlog <= 0.0) and (dl_mbps > 0.0)
	var border_col: Color = COLOR_OK if comms_ok else COLOR_WARN
	var bg_col: Color = COLOR_CARD_BG if comms_ok else COLOR_CARD_WARN_BG

	if eng:
		comms_value_label.text = "%.0f / %.0f GB/d" % [data_gen, dl_cap]
		comms_sub_label.text = "%.0f Mbps  •  DTE %.0f%%" % [dl_mbps, dte_pct]
	else:
		comms_value_label.text = "%.1f Mbps" % dl_mbps
		comms_sub_label.text = "%s  •  %.0f pts" % ["LINK NOMINAL" if comms_ok else "DATA BOTTLENECK", sci_eff]

	comms_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	comms_sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	comms_value_label.add_theme_color_override("font_color", COLOR_WHITE if comms_ok else COLOR_WARN)
	_apply_card_style(card_comms, border_col, bg_col)

	card_comms.tooltip_text = (
		"Deep Space Network (DSN) Direct-to-Earth Link Budget\n"
		+ "Science Payload Generation: %.2f GB/day\n" % data_gen
		+ "Downlink Bandwidth: %.2f Mbps (DTE Vis: %.1f%%)\n" % [dl_mbps, dte_pct]
		+ "Effective Downlink Capacity: %.2f GB/day\n" % dl_cap
		+ "Daily Backlog: %.2f GB/day | Effective Science: %.1f pts\n" % [backlog, sci_eff]
		+ "Orbit: %s | Site: %s\n\n" % [str(orbit.get("name", "")), str(zone.get("label", ""))]
		+ "[NASA Citation]\nNASA Deep Space Network (DSN) Link Budget & %s" % str(orbit.get("nasa_citation", ""))
	)


func _update_radiation_card(snap: Dictionary, eng: bool) -> void:
	var life_days: float = float(snap.get("mission_lifetime_days", 0.0))
	var theo_days: float = float(snap.get("theoretical_lifetime_days", 0.0))
	var dose_msv: float = float(snap.get("total_mission_dose_msv", 0.0))
	var shield_g: float = float(snap.get("shielding_g_cm2", 2.0))
	var tol_krad: float = float(snap.get("radiation_tolerance_krad", 15.0))
	var dose_limit: float = NasaDataLoader.get_mission_dose_limit_msv()

	var rad_ok: bool = (life_days >= 14.0) and (dose_msv <= dose_limit)
	var border_col: Color = COLOR_OK if rad_ok else (COLOR_CRIT if life_days <= 0.0 else COLOR_WARN)
	var bg_col: Color = COLOR_CARD_BG if rad_ok else (COLOR_CARD_ERR_BG if life_days <= 0.0 else COLOR_CARD_WARN_BG)

	if eng:
		rad_value_label.text = "%.0f d  •  %.0f mSv" % [life_days, dose_msv]
		rad_sub_label.text = "%.1f g/cm²  •  %.0f krad" % [shield_g, tol_krad]
	else:
		var badge: String = "RAD SAFE" if rad_ok else ("RAD HAZARD" if life_days <= 0.0 else "SHORT LIFE")
		rad_value_label.text = "%.0f d" % life_days
		rad_sub_label.text = "%s  •  %.0f mSv" % [badge, dose_msv]

	rad_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rad_sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rad_value_label.add_theme_color_override("font_color", COLOR_WHITE if rad_ok else (COLOR_CRIT if life_days <= 0.0 else COLOR_WARN))
	_apply_card_style(card_radiation, border_col, bg_col)

	card_radiation.tooltip_text = (
		"OSDR RadLab Dose & Operational Surface Lifetime\n"
		+ "Operational Surface Lifetime: %.1f days (Rad Cap: %.1f d)\n" % [life_days, theo_days]
		+ "Cumulative Mission Dose: %.2f mSv (Limit: %.1f mSv)\n" % [dose_msv, dose_limit]
		+ "Daily GCR Rate: %.3f mSv/day | SPE Dose: %.2f mSv\n" % [float(snap.get("daily_gcr_msv", 0.0)), float(snap.get("spe_dose_msv", 0.0))]
		+ "Areal Shielding: %.1f g/cm^2 | Avionics Tol: %.0f krad\n\n" % [shield_g, tol_krad]
		+ "[NASA Citation]\n%s" % NasaDataLoader.get_radiation_citation()
	)


func _apply_card_style(card: PanelContainer, border_col: Color, bg_col: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_col
	style.border_color = border_col
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)
