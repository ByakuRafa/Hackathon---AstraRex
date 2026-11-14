class_name MainShell
extends Control

## Root Application Shell for AstraRex Space Mission Engineering Simulator.
## Enforces "One Frame, Four Phases" (84px Top HUD + 600px Phase Canvas + 36px Bottom Bar = 720px).

const COL_EMERALD: Color = BrandStyle.PASS_EMERALD      # #35E0A1
const COL_AMBER: Color = BrandStyle.CAUTION_AMBER       # #FFB224
const COL_RED: Color = BrandStyle.CRITICAL_RED          # #FF4560
const COL_CYAN: Color = BrandStyle.NOMINAL_CYAN         # #2FD3FF
const COL_GUIDE_VIOLET: Color = BrandStyle.GUIDE_VIOLET # #8B6CFF
const COL_NEON_YELLOW: Color = BrandStyle.NEON_YELLOW   # #EAFE07

const SFX_PATHS: Dictionary = {
	"vab_snap": "res://assets/audio/vab_snap.wav",
	"quindar_beep": "res://assets/audio/quindar_beep.wav",
	"ui_hover_tick": "res://assets/audio/ui_hover_tick.wav",
	"thruster_burn": "res://assets/audio/thruster_burn.wav",
	"spe_alarm": "res://assets/audio/spe_alarm.wav",
	"touchdown_confirm": "res://assets/audio/touchdown_confirm.wav",
}

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

var btn_mute_audio: Button = null

var _current_phase_index: int = 0
var _next_step_glow_active: bool = false
var _glow_phase: float = 0.0
var _cta_style_normal: StyleBoxFlat
var _cta_style_hover: StyleBoxFlat
var _phase_tween: Tween = null

var _sfx_players: Dictionary = {}
var _audio_muted: bool = false
var _thruster_loop_active: bool = false


func _ready() -> void:
	add_to_group("main_shell")
	_setup_audio_players()
	_setup_bottom_bar_styles()
	_setup_mute_button()
	_apply_tabular_fonts()

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

	_switch_to_phase(0, false)
	_on_mission_state_updated(MissionState.get_telemetry_snapshot())


func _exit_tree() -> void:
	for p_var: Variant in _sfx_players.values():
		var p: AudioStreamPlayer = p_var as AudioStreamPlayer
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_sfx_players.clear()


func _process(delta: float) -> void:
	if not _next_step_glow_active or _cta_style_normal == null:
		return
	# Exclusive 1.2s smooth sine cycle on the Single Guidance Pulse (#8B6CFF)
	_glow_phase += delta * (TAU / 1.2)
	var pulse: float = 0.50 + 0.50 * sin(_glow_phase)
	_cta_style_normal.border_color = Color(COL_GUIDE_VIOLET.r, COL_GUIDE_VIOLET.g, COL_GUIDE_VIOLET.b, 0.48 + 0.52 * pulse)
	_cta_style_normal.bg_color = Color(0.14 + 0.12 * pulse, 0.10 + 0.08 * pulse, 0.32 + 0.18 * pulse, 0.96)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_ev: InputEventKey = event as InputEventKey
	if not key_ev.pressed or key_ev.echo:
		return
	if key_ev.keycode != KEY_SPACE and key_ev.keycode != KEY_ENTER and key_ev.keycode != KEY_KP_ENTER:
		return
	if is_instance_valid(bottom_design_code_edit) and bottom_design_code_edit.has_focus():
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	if get_viewport() != null:
		get_viewport().set_input_as_handled()
	_on_primary_next_step_pressed()


func _setup_audio_players() -> void:
	for sfx_key_var: Variant in SFX_PATHS.keys():
		var sfx_key: String = str(sfx_key_var)
		var wav_path: String = str(SFX_PATHS[sfx_key])
		if not ResourceLoader.exists(wav_path):
			continue
		var stream: AudioStream = ResourceLoader.load(wav_path) as AudioStream
		if stream == null:
			continue
		if sfx_key == "thruster_burn" and stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Sfx_%s" % sfx_key
		player.stream = stream
		player.volume_db = -8.0 if sfx_key == "thruster_burn" else (-10.0 if sfx_key == "ui_hover_tick" else -5.0)
		add_child(player)
		_sfx_players[sfx_key] = player


func play_sfx(sfx_name: String) -> void:
	if _audio_muted:
		return
	var player: AudioStreamPlayer = _sfx_players.get(sfx_name, null) as AudioStreamPlayer
	if is_instance_valid(player):
		player.play()


func set_loop_sfx(sfx_name: String, active: bool) -> void:
	var player: AudioStreamPlayer = _sfx_players.get(sfx_name, null) as AudioStreamPlayer
	if not is_instance_valid(player):
		return
	if sfx_name == "thruster_burn":
		_thruster_loop_active = active
	if _audio_muted or not active:
		if player.playing:
			player.stop()
	elif not player.playing:
		player.play()


func set_audio_muted(muted: bool) -> void:
	_audio_muted = muted
	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_mute(bus_idx, muted)
	if muted:
		for p_var: Variant in _sfx_players.values():
			var p: AudioStreamPlayer = p_var as AudioStreamPlayer
			if is_instance_valid(p) and p.playing:
				p.stop()
	elif _thruster_loop_active and _current_phase_index == 2:
		set_loop_sfx("thruster_burn", true)
	if is_instance_valid(btn_mute_audio):
		btn_mute_audio.set_pressed_no_signal(muted)
		btn_mute_audio.text = "MUTE: ON" if muted else "SFX: ON"


func is_audio_muted() -> bool:
	return _audio_muted


func _setup_mute_button() -> void:
	var utility_cluster: HBoxContainer = get_node_or_null("MainVBox/BottomActionBar/Margin/HBox/UtilityCluster") as HBoxContainer
	if not is_instance_valid(utility_cluster):
		return
	btn_mute_audio = Button.new()
	btn_mute_audio.name = "BtnMuteAudio"
	btn_mute_audio.toggle_mode = true
	btn_mute_audio.focus_mode = Control.FOCUS_NONE
	btn_mute_audio.custom_minimum_size = Vector2(72, 26)
	btn_mute_audio.text = "SFX: ON"
	btn_mute_audio.tooltip_text = "Mute or unmute NASA Web Audio telemetry & propulsion cues (44.1 kHz mono)."
	btn_mute_audio.add_theme_font_size_override("font_size", 11)
	BrandStyle.bind_mono_font(btn_mute_audio)

	var mute_norm: StyleBoxFlat = _make_util_style(Color(0.055, 0.086, 0.141, 0.92), BrandStyle.BTN_BORDER)
	var mute_hover: StyleBoxFlat = _make_util_style(Color(0.082, 0.133, 0.224, 0.96), COL_NEON_YELLOW)
	var mute_pressed: StyleBoxFlat = _make_util_style(Color(0.22, 0.08, 0.11, 0.94), COL_AMBER)
	btn_mute_audio.add_theme_stylebox_override("normal", mute_norm)
	btn_mute_audio.add_theme_stylebox_override("focus", mute_norm)
	btn_mute_audio.add_theme_stylebox_override("hover", mute_hover)
	btn_mute_audio.add_theme_stylebox_override("pressed", mute_pressed)

	btn_mute_audio.toggled.connect(func(toggled_on: bool) -> void:
		set_audio_muted(toggled_on)
		if not toggled_on:
			play_sfx("ui_hover_tick")
	)
	utility_cluster.add_child(btn_mute_audio)


func _apply_tabular_fonts() -> void:
	BrandStyle.bind_mono_font(system_status_badge)
	BrandStyle.bind_mono_font(bottom_design_code_edit)


func _make_util_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	return sb


func _setup_bottom_bar_styles() -> void:
	var bar_bg: StyleBoxFlat = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.055, 0.086, 0.141, 0.94)
	bar_bg.border_color = BrandStyle.PANEL_BORDER
	bar_bg.border_width_top = 1
	bar_bg.content_margin_left = 10.0
	bar_bg.content_margin_right = 10.0
	bar_bg.content_margin_top = 3.0
	bar_bg.content_margin_bottom = 3.0
	bottom_action_bar.add_theme_stylebox_override("panel", bar_bg)

	_cta_style_normal = StyleBoxFlat.new()
	_cta_style_normal.bg_color = Color(0.03, 0.22, 0.36, 0.96)
	_cta_style_normal.border_color = COL_CYAN
	_cta_style_normal.set_border_width_all(2)
	_cta_style_normal.set_corner_radius_all(5)
	_cta_style_normal.content_margin_left = 12.0
	_cta_style_normal.content_margin_right = 12.0
	_cta_style_normal.content_margin_top = 2.0
	_cta_style_normal.content_margin_bottom = 2.0

	_cta_style_hover = _cta_style_normal.duplicate() as StyleBoxFlat
	_cta_style_hover.bg_color = Color(0.043, 0.239, 0.569, 0.98)
	_cta_style_hover.border_color = COL_NEON_YELLOW

	for state_name: String in ["normal", "focus"]:
		primary_next_step_btn.add_theme_stylebox_override(state_name, _cta_style_normal)
	for state_name: String in ["hover", "pressed"]:
		primary_next_step_btn.add_theme_stylebox_override(state_name, _cta_style_hover)
	primary_next_step_btn.add_theme_color_override("font_color", BrandStyle.TEXT_WHITE)
	primary_next_step_btn.add_theme_color_override("font_hover_color", COL_NEON_YELLOW)

	var util_style: StyleBoxFlat = _make_util_style(Color(0.055, 0.086, 0.141, 0.92), BrandStyle.BTN_BORDER)
	var util_hover: StyleBoxFlat = _make_util_style(Color(0.082, 0.133, 0.224, 0.96), COL_NEON_YELLOW)
	var util_dis: StyleBoxFlat = _make_util_style(Color(0.035, 0.055, 0.098, 0.72), Color(0.165, 0.231, 0.333, 0.55))
	for btn: Button in [btn_copy_design_code, btn_load_design_code, btn_export_csv, btn_export_json]:
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", util_style)
		btn.add_theme_stylebox_override("focus", util_style)
		btn.add_theme_stylebox_override("hover", util_hover)
		btn.add_theme_stylebox_override("pressed", util_hover)
		btn.add_theme_stylebox_override("disabled", util_dis)

	var line_sb: StyleBoxFlat = StyleBoxFlat.new()
	line_sb.bg_color = BrandStyle.SPACE_950
	line_sb.border_color = BrandStyle.BTN_BORDER
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
	play_sfx("quindar_beep")
	_switch_to_phase(phase_index)


func _on_preset_loaded(_preset_index: int, _preset_name: String) -> void:
	_set_next_step_glow(true)
	play_sfx("quindar_beep")


func _on_descent_completed(_survived: bool) -> void:
	_set_next_step_glow(true)


func _set_next_step_glow(enabled: bool) -> void:
	_next_step_glow_active = enabled
	_glow_phase = 0.0
	if not enabled and _cta_style_normal != null:
		_cta_style_normal.border_color = COL_CYAN
		_cta_style_normal.bg_color = Color(0.03, 0.22, 0.36, 0.96)


func _switch_to_phase(phase_index: int, play_transition_tween: bool = true) -> void:
	_current_phase_index = clampi(phase_index, 0, 3)
	main_hud.set_active_phase(_current_phase_index)

	phase1_planning.visible = (_current_phase_index == 0)
	phase2_vab.set_vab_active(_current_phase_index == 1)
	phase3_lunar_sim.set_lunar_sim_active(_current_phase_index == 2)
	phase4_debrief.set_debrief_active(_current_phase_index == 3)
	if _current_phase_index != 2:
		set_loop_sfx("thruster_burn", false)
	_update_next_step_button()

	if play_transition_tween and is_inside_tree() and is_instance_valid(phase_container):
		if _phase_tween != null and _phase_tween.is_valid():
			_phase_tween.kill()
		phase_container.modulate.a = 0.88
		_phase_tween = create_tween()
		_phase_tween.tween_property(phase_container, "modulate:a", 1.0, 0.09)


func _update_next_step_button() -> void:
	match _current_phase_index:
		0:
			primary_next_step_btn.text = "2. Assemble in VAB ->"
			primary_next_step_btn.tooltip_text = "Proceed to Phase 2: 3D Vehicle Assembly Building (Shortcut: Space / Enter)."
		1:
			primary_next_step_btn.text = "3. Launch Lunar Descent ->"
			primary_next_step_btn.tooltip_text = "Proceed to Phase 3: South Pole TLI & Terminal Descent (Shortcut: Space / Enter)."
		2:
			primary_next_step_btn.text = "4. Open Pareto Debrief ->"
			primary_next_step_btn.tooltip_text = "Proceed to Phase 4: Pareto Optimization & Engineering Debrief (Shortcut: Space / Enter)."
		_:
			primary_next_step_btn.text = "<- Iterate in VAB"
			primary_next_step_btn.tooltip_text = "Return to Phase 2: Refine subsystem architecture in 3D VAB (Shortcut: Space / Enter)."


func _on_primary_next_step_pressed() -> void:
	_set_next_step_glow(false)
	play_sfx("quindar_beep")
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
			system_status_badge.text = "✖ LOCKOUT: %s | T/W %.2f | dV %.0f m/s" % [reason, tw, dv]
		else:
			var student_reason: String = "THRUST DEFICIT" if reason == "CRITICAL_THRUST_DEFICIT" else ("DV SHORTFALL" if reason == "PROPELLANT_DV_SHORTFALL" else "NO DESCENT ENGINE")
			system_status_badge.text = "✖ FAIL • %s" % student_reason
		system_status_badge.add_theme_color_override("font_color", COL_RED)
		system_status_badge.tooltip_text = "%s (%s)" % [str(land.get("message", "")), str(land.get("citation", "NASA SP-2016-6105"))]
	elif not bool(compat.get("compatible", false)):
		if engineer_mode:
			system_status_badge.text = "✖ CRITICAL • m0 %.0f / %.0f kg | $%.0fM" % [m0, float(compat.get("max_tli_mass_kg", 0.0)), float(snap.get("total_cost_musd", 0.0))]
		else:
			system_status_badge.text = "✖ FAIL • TLI MASS OR BUDGET EXCEEDED"
		system_status_badge.add_theme_color_override("font_color", COL_RED)
		var reasons: Array = compat.get("reasons", []) as Array
		system_status_badge.tooltip_text = str(reasons[0]) if not reasons.is_empty() else "Launcher / Budget constraint violated."
	elif net_w < 0.0 or not night_ok or not trn_ok:
		var warn_tag: String = "NO TRN (>15 deg)" if not trn_ok else ("LUNAR NIGHT RISK" if not night_ok else "POWER DEFICIT")
		if engineer_mode:
			system_status_badge.text = "⚠ CAUTION • %s | Pnet %+.0f W" % [warn_tag, net_w]
		else:
			system_status_badge.text = "⚠ CAUTION • %s" % warn_tag
		system_status_badge.add_theme_color_override("font_color", COL_AMBER)
		system_status_badge.tooltip_text = "Mission compatible with launcher, but surface hazards or power shortfalls remain."
	else:
		if engineer_mode:
			system_status_badge.text = "✔ NOMINAL • T/W %.2f | dV %.0f m/s | %.0f kg" % [tw, dv, m0]
		else:
			system_status_badge.text = "✔ PASS • READY (SAFE T/W & LAUNCH MARGIN)"
		system_status_badge.add_theme_color_override("font_color", COL_EMERALD)
		system_status_badge.tooltip_text = "All launch, orbital Delta-V, lunar T/W, and night survival checks nominal (NASA SP-2016-6105 Rev2)."


func _on_copy_design_code_pressed() -> void:
	var code: String = MissionState.export_design_code()
	bottom_design_code_edit.text = code
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(code)
	play_sfx("vab_snap")
	system_status_badge.text = "✔ DESIGN CODE COPIED (%d chars)" % code.length()
	system_status_badge.add_theme_color_override("font_color", COL_CYAN)


func _on_load_design_code_pressed() -> void:
	var code: String = bottom_design_code_edit.text.strip_edges()
	if code.is_empty():
		play_sfx("spe_alarm")
		system_status_badge.text = "⚠ CAUTION • PASTE A DESIGN CODE FIRST"
		system_status_badge.add_theme_color_override("font_color", COL_AMBER)
		return
	var ok: bool = MissionState.import_design_code(code)
	if not ok:
		play_sfx("spe_alarm")
		system_status_badge.text = "✖ FAIL • INVALID DESIGN CODE"
		system_status_badge.add_theme_color_override("font_color", COL_RED)
	else:
		play_sfx("quindar_beep")
		_set_next_step_glow(true)


func _on_export_csv_pressed() -> void:
	if not MissionState.engineer_mode:
		return
	play_sfx("vab_snap")
	ParetoSolver.export_telemetry_report("csv")


func _on_export_json_pressed() -> void:
	if not MissionState.engineer_mode:
		return
	play_sfx("vab_snap")
	ParetoSolver.export_telemetry_report("json")


func _on_report_exported(file_path_or_name: String, fmt: String) -> void:
	system_status_badge.text = "✔ EXPORTED %s -> %s" % [fmt.to_upper(), file_path_or_name]
	system_status_badge.add_theme_color_override("font_color", COL_EMERALD)
