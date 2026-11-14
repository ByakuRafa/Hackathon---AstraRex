class_name MainShell
extends Control

## Root Application Shell for AstraRex Space Mission Engineering Simulator.
## Enforces "One Frame, Four Phases" (84px Top HUD + 600px Phase Canvas + 36px Bottom Bar = 720px).

const COL_EMERALD: Color = Color(0.063, 0.725, 0.506, 1.0)
const COL_AMBER: Color = Color(0.961, 0.620, 0.043, 1.0)
const COL_RED: Color = Color(0.937, 0.267, 0.267, 1.0)
const COL_CYAN: Color = Color(0.0, 0.941, 1.0, 1.0)

@onready var main_hud: MainHUD = %MainHUD
@onready var phase_container: Control = %PhaseContainer
@onready var phase1_planning: Phase1Planning = %Phase1_Planning
@onready var phase2_vab: Phase2VAB = %Phase2_VAB
@onready var phase3_lunar_sim: Phase3LunarSim = %Phase3_LunarSim
@onready var phase4_debrief: Phase4Debrief = %Phase4_Debrief

@onready var bottom_action_bar: PanelContainer = %BottomActionBar
@onready var system_status_badge: Label = %SystemStatusBadge
@onready var bottom_design_code_edit: LineEdit = %BottomDesignCodeEdit
@onready var btn_copy_design_code: Button = %BtnCopyDesignCode
@onready var btn_load_design_code: Button = %BtnLoadDesignCode
@onready var btn_export_csv: Button = %BtnExportCSV
@onready var btn_export_json: Button = %BtnExportJSON
@onready var primary_next_step_btn: Button = %PrimaryNextStepBtn

var _current_phase_index: int = 0
var _next_step_glow_active: bool = false
var _glow_phase: float = 0.0
var _cta_style_normal: StyleBoxFlat
var _cta_style_hover: StyleBoxFlat


func _ready() -> void:
	_setup_bottom_bar_styles()
	main_hud.phase_requested.connect(_on_phase_requested)
	phase1_planning.proceed_to_vab_requested.connect(_switch_to_phase.bind(1))
	phase2_vab.proceed_to_descent_requested.connect(_switch_to_phase.bind(2))
	phase3_lunar_sim.return_to_vab_requested.connect(_switch_to_phase.bind(1))
	phase3_lunar_sim.proceed_to_debrief_requested.connect(_switch_to_phase.bind(3))
	phase3_lunar_sim.descent_completed.connect(_on_descent_completed)
	phase4_debrief.iterate_in_vab_requested.connect(_switch_to_phase.bind(1))

	MissionState.state_updated.connect(_on_mission_state_updated)
	MissionState.preset_loaded.connect(_on_preset_loaded)
	ParetoSolver.report_exported.connect(_on_report_exported)

	btn_copy_design_code.pressed.connect(_on_copy_design_code_pressed)
	btn_load_design_code.pressed.connect(_on_load_design_code_pressed)
	btn_export_csv.pressed.connect(_on_export_csv_pressed)
	btn_export_json.pressed.connect(_on_export_json_pressed)
	primary_next_step_btn.pressed.connect(_on_primary_next_step_pressed)

	_switch_to_phase(0)
	_on_mission_state_updated(MissionState.get_telemetry_snapshot())


func _process(delta: float) -> void:
	if not _next_step_glow_active or _cta_style_normal == null:
		return
	_glow_phase += delta * 4.0
	var pulse: float = 0.55 + 0.45 * sin(_glow_phase)
	_cta_style_normal.border_color = Color(0.0, 0.941, 1.0, pulse)
	_cta_style_normal.bg_color = Color(0.03, 0.24 + 0.08 * pulse, 0.34 + 0.10 * pulse, 0.96)


func _setup_bottom_bar_styles() -> void:
	var bar_bg: StyleBoxFlat = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.055, 0.075, 0.114, 0.98)
	bar_bg.border_color = Color(0.16, 0.24, 0.36, 1.0)
	bar_bg.border_width_top = 1
	bar_bg.content_margin_left = 10.0
	bar_bg.content_margin_right = 10.0
	bar_bg.content_margin_top = 3.0
	bar_bg.content_margin_bottom = 3.0
	bottom_action_bar.add_theme_stylebox_override("panel", bar_bg)

	_cta_style_normal = StyleBoxFlat.new()
	_cta_style_normal.bg_color = Color(0.03, 0.25, 0.35, 0.96)
	_cta_style_normal.border_color = Color(0.22, 0.78, 0.92, 0.85)
	_cta_style_normal.set_border_width_all(2)
	_cta_style_normal.set_corner_radius_all(5)
	_cta_style_normal.content_margin_left = 12.0
	_cta_style_normal.content_margin_right = 12.0
	_cta_style_normal.content_margin_top = 2.0
	_cta_style_normal.content_margin_bottom = 2.0

	_cta_style_hover = _cta_style_normal.duplicate() as StyleBoxFlat
	_cta_style_hover.bg_color = Color(0.05, 0.35, 0.48, 1.0)
	_cta_style_hover.border_color = Color(0.55, 0.98, 1.0, 1.0)

	for state_name: String in ["normal", "focus"]:
		primary_next_step_btn.add_theme_stylebox_override(state_name, _cta_style_normal)
	for state_name: String in ["hover", "pressed"]:
		primary_next_step_btn.add_theme_stylebox_override(state_name, _cta_style_hover)
	primary_next_step_btn.add_theme_color_override("font_color", Color(0.92, 0.99, 1.0, 1.0))

	var util_style: StyleBoxFlat = StyleBoxFlat.new()
	util_style.bg_color = Color(0.10, 0.14, 0.21, 0.95)
	util_style.border_color = Color(0.22, 0.30, 0.42, 1.0)
	util_style.set_border_width_all(1)
	util_style.set_corner_radius_all(4)
	util_style.content_margin_left = 8.0
	util_style.content_margin_right = 8.0
	util_style.content_margin_top = 2.0
	util_style.content_margin_bottom = 2.0
	var util_hover: StyleBoxFlat = util_style.duplicate() as StyleBoxFlat
	util_hover.border_color = COL_CYAN
	var util_dis: StyleBoxFlat = util_style.duplicate() as StyleBoxFlat
	util_dis.bg_color = Color(0.055, 0.078, 0.125, 0.7)
	for btn: Button in [btn_copy_design_code, btn_load_design_code, btn_export_csv, btn_export_json]:
		btn.add_theme_stylebox_override("normal", util_style)
		btn.add_theme_stylebox_override("focus", util_style)
		btn.add_theme_stylebox_override("hover", util_hover)
		btn.add_theme_stylebox_override("pressed", util_hover)
		btn.add_theme_stylebox_override("disabled", util_dis)

	var line_sb: StyleBoxFlat = StyleBoxFlat.new()
	line_sb.bg_color = Color(0.043, 0.067, 0.125, 0.98)
	line_sb.border_color = Color(0.2, 0.31, 0.482, 0.85)
	line_sb.set_border_width_all(1)
	line_sb.set_corner_radius_all(4)
	line_sb.content_margin_left = 8.0
	line_sb.content_margin_right = 8.0
	line_sb.content_margin_top = 2.0
	line_sb.content_margin_bottom = 2.0
	bottom_design_code_edit.add_theme_stylebox_override("normal", line_sb)
	bottom_design_code_edit.add_theme_stylebox_override("focus", line_sb)


func _on_phase_requested(phase_index: int) -> void:
	_set_next_step_glow(false)
	_switch_to_phase(phase_index)


func _on_preset_loaded(_preset_index: int, _preset_name: String) -> void:
	_set_next_step_glow(true)


func _on_descent_completed(_survived: bool) -> void:
	_set_next_step_glow(true)


func _set_next_step_glow(enabled: bool) -> void:
	_next_step_glow_active = enabled
	_glow_phase = 0.0
	if not enabled and _cta_style_normal != null:
		_cta_style_normal.border_color = Color(0.22, 0.78, 0.92, 0.85)
		_cta_style_normal.bg_color = Color(0.03, 0.24, 0.34, 0.96)


func _switch_to_phase(phase_index: int) -> void:
	_current_phase_index = clampi(phase_index, 0, 3)
	main_hud.set_active_phase(_current_phase_index)

	phase1_planning.visible = (_current_phase_index == 0)
	phase2_vab.set_vab_active(_current_phase_index == 1)
	phase3_lunar_sim.set_lunar_sim_active(_current_phase_index == 2)
	phase4_debrief.set_debrief_active(_current_phase_index == 3)
	_update_next_step_button()


func _update_next_step_button() -> void:
	match _current_phase_index:
		0:
			primary_next_step_btn.text = "2. Assemble in VAB ->"
			primary_next_step_btn.tooltip_text = "Proceed to Phase 2: 3D Vehicle Assembly Building."
		1:
			primary_next_step_btn.text = "3. Launch Lunar Descent ->"
			primary_next_step_btn.tooltip_text = "Proceed to Phase 3: South Pole TLI & Terminal Descent."
		2:
			primary_next_step_btn.text = "4. Open Pareto Debrief ->"
			primary_next_step_btn.tooltip_text = "Proceed to Phase 4: Pareto Optimization & Engineering Debrief."
		_:
			primary_next_step_btn.text = "<- Iterate in VAB"
			primary_next_step_btn.tooltip_text = "Return to Phase 2: Refine subsystem architecture in 3D VAB."


func _on_primary_next_step_pressed() -> void:
	_set_next_step_glow(false)
	match _current_phase_index:
		0:
			_switch_to_phase(1)
		1:
			_switch_to_phase(2)
		2:
			_switch_to_phase(3)
		_:
			_switch_to_phase(1)


func _on_mission_state_updated(snap: Dictionary) -> void:
	var engineer_mode: bool = bool(snap.get("engineer_mode", false))
	if is_instance_valid(phase4_debrief) and phase4_debrief.has_method("sync_engineer_mode"):
		phase4_debrief.call("sync_engineer_mode", engineer_mode)
	btn_export_csv.disabled = not engineer_mode
	btn_export_json.disabled = not engineer_mode
	btn_export_csv.modulate = Color(1.0, 1.0, 1.0, 1.0) if engineer_mode else Color(0.55, 0.62, 0.72, 0.45)
	btn_export_json.modulate = Color(1.0, 1.0, 1.0, 1.0) if engineer_mode else Color(0.55, 0.62, 0.72, 0.45)
	btn_export_csv.tooltip_text = "Export telemetry & Pareto frontier CSV." if engineer_mode else "Switch to ENGINEER mode to unlock CSV telemetry export."
	btn_export_json.tooltip_text = "Export mission design & engineering diagnostics JSON." if engineer_mode else "Switch to ENGINEER mode to unlock JSON telemetry export."

	var compat: Dictionary = MissionState.validate_launch_compatibility()
	var land: Dictionary = MissionState.can_safely_land_on_moon()
	var tw: float = float(snap.get("lunar_tw_ratio", 0.0))
	var dv: float = float(snap.get("delta_v_ms", 0.0))
	var m0: float = float(snap.get("m0_wet_kg", 0.0))
	var net_w: float = float(snap.get("net_power_w", 0.0))
	var night_ok: bool = bool(snap.get("can_survive_lunar_night", true))
	var trn_ok: bool = bool(snap.get("can_survive_slope_hazard", true))

	if not bool(land.get("can_land", false)):
		var reason: String = str(land.get("reason", "LANDING_LOCKOUT"))
		if engineer_mode:
			system_status_badge.text = "LOCKOUT: %s | T/W %.2f | dV %.0f m/s" % [reason, tw, dv]
		else:
			var student_reason: String = "THRUST DEFICIT" if reason == "CRITICAL_THRUST_DEFICIT" else ("DV SHORTFALL" if reason == "PROPELLANT_DV_SHORTFALL" else "NO DESCENT ENGINE")
			system_status_badge.text = "LOCKOUT • %s" % student_reason
		system_status_badge.add_theme_color_override("font_color", COL_RED)
		system_status_badge.tooltip_text = "%s (%s)" % [str(land.get("message", "")), str(land.get("citation", "NASA SP-2016-6105"))]
	elif not bool(compat.get("compatible", false)):
		if engineer_mode:
			system_status_badge.text = "INCOMPATIBLE • m0 %.0f / %.0f kg | $%.0fM" % [m0, float(compat.get("max_tli_mass_kg", 0.0)), float(snap.get("total_cost_musd", 0.0))]
		else:
			system_status_badge.text = "WARNING • TLI MASS OR BUDGET EXCEEDED"
		system_status_badge.add_theme_color_override("font_color", COL_RED)
		var reasons: Array = compat.get("reasons", []) as Array
		system_status_badge.tooltip_text = str(reasons[0]) if not reasons.is_empty() else "Launcher / Budget constraint violated."
	elif net_w < 0.0 or not night_ok or not trn_ok:
		var warn_tag: String = "NO TRN (>15 deg)" if not trn_ok else ("LUNAR NIGHT RISK" if not night_ok else "POWER DEFICIT")
		if engineer_mode:
			system_status_badge.text = "CAUTION • %s | Pnet %.0f W" % [warn_tag, net_w]
		else:
			system_status_badge.text = "CAUTION • %s" % warn_tag
		system_status_badge.add_theme_color_override("font_color", COL_AMBER)
		system_status_badge.tooltip_text = "Mission compatible with launcher, but surface hazards or power shortfalls remain."
	else:
		if engineer_mode:
			system_status_badge.text = "NOMINAL • COMPATIBLE | T/W %.2f | dV %.0f m/s | %.0f kg" % [tw, dv, m0]
		else:
			system_status_badge.text = "READY • SAFE LANDING T/W & LAUNCH MARGIN"
		system_status_badge.add_theme_color_override("font_color", COL_EMERALD)
		system_status_badge.tooltip_text = "All launch, orbital Delta-V, lunar T/W, and night survival checks nominal (NASA SP-2016-6105 Rev2)."


func _on_copy_design_code_pressed() -> void:
	var code: String = MissionState.export_design_code()
	bottom_design_code_edit.text = code
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(code)
	system_status_badge.text = "DESIGN CODE COPIED (%d chars)" % code.length()
	system_status_badge.add_theme_color_override("font_color", COL_CYAN)


func _on_load_design_code_pressed() -> void:
	var code: String = bottom_design_code_edit.text.strip_edges()
	if code.is_empty():
		system_status_badge.text = "PASTE A DESIGN CODE FIRST"
		system_status_badge.add_theme_color_override("font_color", COL_AMBER)
		return
	var ok: bool = MissionState.import_design_code(code)
	if not ok:
		system_status_badge.text = "INVALID DESIGN CODE"
		system_status_badge.add_theme_color_override("font_color", COL_RED)
	else:
		_set_next_step_glow(true)


func _on_export_csv_pressed() -> void:
	if not MissionState.engineer_mode:
		return
	ParetoSolver.export_telemetry_report("csv")


func _on_export_json_pressed() -> void:
	if not MissionState.engineer_mode:
		return
	ParetoSolver.export_telemetry_report("json")


func _on_report_exported(file_path_or_name: String, fmt: String) -> void:
	system_status_badge.text = "EXPORTED %s -> %s" % [fmt.to_upper(), file_path_or_name]
	system_status_badge.add_theme_color_override("font_color", COL_EMERALD)
