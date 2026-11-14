class_name MainShell
extends Control

## Root Application Shell for AstraRex Space Mission Engineering Simulator.
## Docks MainHUD persistently at the top and swaps active Phase views inside PhaseContainer.

@onready var main_hud: MainHUD = %MainHUD
@onready var phase1_planning: Phase1Planning = %Phase1_Planning
@onready var phase2_vab: Phase2VAB = %Phase2_VAB
@onready var phase3_placeholder: Control = %Phase3_Placeholder
@onready var phase4_placeholder: Control = %Phase4_Placeholder

@onready var phase3_status_label: Label = %Phase3StatusLabel
@onready var phase4_status_label: Label = %Phase4StatusLabel
@onready var btn_p3_back_vab: Button = %BtnP3BackVAB
@onready var btn_p4_back_vab: Button = %BtnP4BackVAB

var _current_phase_index: int = 0


func _ready() -> void:
	main_hud.phase_requested.connect(_on_phase_requested)
	phase1_planning.proceed_to_vab_requested.connect(_switch_to_phase.bind(1))
	phase2_vab.proceed_to_descent_requested.connect(_switch_to_phase.bind(2))
	btn_p3_back_vab.pressed.connect(_switch_to_phase.bind(1))
	btn_p4_back_vab.pressed.connect(_switch_to_phase.bind(1))

	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)

	_switch_to_phase(0)
	_refresh_placeholder_summaries(MissionState.get_telemetry_snapshot())


func _on_phase_requested(phase_index: int) -> void:
	_switch_to_phase(phase_index)


func _switch_to_phase(phase_index: int) -> void:
	_current_phase_index = clampi(phase_index, 0, 3)
	main_hud.set_active_phase(_current_phase_index)

	phase1_planning.visible = (_current_phase_index == 0)
	phase2_vab.set_vab_active(_current_phase_index == 1)
	phase3_placeholder.visible = (_current_phase_index == 2)
	phase4_placeholder.visible = (_current_phase_index == 3)


func _on_state_updated(snap: Dictionary) -> void:
	_refresh_placeholder_summaries(snap)


func _refresh_placeholder_summaries(snap: Dictionary) -> void:
	if snap.is_empty():
		return

	var tw: float = float(snap.get("lunar_tw_ratio", 0.0))
	var dv: float = float(snap.get("delta_v_ms", 0.0))
	var req_dv: float = float(snap.get("required_dv_ms", 1750.0))
	var fail_code: String = str(snap.get("failure_code", "NOMINAL"))
	var zone_id: String = str(snap.get("landing_zone_id", "connecting_ridge_rim"))

	if is_instance_valid(phase3_status_label):
		phase3_status_label.text = (
			"Stage 3B Target: Shackleton Crater 3D Descent & PSR Illumination Sim\n"
			+ "Selected Zone: %s | Lunar T/W: %.3f | Delta-V: %.0f / %.0f m/s | Status: %s"
			% [zone_id, tw, dv, req_dv, fail_code]
		)

	if is_instance_valid(phase4_status_label):
		phase4_status_label.text = (
			"Stage 3B Target: Multi-Objective Pareto Frontier Solver & Root-Cause Debrief\n"
			+ "Current Science: %.1f pts | Wet Mass: %.1f kg | Cost: $%.1fM | Status: %s"
			% [
				float(snap.get("science_points_effective", 0.0)),
				float(snap.get("m0_wet_kg", 0.0)),
				float(snap.get("total_cost_musd", 0.0)),
				fail_code
			]
		)
