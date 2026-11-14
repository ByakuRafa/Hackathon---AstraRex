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
	"pwr_solar_lro": Vector3(-0.04, 0.12, 0.0),
	"pwr_rtg_mmrtg": Vector3(-0.24, -0.12, 0.0),
	"pwr_batt_liion": Vector3(0.22, -0.08, 0.0),
	"comm_hga_ka": Vector3(0.0, 0.02, 0.0),
	"comm_uga_s": Vector3(0.0, 0.0, 0.0),
	"obc_adcs_radhard": Vector3(-0.34, 0.0, 0.05),
	"obc_adcs_cots": Vector3(-0.34, 0.0, 0.05),
	"avionics_lidar_trn": Vector3(0.34, -0.18, 0.42),
	"pay_drill_trident": Vector3(0.22, -0.06, 0.16),
	"pay_spec_msolo": Vector3(-0.16, -0.04, 0.16),
	"pay_sar_lband": Vector3(0.08, 0.0, 0.0),
	"shield_heavy": Vector3(0.0, 0.0, -0.06)
}

const PART_LOCAL_ROTATIONS_DEG: Dictionary = {
	"prop_chem_biprop": Vector3(0.0, 0.0, 0.0),
	"prop_ion_sep": Vector3(0.0, 0.0, 0.0),
	"pwr_solar_lro": Vector3(28.0, 0.0, -12.0),
	"pwr_rtg_mmrtg": Vector3(0.0, 0.0, 38.0),
	"pwr_batt_liion": Vector3(0.0, 0.0, 0.0),
	"comm_hga_ka": Vector3(-18.0, 0.0, 0.0),
	"comm_uga_s": Vector3(0.0, 0.0, 0.0),
	"obc_adcs_radhard": Vector3(0.0, 160.0, 0.0),
	"obc_adcs_cots": Vector3(0.0, 160.0, 0.0),
	"avionics_lidar_trn": Vector3(-32.0, 180.0, 0.0),
	"pay_drill_trident": Vector3(0.0, -35.0, 0.0),
	"pay_spec_msolo": Vector3(0.0, 140.0, 0.0),
	"pay_sar_lband": Vector3(0.0, -25.0, 0.0),
	"shield_heavy": Vector3(90.0, 0.0, 0.0)
}

const PART_LOCAL_SCALES: Dictionary = {
	"prop_chem_biprop": Vector3(0.44, 0.44, 0.44),
	"prop_ion_sep": Vector3(0.80, 0.80, 0.80),
	"pwr_solar_lro": Vector3(0.52, 0.52, 0.52),
	"pwr_rtg_mmrtg": Vector3(0.44, 0.44, 0.44),
	"pwr_batt_liion": Vector3(0.46, 0.46, 0.46),
	"comm_hga_ka": Vector3(0.58, 0.58, 0.58),
	"comm_uga_s": Vector3(0.85, 0.85, 0.85),
	"obc_adcs_radhard": Vector3(0.52, 0.52, 0.52),
	"obc_adcs_cots": Vector3(0.52, 0.52, 0.52),
	"avionics_lidar_trn": Vector3(0.52, 0.52, 0.52),
	"pay_drill_trident": Vector3(0.55, 0.55, 0.55),
	"pay_spec_msolo": Vector3(0.58, 0.58, 0.58),
	"pay_sar_lband": Vector3(0.45, 0.45, 0.45),
	"shield_heavy": Vector3(0.52, 0.26, 0.52)
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


func _ready() -> void:
	_register_mounts()
	_enforce_double_sided_materials(self)
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
	_enforce_double_sided_materials(node_3d)
	mount_node.add_child(node_3d)
	_instanced_parts[part_id] = node_3d
	return node_3d


func _enforce_double_sided_materials(root_node: Node) -> void:
	if not is_instance_valid(root_node):
		return
	if root_node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = root_node as MeshInstance3D
		if mesh_inst.material_override is BaseMaterial3D:
			(mesh_inst.material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		if mesh_inst.mesh != null:
			var surf_count: int = mesh_inst.mesh.get_surface_count()
			for surf_idx: int in range(surf_count):
				var override_mat: Material = mesh_inst.get_surface_override_material(surf_idx)
				if override_mat is BaseMaterial3D:
					(override_mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
				var surf_mat: Material = mesh_inst.mesh.surface_get_material(surf_idx)
				if surf_mat is BaseMaterial3D:
					(surf_mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	for child: Node in root_node.get_children():
		_enforce_double_sided_materials(child)


func get_active_slot_records() -> Array[Dictionary]:
	return _active_slot_records.duplicate(true)


func get_registered_mount_names() -> Array[String]:
	var names: Array[String] = []
	for key_var: Variant in _mounts_by_name.keys():
		names.append(str(key_var))
	return names
