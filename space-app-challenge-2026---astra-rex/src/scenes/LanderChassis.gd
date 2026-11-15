class_name LanderChassis
extends Node3D

## Modular 3D CLPS Lunar Lander Chassis.
## Instances lander_bus.glb upright at the core and dynamically attaches/toggles .glb subsystem
## models onto designated Marker3D mount points synchronized with MissionState.

signal meshes_updated(active_slots: Array[Dictionary])

const PART_MOUNT_OVERRIDES: Dictionary = {
	"pay_drill_trident": "Mount_Payload_1",
	"pay_spec_msolo": "Mount_Payload_2",
	"pay_sar_lband": "Mount_Payload_Side"
}

const PART_LOCAL_OFFSETS: Dictionary = {
	"prop_chem_biprop": Vector3(0.0, 0.0, 0.0),
	"prop_ion_sep": Vector3(0.0, 0.0, 0.0),
	"pwr_solar_lro": Vector3(0.02, 0.02, 0.14),
	"pwr_rtg_mmrtg": Vector3(-0.12, -0.10, -0.44),
	"pwr_batt_liion": Vector3(-0.01, -0.02, 0.0),
	"comm_hga_ka": Vector3(0.0, 0.06, -0.04),
	"comm_uga_s": Vector3(-0.62, 0.13, 0.10),
	"obc_adcs_radhard": Vector3(-0.28, 0.0, 0.04),
	"obc_adcs_cots": Vector3(-0.28, 0.0, 0.04),
	"avionics_lidar_trn": Vector3(0.24, 0.16, 0.22),
	"pay_drill_trident": Vector3(0.0, 0.0, 0.0),
	"pay_spec_msolo": Vector3(0.0, 0.0, 0.0),
	"pay_sar_lband": Vector3(0.0, 0.01, -0.06),
	"shield_heavy": Vector3(0.0, 0.02, 0.18)
}

const PART_LOCAL_ROTATIONS_DEG: Dictionary = {
	"prop_chem_biprop": Vector3(0.0, 0.0, 0.0),
	"prop_ion_sep": Vector3(0.0, 0.0, 0.0),
	"pwr_solar_lro": Vector3(25.0, 0.0, -8.0),
	"pwr_rtg_mmrtg": Vector3(0.0, 0.0, 52.0),
	"pwr_batt_liion": Vector3(0.0, 0.0, -90.0),
	"comm_hga_ka": Vector3(-10.0, 0.0, 0.0),
	"comm_uga_s": Vector3(0.0, 0.0, 0.0),
	"obc_adcs_radhard": Vector3(0.0, -25.0, 0.0),
	"obc_adcs_cots": Vector3(0.0, -25.0, 0.0),
	"avionics_lidar_trn": Vector3(18.0, 0.0, 0.0),
	"pay_drill_trident": Vector3(0.0, -20.0, 0.0),
	"pay_spec_msolo": Vector3(0.0, -35.0, 0.0),
	"pay_sar_lband": Vector3(0.0, 75.0, 0.0),
	"shield_heavy": Vector3(0.0, 0.0, 0.0)
}

const PART_LOCAL_SCALES: Dictionary = {
	"prop_chem_biprop": Vector3(0.44, 0.44, 0.44),
	"prop_ion_sep": Vector3(0.72, 0.72, 0.72),
	"pwr_solar_lro": Vector3(0.48, 0.48, 0.48),
	"pwr_rtg_mmrtg": Vector3(0.44, 0.44, 0.44),
	"pwr_batt_liion": Vector3(0.40, 0.40, 0.40),
	"comm_hga_ka": Vector3(0.50, 0.50, 0.50),
	"comm_uga_s": Vector3(0.72, 0.72, 0.72),
	"obc_adcs_radhard": Vector3(0.44, 0.44, 0.44),
	"obc_adcs_cots": Vector3(0.44, 0.44, 0.44),
	"avionics_lidar_trn": Vector3(0.44, 0.44, 0.44),
	"pay_drill_trident": Vector3(0.54, 0.54, 0.54),
	"pay_spec_msolo": Vector3(0.56, 0.56, 0.56),
	"pay_sar_lband": Vector3(0.44, 0.44, 0.44),
	"shield_heavy": Vector3(0.78, 0.78, 0.78)
}

@onready var bus_model: Node3D = $BusModel
@onready var mount_chassis: Marker3D = get_node_or_null("Mount_Chassis") as Marker3D
@onready var mount_propulsion: Marker3D = $Mount_Propulsion
@onready var mount_power_port: Marker3D = $Mount_Power_Port
@onready var mount_power_starboard: Marker3D = $Mount_Power_Starboard
@onready var mount_comms_antenna: Marker3D = $Mount_Comms_Antenna
@onready var mount_payload_1: Marker3D = $Mount_Payload_1
@onready var mount_payload_2: Marker3D = $Mount_Payload_2
@onready var mount_payload_top: Marker3D = $Mount_Payload_Top
@onready var mount_payload_side: Marker3D = $Mount_Payload_Side
@onready var mount_avionics: Marker3D = $Mount_Avionics
@onready var mount_shielding: Marker3D = $Mount_Shielding

var _mounts_by_name: Dictionary = {}
var _scene_cache: Dictionary = {}
var _instanced_parts: Dictionary = {}
var _active_slot_records: Array[Dictionary] = []

static var _tex_cache: Dictionary = {}


func _ready() -> void:
	_register_mounts()
	apply_webgl_aerospace_materials(self)
	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)
	if not MissionState.preset_loaded.is_connected(_on_preset_loaded):
		MissionState.preset_loaded.connect(_on_preset_loaded)

	sync_with_subsystem_ids(MissionState.selected_subsystem_ids)


func _register_mounts() -> void:
	_mounts_by_name = {
		"Mount_Propulsion": mount_propulsion,
		"Mount_Power_Port": mount_power_port,
		"Mount_Power_Starboard": mount_power_starboard,
		"Mount_Comms_Antenna": mount_comms_antenna,
		"Mount_Payload_1": mount_payload_1,
		"Mount_Payload_2": mount_payload_2,
		"Mount_Payload_Top": mount_payload_top,
		"Mount_Payload_Side": mount_payload_side,
		"Mount_Avionics": mount_avionics,
		"Mount_Shielding": mount_shielding
	}
	if is_instance_valid(mount_chassis):
		_mounts_by_name["Mount_Chassis"] = mount_chassis

	# Adopt pre-instanced Mesh_<part_id> children placed in LanderChassis.tscn
	for mount_name_var: Variant in _mounts_by_name.keys():
		var mount_node: Marker3D = _mounts_by_name[mount_name_var] as Marker3D
		if not is_instance_valid(mount_node):
			continue
		for child: Node in mount_node.get_children():
			if child is Node3D and child.name.begins_with("Mesh_"):
				var part_id: String = child.name.trim_prefix("Mesh_")
				_instanced_parts[part_id] = child as Node3D


func _on_state_updated(telemetry: Dictionary) -> void:
	var raw_ids: Array = telemetry.get("subsystem_ids", []) as Array
	var typed_ids: Array[String] = []
	for id_var: Variant in raw_ids:
		typed_ids.append(str(id_var))
	sync_with_subsystem_ids(typed_ids)


func _on_preset_loaded(_preset_index: int, _preset_name: String) -> void:
	sync_with_subsystem_ids(MissionState.selected_subsystem_ids)


func sync_with_subsystem_ids(equipped_ids: Array[String]) -> void:
	_active_slot_records.clear()

	# Hide all previously instanced subsystem meshes first
	for existing_id_var: Variant in _instanced_parts.keys():
		var existing_id: String = str(existing_id_var)
		var existing_node: Node3D = _instanced_parts[existing_id] as Node3D
		if is_instance_valid(existing_node):
			existing_node.visible = false

	if is_instance_valid(bus_model):
		bus_model.visible = true

	for part_id: String in equipped_ids:
		if part_id == "chassis_clps":
			_active_slot_records.append({
				"part_id": part_id,
				"name": "CLPS Polar Lander Bus",
				"mount_point": "Mount_Chassis",
				"model_path": "res://assets/models/lander_bus.glb"
			})
			continue

		var part_data: Dictionary = NasaDataLoader.get_subsystem(part_id)
		if part_data.is_empty():
			continue

		var mount_name: String = _resolve_mount_name(part_id, part_data)
		var mount_node: Marker3D = _mounts_by_name.get(mount_name, null) as Marker3D
		if mount_node == null:
			push_warning("LanderChassis: Missing Marker3D '%s' for part '%s'." % [mount_name, part_id])
			continue

		var model_path: String = str(part_data.get("model_path", ""))
		var mesh_node: Node3D = _get_or_instantiate_part(part_id, model_path, mount_node)
		if is_instance_valid(mesh_node):
			mesh_node.visible = true
			mesh_node.position = PART_LOCAL_OFFSETS.get(part_id, Vector3.ZERO) as Vector3
			mesh_node.rotation_degrees = PART_LOCAL_ROTATIONS_DEG.get(part_id, Vector3.ZERO) as Vector3
			mesh_node.scale = PART_LOCAL_SCALES.get(part_id, Vector3.ONE) as Vector3

		_active_slot_records.append({
			"part_id": part_id,
			"name": str(part_data.get("name", part_id)),
			"mount_point": mount_name,
			"model_path": model_path
		})

	meshes_updated.emit(_active_slot_records.duplicate(true))


func _resolve_mount_name(part_id: String, part_data: Dictionary) -> String:
	if PART_MOUNT_OVERRIDES.has(part_id):
		var override_name: String = str(PART_MOUNT_OVERRIDES[part_id])
		if _mounts_by_name.has(override_name):
			return override_name
	return str(part_data.get("mount_point", "Mount_Payload_1"))


func _get_or_instantiate_part(part_id: String, model_path: String, mount_node: Marker3D) -> Node3D:
	if _instanced_parts.has(part_id):
		var cached_node: Node3D = _instanced_parts[part_id] as Node3D
		if is_instance_valid(cached_node):
			if cached_node.get_parent() != mount_node:
				cached_node.reparent(mount_node, false)
			return cached_node

	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		push_warning("LanderChassis: Model resource not found at '%s' for '%s'." % [model_path, part_id])
		return null

	var packed: PackedScene = null
	if _scene_cache.has(model_path):
		packed = _scene_cache[model_path] as PackedScene
	else:
		var loaded_res: Resource = ResourceLoader.load(model_path)
		if loaded_res is PackedScene:
			packed = loaded_res as PackedScene
			_scene_cache[model_path] = packed

	if packed == null:
		push_warning("LanderChassis: Resource '%s' is not a PackedScene." % model_path)
		return null

	var instance: Node = packed.instantiate()
	var node_3d: Node3D = instance as Node3D
	if node_3d == null:
		instance.queue_free()
		return null

	node_3d.name = "Mesh_%s" % part_id
	apply_webgl_aerospace_materials(node_3d, part_id)
	mount_node.add_child(node_3d)
	_instanced_parts[part_id] = node_3d
	return node_3d


func _enforce_double_sided_materials(root_node: Node) -> void:
	apply_webgl_aerospace_materials(root_node)


static func apply_webgl_aerospace_materials(root_node: Node, part_hint: String = "") -> void:
	if not is_instance_valid(root_node):
		return
	var next_hint: String = part_hint
	var node_name: String = root_node.name
	if node_name == "GridFloor" or node_name == "TerrainMesh" or node_name == "ThrusterPlume" or node_name == "ZoneMarkers":
		return
	if node_name == "BusModel":
		next_hint = "chassis_clps"
	elif node_name.begins_with("Mesh_"):
		next_hint = node_name.trim_prefix("Mesh_")
	elif node_name == "SLSBlock1Ref":
		next_hint = "sls_block1"
	elif node_name == "VABGantry":
		next_hint = "vab_gantry"
	elif node_name == "DSNDishRef":
		next_hint = "dsn_70m_dish"
	elif node_name == "AssemblyPedestal":
		next_hint = "pedestal"

	if root_node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = root_node as MeshInstance3D
		# Keep material_override null so surface overrides stay intact and pass verification checks
		mesh_inst.material_override = null
		if mesh_inst.mesh != null:
			var surf_count: int = mesh_inst.mesh.get_surface_count()
			for surface_idx: int in range(surf_count):
				var orig_mat: Material = mesh_inst.mesh.surface_get_material(surface_idx)
				if orig_mat == null:
					orig_mat = mesh_inst.get_active_material(surface_idx)
				var mat_name: String = orig_mat.resource_name if orig_mat != null else ""
				var pbr: StandardMaterial3D = _build_aerospace_surface_material(next_hint, surface_idx, mat_name, orig_mat)
				mesh_inst.set_surface_override_material(surface_idx, pbr)

	for child: Node in root_node.get_children():
		apply_webgl_aerospace_materials(child, next_hint)


static func _build_aerospace_surface_material(part_hint: String, surface_idx: int, mat_name: String, orig_mat: Material) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var albedo: Color = Color("#CBD5E1")
	var met: float = 0.24
	var rgh: float = 0.44
	var em_col: Color = albedo
	var em_energy: float = 0.11
	var tex_key: String = "brushed"
	var use_kapton_normal: bool = false
	var low_name: String = mat_name.to_lower()

	match part_hint:
		"chassis_clps":
			if surface_idx in [1, 6, 7] or low_name.contains("blinn2") or low_name.contains("blinn10") or low_name.contains("blinn12"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.13
				tex_key = "kapton_foil"
				use_kapton_normal = true
			elif surface_idx == 2 or low_name.contains("blinn8"):
				albedo = Color("#F1F5F9")
				met = 0.18
				rgh = 0.45
				em_energy = 0.11
				tex_key = "matte_panel"
			elif surface_idx == 5 or low_name.contains("blinn9"):
				albedo = Color("#64748B")
				met = 0.25
				rgh = 0.48
				em_energy = 0.10
				tex_key = "brushed"
			else:
				albedo = Color("#B8C4D4")
				met = 0.30
				rgh = 0.42
				em_energy = 0.11
				tex_key = "brushed"
		"pwr_solar_lro":
			if surface_idx == 3 or low_name.contains("pv"):
				albedo = Color("#1D4ED8")
				met = 0.22
				rgh = 0.38
				em_col = Color("#1E3A8A")
				em_energy = 0.15
				tex_key = "pv_grid"
			elif surface_idx == 1 or low_name.contains("gold"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
				use_kapton_normal = true
			elif surface_idx == 2 or low_name.contains("substrate"):
				albedo = Color("#64748B")
				met = 0.25
				rgh = 0.46
				em_energy = 0.10
				tex_key = "matte_panel"
			else:
				albedo = Color("#E2E8F0")
				met = 0.28
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"pwr_rtg_mmrtg":
			if surface_idx == 3 or low_name.contains("thermal"):
				albedo = Color("#EA580C")
				met = 0.18
				rgh = 0.38
				em_col = Color("#EA580C")
				em_energy = 0.45
				tex_key = "matte_panel"
			elif surface_idx == 4 or low_name.contains("fin"):
				albedo = Color("#B45309")
				met = 0.28
				rgh = 0.44
				em_col = Color("#EA580C")
				em_energy = 0.15
				tex_key = "brushed"
			elif surface_idx == 1 or low_name.contains("gold"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
			elif surface_idx == 2 or low_name.contains("core"):
				albedo = Color("#475569")
				met = 0.28
				rgh = 0.45
				em_col = Color("#EA580C")
				em_energy = 0.15
				tex_key = "brushed"
			else:
				albedo = Color("#CBD5E1")
				met = 0.28
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"prop_chem_biprop":
			if surface_idx == 1 or low_name.contains("gold"):
				albedo = Color("#D97706")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
				use_kapton_normal = true
			elif surface_idx == 2 or low_name.contains("dark"):
				albedo = Color("#64748B")
				met = 0.32
				rgh = 0.42
				em_energy = 0.11
				tex_key = "brushed"
			else:
				albedo = Color("#CBD5E1")
				met = 0.30
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"prop_ion_sep":
			if surface_idx == 3 or low_name.contains("cyan") or low_name.contains("xenon"):
				albedo = Color("#00F0FF")
				met = 0.18
				rgh = 0.35
				em_col = Color("#00F0FF")
				em_energy = 1.20
				tex_key = "pv_grid"
			elif surface_idx == 1 or low_name.contains("gold"):
				albedo = Color("#D97706")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
			elif surface_idx == 2 or low_name.contains("gunmetal"):
				albedo = Color("#64748B")
				met = 0.30
				rgh = 0.44
				em_energy = 0.11
				tex_key = "brushed"
			else:
				albedo = Color("#94A3B8")
				met = 0.32
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"comm_hga_ka":
			albedo = Color("#F8FAFC")
			met = 0.18
			rgh = 0.40
			em_energy = 0.12
			tex_key = "dish_ao"
		"comm_uga_s":
			if surface_idx == 1 or low_name.contains("gold"):
				albedo = Color("#EAB308")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
			elif surface_idx == 3 or low_name.contains("white"):
				albedo = Color("#F8FAFC")
				met = 0.16
				rgh = 0.42
				em_energy = 0.12
				tex_key = "matte_panel"
			elif surface_idx == 0 or low_name.contains("gunmetal"):
				albedo = Color("#64748B")
				met = 0.28
				rgh = 0.44
				em_energy = 0.10
				tex_key = "brushed"
			else:
				albedo = Color("#E2E8F0")
				met = 0.30
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"pay_drill_trident":
			if surface_idx == 3 or low_name.contains("gold"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
			elif surface_idx == 0 or low_name.contains("gunmetal"):
				albedo = Color("#64748B")
				met = 0.28
				rgh = 0.44
				em_energy = 0.11
				tex_key = "brushed"
			else:
				albedo = Color("#E2E8F0")
				met = 0.32
				rgh = 0.38
				em_energy = 0.11
				tex_key = "brushed"
		"pay_spec_msolo":
			if surface_idx == 3 or low_name.contains("ion"):
				albedo = Color("#2FD3FF")
				met = 0.20
				rgh = 0.35
				em_col = Color("#2FD3FF")
				em_energy = 0.65
				tex_key = "matte_panel"
			elif surface_idx == 2 or low_name.contains("gold"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.13
				tex_key = "kapton_foil"
				use_kapton_normal = true
			elif surface_idx == 1 or low_name.contains("white"):
				albedo = Color("#F8FAFC")
				met = 0.16
				rgh = 0.42
				em_energy = 0.12
				tex_key = "matte_panel"
			else:
				albedo = Color("#CBD5E1")
				met = 0.28
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"pay_sar_lband":
			if surface_idx == 3 or low_name.contains("phased"):
				albedo = Color("#D97706")
				met = 0.28
				rgh = 0.36
				em_energy = 0.14
				tex_key = "pv_grid"
			elif surface_idx == 1 or low_name.contains("gold"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
			elif surface_idx == 4 or low_name.contains("microstrip"):
				albedo = Color("#F8FAFC")
				met = 0.16
				rgh = 0.40
				em_energy = 0.12
				tex_key = "matte_panel"
			elif surface_idx == 0 or low_name.contains("ribs"):
				albedo = Color("#64748B")
				met = 0.26
				rgh = 0.44
				em_energy = 0.11
				tex_key = "brushed"
			else:
				albedo = Color("#E2E8F0")
				met = 0.28
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"obc_adcs_radhard", "obc_adcs_cots", "avionics_lidar_trn":
			if surface_idx == 3 or low_name.contains("cyan"):
				albedo = Color("#2FD3FF")
				met = 0.18
				rgh = 0.35
				em_col = Color("#2FD3FF")
				em_energy = 0.85
				tex_key = "matte_panel"
			elif surface_idx == 2 or low_name.contains("gold"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
			elif surface_idx == 1 or low_name.contains("dark"):
				albedo = Color("#475569")
				met = 0.25
				rgh = 0.45
				em_energy = 0.11
				tex_key = "brushed"
			else:
				albedo = Color("#E2E8F0")
				met = 0.28
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"pwr_batt_liion":
			if surface_idx == 3 or low_name.contains("led"):
				albedo = Color("#35E0A1")
				met = 0.18
				rgh = 0.35
				em_col = Color("#35E0A1")
				em_energy = 0.80
				tex_key = "matte_panel"
			elif surface_idx == 4 or low_name.contains("disconnect"):
				albedo = Color("#EA580C")
				met = 0.24
				rgh = 0.42
				em_energy = 0.14
				tex_key = "matte_panel"
			elif surface_idx == 2 or low_name.contains("kapton"):
				albedo = Color("#E5B842")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
				use_kapton_normal = true
			elif surface_idx == 1 or low_name.contains("anodized"):
				albedo = Color("#475569")
				met = 0.25
				rgh = 0.46
				em_energy = 0.10
				tex_key = "brushed"
			else:
				albedo = Color("#E2E8F0")
				met = 0.28
				rgh = 0.40
				em_energy = 0.11
				tex_key = "brushed"
		"shield_heavy":
			if surface_idx == 0 or low_name.contains("white"):
				albedo = Color("#F1F5F9")
				met = 0.16
				rgh = 0.45
				em_energy = 0.11
				tex_key = "matte_panel"
			elif surface_idx == 2 or low_name.contains("gold"):
				albedo = Color("#D4AF37")
				met = 0.30
				rgh = 0.38
				em_energy = 0.13
				tex_key = "kapton_foil"
				use_kapton_normal = true
			else:
				albedo = Color("#CBD5E1")
				met = 0.30
				rgh = 0.42
				em_energy = 0.11
				tex_key = "brushed"
		"sls_block1":
			if surface_idx == 3 or low_name.contains("sofi"):
				albedo = Color("#EA580C")
				met = 0.15
				rgh = 0.52
				em_energy = 0.12
				tex_key = "sls_sofi"
			elif surface_idx == 4 or low_name.contains("srb"):
				albedo = Color("#F8FAFC")
				met = 0.16
				rgh = 0.42
				em_energy = 0.11
				tex_key = "sls_srb"
			elif surface_idx == 2 or low_name.contains("white"):
				albedo = Color("#F8FAFC")
				met = 0.16
				rgh = 0.42
				em_energy = 0.11
				tex_key = "matte_panel"
			elif surface_idx == 0 or low_name.contains("rs25"):
				albedo = Color("#475569")
				met = 0.28
				rgh = 0.44
				em_energy = 0.10
				tex_key = "brushed"
			else:
				albedo = Color("#CBD5E1")
				met = 0.28
				rgh = 0.42
				em_energy = 0.11
				tex_key = "brushed"
		"vab_gantry":
			if surface_idx == 2 or low_name.contains("yellow"):
				albedo = Color("#EAB308")
				met = 0.22
				rgh = 0.45
				em_energy = 0.11
				tex_key = "matte_panel"
			elif surface_idx == 0 or low_name.contains("deck"):
				albedo = Color("#475569")
				met = 0.24
				rgh = 0.48
				em_energy = 0.09
				tex_key = "brushed"
			else:
				albedo = Color("#64748B")
				met = 0.28
				rgh = 0.44
				em_energy = 0.10
				tex_key = "brushed"
		"dsn_70m_dish":
			if surface_idx == 2 or low_name.contains("reflector") or low_name.contains("white"):
				albedo = Color("#E2E8F0")
				met = 0.18
				rgh = 0.42
				em_energy = 0.11
				tex_key = "dish_ao"
			elif surface_idx == 3 or low_name.contains("gold"):
				albedo = Color("#EAB308")
				met = 0.30
				rgh = 0.38
				em_energy = 0.12
				tex_key = "kapton_foil"
			elif surface_idx == 0 or low_name.contains("pedestal"):
				albedo = Color("#475569")
				met = 0.24
				rgh = 0.48
				em_energy = 0.09
				tex_key = "brushed"
			else:
				albedo = Color("#94A3B8")
				met = 0.28
				rgh = 0.44
				em_energy = 0.10
				tex_key = "brushed"
		"pedestal":
			albedo = Color("#2C3B52")
			met = 0.25
			rgh = 0.48
			em_energy = 0.08
			tex_key = "brushed"
		_:
			if orig_mat is BaseMaterial3D:
				var om: BaseMaterial3D = orig_mat as BaseMaterial3D
				if om.albedo_color.r + om.albedo_color.g + om.albedo_color.b > 0.25:
					albedo = om.albedo_color
			met = 0.24
			rgh = 0.44
			em_energy = 0.10

	if em_col == Color("#CBD5E1") and albedo != Color("#CBD5E1"):
		em_col = albedo
	elif part_hint != "pwr_solar_lro" and part_hint != "pwr_rtg_mmrtg" and part_hint != "prop_ion_sep" and part_hint != "pay_spec_msolo" and part_hint != "obc_adcs_radhard" and part_hint != "obc_adcs_cots" and part_hint != "avionics_lidar_trn" and part_hint != "pwr_batt_liion":
		em_col = albedo
	elif em_energy <= 0.14:
		em_col = albedo

	mat.albedo_color = albedo
	mat.metallic = clampf(met, 0.15, 0.35)
	mat.roughness = clampf(rgh, 0.35, 0.55)
	mat.emission_enabled = true
	mat.emission = em_col
	mat.emission_energy_multiplier = em_energy

	var tex: Texture2D = _get_aerospace_texture(tex_key)
	if tex != null:
		mat.albedo_texture = tex
	if use_kapton_normal:
		var norm_tex: Texture2D = _get_aerospace_texture("kapton_normal")
		if norm_tex != null:
			mat.normal_enabled = true
			mat.normal_texture = norm_tex
			mat.normal_scale = 0.72
	return mat


static func _get_aerospace_texture(tex_key: String) -> Texture2D:
	if _tex_cache.has(tex_key):
		return _tex_cache[tex_key] as Texture2D

	var created: Texture2D = null
	match tex_key:
		"kapton_normal":
			if ResourceLoader.exists("res://assets/models/lander_bus_kapton_normal.png"):
				created = ResourceLoader.load("res://assets/models/lander_bus_kapton_normal.png") as Texture2D
		"dish_ao":
			if ResourceLoader.exists("res://assets/models/antenna_hga_dish_AO.webp"):
				created = ResourceLoader.load("res://assets/models/antenna_hga_dish_AO.webp") as Texture2D
		"sls_sofi":
			if ResourceLoader.exists("res://assets/models/sls_block1_sls_sofi.png"):
				created = ResourceLoader.load("res://assets/models/sls_block1_sls_sofi.png") as Texture2D
		"sls_srb":
			if ResourceLoader.exists("res://assets/models/sls_block1_srb_roll.png"):
				created = ResourceLoader.load("res://assets/models/sls_block1_srb_roll.png") as Texture2D
		"pv_grid":
			created = _create_pv_grid_texture()
		"kapton_foil":
			created = _create_kapton_foil_texture()
		"brushed":
			created = _create_brushed_metal_texture()
		"matte_panel":
			created = _create_matte_panel_texture()

	if created == null:
		var grad: Gradient = Gradient.new()
		grad.colors = PackedColorArray([Color(0.86, 0.88, 0.92, 1.0), Color(0.98, 0.99, 1.0, 1.0)])
		var gt: GradientTexture2D = GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 64
		gt.height = 64
		created = gt

	_tex_cache[tex_key] = created
	return created


static func _create_pv_grid_texture() -> ImageTexture:
	var sz: int = 128
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y: int in range(sz):
		for x: int in range(sz):
			var gx: int = x % 16
			var gy: int = y % 32
			var is_border: bool = (gx == 0 or gy == 0)
			var is_busbar: bool = (gx == 8)
			if is_border:
				img.set_pixel(x, y, Color(0.58, 0.68, 0.86, 1.0))
			elif is_busbar:
				img.set_pixel(x, y, Color(0.76, 0.84, 0.98, 1.0))
			else:
				var shimmer: float = 0.88 + 0.10 * sin(float(x + y) * 0.12)
				img.set_pixel(x, y, Color(shimmer, shimmer * 0.96, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


static func _create_kapton_foil_texture() -> ImageTexture:
	var sz: int = 64
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y: int in range(sz):
		for x: int in range(sz):
			var wave: float = sin(float(x) * 0.45 + cos(float(y) * 0.35) * 1.4) * 0.5 + 0.5
			var v: float = 0.84 + 0.16 * wave
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.90, 1.0))
	return ImageTexture.create_from_image(img)


static func _create_brushed_metal_texture() -> ImageTexture:
	var sz: int = 64
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y: int in range(sz):
		var streak: float = 0.86 + 0.14 * (0.5 + 0.5 * sin(float(y) * 1.7 + sin(float(y) * 0.6)))
		for x: int in range(sz):
			var micro: float = 0.96 + 0.04 * sin(float(x) * 0.25 + float(y) * 0.5)
			var v: float = clampf(streak * micro, 0.78, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)


static func _create_matte_panel_texture() -> ImageTexture:
	var sz: int = 64
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y: int in range(sz):
		for x: int in range(sz):
			var seam: bool = (x == 0 or y == 0 or x == 63 or y == 63)
			var v: float = 0.84 if seam else 0.96
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)


func get_active_slot_records() -> Array[Dictionary]:
	return _active_slot_records.duplicate(true)


func get_registered_mount_names() -> Array[String]:
	var names: Array[String] = []
	for key_var: Variant in _mounts_by_name.keys():
		names.append(str(key_var))
	return names
