class_name MainHUD
extends PanelContainer

## Persistent NASA Mission Control Top HUD Bar.
## Hosts 1-Click Judge Presets, Student/Engineer Dual-Scale Toggle,
## 4-Phase Navigation, and 6 Mandatory SI Resource Telemetry Cards with NASA citations.

signal phase_requested(phase_index: int)

const COLOR_BG_BAR: Color = Color(0.055, 0.075, 0.115, 0.96)
const COLOR_CARD_BG: Color = Color(0.085, 0.115, 0.175, 0.95)
const COLOR_CARD_ERR_BG: Color = Color(0.22, 0.06, 0.075, 0.96)
const COLOR_CARD_WARN_BG: Color = Color(0.20, 0.145, 0.055, 0.96)

const COLOR_OK: Color = Color(0.24, 0.88, 0.56, 1.0)
const COLOR_WARN: Color = Color(0.98, 0.74, 0.22, 1.0)
const COLOR_CRIT: Color = Color(1.0, 0.30, 0.34, 1.0)
const COLOR_ACCENT: Color = Color(0.32, 0.72, 1.0, 1.0)
const COLOR_MUTED: Color = Color(0.68, 0.76, 0.86, 1.0)

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
	_connect_ui_signals()
	_connect_state_signals()

	set_active_phase(0)
	_sync_controls_from_state()
	refresh_telemetry(MissionState.get_telemetry_snapshot())


func _apply_bar_style() -> void:
	var bar_style: StyleBoxFlat = StyleBoxFlat.new()
	bar_style.bg_color = COLOR_BG_BAR
	bar_style.border_color = Color(0.20, 0.34, 0.54, 0.9)
	bar_style.border_width_bottom = 2
	bar_style.content_margin_left = 10
	bar_style.content_margin_right = 10
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", bar_style)


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
		btn.button_pressed = is_active
		if is_active:
			btn.add_theme_color_override("font_color", COLOR_ACCENT)
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
	status_badge_label.text = alert_code
	status_badge_label.add_theme_color_override("font_color", COLOR_CRIT)
	status_badge_label.tooltip_text = "%s\n\n[Reference]: %s" % [message, citation]


func _sync_controls_from_state() -> void:
	var eng: bool = MissionState.engineer_mode
	if btn_mode_toggle.button_pressed != eng:
		btn_mode_toggle.set_pressed_no_signal(eng)
	btn_mode_toggle.text = "ENGINEER MODE (SI)" if eng else "STUDENT MODE"
	btn_mode_toggle.tooltip_text = (
		"Dual-Scale Interface Mode.\n"
		+ "Student Mode: Guided engineering status badges and plain-language checks.\n"
		+ "Engineer Mode: Full SI numerical precision, MGA margins, and NASA citations.\n\n"
		+ "[Reference]: %s" % NasaDataLoader.get_catalog_citation()
	)

	for idx: int in range(_preset_buttons.size()):
		var p_btn: Button = _preset_buttons[idx]
		var is_selected: bool = (idx + 1 == MissionState.current_preset_index)
		p_btn.button_pressed = is_selected


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
		status_badge_label.text = "STATUS: NOMINAL" if eng else "MISSION READY"
		status_badge_label.add_theme_color_override("font_color", COLOR_OK)
		status_badge_label.tooltip_text = (
			"All primary NASA SP-2016-6105 physical trade constraints satisfied.\n"
			+ "Wet Mass m0: %.1f kg | Lunar T/W: %.2f | Net Power: %+.1f W"
			% [float(snap.get("m0_wet_kg", 0.0)), float(snap.get("lunar_tw_ratio", 0.0)), float(snap.get("net_power_w", 0.0))]
		)
	else:
		status_badge_label.text = failure_code
		status_badge_label.add_theme_color_override("font_color", COLOR_CRIT)


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
		mass_value_label.text = "%.1f / %.0f kg" % [m0_wet, max_tli]
		mass_sub_label.text = "Dry %.1f (+%.1f%% MGA) | Prop %.0f kg" % [mf_dry, mga_pct, prop_kg]
	else:
		var badge: String = "FITS LV" if mass_ok else "OVERWEIGHT"
		mass_value_label.text = "%.0f kg [%s]" % [m0_wet, badge]
		mass_sub_label.text = "Cap: %.0f kg | +%.0f%% MGA" % [max_tli, mga_pct]

	mass_value_label.add_theme_color_override("font_color", COLOR_OK if mass_ok else COLOR_CRIT)
	_apply_card_style(card_mass, border_col, bg_col)

	var citation: String = str(lv.get("nasa_citation", NasaDataLoader.get_catalog_citation()))
	card_mass.tooltip_text = (
		"Launch Mass & Mass Growth Allowance (MGA)\n"
		+ "Nominal Dry Mass: %.2f kg\n" % dry_nom
		+ "MGA Reserve: +%.2f kg (+%.1f%%)\n" % [mga_kg, mga_pct]
		+ "Effective Dry Mass (mf): %.2f kg\n" % mf_dry
		+ "Propellant Load: %.1f kg\n" % prop_kg
		+ "Total Wet Mass (m0): %.2f kg / %.1f kg TLI Cap\n\n" % [m0_wet, max_tli]
		+ "[NASA Citation]:\n%s\n%s" % [citation, "NASA SP-2016-6105 Rev2 Sec 4.3 & Appendix G (MGA)"]
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
		prop_value_label.text = "T/W %.3f (<1.0!) | %.0f m/s" % [tw, dv]
		prop_sub_label.text = "LOCKOUT: Thrust %.1f N < Lunar Wt" % thrust_n
		prop_value_label.add_theme_color_override("font_color", COLOR_CRIT)
	elif not dv_ok:
		prop_value_label.text = "%.0f / %.0f m/s | T/W %.2f" % [dv, req_dv, tw]
		prop_sub_label.text = "Δv SHORTFALL (%.0f N | %.0f s)" % [thrust_n, isp_s]
		prop_value_label.add_theme_color_override("font_color", COLOR_WARN)
	else:
		if eng:
			prop_value_label.text = "%.0f / %.0f m/s | T/W %.2f" % [dv, req_dv, tw]
			prop_sub_label.text = "F %.0f N | Isp %.0f s (+%.0f m/s)" % [thrust_n, isp_s, dv - req_dv]
		else:
			prop_value_label.text = "%.0f m/s | T/W %.2f [OK]" % [dv, tw]
			prop_sub_label.text = "Req: %.0f m/s | Safe Descent" % req_dv
		prop_value_label.add_theme_color_override("font_color", COLOR_OK)

	_apply_card_style(card_propulsion, border_col, bg_col)

	var orb_citation: String = str(orbit.get("nasa_citation", "NASA SP-2016-6105 Rev2 Sec 4.4"))
	card_propulsion.tooltip_text = (
		"Propulsion & Lunar Terminal Descent Lockout\n"
		+ "Tsiolkovsky Equation: dV = Isp * 9.80665 * ln(m0 / mf)\n"
		+ "Available Delta-V: %.2f m/s (Required: %.1f m/s)\n" % [dv, req_dv]
		+ "Lunar T/W Ratio: %.4f (Thrust %.2f N / Weight %.1f N)\n" % [tw, thrust_n, float(snap.get("lunar_weight_n", 0.0))]
		+ "Effective Isp: %.1f s\n" % isp_s
		+ "Rule: T/W >= 1.0 mandatory against g_moon = 1.625 m/s^2\n\n"
		+ "[NASA Citation]:\n%s\nNASA SP-2016-6105 Rev2 Sec 4.4 & 6.1" % orb_citation
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
		power_value_label.text = "%+.1f W (%.0f/%.0f)" % [net_p, p_gen, p_use]
		power_sub_label.text = "Batt %.0f Wh | Heat %.0f W" % [batt_wh, thermal_w]
	else:
		var status_str: String = "SURPLUS" if power_ok else "BLACKOUT"
		power_value_label.text = "%+.0f W [%s]" % [net_p, status_str]
		power_sub_label.text = "Batt %.0f Wh | %s" % [batt_wh, "PSR OK" if night_ok else "NO NIGHT PWR"]

	power_value_label.add_theme_color_override("font_color", COLOR_OK if power_ok else COLOR_CRIT)
	_apply_card_style(card_power, border_col, bg_col)

	card_power.tooltip_text = (
		"Electrical Power & Thermal Balance (SI)\n"
		+ "Equation: P = P0 * cos(theta_incidence) * (1 - shadow_occlusion)\n"
		+ "Generated Power: %.2f W | Duty Load: %.2f W\n" % [p_gen, p_use]
		+ "Net Margin: %+.2f W (Peak Load: %.1f W)\n" % [net_p, float(snap.get("power_peak_consumed_w", 0.0))]
		+ "Energy Storage: %.0f Wh | RTG Thermal: %.0f W\n" % [batt_wh, thermal_w]
		+ "Zone: %s (Solar %.0f%%)\n\n" % [str(zone.get("label", "Shackleton")), float(zone.get("solar_illumination_percent", 0.0))]
		+ "[NASA Citation]:\nLRO / CLPS South Pole Illumination Constraint & NASA SP-2016-6105 Rev2"
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
		budget_value_label.text = "$%.1fM / $%.0fM" % [total_cost, cap_musd]
		budget_sub_label.text = "LV $%.1fM | Sub $%.1fM" % [lv_cost, sub_cost]
	else:
		var badge: String = "SANDBOX" if is_sandbox else ("ON BUDGET" if budget_ok else "OVER CAP")
		budget_value_label.text = "$%.1fM [%s]" % [total_cost, badge]
		budget_sub_label.text = "Cap: $%.0fM | %s" % [cap_musd, str(lv.get("id", ""))]

	budget_value_label.add_theme_color_override("font_color", COLOR_OK if budget_ok else COLOR_CRIT)
	_apply_card_style(card_budget, border_col, bg_col)

	card_budget.tooltip_text = (
		"Lifecycle Mission Cost Cap (M$ USD)\n"
		+ "Launch Vehicle (%s): $%.2f M\n" % [str(lv.get("name", "")), lv_cost]
		+ "Spacecraft Subsystems: $%.2f M\n" % sub_cost
		+ "Total Mission Cost: $%.2f M / Cap: $%.1f M\n\n" % [total_cost, cap_musd]
		+ "[NASA Citation]:\n%s" % str(lv.get("nasa_citation", NasaDataLoader.get_catalog_citation()))
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
		comms_value_label.text = "%.1f / %.1f GB/d" % [data_gen, dl_cap]
		comms_sub_label.text = "%.1f Mbps | DTE %.0f%% | Sci %.0f" % [dl_mbps, dte_pct, sci_eff]
	else:
		var badge: String = "LINK OK" if comms_ok else "BOTTLENECK"
		comms_value_label.text = "%.1f Mbps [%s]" % [dl_mbps, badge]
		comms_sub_label.text = "DTE %.0f%% | Sci %.0f pts" % [dte_pct, sci_eff]

	comms_value_label.add_theme_color_override("font_color", COLOR_OK if comms_ok else COLOR_WARN)
	_apply_card_style(card_comms, border_col, bg_col)

	card_comms.tooltip_text = (
		"Deep Space Network (DSN) Direct-to-Earth Link Budget\n"
		+ "Science Payload Generation: %.2f GB/day\n" % data_gen
		+ "Downlink Bandwidth: %.2f Mbps (DTE Vis: %.1f%%)\n" % [dl_mbps, dte_pct]
		+ "Effective Downlink Capacity: %.2f GB/day\n" % dl_cap
		+ "Daily Backlog: %.2f GB/day | Effective Science: %.1f pts\n" % [backlog, sci_eff]
		+ "Orbit: %s | Site: %s\n\n" % [str(orbit.get("name", "")), str(zone.get("label", ""))]
		+ "[NASA Citation]:\nNASA Deep Space Network (DSN) Link Budget & %s" % str(orbit.get("nasa_citation", ""))
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
		rad_value_label.text = "%.1f d | %.1f mSv" % [life_days, dose_msv]
		rad_sub_label.text = "Shield %.1f g/cm² | %.0f krad" % [shield_g, tol_krad]
	else:
		var badge: String = "SURVIVAL OK" if rad_ok else ("CRASH/DEAD" if life_days <= 0.0 else "SHORT LIFE")
		rad_value_label.text = "%.0f d [%s]" % [life_days, badge]
		rad_sub_label.text = "Dose %.1f mSv | %.0f krad" % [dose_msv, tol_krad]

	rad_value_label.add_theme_color_override("font_color", COLOR_OK if rad_ok else (COLOR_CRIT if life_days <= 0.0 else COLOR_WARN))
	_apply_card_style(card_radiation, border_col, bg_col)

	card_radiation.tooltip_text = (
		"OSDR RadLab Dose & Operational Surface Lifetime\n"
		+ "Operational Surface Lifetime: %.1f days (Rad Cap: %.1f d)\n" % [life_days, theo_days]
		+ "Cumulative Mission Dose: %.2f mSv (Limit: %.1f mSv)\n" % [dose_msv, dose_limit]
		+ "Daily GCR Rate: %.3f mSv/day | SPE Dose: %.2f mSv\n" % [float(snap.get("daily_gcr_msv", 0.0)), float(snap.get("spe_dose_msv", 0.0))]
		+ "Areal Shielding: %.1f g/cm^2 | Avionics Tol: %.0f krad\n\n" % [shield_g, tol_krad]
		+ "[NASA Citation]:\n%s" % NasaDataLoader.get_radiation_citation()
	)


func _apply_card_style(card: PanelContainer, border_col: Color, bg_col: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_col
	style.border_color = border_col
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(4)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)
