class_name MainShell
extends Control

## Root Application Shell for AstraRex Space Mission Engineering Simulator.
## Docks MainHUD persistently at the top and swaps active Phase views inside PhaseContainer.

@onready var main_hud: MainHUD = %MainHUD
@onready var phase1_planning: Phase1Planning = %Phase1_Planning
@onready var phase2_vab: Phase2VAB = %Phase2_VAB
@onready var phase3_lunar_sim: Phase3LunarSim = %Phase3_LunarSim
@onready var phase4_debrief: Phase4Debrief = %Phase4_Debrief

var _current_phase_index: int = 0


func _ready() -> void:
	main_hud.phase_requested.connect(_on_phase_requested)
	phase1_planning.proceed_to_vab_requested.connect(_switch_to_phase.bind(1))
	phase2_vab.proceed_to_descent_requested.connect(_switch_to_phase.bind(2))
	phase3_lunar_sim.return_to_vab_requested.connect(_switch_to_phase.bind(1))
	phase3_lunar_sim.proceed_to_debrief_requested.connect(_switch_to_phase.bind(3))
	phase4_debrief.iterate_in_vab_requested.connect(_switch_to_phase.bind(1))

	_switch_to_phase(0)


func _on_phase_requested(phase_index: int) -> void:
	_switch_to_phase(phase_index)


func _switch_to_phase(phase_index: int) -> void:
	_current_phase_index = clampi(phase_index, 0, 3)
	main_hud.set_active_phase(_current_phase_index)

	phase1_planning.visible = (_current_phase_index == 0)
	phase2_vab.set_vab_active(_current_phase_index == 1)
	phase3_lunar_sim.set_lunar_sim_active(_current_phase_index == 2)
	phase4_debrief.set_debrief_active(_current_phase_index == 3)
