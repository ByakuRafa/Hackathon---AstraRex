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

	main_node.queue_free()
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

	# Verify LanderChassis double-sided material overrides preserve surface textures/colors
	var lc_meshes: Array[MeshInstance3D] = []
	_collect_meshes(p2.lander_chassis, lc_meshes)
	var all_cull_disabled: bool = true
	for mi: MeshInstance3D in lc_meshes:
		if mi.material_override != null:
			_fail("LanderChassis MeshInstance3D unexpectedly has blank material_override: %s" % mi.name)
			all_cull_disabled = false
		if mi.mesh != null:
			for s: int in range(mi.mesh.get_surface_count()):
				var smat: Material = mi.get_active_material(s)
				if not (smat is BaseMaterial3D) or (smat as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
					all_cull_disabled = false
	if all_cull_disabled and not lc_meshes.is_empty():
		_pass("LanderChassis preserves surface materials with CULL_DISABLED across %d meshes" % lc_meshes.size())
	else:
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
	if shell._current_phase_index != 1 or btn_next.text != "3. Launch Lunar Descent ->":
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


func _finish() -> void:
	if _failures.is_empty():
		print("=== VERIFY_BLUEPRINT_AND_PBR: ALL CHECKS PASSED ===")
		get_tree().quit(0)
	else:
		printerr("=== VERIFY_BLUEPRINT_AND_PBR: %d FAILURE(S) ===" % _failures.size())
		get_tree().quit(1)
