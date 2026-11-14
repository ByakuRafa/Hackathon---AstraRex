extends Node

## Synchronous loader and validator for pre-hydrated NASA JSON datasets (SP-2016-6105, DE441, OSDR RadLab, LRO LOLA).
## Registered as the NasaDataLoader autoload singleton (single-threaded WebGL safe).

const PARTS_CATALOG_PATH: String = "res://data/nasa_parts_catalog.json"
const EPHEMERIS_PATH: String = "res://data/ephemeris_horizons.json"
const RADIATION_PATH: String = "res://data/radiation_radlab.json"
const TERRAIN_META_PATH: String = "res://data/shackleton_terrain_meta.json"

const REQUIRED_BASE_SUBSYSTEM_KEYS: Array[String] = [
	"id",
	"subsystem",
	"name",
	"mass_dry_kg",
	"mga_percent",
	"power_w",
	"cost_m_usd",
	"mount_point",
	"nasa_citation"
]

const REQUIRED_SI_EXTENSION_KEYS: Array[String] = [
	"thrust_n",
	"isp_s",
	"propellant_capacity_kg",
	"data_rate_gb_day",
	"data_rate_mbps",
	"science_points",
	"energy_capacity_kwh",
	"shielding_g_cm2",
	"max_safe_slope_deg",
	"radiation_tolerance_krad",
	"thermal_output_w"
]

var parts_catalog_raw: Dictionary = {}
var ephemeris_raw: Dictionary = {}
var radiation_raw: Dictionary = {}
var terrain_meta_raw: Dictionary = {}

var subsystems_by_id: Dictionary = {}
var subsystems_order: Array[String] = []
var launch_vehicles_by_id: Dictionary = {}
var launch_vehicles_order: Array[String] = []
var orbits_by_id: Dictionary = {}
var orbits_order: Array[String] = []
var presets_by_id: Dictionary = {}
var landing_zones_by_id: Dictionary = {}

var is_loaded: bool = false
var validation_errors: Array[String] = []


func _ready() -> void:
	load_all_datasets()


func load_all_datasets() -> bool:
	validation_errors.clear()
	subsystems_by_id.clear()
	subsystems_order.clear()
	launch_vehicles_by_id.clear()
	launch_vehicles_order.clear()
	orbits_by_id.clear()
	orbits_order.clear()
	presets_by_id.clear()
	landing_zones_by_id.clear()

	parts_catalog_raw = _load_json_dict(PARTS_CATALOG_PATH)
	ephemeris_raw = _load_json_dict(EPHEMERIS_PATH)
	radiation_raw = _load_json_dict(RADIATION_PATH)
	terrain_meta_raw = _load_json_dict(TERRAIN_META_PATH)

	var catalog_ok: bool = _validate_and_normalize_catalog()
	var ephemeris_ok: bool = _validate_ephemeris()
	var radiation_ok: bool = _validate_radiation()
	var terrain_ok: bool = _validate_terrain_meta()

	is_loaded = catalog_ok and ephemeris_ok and radiation_ok and terrain_ok
	if not is_loaded:
		push_error("NasaDataLoader: Dataset validation failed with %d error(s)." % validation_errors.size())
	return is_loaded


func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		var missing_msg: String = "NasaDataLoader: Missing required JSON file at '%s'." % path
		validation_errors.append(missing_msg)
		push_error(missing_msg)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err_code: int = FileAccess.get_open_error()
		var open_msg: String = "NasaDataLoader: Failed to open '%s' (error %d)." % [path, err_code]
		validation_errors.append(open_msg)
		push_error(open_msg)
		return {}

	var content: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		var parse_msg: String = "NasaDataLoader: Invalid JSON object root in '%s'." % path
		validation_errors.append(parse_msg)
		push_error(parse_msg)
		return {}

	return parsed as Dictionary


func _validate_and_normalize_catalog() -> bool:
	if parts_catalog_raw.is_empty():
		return false

	var ok: bool = true

	if not parts_catalog_raw.has("subsystems") or typeof(parts_catalog_raw.get("subsystems")) != TYPE_ARRAY:
		_record_error("NasaDataLoader: 'subsystems' array missing in '%s'." % PARTS_CATALOG_PATH)
		ok = false
	else:
		var raw_subsystems: Array = parts_catalog_raw.get("subsystems", []) as Array
		for raw_item: Variant in raw_subsystems:
			if typeof(raw_item) != TYPE_DICTIONARY:
				_record_error("NasaDataLoader: Non-dictionary entry found in 'subsystems'.")
				ok = false
				continue
			var item: Dictionary = (raw_item as Dictionary).duplicate(true)
			if not _validate_subsystem_item(item):
				ok = false
			var item_id: String = str(item.get("id", ""))
			if not item_id.is_empty():
				subsystems_by_id[item_id] = item
				subsystems_order.append(item_id)

	if not parts_catalog_raw.has("launch_vehicles") or typeof(parts_catalog_raw.get("launch_vehicles")) != TYPE_ARRAY:
		_record_error("NasaDataLoader: 'launch_vehicles' array missing in '%s'." % PARTS_CATALOG_PATH)
		ok = false
	else:
		var raw_launchers: Array = parts_catalog_raw.get("launch_vehicles", []) as Array
		for raw_lv: Variant in raw_launchers:
			if typeof(raw_lv) != TYPE_DICTIONARY:
				_record_error("NasaDataLoader: Non-dictionary entry found in 'launch_vehicles'.")
				ok = false
				continue
			var lv: Dictionary = (raw_lv as Dictionary).duplicate(true)
			if not _validate_required_keys(lv, ["id", "name", "cost_m_usd", "max_tli_payload_kg", "reliability", "nasa_citation"], "launch_vehicle"):
				ok = false
			var max_tli: float = float(lv.get("max_tli_payload_kg", 0.0))
			lv["max_tli_payload_kg"] = max_tli
			lv["max_tli_mass_kg"] = max_tli
			lv["cost_m_usd"] = float(lv.get("cost_m_usd", 0.0))
			lv["fairing_diameter_m"] = float(lv.get("fairing_diameter_m", 0.0))
			lv["reliability"] = float(lv.get("reliability", 0.98))
			var lv_id: String = str(lv.get("id", ""))
			if not lv_id.is_empty():
				launch_vehicles_by_id[lv_id] = lv
				launch_vehicles_order.append(lv_id)

	if not parts_catalog_raw.has("orbits") or typeof(parts_catalog_raw.get("orbits")) != TYPE_ARRAY:
		_record_error("NasaDataLoader: 'orbits' array missing in '%s'." % PARTS_CATALOG_PATH)
		ok = false
	else:
		var raw_orbits: Array = parts_catalog_raw.get("orbits", []) as Array
		for raw_orb: Variant in raw_orbits:
			if typeof(raw_orb) != TYPE_DICTIONARY:
				_record_error("NasaDataLoader: Non-dictionary entry found in 'orbits'.")
				ok = false
				continue
			var orb: Dictionary = (raw_orb as Dictionary).duplicate(true)
			if not _validate_required_keys(orb, ["id", "name", "delta_v_descent_m_s", "dte_visibility_percent", "nasa_citation"], "orbit"):
				ok = false
			var req_dv: float = float(orb.get("delta_v_descent_m_s", 1750.0))
			var dte_pct: float = float(orb.get("dte_visibility_percent", 50.0))
			orb["delta_v_descent_m_s"] = req_dv
			orb["required_dv_ms"] = req_dv
			orb["dte_visibility_percent"] = dte_pct
			orb["dte_visibility_pct"] = dte_pct
			orb["orbital_period_hours"] = float(orb.get("orbital_period_hours", 1.97))
			var orb_id: String = str(orb.get("id", ""))
			if not orb_id.is_empty():
				orbits_by_id[orb_id] = orb
				orbits_order.append(orb_id)

	if not parts_catalog_raw.has("presets_for_judges") or typeof(parts_catalog_raw.get("presets_for_judges")) != TYPE_DICTIONARY:
		_record_error("NasaDataLoader: 'presets_for_judges' dictionary missing in '%s'." % PARTS_CATALOG_PATH)
		ok = false
	else:
		var raw_presets: Dictionary = parts_catalog_raw.get("presets_for_judges", {}) as Dictionary
		for preset_key_var: Variant in raw_presets.keys():
			var preset_key: String = str(preset_key_var)
			var raw_ids: Variant = raw_presets.get(preset_key)
			if typeof(raw_ids) != TYPE_ARRAY:
				_record_error("NasaDataLoader: Preset '%s' is not an array." % preset_key)
				ok = false
				continue
			var typed_ids: Array[String] = []
			for id_var: Variant in (raw_ids as Array):
				var part_id: String = str(id_var)
				if not subsystems_by_id.has(part_id):
					_record_error("NasaDataLoader: Preset '%s' references unknown subsystem '%s'." % [preset_key, part_id])
					ok = false
				typed_ids.append(part_id)
			presets_by_id[preset_key] = typed_ids

	return ok


func _validate_subsystem_item(item: Dictionary) -> bool:
	var ok: bool = _validate_required_keys(item, REQUIRED_BASE_SUBSYSTEM_KEYS, "subsystem")
	var category: String = str(item.get("subsystem", ""))
	var item_id: String = str(item.get("id", "<unknown>"))

	match category:
		"propulsion":
			if not _validate_required_keys(item, ["thrust_n", "isp_s", "propellant_capacity_kg"], "propulsion(%s)" % item_id):
				ok = false
		"payload":
			if not _validate_required_keys(item, ["data_rate_gb_day", "science_points"], "payload(%s)" % item_id):
				ok = false
		"comms":
			if not _validate_required_keys(item, ["data_rate_mbps"], "comms(%s)" % item_id):
				ok = false
		"shielding":
			if not _validate_required_keys(item, ["shielding_g_cm2"], "shielding(%s)" % item_id):
				ok = false

	item["mass_dry_kg"] = float(item.get("mass_dry_kg", 0.0))
	item["mga_percent"] = float(item.get("mga_percent", 0.15))
	item["power_w"] = float(item.get("power_w", 0.0))
	item["cost_m_usd"] = float(item.get("cost_m_usd", 0.0))

	for ext_key: String in REQUIRED_SI_EXTENSION_KEYS:
		item[ext_key] = float(item.get(ext_key, 0.0))

	if not item.has("requires_sunlight"):
		item["requires_sunlight"] = false
	else:
		item["requires_sunlight"] = bool(item.get("requires_sunlight", false))

	return ok


func _validate_ephemeris() -> bool:
	if ephemeris_raw.is_empty():
		return false
	if not ephemeris_raw.has("bodies") or typeof(ephemeris_raw.get("bodies")) != TYPE_DICTIONARY:
		_record_error("NasaDataLoader: 'bodies' dictionary missing in '%s'." % EPHEMERIS_PATH)
		return false
	var bodies: Dictionary = ephemeris_raw.get("bodies", {}) as Dictionary
	var required_bodies: Array[String] = ["moon_from_earth_301", "sun_from_moon_10", "earth_from_moon_399"]
	var ok: bool = true
	for body_key: String in required_bodies:
		if not bodies.has(body_key) or typeof(bodies.get(body_key)) != TYPE_ARRAY:
			_record_error("NasaDataLoader: Ephemeris series '%s' missing in '%s'." % [body_key, EPHEMERIS_PATH])
			ok = false
		else:
			var series: Array = bodies.get(body_key, []) as Array
			if series.is_empty():
				_record_error("NasaDataLoader: Ephemeris series '%s' is empty." % body_key)
				ok = false
	return ok


func _validate_radiation() -> bool:
	if radiation_raw.is_empty():
		return false
	var ok: bool = true
	if not radiation_raw.has("metadata") or typeof(radiation_raw.get("metadata")) != TYPE_DICTIONARY:
		_record_error("NasaDataLoader: 'metadata' missing in '%s'." % RADIATION_PATH)
		ok = false
	if not radiation_raw.has("environments") or typeof(radiation_raw.get("environments")) != TYPE_DICTIONARY:
		_record_error("NasaDataLoader: 'environments' missing in '%s'." % RADIATION_PATH)
		return false
	var envs: Dictionary = radiation_raw.get("environments", {}) as Dictionary
	if not envs.has("cislunar_transit") or not envs.has("lunar_south_pole_surface"):
		_record_error("NasaDataLoader: Missing required radiation environments in '%s'." % RADIATION_PATH)
		ok = false
	return ok


func _validate_terrain_meta() -> bool:
	if terrain_meta_raw.is_empty():
		return false
	var ok: bool = true
	if not terrain_meta_raw.has("metadata") or not terrain_meta_raw.has("dem_bounds") or not terrain_meta_raw.has("landing_zones"):
		_record_error("NasaDataLoader: Missing required terrain sections in '%s'." % TERRAIN_META_PATH)
		return false
	var raw_zones: Variant = terrain_meta_raw.get("landing_zones", {})
	if typeof(raw_zones) != TYPE_DICTIONARY or (raw_zones as Dictionary).is_empty():
		_record_error("NasaDataLoader: 'landing_zones' dictionary missing or empty in '%s'." % TERRAIN_META_PATH)
		return false
	var zones_dict: Dictionary = raw_zones as Dictionary
	for zone_key_var: Variant in zones_dict.keys():
		var zone_key: String = str(zone_key_var)
		var zone_val: Variant = zones_dict.get(zone_key)
		if typeof(zone_val) == TYPE_DICTIONARY:
			var zone: Dictionary = (zone_val as Dictionary).duplicate(true)
			zone["id"] = zone_key
			landing_zones_by_id[zone_key] = zone
		else:
			ok = false
	return ok


func _validate_required_keys(dict: Dictionary, required_keys: Array[String], context_label: String) -> bool:
	var all_present: bool = true
	for key: String in required_keys:
		if not dict.has(key):
			_record_error("NasaDataLoader: Missing mandatory key '%s' in %s." % [key, context_label])
			all_present = false
	return all_present


func _record_error(msg: String) -> void:
	validation_errors.append(msg)
	push_error(msg)


func get_subsystem(id: String) -> Dictionary:
	if subsystems_by_id.has(id):
		return (subsystems_by_id[id] as Dictionary).duplicate(true)
	push_warning("NasaDataLoader: Unknown subsystem id '%s'." % id)
	return {}


func get_all_subsystems() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id: String in subsystems_order:
		result.append((subsystems_by_id[item_id] as Dictionary).duplicate(true))
	return result


func get_subsystems_by_slot(slot_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normalized: String = slot_name.strip_edges().to_lower()
	for item_id: String in subsystems_order:
		var item: Dictionary = subsystems_by_id[item_id] as Dictionary
		var mount_point: String = str(item.get("mount_point", ""))
		var category: String = str(item.get("subsystem", ""))
		if mount_point == slot_name or mount_point.to_lower() == normalized or category.to_lower() == normalized:
			result.append(item.duplicate(true))
	return result


func get_subsystems_by_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normalized: String = category.strip_edges().to_lower()
	for item_id: String in subsystems_order:
		var item: Dictionary = subsystems_by_id[item_id] as Dictionary
		if str(item.get("subsystem", "")).to_lower() == normalized:
			result.append(item.duplicate(true))
	return result


func get_launch_vehicle(id: String) -> Dictionary:
	if launch_vehicles_by_id.has(id):
		return (launch_vehicles_by_id[id] as Dictionary).duplicate(true)
	push_warning("NasaDataLoader: Unknown launch vehicle id '%s'." % id)
	return {}


func get_all_launch_vehicles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lv_id: String in launch_vehicles_order:
		result.append((launch_vehicles_by_id[lv_id] as Dictionary).duplicate(true))
	return result


func get_orbit(id: String) -> Dictionary:
	if orbits_by_id.has(id):
		return (orbits_by_id[id] as Dictionary).duplicate(true)
	push_warning("NasaDataLoader: Unknown orbit id '%s'." % id)
	return {}


func get_all_orbits() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for orb_id: String in orbits_order:
		result.append((orbits_by_id[orb_id] as Dictionary).duplicate(true))
	return result


func resolve_preset_key(preset_id: String) -> String:
	var key: String = preset_id.strip_edges()
	if presets_by_id.has(key):
		return key
	match key.to_lower():
		"1", "preset_1", "artemis", "optimal":
			return "preset_1_artemis_optimal"
		"2", "preset_2", "failure", "mass_failure":
			return "preset_2_mass_failure"
		"3", "preset_3", "sandbox":
			return "preset_3_sandbox"
	return key


func get_preset_part_ids(preset_id: String) -> Array[String]:
	var resolved_key: String = resolve_preset_key(preset_id)
	if presets_by_id.has(resolved_key):
		return (presets_by_id[resolved_key] as Array[String]).duplicate()
	push_warning("NasaDataLoader: Unknown preset '%s'." % preset_id)
	return []


func get_preset(preset_id: String) -> Dictionary:
	var resolved_key: String = resolve_preset_key(preset_id)
	if not presets_by_id.has(resolved_key):
		push_warning("NasaDataLoader: Unknown preset '%s'." % preset_id)
		return {}

	var part_ids: Array[String] = get_preset_part_ids(resolved_key)
	var parts: Array[Dictionary] = []
	for part_id: String in part_ids:
		var part_data: Dictionary = get_subsystem(part_id)
		if not part_data.is_empty():
			parts.append(part_data)

	var launch_vehicle_id: String = "falcon_9_clps"
	var orbit_id: String = "orbit_llo_polar"
	var landing_zone_id: String = "connecting_ridge_rim"
	var label: String = "Preset"
	var sandbox_unlocked: bool = false

	match resolved_key:
		"preset_1_artemis_optimal":
			label = "Preset 1: Optimal Artemis CLPS"
			launch_vehicle_id = "falcon_9_clps"
			orbit_id = "orbit_llo_polar"
			landing_zone_id = "connecting_ridge_rim"
		"preset_2_mass_failure":
			label = "Preset 2: Critical Thrust & PSR Failure"
			launch_vehicle_id = "falcon_9_clps"
			orbit_id = "orbit_llo_polar"
			landing_zone_id = "crater_floor_psr"
		"preset_3_sandbox":
			label = "Preset 3: VAB Free Sandbox"
			launch_vehicle_id = "sls_block1"
			orbit_id = "orbit_nrho_gateway"
			landing_zone_id = "connecting_ridge_rim"
			sandbox_unlocked = true

	return {
		"id": resolved_key,
		"label": label,
		"subsystem_ids": part_ids,
		"subsystems": parts,
		"launch_vehicle_id": launch_vehicle_id,
		"orbit_id": orbit_id,
		"landing_zone_id": landing_zone_id,
		"sandbox_unlocked": sandbox_unlocked
	}


func get_ephemeris_body_series(body_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bodies: Dictionary = ephemeris_raw.get("bodies", {}) as Dictionary
	if not bodies.has(body_key):
		return result
	var raw_series: Array = bodies.get(body_key, []) as Array
	for entry_var: Variant in raw_series:
		if typeof(entry_var) == TYPE_DICTIONARY:
			result.append((entry_var as Dictionary).duplicate(true))
	return result


func get_ephemeris_citation() -> String:
	var meta: Dictionary = ephemeris_raw.get("metadata", {}) as Dictionary
	return str(meta.get("nasa_citation", "JPL Horizons On-Line Ephemeris System (DE441)"))


func get_sun_vector_km(epoch_index: int = 0) -> Vector3:
	return _extract_position_km("sun_from_moon_10", epoch_index)


func get_sun_direction_unit(epoch_index: int = 0) -> Vector3:
	var vec: Vector3 = get_sun_vector_km(epoch_index)
	if vec.is_zero_approx():
		return Vector3(0.0, 0.026, -0.999).normalized()
	return vec.normalized()


func get_earth_vector_km(epoch_index: int = 0) -> Vector3:
	return _extract_position_km("earth_from_moon_399", epoch_index)


func get_earth_direction_unit(epoch_index: int = 0) -> Vector3:
	var vec: Vector3 = get_earth_vector_km(epoch_index)
	if vec.is_zero_approx():
		return Vector3(0.0, 0.15, 0.988).normalized()
	return vec.normalized()


func _extract_position_km(body_key: String, epoch_index: int) -> Vector3:
	var series: Array[Dictionary] = get_ephemeris_body_series(body_key)
	if series.is_empty():
		return Vector3.ZERO
	var clamped_idx: int = clampi(epoch_index, 0, series.size() - 1)
	var sample: Dictionary = series[clamped_idx]
	var pos: Dictionary = sample.get("position_km", {}) as Dictionary
	# Map ICRF (X, Y, Z) into Godot right-handed (+Y up) celestial frame: X=x, Y=z, Z=-y
	var x_km: float = float(pos.get("x", 0.0))
	var y_km: float = float(pos.get("z", 0.0))
	var z_km: float = -float(pos.get("y", 0.0))
	return Vector3(x_km, y_km, z_km)


func get_radiation_environment(env_key: String) -> Dictionary:
	var envs: Dictionary = radiation_raw.get("environments", {}) as Dictionary
	if envs.has(env_key):
		return (envs[env_key] as Dictionary).duplicate(true)
	if env_key == "low_lunar_orbit" and envs.has("lunar_south_pole_surface"):
		return (envs["lunar_south_pole_surface"] as Dictionary).duplicate(true)
	return {}


func get_mission_dose_limit_msv() -> float:
	var meta: Dictionary = radiation_raw.get("metadata", {}) as Dictionary
	return float(meta.get("mission_dose_limit_msv", 100.0))


func get_radiation_citation() -> String:
	var meta: Dictionary = radiation_raw.get("metadata", {}) as Dictionary
	return str(meta.get("nasa_citation", "NASA OSDR RadLab & LRO CRaTER Lunar Radiation Environment"))


func get_terrain_metadata() -> Dictionary:
	return (terrain_meta_raw.get("metadata", {}) as Dictionary).duplicate(true)


func get_terrain_bounds() -> Dictionary:
	return (terrain_meta_raw.get("dem_bounds", {}) as Dictionary).duplicate(true)


func get_landing_zone(zone_id: String) -> Dictionary:
	if landing_zones_by_id.has(zone_id):
		return (landing_zones_by_id[zone_id] as Dictionary).duplicate(true)
	return {}


func get_all_landing_zones() -> Dictionary:
	return landing_zones_by_id.duplicate(true)


func get_catalog_citation() -> String:
	var meta: Dictionary = parts_catalog_raw.get("metadata", {}) as Dictionary
	return str(meta.get("reference", "NASA Systems Engineering Handbook (NASA SP-2016-6105 Rev2)"))
