extends Node

## Authoritative SI Physics Engine & Mission State Singleton.
## Implements NASA SP-2016-6105 Rev2 MGA, Tsiolkovsky Rocket Equation, Lunar T/W Lockout,
## Solar/RTG Power Balance, DSN Link Budget, and OSDR RadLab Radiation Lifetime.

signal state_updated(telemetry: Dictionary)
signal preset_loaded(preset_index: int, preset_name: String)
signal simulation_alert(alert_code: String, message: String, citation: String)

enum TeamRole {
	PLANNER = 0,
	PROPULSION_GNC = 1,
	SCIENCE = 2,
	COMMS_POWER = 3
}

const G0_M_S2: float = 9.80665
const LUNAR_GRAVITY_M_S2: float = 1.625
const DEFAULT_BUDGET_CAP_MUSD: float = 350.0
const SANDBOX_BUDGET_CAP_MUSD: float = 5000.0
const BASE_BUS_SHIELDING_G_CM2: float = 2.0
const BASE_BUS_BATTERY_WH: float = 1500.0
const MAX_SAFE_SLOPE_DEG: float = 15.0
const TRANSIT_DURATION_DAYS: float = 5.0
const LUNAR_DAY_DURATION_DAYS: float = 14.0
const PSR_BATTERY_SURVIVAL_DAYS: float = 1.5
const NOMINAL_MAX_LIFETIME_DAYS: float = 180.0
const MBPS_TO_GB_PER_DAY: float = 10.8
const RESIDUAL_PROPELLANT_FRACTION: float = 0.0

# Modes & Collaboration
var current_preset_index: int = 1
var engineer_mode: bool = false
var sandbox_mode: bool = false
var team_size: int = 1
var active_role: TeamRole = TeamRole.PLANNER
var assigned_roles: Array[int] = [TeamRole.PLANNER]

# Mission Architecture Selections
var selected_objective: String = "Shackleton South Pole Water-Ice Prospecting"
var selected_launch_vehicle_id: String = "falcon_9_clps"
var selected_orbit_id: String = "orbit_llo_polar"
var selected_landing_zone_id: String = "connecting_ridge_rim"
var selected_subsystem_ids: Array[String] = []
var selected_subsystems: Array[Dictionary] = []
var budget_cap_musd: float = DEFAULT_BUDGET_CAP_MUSD

# Dynamic Environmental & Phase 3 Simulation Conditions
var ephemeris_epoch_index: int = 0
var solar_incidence_deg: float = 15.0
var in_psr_shadow: bool = false
var dte_occluded: bool = false
var spe_storm_active: bool = false
var spe_storm_hours: float = 0.0
var safe_mode_active: bool = false
var last_touchdown_slope_deg: float = 7.5
var mission_failure_code: String = "NONE"

# Cached SI Resource Values
var dry_mass_nominal_kg: float = 0.0
var mga_mass_kg: float = 0.0
var mf_dry_kg: float = 0.0
var propellant_mass_kg: float = 0.0
var m0_wet_kg: float = 0.0

var total_thrust_n: float = 0.0
var effective_isp_s: float = 0.0
var delta_v_ms: float = 0.0
var required_dv_ms: float = 1750.0
var lunar_weight_n: float = 0.0
var lunar_tw_ratio: float = 0.0

var power_generated_w: float = 0.0
var power_consumed_w: float = 0.0
var power_peak_consumed_w: float = 0.0
var net_power_w: float = 0.0
var net_power_peak_w: float = 0.0
var battery_wh: float = BASE_BUS_BATTERY_WH
var thermal_output_w: float = 0.0

var subsystems_cost_musd: float = 0.0
var launch_vehicle_cost_musd: float = 0.0
var total_cost_musd: float = 0.0

var science_points_base: float = 0.0
var science_points_effective: float = 0.0
var data_generated_gb_day: float = 0.0
var downlink_mbps: float = 0.0
var dte_visibility_pct: float = 50.0
var downlink_capacity_gb_day: float = 0.0
var data_backlog_gb_day: float = 0.0

var shielding_g_cm2: float = BASE_BUS_SHIELDING_G_CM2
var daily_gcr_msv: float = 0.0
var spe_dose_msv: float = 0.0
var total_mission_dose_msv: float = 0.0
var radiation_tolerance_krad: float = 15.0
var mission_lifetime_days: float = 0.0
var theoretical_lifetime_days: float = 0.0

# Terrain & Hazard Derived Flags
var can_land_lunar: bool = false
var has_sufficient_dv: bool = false
var has_lidar_trn: bool = false
var has_rad_shielding: bool = false
var has_rtg: bool = false
var has_solar_array: bool = false
var has_cryo_battery: bool = false
var has_radhard_obc: bool = false
var can_survive_lunar_night: bool = false
var can_survive_slope_hazard: bool = false

var telemetry: Dictionary = {}


func _ready() -> void:
	if NasaDataLoader != null and not NasaDataLoader.is_loaded:
		NasaDataLoader.load_all_datasets()
	apply_preset(1)


func apply_preset(preset_index: int) -> void:
	current_preset_index = clampi(preset_index, 1, 3)
	var preset_data: Dictionary = NasaDataLoader.get_preset(str(current_preset_index))
	if preset_data.is_empty():
		push_error("MissionState: Failed to load preset %d from NasaDataLoader." % current_preset_index)
		return

	sandbox_mode = bool(preset_data.get("sandbox_unlocked", false))
	budget_cap_musd = SANDBOX_BUDGET_CAP_MUSD if sandbox_mode else DEFAULT_BUDGET_CAP_MUSD
	selected_launch_vehicle_id = str(preset_data.get("launch_vehicle_id", "falcon_9_clps"))
	selected_orbit_id = str(preset_data.get("orbit_id", "orbit_llo_polar"))
	selected_landing_zone_id = str(preset_data.get("landing_zone_id", "connecting_ridge_rim"))

	var raw_ids: Array = preset_data.get("subsystem_ids", []) as Array
	var typed_ids: Array[String] = []
	for id_var: Variant in raw_ids:
		typed_ids.append(str(id_var))

	selected_subsystem_ids = typed_ids
	_sync_selected_subsystems()

	# Reset transient Phase 3 simulation perturbations on preset switch
	spe_storm_active = false
	spe_storm_hours = 0.0
	safe_mode_active = false
	dte_occluded = false
	var zone: Dictionary = NasaDataLoader.get_landing_zone(selected_landing_zone_id)
	var zone_solar_pct: float = float(zone.get("solar_illumination_percent", 82.0))
	in_psr_shadow = zone_solar_pct <= 0.1
	last_touchdown_slope_deg = float(zone.get("mean_slope_deg", 7.5))
	solar_incidence_deg = 15.0

	recalculate_all_telemetry(true)
	preset_loaded.emit(current_preset_index, str(preset_data.get("label", "Preset %d" % current_preset_index)))


func set_engineer_mode(enabled: bool) -> void:
	engineer_mode = enabled
	recalculate_all_telemetry(false)


func set_team_size(count: int) -> void:
	team_size = clampi(count, 1, 4)
	assigned_roles.clear()
	for i: int in range(team_size):
		assigned_roles.append(i)
	if int(active_role) >= team_size:
		active_role = TeamRole.PLANNER
	recalculate_all_telemetry(false)


func set_active_role(role: int) -> void:
	var clamped: int = clampi(role, TeamRole.PLANNER, TeamRole.COMMS_POWER)
	active_role = clamped as TeamRole
	recalculate_all_telemetry(false)


func get_role_label(role: int) -> String:
	match role:
		TeamRole.PLANNER:
			return "Mission Planner / Launch & Orbit"
		TeamRole.PROPULSION_GNC:
			return "Propulsion & GNC Engineer"
		TeamRole.SCIENCE:
			return "Science Director / Payloads"
		TeamRole.COMMS_POWER:
			return "Comms, Power & Shielding Engineer"
	return "Mission Specialist"


func set_launch_vehicle(lv_id: String) -> void:
	if not NasaDataLoader.get_launch_vehicle(lv_id).is_empty():
		selected_launch_vehicle_id = lv_id
		recalculate_all_telemetry(true)


func set_orbit(orbit_id: String) -> void:
	if not NasaDataLoader.get_orbit(orbit_id).is_empty():
		selected_orbit_id = orbit_id
		recalculate_all_telemetry(true)


func set_landing_zone(zone_id: String) -> void:
	var zone: Dictionary = NasaDataLoader.get_landing_zone(zone_id)
	if not zone.is_empty():
		selected_landing_zone_id = zone_id
		in_psr_shadow = float(zone.get("solar_illumination_percent", 82.0)) <= 0.1
		last_touchdown_slope_deg = float(zone.get("mean_slope_deg", 7.5))
		recalculate_all_telemetry(true)


func set_selected_subsystems(part_ids: Array[String]) -> void:
	var unique_ids: Array[String] = []
	for pid: String in part_ids:
		if not unique_ids.has(pid) and not NasaDataLoader.get_subsystem(pid).is_empty():
			unique_ids.append(pid)
	if not unique_ids.has("chassis_clps"):
		unique_ids.push_front("chassis_clps")
	selected_subsystem_ids = unique_ids
	_sync_selected_subsystems()
	recalculate_all_telemetry(true)


func equip_subsystem(part_id: String) -> void:
	var part_data: Dictionary = NasaDataLoader.get_subsystem(part_id)
	if part_data.is_empty():
		return

	var category: String = str(part_data.get("subsystem", ""))
	var mount_point: String = str(part_data.get("mount_point", ""))

	# Single-slot categories replace previous mutually-exclusive part at same mount/category
	if category == "propulsion" or category == "comms":
		_remove_by_category(category)
	elif mount_point == "Mount_Power_Port":
		_remove_by_mount_point("Mount_Power_Port")
	elif part_id == "obc_adcs_radhard" or part_id == "obc_adcs_cots":
		selected_subsystem_ids.erase("obc_adcs_radhard")
		selected_subsystem_ids.erase("obc_adcs_cots")

	if not selected_subsystem_ids.has(part_id):
		selected_subsystem_ids.append(part_id)

	_sync_selected_subsystems()
	recalculate_all_telemetry(true)


func remove_subsystem(part_id: String) -> void:
	if part_id == "chassis_clps":
		return
	if selected_subsystem_ids.has(part_id):
		selected_subsystem_ids.erase(part_id)
		_sync_selected_subsystems()
		recalculate_all_telemetry(true)


func toggle_subsystem(part_id: String) -> void:
	if selected_subsystem_ids.has(part_id):
		remove_subsystem(part_id)
	else:
		equip_subsystem(part_id)


func _remove_by_category(category: String) -> void:
	var kept: Array[String] = []
	for pid: String in selected_subsystem_ids:
		var part: Dictionary = NasaDataLoader.get_subsystem(pid)
		if str(part.get("subsystem", "")) != category:
			kept.append(pid)
	selected_subsystem_ids = kept


func _remove_by_mount_point(mount_point: String) -> void:
	var kept: Array[String] = []
	for pid: String in selected_subsystem_ids:
		var part: Dictionary = NasaDataLoader.get_subsystem(pid)
		if str(part.get("mount_point", "")) != mount_point:
			kept.append(pid)
	selected_subsystem_ids = kept


func _sync_selected_subsystems() -> void:
	selected_subsystems.clear()
	for pid: String in selected_subsystem_ids:
		var part: Dictionary = NasaDataLoader.get_subsystem(pid)
		if not part.is_empty():
			selected_subsystems.append(part)


func set_solar_environment(shadowed: bool, incidence_deg: float) -> void:
	in_psr_shadow = shadowed
	solar_incidence_deg = clampf(incidence_deg, 0.0, 90.0)
	recalculate_all_telemetry(true)


func set_dte_occluded(occluded: bool) -> void:
	dte_occluded = occluded
	recalculate_all_telemetry(true)


func trigger_spe_storm(duration_hours: float, engage_safe_mode: bool = false) -> void:
	spe_storm_active = duration_hours > 0.0
	spe_storm_hours = maxf(0.0, duration_hours)
	safe_mode_active = engage_safe_mode
	recalculate_all_telemetry(true)


func clear_spe_storm() -> void:
	spe_storm_active = false
	spe_storm_hours = 0.0
	safe_mode_active = false
	recalculate_all_telemetry(false)


func record_touchdown_slope(slope_deg: float) -> void:
	last_touchdown_slope_deg = maxf(0.0, slope_deg)
	recalculate_all_telemetry(true)


func calculate_total_dry_mass() -> float:
	var total_dry: float = 0.0
	for part: Dictionary in selected_subsystems:
		var base_mass: float = float(part.get("mass_dry_kg", 0.0))
		var mga: float = float(part.get("mga_percent", 0.15))
		total_dry += base_mass * (1.0 + mga)
	return total_dry


func calculate_wet_mass() -> float:
	var total_propellant: float = 0.0
	for part: Dictionary in selected_subsystems:
		total_propellant += float(part.get("propellant_capacity_kg", 0.0))
	return calculate_total_dry_mass() + total_propellant


func calculate_burnout_mass() -> float:
	var total_propellant: float = 0.0
	for part: Dictionary in selected_subsystems:
		total_propellant += float(part.get("propellant_capacity_kg", 0.0))
	return calculate_total_dry_mass() + (total_propellant * RESIDUAL_PROPELLANT_FRACTION)


func calculate_delta_v() -> float:
	var m0: float = calculate_wet_mass()
	var mf: float = calculate_burnout_mass()
	if mf <= 0.0 or m0 <= mf or effective_isp_s <= 0.0:
		return 0.0
	return effective_isp_s * G0_M_S2 * log(m0 / mf)


func calculate_lunar_tw_ratio() -> float:
	var m0: float = calculate_wet_mass()
	if m0 <= 0.0:
		return 0.0
	var lunar_weight: float = m0 * LUNAR_GRAVITY_M_S2
	return total_thrust_n / lunar_weight


func can_safely_land_on_moon() -> Dictionary:
	var tw: float = calculate_lunar_tw_ratio()
	var dv: float = calculate_delta_v()
	var orbit: Dictionary = NasaDataLoader.get_orbit(selected_orbit_id)
	var orbit_req_dv: float = float(orbit.get("required_dv_ms", 1750.0))

	if total_thrust_n <= 0.0:
		return {
			"can_land": false,
			"reason": "NO_PROPULSION_MODULE",
			"message": "No propulsion subsystem attached. Attach a high-thrust descent engine for lunar landing.",
			"citation": "NASA SP-2016-6105 Rev2 Sec 4.4"
		}
	if tw < 1.0:
		return {
			"can_land": false,
			"reason": "CRITICAL_THRUST_DEFICIT",
			"message": "Lunar T/W is %.4f (< 1.0). Engine thrust (%.2f N) cannot overcome lunar weight (%.1f N). Soft landing physically impossible." % [tw, total_thrust_n, m0_wet_kg * LUNAR_GRAVITY_M_S2],
			"citation": "NASA SP-2016-6105 Rev2 Sec 4.4 & 6.1"
		}
	if dv < orbit_req_dv:
		return {
			"can_land": false,
			"reason": "PROPELLANT_DV_SHORTFALL",
			"message": "Available Delta-V is %.1f m/s (< %.1f m/s required for %s). Propellant exhausted prior to touchdown." % [dv, orbit_req_dv, str(orbit.get("name", selected_orbit_id))],
			"citation": "NASA SP-2016-6105 Rev2 Sec 4.2"
		}
	return {
		"can_land": true,
		"reason": "NOMINAL",
		"tw_ratio": tw,
		"margin_dv_ms": dv - orbit_req_dv,
		"citation": "NASA SP-2016-6105 Rev2 Sec 4.4"
	}


func validate_launch_compatibility() -> Dictionary:
	var lv: Dictionary = NasaDataLoader.get_launch_vehicle(selected_launch_vehicle_id)
	var orbit: Dictionary = NasaDataLoader.get_orbit(selected_orbit_id)
	var max_tli_kg: float = float(lv.get("max_tli_mass_kg", 0.0))
	var orbit_req_dv: float = float(orbit.get("required_dv_ms", 1750.0))

	var reasons: Array[String] = []
	var mass_ok: bool = m0_wet_kg <= max_tli_kg and max_tli_kg > 0.0
	var dv_ok: bool = delta_v_ms >= orbit_req_dv
	var tw_ok: bool = lunar_tw_ratio >= 1.0
	var budget_ok: bool = total_cost_musd <= budget_cap_musd or sandbox_mode

	if not mass_ok:
		reasons.append("Wet mass %.1f kg exceeds %s TLI capability (%.1f kg)." % [m0_wet_kg, str(lv.get("name", selected_launch_vehicle_id)), max_tli_kg])
	if not tw_ok:
		reasons.append("Lunar T/W ratio %.4f < 1.0 (CRITICAL_THRUST_DEFICIT): cannot decelerate against g_moon = 1.625 m/s^2." % lunar_tw_ratio)
	if not dv_ok:
		reasons.append("Propulsion Delta-V %.1f m/s is below required %.1f m/s for %s." % [delta_v_ms, orbit_req_dv, str(orbit.get("name", selected_orbit_id))])
	if not budget_ok:
		reasons.append("Total mission cost %.1f M$ exceeds budget cap %.1f M$." % [total_cost_musd, budget_cap_musd])

	var passed: bool = mass_ok and dv_ok and tw_ok and budget_ok
	if passed:
		reasons.append("Launcher TLI capacity (%.1f kg margin), orbital Delta-V (%.1f m/s margin), and lunar T/W (%.2f) validated." % [max_tli_kg - m0_wet_kg, delta_v_ms - orbit_req_dv, lunar_tw_ratio])

	return {
		"compatible": passed,
		"mass_ok": mass_ok,
		"dv_ok": dv_ok,
		"tw_ok": tw_ok,
		"budget_ok": budget_ok,
		"m0_wet_kg": m0_wet_kg,
		"max_tli_mass_kg": max_tli_kg,
		"tli_mass_margin_kg": max_tli_kg - m0_wet_kg,
		"delta_v_ms": delta_v_ms,
		"required_dv_ms": orbit_req_dv,
		"dv_margin_ms": delta_v_ms - orbit_req_dv,
		"lunar_tw_ratio": lunar_tw_ratio,
		"total_cost_musd": total_cost_musd,
		"budget_cap_musd": budget_cap_musd,
		"reasons": reasons,
		"citation": str(lv.get("nasa_citation", "NASA SP-2016-6105 Rev2"))
	}


func recalculate_all_telemetry(emit_alerts: bool = true) -> Dictionary:
	var lv: Dictionary = NasaDataLoader.get_launch_vehicle(selected_launch_vehicle_id)
	var orbit: Dictionary = NasaDataLoader.get_orbit(selected_orbit_id)
	var zone: Dictionary = NasaDataLoader.get_landing_zone(selected_landing_zone_id)

	# 1. Reset accumulators
	dry_mass_nominal_kg = 0.0
	mga_mass_kg = 0.0
	propellant_mass_kg = 0.0
	total_thrust_n = 0.0
	var weighted_isp_sum: float = 0.0

	var solar_raw_power_w: float = 0.0
	var rtg_power_w: float = 0.0
	var battery_kwh_total: float = 0.0
	thermal_output_w = 0.0

	var bus_obc_load_w: float = 0.0
	var comms_load_w: float = 0.0
	var payload_load_w: float = 0.0
	var prop_trn_load_w: float = 0.0
	var electric_prop_load_w: float = 0.0

	subsystems_cost_musd = 0.0
	science_points_base = 0.0
	data_generated_gb_day = 0.0
	downlink_mbps = 0.0
	var extra_shielding_g_cm2: float = 0.0
	var best_rad_tolerance_krad: float = 15.0

	has_lidar_trn = false
	has_rad_shielding = false
	has_rtg = false
	has_solar_array = false
	has_cryo_battery = false
	has_radhard_obc = false

	# 2. Aggregate subsystem SI parameters
	for part: Dictionary in selected_subsystems:
		var part_id: String = str(part.get("id", ""))
		var category: String = str(part.get("subsystem", ""))
		var mass_dry: float = float(part.get("mass_dry_kg", 0.0))
		var mga_pct: float = float(part.get("mga_percent", 0.15))

		dry_mass_nominal_kg += mass_dry
		mga_mass_kg += mass_dry * mga_pct
		propellant_mass_kg += float(part.get("propellant_capacity_kg", 0.0))

		var thrust: float = float(part.get("thrust_n", 0.0))
		var isp: float = float(part.get("isp_s", 0.0))
		total_thrust_n += thrust
		weighted_isp_sum += thrust * isp

		var pwr: float = float(part.get("power_w", 0.0))
		if pwr >= 0.0:
			if bool(part.get("requires_sunlight", false)):
				solar_raw_power_w += pwr
				has_solar_array = true
			else:
				rtg_power_w += pwr
				if pwr > 0.0:
					has_rtg = true
		else:
			var abs_pwr: float = absf(pwr)
			match category:
				"bus":
					bus_obc_load_w += abs_pwr
				"avionics":
					if part_id == "avionics_lidar_trn":
						prop_trn_load_w += abs_pwr
					else:
						bus_obc_load_w += abs_pwr
				"comms":
					comms_load_w += abs_pwr
				"payload":
					payload_load_w += abs_pwr
				"propulsion":
					if part_id == "prop_ion_sep":
						electric_prop_load_w += abs_pwr
					else:
						prop_trn_load_w += abs_pwr

		var cap_kwh: float = float(part.get("energy_capacity_kwh", 0.0))
		if cap_kwh > 0.0:
			battery_kwh_total += cap_kwh
			has_cryo_battery = true
		thermal_output_w += float(part.get("thermal_output_w", 0.0))

		subsystems_cost_musd += float(part.get("cost_m_usd", 0.0))
		science_points_base += float(part.get("science_points", 0.0))
		data_generated_gb_day += float(part.get("data_rate_gb_day", 0.0))
		downlink_mbps += float(part.get("data_rate_mbps", 0.0))

		var shield_val: float = float(part.get("shielding_g_cm2", 0.0))
		if shield_val > 0.0:
			extra_shielding_g_cm2 += shield_val
			has_rad_shielding = true

		if part_id == "avionics_lidar_trn" or float(part.get("max_safe_slope_deg", 0.0)) > 0.0:
			has_lidar_trn = true

		var rad_tol: float = float(part.get("radiation_tolerance_krad", 0.0))
		if rad_tol > best_rad_tolerance_krad:
			best_rad_tolerance_krad = rad_tol
		if part_id == "obc_adcs_radhard" or rad_tol >= 100.0:
			has_radhard_obc = true

	# 3. Mass & Propulsion (SI)
	mf_dry_kg = dry_mass_nominal_kg + mga_mass_kg
	m0_wet_kg = mf_dry_kg + propellant_mass_kg
	effective_isp_s = (weighted_isp_sum / total_thrust_n) if total_thrust_n > 0.0 else 0.0
	delta_v_ms = (effective_isp_s * G0_M_S2 * log(m0_wet_kg / mf_dry_kg)) if (mf_dry_kg > 0.0 and m0_wet_kg > mf_dry_kg and effective_isp_s > 0.0) else 0.0
	required_dv_ms = float(orbit.get("required_dv_ms", 1750.0))
	lunar_weight_n = m0_wet_kg * LUNAR_GRAVITY_M_S2
	lunar_tw_ratio = (total_thrust_n / lunar_weight_n) if lunar_weight_n > 0.0 else 0.0

	can_land_lunar = lunar_tw_ratio >= 1.0
	has_sufficient_dv = delta_v_ms >= required_dv_ms

	# 4. Power Balance (W & Wh)
	var zone_solar_pct: float = float(zone.get("solar_illumination_percent", 82.0))
	var shadow_occlusion: float = 1.0 if in_psr_shadow else clampf(1.0 - (zone_solar_pct / 100.0), 0.0, 1.0)
	var solar_cos: float = clampf(cos(deg_to_rad(solar_incidence_deg)), 0.0, 1.0)
	var solar_generated_w: float = solar_raw_power_w * solar_cos * (1.0 - shadow_occlusion)
	power_generated_w = solar_generated_w + rtg_power_w

	power_peak_consumed_w = bus_obc_load_w + comms_load_w + payload_load_w + prop_trn_load_w + electric_prop_load_w
	if safe_mode_active:
		# Safe mode suspends high-power payloads and electric propulsion, retaining bus/OBC and telemetry beacon
		power_consumed_w = bus_obc_load_w + comms_load_w * 0.25
	else:
		# Continuous surface duty cycle: Bus/OBC 100%, Comms 25% pass duty, Payloads 20% scheduled ops, Electric Hall thruster 100% if active
		power_consumed_w = bus_obc_load_w + (comms_load_w * 0.25) + (payload_load_w * 0.20) + electric_prop_load_w

	net_power_w = power_generated_w - power_consumed_w
	net_power_peak_w = power_generated_w - power_peak_consumed_w
	battery_wh = BASE_BUS_BATTERY_WH + (battery_kwh_total * 1000.0)
	can_survive_lunar_night = has_rtg or battery_kwh_total >= 45.0

	# 5. Budget (M$)
	launch_vehicle_cost_musd = float(lv.get("cost_m_usd", 0.0))
	total_cost_musd = subsystems_cost_musd + launch_vehicle_cost_musd

	# 6. Data & Communications (GB/day vs Mbps)
	var orbit_dte_pct: float = float(orbit.get("dte_visibility_percent", 50.0))
	var zone_dte_pct: float = float(zone.get("dte_visibility_percent", 45.0))
	if dte_occluded:
		dte_visibility_pct = 0.0
	else:
		dte_visibility_pct = orbit_dte_pct if selected_landing_zone_id == "connecting_ridge_rim" else minf(orbit_dte_pct, zone_dte_pct)
		if selected_landing_zone_id == "crater_floor_psr" and orbit_id_is_nrho():
			# NRHO apolune geometry still provides intermittent high-elevation polar relay/visibility window
			dte_visibility_pct = 35.0

	var pointing_efficiency: float = 1.0 if has_radhard_obc else 0.75
	downlink_capacity_gb_day = downlink_mbps * MBPS_TO_GB_PER_DAY * (dte_visibility_pct / 100.0) * pointing_efficiency
	data_backlog_gb_day = maxf(0.0, data_generated_gb_day - downlink_capacity_gb_day)

	var zone_sci_mult: float = float(zone.get("science_multiplier", 1.0))
	var downlink_delivery_ratio: float = 1.0
	if data_generated_gb_day > 0.0:
		downlink_delivery_ratio = clampf(downlink_capacity_gb_day / data_generated_gb_day, 0.0, 1.0)
	science_points_effective = science_points_base * zone_sci_mult * downlink_delivery_ratio

	# 7. Radiation (mSv) & Operational Lifetime (days)
	radiation_tolerance_krad = best_rad_tolerance_krad
	shielding_g_cm2 = BASE_BUS_SHIELDING_G_CM2 + extra_shielding_g_cm2
	var cislunar_env: Dictionary = NasaDataLoader.get_radiation_environment("cislunar_transit")
	var surface_env: Dictionary = NasaDataLoader.get_radiation_environment("lunar_south_pole_surface")
	var cislunar_gcr_day: float = float(cislunar_env.get("gcr_baseline_msv_day", 1.15))
	var cislunar_spe_hour: float = float(cislunar_env.get("spe_storm_msv_hour", 42.0))
	var surface_gcr_day: float = float(surface_env.get("gcr_baseline_msv_day", 0.58))
	var hvl_g_cm2: float = float(cislunar_env.get("al_shielding_half_value_g_cm2", 6.5))

	var attenuation: float = pow(0.5, shielding_g_cm2 / maxf(0.5, hvl_g_cm2))
	daily_gcr_msv = surface_gcr_day * attenuation
	spe_dose_msv = (spe_storm_hours * cislunar_spe_hour * attenuation) if spe_storm_active else 0.0
	var transit_gcr_msv: float = TRANSIT_DURATION_DAYS * cislunar_gcr_day * attenuation

	var dose_limit_msv: float = NasaDataLoader.get_mission_dose_limit_msv()
	var effective_dose_cap_msv: float = dose_limit_msv * (radiation_tolerance_krad / 100.0)
	var remaining_dose_budget_msv: float = maxf(0.0, effective_dose_cap_msv - (transit_gcr_msv + spe_dose_msv))
	var rad_lifetime_days: float = remaining_dose_budget_msv / maxf(0.001, daily_gcr_msv)

	theoretical_lifetime_days = minf(NOMINAL_MAX_LIFETIME_DAYS, rad_lifetime_days)
	can_survive_slope_hazard = (last_touchdown_slope_deg <= MAX_SAFE_SLOPE_DEG) or has_lidar_trn

	var power_survival_days: float = NOMINAL_MAX_LIFETIME_DAYS
	if net_power_w < 0.0:
		var hours_until_battery_empty: float = battery_wh / maxf(1.0, absf(net_power_w))
		power_survival_days = maxf(0.25, hours_until_battery_empty / 24.0)
	elif not can_survive_lunar_night:
		power_survival_days = PSR_BATTERY_SURVIVAL_DAYS if in_psr_shadow else LUNAR_DAY_DURATION_DAYS

	if not can_land_lunar or not has_sufficient_dv or not can_survive_slope_hazard:
		mission_lifetime_days = 0.0
	else:
		mission_lifetime_days = minf(theoretical_lifetime_days, power_survival_days)

	total_mission_dose_msv = transit_gcr_msv + spe_dose_msv + (daily_gcr_msv * mission_lifetime_days)

	# 8. Determine Primary Physical Status / Failure Code
	mission_failure_code = _evaluate_primary_failure_code(lv, emit_alerts)

	# 9. Build Telemetry Snapshot
	telemetry = get_telemetry_snapshot()
	state_updated.emit(telemetry)
	return telemetry


func orbit_id_is_nrho() -> bool:
	return selected_orbit_id == "orbit_nrho_gateway"


func _evaluate_primary_failure_code(lv: Dictionary, emit_alerts: bool) -> String:
	var max_tli_kg: float = float(lv.get("max_tli_mass_kg", 0.0))
	var dose_limit_msv: float = NasaDataLoader.get_mission_dose_limit_msv()

	if total_thrust_n <= 0.0:
		return "NO_PROPULSION_MODULE"

	if not can_land_lunar:
		if emit_alerts:
			simulation_alert.emit(
				"CRITICAL_THRUST_DEFICIT",
				"CRITICAL FAILURE: Lunar T/W = %.4f (< 1.0). Thrust %.2f N cannot decelerate %.1f kg against g_moon = 1.625 m/s^2." % [lunar_tw_ratio, total_thrust_n, m0_wet_kg],
				"NASA SP-2016-6105 Rev2 Sec 4.4 & 6.1"
			)
		return "CRITICAL_THRUST_DEFICIT"

	if not has_sufficient_dv:
		if emit_alerts:
			simulation_alert.emit(
				"PROPELLANT_DV_SHORTFALL",
				"Delta-V %.1f m/s is insufficient for descent (required %.1f m/s)." % [delta_v_ms, required_dv_ms],
				"NASA SP-2016-6105 Rev2 Sec 4.2"
			)
		return "PROPELLANT_DV_SHORTFALL"

	if max_tli_kg > 0.0 and m0_wet_kg > max_tli_kg:
		if emit_alerts:
			simulation_alert.emit(
				"LAUNCH_VEHICLE_OVERWEIGHT",
				"Wet mass %.1f kg exceeds %s TLI limit (%.1f kg)." % [m0_wet_kg, str(lv.get("name", selected_launch_vehicle_id)), max_tli_kg],
				str(lv.get("nasa_citation", "NASA SLS / CLPS Launch Vehicle Guide"))
			)
		return "LAUNCH_VEHICLE_OVERWEIGHT"

	if net_power_w < 0.0:
		if emit_alerts:
			simulation_alert.emit(
				"PSR_POWER_BLACKOUT",
				"Net power deficit %.1f W (Gen %.1f W vs Load %.1f W). Battery depleted before mission goal." % [net_power_w, power_generated_w, power_consumed_w],
				"NASA SP-2016-6105 Rev2 Chapter 4: Power & Thermal Balance"
			)
		return "PSR_POWER_BLACKOUT"

	if not can_survive_slope_hazard:
		if emit_alerts:
			simulation_alert.emit(
				"SLOPE_TIPOVER_HAZARD",
				"Touchdown slope %.1f deg exceeds 15.0 deg limit without Hazard Avoidance LiDAR & TRN." % last_touchdown_slope_deg,
				"LRO LOLA DEM & NASA SPLICE Safe Landing Standards"
			)
		return "SLOPE_TIPOVER_HAZARD"

	if total_mission_dose_msv > dose_limit_msv or (not has_radhard_obc and total_mission_dose_msv > 15.0):
		if emit_alerts:
			simulation_alert.emit(
				"RADIATION_SEU_RISK",
				"Cumulative radiation %.1f mSv threatens avionics (tolerance %.0f krad)." % [total_mission_dose_msv, radiation_tolerance_krad],
				NasaDataLoader.get_radiation_citation()
			)
		return "RADIATION_SEU_RISK"

	if data_backlog_gb_day > 0.0:
		if emit_alerts:
			simulation_alert.emit(
				"DSN_DOWNLINK_BOTTLENECK",
				"Science data %.2f GB/day exceeds DSN downlink capacity %.2f GB/day." % [data_generated_gb_day, downlink_capacity_gb_day],
				"NASA Deep Space Network (DSN) Link Budget"
			)
		return "DSN_DOWNLINK_BOTTLENECK"

	return "NOMINAL"


func get_telemetry_snapshot() -> Dictionary:
	return {
		"preset_index": current_preset_index,
		"engineer_mode": engineer_mode,
		"sandbox_mode": sandbox_mode,
		"team_size": team_size,
		"active_role": int(active_role),
		"selected_objective": selected_objective,
		"launch_vehicle_id": selected_launch_vehicle_id,
		"orbit_id": selected_orbit_id,
		"landing_zone_id": selected_landing_zone_id,
		"subsystem_ids": selected_subsystem_ids.duplicate(),
		"dry_mass_nominal_kg": dry_mass_nominal_kg,
		"mga_mass_kg": mga_mass_kg,
		"mf_dry_kg": mf_dry_kg,
		"propellant_mass_kg": propellant_mass_kg,
		"m0_wet_kg": m0_wet_kg,
		"total_thrust_n": total_thrust_n,
		"effective_isp_s": effective_isp_s,
		"delta_v_ms": delta_v_ms,
		"required_dv_ms": required_dv_ms,
		"lunar_weight_n": lunar_weight_n,
		"lunar_tw_ratio": lunar_tw_ratio,
		"power_generated_w": power_generated_w,
		"power_consumed_w": power_consumed_w,
		"power_peak_consumed_w": power_peak_consumed_w,
		"net_power_w": net_power_w,
		"net_power_peak_w": net_power_peak_w,
		"battery_wh": battery_wh,
		"thermal_output_w": thermal_output_w,
		"subsystems_cost_musd": subsystems_cost_musd,
		"launch_vehicle_cost_musd": launch_vehicle_cost_musd,
		"total_cost_musd": total_cost_musd,
		"budget_cap_musd": budget_cap_musd,
		"science_points_base": science_points_base,
		"science_points_effective": science_points_effective,
		"data_generated_gb_day": data_generated_gb_day,
		"downlink_mbps": downlink_mbps,
		"dte_visibility_pct": dte_visibility_pct,
		"downlink_capacity_gb_day": downlink_capacity_gb_day,
		"data_backlog_gb_day": data_backlog_gb_day,
		"shielding_g_cm2": shielding_g_cm2,
		"daily_gcr_msv": daily_gcr_msv,
		"spe_dose_msv": spe_dose_msv,
		"total_mission_dose_msv": total_mission_dose_msv,
		"radiation_tolerance_krad": radiation_tolerance_krad,
		"mission_lifetime_days": mission_lifetime_days,
		"theoretical_lifetime_days": theoretical_lifetime_days,
		"can_land_lunar": can_land_lunar,
		"has_sufficient_dv": has_sufficient_dv,
		"has_lidar_trn": has_lidar_trn,
		"has_rad_shielding": has_rad_shielding,
		"has_rtg": has_rtg,
		"has_solar_array": has_solar_array,
		"has_cryo_battery": has_cryo_battery,
		"has_radhard_obc": has_radhard_obc,
		"can_survive_lunar_night": can_survive_lunar_night,
		"can_survive_slope_hazard": can_survive_slope_hazard,
		"in_psr_shadow": in_psr_shadow,
		"dte_occluded": dte_occluded,
		"spe_storm_active": spe_storm_active,
		"safe_mode_active": safe_mode_active,
		"last_touchdown_slope_deg": last_touchdown_slope_deg,
		"failure_code": mission_failure_code
	}


func export_design_code() -> String:
	var payload: Dictionary = {
		"lv": selected_launch_vehicle_id,
		"orb": selected_orbit_id,
		"zone": selected_landing_zone_id,
		"parts": selected_subsystem_ids
	}
	var json_str: String = JSON.stringify(payload)
	return Marshalls.utf8_to_base64(json_str)


func import_design_code(code: String) -> bool:
	var decoded: String = Marshalls.base64_to_utf8(code.strip_edges())
	if decoded.is_empty():
		return false
	var parsed: Variant = JSON.parse_string(decoded)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = parsed as Dictionary
	if dict.has("lv"):
		selected_launch_vehicle_id = str(dict.get("lv", selected_launch_vehicle_id))
	if dict.has("orb"):
		selected_orbit_id = str(dict.get("orb", selected_orbit_id))
	if dict.has("zone"):
		selected_landing_zone_id = str(dict.get("zone", selected_landing_zone_id))
	if dict.has("parts") and typeof(dict.get("parts")) == TYPE_ARRAY:
		var part_ids: Array[String] = []
		for pid_var: Variant in (dict.get("parts", []) as Array):
			part_ids.append(str(pid_var))
		set_selected_subsystems(part_ids)
	else:
		recalculate_all_telemetry(true)
	return true
