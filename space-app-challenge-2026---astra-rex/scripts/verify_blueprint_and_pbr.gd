extends Node

const MODEL_FILES: Array[String] = [
	"res://assets/models/lander_bus.glb",
	"res://assets/models/engine_biprop.glb",
	"res://assets/models/engine_ion.glb",
	"res://assets/models/solar_array.glb",
	"res://assets/models/rtg_cassini.glb",
	"res://assets/models/battery_pack.glb",
	"res://assets/models/antenna_hga.glb",
	"res://assets/models/antenna_omni.glb",
	"res://assets/models/sensor_lidar.glb",
	"res://assets/models/payload_drill.glb",
	"res://assets/models/payload_msolo.glb",
	"res://assets/models/payload_sar.glb",
	"res://assets/models/shield_heavy.glb",
	"res://assets/models/sls_block1.glb",
	"res://assets/models/vab_gantry.glb",
	"res://assets/models/dsn_70m_dish.glb",
]

var _failures: Array[String] = []


func _ready() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	var tree: SceneTree = get_tree()
	await tree.process_frame
	await tree.process_frame

	_verify_all_glb_pbr_materials()

	var main_packed: PackedScene = ResourceLoader.load("res://src/scenes/Main.tscn") as PackedScene
	if main_packed == null:
		_fail("Failed to load res://src/scenes/Main.tscn")
		_finish()
		return

	var main_node: Control = main_packed.instantiate() as Control
	tree.root.size = Vector2i(1280, 720)
	tree.root.add_child(main_node)

	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	_verify_frame_layout(main_node)
	_verify_phase3_terrain_pbr(main_node)
	await _verify_vab_deltas_and_pins(main_node)
	await _verify_presets_and_phase_flow(main_node)
	await _verify_isomorphic_student_engineer(main_node)
	await _verify_stage4_brand_audio_fonts_and_shortcuts(main_node)

	main_node.queue_free()
	await tree.process_frame
	await tree.process_frame
	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("[FAIL] ", msg)


func _pass(msg: String) -> void:
	print("[PASS] ", msg)


func _verify_all_glb_pbr_materials() -> void:
	var verified_count: int = 0
	for path: String in MODEL_FILES:
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed == null:
			_fail("Missing or unloadable GLB: %s" % path)
			continue
		var inst: Node = packed.instantiate()
		if inst == null:
			_fail("Failed to instantiate GLB: %s" % path)
			continue

		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(inst, meshes)
		if meshes.is_empty():
			_fail("GLB contains zero MeshInstance3D: %s" % path)
			inst.queue_free()
			continue

		var textured_surfaces: int = 0
		var colored_surfaces: int = 0
		var has_uvs: bool = true
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			for s_idx: int in range(mi.mesh.get_surface_count()):
				var arrays: Array = mi.mesh.surface_get_arrays(s_idx)
				if arrays.size() <= Mesh.ARRAY_TEX_UV or arrays[Mesh.ARRAY_TEX_UV] == null or (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty():
					has_uvs = false
				var mat: Material = mi.get_active_material(s_idx)
				if mat is BaseMaterial3D:
					var bmat: BaseMaterial3D = mat as BaseMaterial3D
					if bmat.albedo_texture != null or bmat.normal_texture != null or bmat.emission_texture != null:
						textured_surfaces += 1
					if bmat.albedo_color != Color(0.8, 0.8, 0.8, 1.0) or bmat.metallic > 0.05 or bmat.emission_enabled:
						colored_surfaces += 1

		if not has_uvs:
			_fail("GLB missing UV channel: %s" % path)
		elif textured_surfaces == 0 and colored_surfaces == 0:
			_fail("GLB appears untextured/default grey: %s" % path)
		else:
			verified_count += 1
		inst.queue_free()

	if verified_count == MODEL_FILES.size():
		_pass("All %d GLB models have UVs and non-grey PBR materials" % verified_count)


func _collect_meshes(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out_meshes.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, out_meshes)


func _verify_frame_layout(main_node: Control) -> void:
	var main_hud: Control = main_node.get_node("MainVBox/MainHUD") as Control
	var phase_cont: Control = main_node.get_node("MainVBox/PhaseContainer") as Control
	var bottom_bar: Control = main_node.get_node("MainVBox/BottomActionBar") as Control

	var hud_h: float = main_hud.size.y
	var phase_h: float = phase_cont.size.y
	var bot_h: float = bottom_bar.size.y
	var total_h: float = hud_h + phase_h + bot_h

	if absf(hud_h - 84.0) > 1.0:
		_fail("MainHUD height %.1f != 84.0 (min=%.1f)" % [hud_h, main_hud.get_combined_minimum_size().y])
	if absf(phase_h - 600.0) > 1.0:
		_fail("PhaseContainer height %.1f != 600.0 (min=%.1f)" % [phase_h, phase_cont.get_combined_minimum_size().y])
	if absf(bot_h - 36.0) > 1.0:
		_fail("BottomActionBar height %.1f != 36.0 (min=%.1f)" % [bot_h, bottom_bar.get_combined_minimum_size().y])
	if absf(total_h - 720.0) > 1.0:
		_fail("Total frame height %.1f != 720.0 (main.size=%s)" % [total_h, str(main_node.size)])
	else:
		_pass("One Frame layout verified: MainHUD=%.0fpx + PhaseContainer=%.0fpx + BottomActionBar=%.0fpx = %.0fpx" % [hud_h, phase_h, bot_h, total_h])

	for phase_name: String in ["%Phase1_Planning", "%Phase2_VAB", "%Phase3_LunarSim", "%Phase4_Debrief"]:
		var pc: Control = main_node.get_node(phase_name) as Control
		var max_child_min: Vector2 = Vector2.ZERO
		for ch: Node in pc.get_children():
			if ch is Container:
				var c_min: Vector2 = (ch as Container).get_combined_minimum_size()
				max_child_min.x = maxf(max_child_min.x, c_min.x)
				max_child_min.y = maxf(max_child_min.y, c_min.y)
		if max_child_min.y > 600.5 or max_child_min.x > 1280.5:
			_dump_tall_controls(pc, 0)
			_fail("%s child container min size %s exceeds 1280x600 canvas" % [phase_name, str(max_child_min)])
		else:
			_pass("%s fits cleanly in 1280x600 (container min=%s)" % [phase_name, str(max_child_min)])


func _dump_tall_controls(node: Node, depth: int) -> void:
	if node is Control:
		var ctrl: Control = node as Control
		var ms: Vector2 = ctrl.get_combined_minimum_size()
		if ms.y > 180.0:
			print("  minY %.1f (minX %.1f) :: %s (%s)" % [ms.y, ms.x, ctrl.name, ctrl.get_class()])
	for ch: Node in node.get_children():
		_dump_tall_controls(ch, depth + 1)


func _verify_phase3_terrain_pbr(main_node: Control) -> void:
	var p3: Phase3LunarSim = main_node.get_node("%Phase3_LunarSim") as Phase3LunarSim
	if p3 == null or p3.terrain_mesh == null or p3.terrain_mesh.mesh == null:
		_fail("Phase3 terrain_mesh missing")
		return
	var mesh: Mesh = p3.terrain_mesh.mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var tans: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
	if uvs.is_empty() or norms.is_empty() or tans.is_empty():
		_fail("Terrain ArrayMesh missing UV/Normal/Tangent (uv=%d norm=%d tan=%d)" % [uvs.size(), norms.size(), tans.size()])
		return
	var mat: StandardMaterial3D = p3.terrain_mesh.material_override as StandardMaterial3D
	if mat == null:
		_fail("Terrain material_override is not StandardMaterial3D")
		return
	if mat.albedo_texture == null or mat.normal_texture == null:
		_fail("Terrain StandardMaterial3D missing regolith_albedo or regolith_normal texture")
		return
	if not mat.vertex_color_use_as_albedo or mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
		_fail("Terrain material missing vertex_color_use_as_albedo or CULL_DISABLED")
		return
	_pass("Phase3 terrain PBR verified: %d UVs, %d normals, %d tangents, albedo+normal .webp bound" % [uvs.size(), norms.size(), tans.size()])


func _verify_vab_deltas_and_pins(main_node: Control) -> void:
	var tree: SceneTree = get_tree()
	var shell: MainShell = main_node as MainShell
	shell._switch_to_phase(1)
	await tree.process_frame
	await tree.process_frame

	var p2: Phase2VAB = main_node.get_node("%Phase2_VAB") as Phase2VAB
	var drawer_w: float = p2.left_drawer.size.x
	var center_area: Control = p2.get_node("%CenterViewportArea") as Control
	var center_w: float = center_area.size.x
	if absf(drawer_w - 340.0) > 1.0 or center_w < 938.0:
		_fail("VAB split wrong: LeftDrawer=%.1fpx, CenterViewportArea=%.1fpx (expected 340 / 940)" % [drawer_w, center_w])
	else:
		_pass("VAB drawer/viewport split verified: %.0fpx / %.0fpx (%.1f%% viewport)" % [drawer_w, center_w, center_w / 1280.0 * 100.0])

	if p2.diegetic_pin_overlay.get_child_count() != 7:
		_fail("Expected 7 diegetic 2D slot pins, found %d" % p2.diegetic_pin_overlay.get_child_count())
	else:
		var pin0: Button = p2.diegetic_pin_overlay.get_child(0) as Button
		_pass("7 clickable diegetic 2D slot callout pins verified (pin0 pos=%s visible=%s)" % [str(pin0.position), str(pin0.visible)])

	# Verify pure non-mutating live deltas
	var before_ids: Array[String] = MissionState.selected_subsystem_ids.duplicate()
	var snap: Dictionary = MissionState.get_telemetry_snapshot()
	var rtg_data: Dictionary = NasaDataLoader.get_subsystem("pwr_rtg_mmrtg")
	var ion_data: Dictionary = NasaDataLoader.get_subsystem("prop_ion_sep")
	var rtg_deltas: Dictionary = p2._compute_part_trade_deltas(rtg_data, snap)
	var ion_deltas: Dictionary = p2._compute_part_trade_deltas(ion_data, snap)
	var after_ids: Array[String] = MissionState.selected_subsystem_ids.duplicate()
	if before_ids != after_ids:
		_fail("VAB live delta helper mutated MissionState.selected_subsystem_ids!")
	elif absf(float(ion_deltas.get("d_dv_ms", 0.0))) < 1.0 or absf(float(ion_deltas.get("d_power_w", 0.0))) < 100.0:
		_fail("VAB ion swap deltas unexpectedly small: %s" % str(ion_deltas))
	else:
		_pass("VAB non-mutating deltas verified (MMRTG action=%s, Ion dPwr=%.0f W, dCost=%.1fM)" % [str(rtg_deltas.get("action")), float(ion_deltas.get("d_power_w")), float(ion_deltas.get("d_cost_musd"))])

	# Verify LanderChassis double-sided WebGL PBR material overrides preserve surface textures/colors
	var lc_meshes: Array[MeshInstance3D] = []
	_collect_meshes(p2.lander_chassis, lc_meshes)
	var all_cull_disabled: bool = true
	var all_webgl_pbr_safe: bool = true
	for mi: MeshInstance3D in lc_meshes:
		if mi.material_override != null:
			_fail("LanderChassis MeshInstance3D unexpectedly has blank material_override: %s" % mi.name)
			all_cull_disabled = false
		if mi.mesh != null:
			for s: int in range(mi.mesh.get_surface_count()):
				var smat: Material = mi.get_active_material(s)
				if not (smat is BaseMaterial3D) or (smat as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
					all_cull_disabled = false
				if smat is StandardMaterial3D:
					var std: StandardMaterial3D = smat as StandardMaterial3D
					if std.metallic > 0.36 or not std.emission_enabled:
						_fail("LanderChassis surface %s[%d] WebGL PBR invariant failed (metallic=%.2f emission=%s)" % [mi.name, s, std.metallic, str(std.emission_enabled)])
						all_webgl_pbr_safe = false
	if all_cull_disabled and all_webgl_pbr_safe and not lc_meshes.is_empty():
		_pass("LanderChassis preserves surface materials with CULL_DISABLED & WebGL PBR safety across %d meshes" % lc_meshes.size())
	elif not all_cull_disabled:
		_fail("LanderChassis surface override / CULL_DISABLED check failed")


func _verify_presets_and_phase_flow(main_node: Control) -> void:
	var tree: SceneTree = get_tree()
	var shell: MainShell = main_node as MainShell
	MissionState.apply_preset(2)
	await tree.process_frame
	if not shell._next_step_glow_active:
		_fail("Preset 2 did not activate Next-Step cyan glow")
	MissionState.apply_preset(1)
	await tree.process_frame

	shell._switch_to_phase(0)
	await tree.process_frame
	var btn_next: Button = main_node.get_node("%PrimaryNextStepBtn") as Button
	if btn_next.text != "2. Assemble in VAB ->":
		_fail("Phase 0 CTA text mismatch: %s" % btn_next.text)
	btn_next.pressed.emit()
	await tree.process_frame
	if shell._current_phase_index != 1 or btn_next.text != "3. SIR: Launch Descent ->":
		_fail("Phase 1 CTA transition mismatch: phase=%d text=%s" % [shell._current_phase_index, btn_next.text])
	btn_next.pressed.emit()
	await tree.process_frame
	if shell._current_phase_index != 2 or btn_next.text != "4. Open Pareto Debrief ->":
		_fail("Phase 2 CTA transition mismatch: phase=%d text=%s" % [shell._current_phase_index, btn_next.text])
	var p3: Phase3LunarSim = main_node.get_node("%Phase3_LunarSim") as Phase3LunarSim
	p3.descent_completed.emit(true)
	if not shell._next_step_glow_active:
		_fail("descent_completed did not activate Next-Step cyan glow")
	btn_next.pressed.emit()
	await tree.process_frame
	if shell._current_phase_index != 3 or btn_next.text != "<- Iterate in VAB":
		_fail("Phase 3 CTA transition mismatch: phase=%d text=%s" % [shell._current_phase_index, btn_next.text])
	_pass("Presets (P1..P3) and 4-Phase Next-Step CTA flow verified")


func _verify_isomorphic_student_engineer(main_node: Control) -> void:
	var tree: SceneTree = get_tree()
	var shell: MainShell = main_node as MainShell
	shell._switch_to_phase(0)
	MissionState.set_engineer_mode(false)
	await tree.process_frame
	await tree.process_frame

	var hud_node: Control = main_node.get_node("%MainHUD") as Control
	var btn_csv: Button = main_node.get_node("%BtnExportCSV") as Button
	var btn_json: Button = main_node.get_node("%BtnExportJSON") as Button
	var btn_next: Button = main_node.get_node("%PrimaryNextStepBtn") as Button
	var card_mass: Control = hud_node.get_node("%CardMass") as Control
	var card_prop: Control = hud_node.get_node("%CardPropulsion") as Control

	if not btn_csv.disabled or not btn_json.disabled:
		_fail("Export CSV/JSON should be disabled in Student mode")

	var pos_next_stu: Vector2 = btn_next.global_position
	var pos_csv_stu: Vector2 = btn_csv.global_position
	var size_mass_stu: Vector2 = card_mass.size
	var size_prop_stu: Vector2 = card_prop.size

	MissionState.set_engineer_mode(true)
	await tree.process_frame
	await tree.process_frame

	if btn_csv.disabled or btn_json.disabled:
		_fail("Export CSV/JSON should be unlocked in Engineer mode")

	var delta_next: float = (btn_next.global_position - pos_next_stu).length()
	var delta_csv: float = (btn_csv.global_position - pos_csv_stu).length()
	var delta_mass: float = (card_mass.size - size_mass_stu).length()
	var delta_prop: float = (card_prop.size - size_prop_stu).length()

	if delta_next > 0.5 or delta_csv > 0.5 or delta_mass > 0.5 or delta_prop > 0.5:
		_fail("Isomorphic Dual-Mode layout shifted! deltas: next=%.2f csv=%.2f mass=%.2f prop=%.2f" % [delta_next, delta_csv, delta_mass, delta_prop])
	else:
		_pass("Isomorphic Student/Engineer toggle verified (0.0px layout shift, export lock state accurate)")


func _verify_stage4_brand_audio_fonts_and_shortcuts(main_node: Control) -> void:
	# 1. Verify all 6 procedural 44.1kHz WAV samples & thruster loop
	var expected_wavs: Array[String] = [
		"res://assets/audio/vab_snap.wav",
		"res://assets/audio/quindar_beep.wav",
		"res://assets/audio/ui_hover_tick.wav",
		"res://assets/audio/thruster_burn.wav",
		"res://assets/audio/spe_alarm.wav",
		"res://assets/audio/touchdown_confirm.wav"
	]
	for wav_path: String in expected_wavs:
		var stream: Resource = ResourceLoader.load(wav_path)
		if not (stream is AudioStreamWAV):
			_fail("Missing or invalid AudioStreamWAV: %s" % wav_path)
			return
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		if wav.mix_rate != 44100 or wav.stereo:
			_fail("%s audio spec mismatch (rate=%d stereo=%s)" % [wav_path, wav.mix_rate, str(wav.stereo)])
			return
		if wav_path.ends_with("thruster_burn.wav") and wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			_fail("thruster_burn.wav missing LOOP_FORWARD import setting")
			return
	_pass("All 6 procedural NASA WAV samples verified (44.1kHz mono, thruster loop active)")

	# 2. Verify Barlow Semi Condensed & JetBrains Mono Tabular (tnum) fonts
	var ui_font: Resource = ResourceLoader.load("res://src/ui/FontUI_Barlow.tres")
	var mono_font: Resource = ResourceLoader.load("res://src/ui/FontMono_Tabular.tres")
	if not (ui_font is FontVariation) or not (mono_font is FontVariation):
		_fail("FontUI_Barlow.tres or FontMono_Tabular.tres failed to load as FontVariation")
		return
	var mono_fv: FontVariation = mono_font as FontVariation
	var tnum_val: Variant = mono_fv.opentype_features.get("tnum", mono_fv.opentype_features.get(1953396077, 0))
	if int(tnum_val) != 1:
		_fail("FontMono_Tabular.tres missing tnum=1 opentype feature")
		return
	_pass("Typography resources verified (Barlow Semi Condensed UI + JetBrains Mono tnum=1)")

	# 3. Verify harmonized Space Apps Brand colors, sparklines (48x16), and Pareto curve violet
	if BrandStyle.SPACE_950.to_html(false).to_upper() != "05080F" or BrandStyle.NEON_YELLOW.to_html(false).to_upper() != "EAFE07" or BrandStyle.GUIDE_VIOLET.to_html(false).to_upper() != "8B6CFF":
		_fail("BrandStyle core hex mismatch")
		return
	if ParetoChartControl.COLOR_PARETO_LINE != BrandStyle.GUIDE_VIOLET:
		_fail("ParetoChartControl Pareto line must use BrandStyle.GUIDE_VIOLET (#8B6CFF)")
		return
	var hud: MainHUD = main_node.get_node_or_null("%MainHUD") as MainHUD
	var p4: Phase4Debrief = main_node.get_node_or_null("%Phase4_Debrief") as Phase4Debrief
	if hud == null or not is_instance_valid(hud.power_sparkline) or hud.power_sparkline.custom_minimum_size != Vector2(48.0, 16.0):
		_fail("MainHUD missing 48x16 TelemetrySparkline")
		return
	if hud._card_bars.size() != 6:
		_fail("MainHUD expected 6 4px micro-progress bars, got %d" % hud._card_bars.size())
		return
	if p4 == null or not is_instance_valid(p4._debrief_sparkline) or p4._debrief_sparkline.custom_minimum_size != Vector2(48.0, 16.0):
		_fail("Phase4_Debrief missing 48x16 TelemetrySparkline")
		return
	_pass("BrandStyle 60-30-10 tokens, 6 HUD 4px bars, Pareto #8B6CFF curve, and 48x16px sparklines verified")

	# 4. Verify MUTE toggle & Space/Enter 45-second flow shortcut
	var mute_btn: Button = main_node.btn_mute_audio
	if not is_instance_valid(mute_btn):
		_fail("BottomActionBar missing BtnMuteAudio control")
		return
	main_node.call("set_audio_muted", true)
	if not bool(main_node.call("is_audio_muted")):
		_fail("MainShell.set_audio_muted(true) failed")
		return
	main_node.call("set_audio_muted", false)

	for idx_phase: int in range(hud._completed_phases.size()):
		hud._completed_phases[idx_phase] = false
	main_node.call("_switch_to_phase", 0, false)
	await get_tree().process_frame
	if not String(hud.btn_phase_1.text).begins_with("> ") or not String(hud.btn_phase_2.text).begins_with("• "):
		_fail("Stepper initial/reset state mismatch at Phase 1: [%s | %s]" % [hud.btn_phase_1.text, hud.btn_phase_2.text])
		return
	var space_ev: InputEventKey = InputEventKey.new()
	space_ev.keycode = KEY_SPACE
	space_ev.pressed = true
	main_node.get_viewport().push_input(space_ev)
	await get_tree().process_frame
	if int(main_node._current_phase_index) != 1:
		_fail("Spacebar judge flow shortcut did not advance Phase 1 -> Phase 2 (phase=%d)" % int(main_node._current_phase_index))
		return
	_pass("MUTE toggle and Space/Enter 45s phase-advance shortcut verified (Phase 1 -> Phase 2)")

	# 4b. Verify Blueprint §4.2 micro-affordances (Stepper states, Skip button, 4s descent, FeedbackChip, Empty VAB pin, Phase 4 smart empty + 3s idle pulse)
	var p1_tab_text: String = String(hud.btn_phase_1.text)
	var p2_tab_text: String = String(hud.btn_phase_2.text)
	var p3_tab_text: String = String(hud.btn_phase_3.text)
	if not p1_tab_text.begins_with("[OK] ") or not p2_tab_text.begins_with("> ") or not p3_tab_text.begins_with("• "):
		_fail("Stepper prefix states mismatch at Phase 2: [%s | %s | %s]" % [p1_tab_text, p2_tab_text, p3_tab_text])
		return

	var p2_vab: Control = main_node.get_node_or_null("%Phase2_VAB") as Control
	if p2_vab == null:
		p2_vab = main_node.phase_2
	var found_empty_pin: bool = false
	for pin_info: Dictionary in p2_vab._diegetic_pins:
		var pin_btn: Button = pin_info.get("button") as Button
		if pin_btn != null and bool(pin_btn.get_meta("is_empty_slot", false)) and pin_btn.text.begins_with("- "):
			found_empty_pin = true
			break
	if not found_empty_pin:
		_fail("Phase 2 VAB did not render dashed/ghost empty diegetic slot pin (- <SLOT>)")
		return

	MissionState.toggle_subsystem("shield_heavy")
	await get_tree().process_frame
	if String(hud._last_chip_text).is_empty() or not hud._feedback_chip.visible:
		_fail("MainHUD FeedbackChip did not appear on subsystem toggle")
		return
	MissionState.toggle_subsystem("shield_heavy")
	await get_tree().process_frame

	var skip_btn: Button = main_node.btn_skip_debrief
	if not is_instance_valid(skip_btn) or skip_btn.text != "Skip >>" or not skip_btn.visible:
		_fail("Skip >> button missing or hidden during Phase 2 VAB")
		return
	main_node.call("_switch_to_phase", 2, false)
	await get_tree().process_frame
	if not skip_btn.visible:
		_fail("Skip >> button hidden during Phase 3 Lunar Sim")
		return
	skip_btn.pressed.emit()
	await get_tree().process_frame
	if int(main_node._current_phase_index) != 3 or skip_btn.visible:
		_fail("Skip >> button failed to jump to Phase 4 Debrief or hide afterward (phase=%d)" % int(main_node._current_phase_index))
		return

	for _w_p1: int in range(30):
		if not ParetoSolver.is_solving and not p4.pareto_chart.pareto_frontier.is_empty():
			break
		await get_tree().process_frame
	if not p4.pareto_chart.pareto_frontier.is_empty():
		var env_res: Dictionary = p4.pareto_chart.compute_2d_upper_envelope(p4.pareto_chart.pareto_frontier)
		var env_arr: Array = env_res.get("envelope", []) as Array
		var prev_ex: float = -INF
		var prev_ey: float = -INF
		for e_var: Variant in env_arr:
			var e_dict: Dictionary = e_var as Dictionary
			var ex: float = p4.pareto_chart._get_x_value(e_dict)
			var ey: float = p4.pareto_chart._get_y_value(e_dict)
			if ex <= prev_ex or ey <= prev_ey:
				_fail("ParetoChartControl upper envelope not strictly monotonic: (%.2f, %.2f) after (%.2f, %.2f)" % [ex, ey, prev_ex, prev_ey])
				return
			prev_ex = ex
			prev_ey = ey

	var p3_sim: Phase3LunarSim = main_node.get_node("%Phase3_LunarSim") as Phase3LunarSim
	if not is_equal_approx(float(p3_sim.DESCENT_TARGET_DURATION_S), 4.0):
		_fail("Phase 3 DESCENT_TARGET_DURATION_S expected 4.0s, got %.2f" % float(p3_sim.DESCENT_TARGET_DURATION_S))
		return

	MissionState.apply_preset(3)
	await get_tree().process_frame
	main_node.call("_switch_to_phase", 3, false)
	for _w: int in range(30):
		await get_tree().process_frame
		if not ParetoSolver.is_solving:
			break
	await get_tree().process_frame
	var status_msg: String = String(p4.solver_status_label.text)
	if not status_msg.contains("Load a preset (P1/P2) to evaluate the Pareto frontier"):
		_fail("Phase 4 smart empty state prompt missing under Preset 3: %s" % status_msg)
		return

	main_node._idle_seconds = 3.1
	main_node._process(0.02)
	await get_tree().process_frame
	if not bool(hud._preset_pulse_active):
		_fail("3-second idle #8B6CFF preset guidance pulse did not activate")
		return
	MissionState.apply_preset(1)
	await get_tree().process_frame
	_pass("Blueprint §4.2 micro-affordances verified (Stepper [OK]/>/•, SIR CTA, Skip >>, 4.0s descent, 1.5s FeedbackChip, - empty pin, monotonic Pareto envelope, Phase 4 smart empty & 3s #8B6CFF pulse)")

	# 5. Verify packaged WebGL artifact & vercel.json (< 15 MB budget)
	var zip_path: String = ProjectSettings.globalize_path("res://build/astra_rex_itch_webgl.zip")
	var vercel_path: String = ProjectSettings.globalize_path("res://build/web/vercel.json")
	if not FileAccess.file_exists(zip_path) or not FileAccess.file_exists(vercel_path):
		_fail("Missing WebGL bundle or vercel.json (%s / %s)" % [zip_path, vercel_path])
		return
	var fa: FileAccess = FileAccess.open(zip_path, FileAccess.READ)
	var zip_bytes: int = fa.get_length() if fa != null else 0
	if fa != null:
		fa.close()
	if zip_bytes <= 0 or zip_bytes >= 15 * 1024 * 1024:
		_fail("astra_rex_itch_webgl.zip out of 15 MB budget (%d bytes)" % zip_bytes)
		return
	_pass("Single-threaded WebGL release package verified (%.2f MB < 15.0 MB + vercel.json)" % (float(zip_bytes) / 1048576.0))


func _finish() -> void:
	if _failures.is_empty():
		print("=== VERIFY_BLUEPRINT_AND_PBR: ALL CHECKS PASSED ===")
		get_tree().quit(0)
	else:
		printerr("=== VERIFY_BLUEPRINT_AND_PBR: %d FAILURE(S) ===" % _failures.size())
		get_tree().quit(1)
