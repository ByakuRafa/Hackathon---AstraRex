extends Node

## Multi-Objective Pareto Frontier Solver, Physical Root-Cause Diagnostic Engine,
## and Single-Threaded WebGL Browser Exporter (CSV/JSON via JavaScriptBridge).

signal pareto_solved(pareto_frontier: Array[Dictionary], all_candidates: Array[Dictionary])
signal report_exported(file_path_or_name: String, format: String)

var cached_candidates: Array[Dictionary] = []
var cached_pareto_frontier: Array[Dictionary] = []
var is_solving: bool = false


func solve_pareto_frontier_sync(orbit_id: String = "", landing_zone_id: String = "") -> Array[Dictionary]:
	var target_orbit_id: String = MissionState.selected_orbit_id if orbit_id.is_empty() else orbit_id
	var target_zone_id: String = MissionState.selected_landing_zone_id if landing_zone_id.is_empty() else landing_zone_id

	var candidates: Array[Dictionary] = _generate_candidate_designs(target_orbit_id, target_zone_id)
	var feasible: Array[Dictionary] = []
	for cand: Dictionary in candidates:
		if bool(cand.get("feasible", false)):
			feasible.append(cand)

	var pareto_set: Array[Dictionary] = []
	for i: int in range(feasible.size()):
		var cand_a: Dictionary = feasible[i]
		var dominated: bool = false
		for j: int in range(feasible.size()):
			if i == j:
				continue
			if _dominates(feasible[j], cand_a):
				dominated = true
				break
		if not dominated:
			pareto_set.append(cand_a)

	pareto_set.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("total_mass_kg", 0.0)) < float(b.get("total_mass_kg", 0.0))
	)

	cached_candidates = candidates
	cached_pareto_frontier = pareto_set
	pareto_solved.emit(pareto_set, candidates)
	return pareto_set


func solve_pareto_frontier_async(yield_interval: int = 50, orbit_id: String = "", landing_zone_id: String = "") -> Array[Dictionary]:
	if is_solving:
		return cached_pareto_frontier

	is_solving = true
	var step_limit: int = maxi(1, yield_interval)
	var target_orbit_id: String = MissionState.selected_orbit_id if orbit_id.is_empty() else orbit_id
	var target_zone_id: String = MissionState.selected_landing_zone_id if landing_zone_id.is_empty() else landing_zone_id

	var configs: Array[Array] = _build_candidate_part_lists()
	var candidates: Array[Dictionary] = []
	var feasible: Array[Dictionary] = []

	for idx: int in range(configs.size()):
		var part_list: Array = configs[idx]
		var evaluated: Dictionary = _evaluate_candidate(part_list, target_orbit_id, target_zone_id)
		candidates.append(evaluated)
		if bool(evaluated.get("feasible", false)):
			feasible.append(evaluated)
		if (idx + 1) % step_limit == 0 and get_tree() != null:
			await get_tree().process_frame

	var pareto_set: Array[Dictionary] = []
	for i: int in range(feasible.size()):
		var cand_a: Dictionary = feasible[i]
		var dominated: bool = false
		for j: int in range(feasible.size()):
			if i == j:
				continue
			if _dominates(feasible[j], cand_a):
				dominated = true
				break
		if not dominated:
			pareto_set.append(cand_a)
		if (i + 1) % step_limit == 0 and get_tree() != null:
			await get_tree().process_frame

	pareto_set.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("total_mass_kg", 0.0)) < float(b.get("total_mass_kg", 0.0))
	)

	cached_candidates = candidates
	cached_pareto_frontier = pareto_set
	is_solving = false
	pareto_solved.emit(pareto_set, candidates)
	return pareto_set


func _generate_candidate_designs(orbit_id: String, landing_zone_id: String) -> Array[Dictionary]:
	var configs: Array[Array] = _build_candidate_part_lists()
	var candidates: Array[Dictionary] = []
	for part_list: Array in configs:
		candidates.append(_evaluate_candidate(part_list, orbit_id, landing_zone_id))
	return candidates


func _build_candidate_part_lists() -> Array[Array]:
	var buses: Array[Dictionary] = NasaDataLoader.get_subsystems_by_category("bus")
	var propulsions: Array[Dictionary] = NasaDataLoader.get_subsystems_by_category("propulsion")
	var comms_list: Array[Dictionary] = NasaDataLoader.get_subsystems_by_category("comms")
	var payloads: Array[Dictionary] = NasaDataLoader.get_subsystems_by_category("payload")
	var shieldings: Array[Dictionary] = NasaDataLoader.get_subsystems_by_category("shielding")

	var primary_power: Array[Dictionary] = []
	var batteries: Array[Dictionary] = []
	for pwr: Dictionary in NasaDataLoader.get_subsystems_by_category("power"):
		if str(pwr.get("mount_point", "")) == "Mount_Power_Starboard":
			batteries.append(pwr)
		else:
			primary_power.append(pwr)

	var obc_list: Array[Dictionary] = []
	var lidar_list: Array[Dictionary] = []
	for av: Dictionary in NasaDataLoader.get_subsystems_by_category("avionics"):
		if str(av.get("id", "")) == "avionics_lidar_trn":
			lidar_list.append(av)
		else:
			obc_list.append(av)

	var payload_subsets: Array[Array] = _non_empty_subsets(payloads)
	var battery_options: Array[Variant] = [null]
	for b: Dictionary in batteries:
		battery_options.append(b)
	var lidar_options: Array[Variant] = [null]
	for l: Dictionary in lidar_list:
		lidar_options.append(l)
	var shield_options: Array[Variant] = [null]
	for s: Dictionary in shieldings:
		shield_options.append(s)

	var configs: Array[Array] = []
	for bus: Dictionary in buses:
		for prop: Dictionary in propulsions:
			for pwr: Dictionary in primary_power:
				for batt_opt: Variant in battery_options:
					for comm: Dictionary in comms_list:
						for obc: Dictionary in obc_list:
							for lidar_opt: Variant in lidar_options:
								for shield_opt: Variant in shield_options:
									for p_subset: Array in payload_subsets:
										var cfg: Array[Dictionary] = [bus, prop, pwr, comm, obc]
										if batt_opt != null:
											cfg.append(batt_opt as Dictionary)
										if lidar_opt != null:
											cfg.append(lidar_opt as Dictionary)
										if shield_opt != null:
											cfg.append(shield_opt as Dictionary)
										for pay_var: Variant in p_subset:
											cfg.append(pay_var as Dictionary)
										configs.append(cfg)
	return configs


func _non_empty_subsets(items: Array[Dictionary]) -> Array[Array]:
	var subsets: Array[Array] = []
	var count: int = items.size()
	var total_masks: int = 1 << count
	for mask: int in range(1, total_masks):
		var subset: Array[Dictionary] = []
		for bit: int in range(count):
			if (mask & (1 << bit)) != 0:
				subset.append(items[bit])
		subsets.append(subset)
	return subsets


func _evaluate_candidate(parts: Array, orbit_id: String, landing_zone_id: String) -> Dictionary:
	var orbit: Dictionary = NasaDataLoader.get_orbit(orbit_id)
	var zone: Dictionary = NasaDataLoader.get_landing_zone(landing_zone_id)
	var req_dv: float = float(orbit.get("required_dv_ms", 1750.0))
	var zone_solar_pct: float = float(zone.get("solar_illumination_percent", 82.0))
	var zone_slope_deg: float = float(zone.get("mean_slope_deg", 7.5))
	var zone_sci_mult: float = float(zone.get("science_multiplier", 1.0))
	var orbit_dte_pct: float = float(orbit.get("dte_visibility_percent", 50.0))
	var zone_dte_pct: float = float(zone.get("dte_visibility_percent", 45.0))
	var effective_dte_pct: float = orbit_dte_pct if landing_zone_id == "connecting_ridge_rim" else minf(orbit_dte_pct, zone_dte_pct)
	if landing_zone_id == "crater_floor_psr" and orbit_id == "orbit_nrho_gateway":
		effective_dte_pct = 35.0

	var mf_dry_kg: float = 0.0
	var propellant_kg: float = 0.0
	var thrust_n: float = 0.0
	var weighted_isp: float = 0.0
	var cost_musd: float = 0.0
	var sci_base: float = 0.0
	var data_gb_day: float = 0.0
	var downlink_mbps: float = 0.0
	var solar_raw_w: float = 0.0
	var rtg_w: float = 0.0
	var batt_kwh: float = 0.0
	var bus_obc_load_w: float = 0.0
	var comms_load_w: float = 0.0
	var payload_load_w: float = 0.0
	var electric_prop_load_w: float = 0.0
	var shield_g_cm2: float = MissionState.BASE_BUS_SHIELDING_G_CM2
	var rad_tol_krad: float = 15.0
	var has_lidar: bool = false
	var has_rtg: bool = false
	var has_radhard: bool = false
	var part_ids: Array[String] = []

	for part_var: Variant in parts:
		var part: Dictionary = part_var as Dictionary
		var pid: String = str(part.get("id", ""))
		var cat: String = str(part.get("subsystem", ""))
		part_ids.append(pid)

		var dry: float = float(part.get("mass_dry_kg", 0.0))
		var mga: float = float(part.get("mga_percent", 0.15))
		mf_dry_kg += dry * (1.0 + mga)
		propellant_kg += float(part.get("propellant_capacity_kg", 0.0))

		var t_n: float = float(part.get("thrust_n", 0.0))
		var isp: float = float(part.get("isp_s", 0.0))
		thrust_n += t_n
		weighted_isp += t_n * isp

		var pwr: float = float(part.get("power_w", 0.0))
		if pwr >= 0.0:
			if bool(part.get("requires_sunlight", false)):
				solar_raw_w += pwr
			else:
				rtg_w += pwr
				if pwr > 0.0:
					has_rtg = true
		else:
			var abs_p: float = absf(pwr)
			match cat:
				"bus":
					bus_obc_load_w += abs_p
				"avionics":
					if pid != "avionics_lidar_trn":
						bus_obc_load_w += abs_p
				"comms":
					comms_load_w += abs_p
				"payload":
					payload_load_w += abs_p
				"propulsion":
					if pid == "prop_ion_sep":
						electric_prop_load_w += abs_p

		batt_kwh += float(part.get("energy_capacity_kwh", 0.0))
		cost_musd += float(part.get("cost_m_usd", 0.0))
		sci_base += float(part.get("science_points", 0.0))
		data_gb_day += float(part.get("data_rate_gb_day", 0.0))
		downlink_mbps += float(part.get("data_rate_mbps", 0.0))
		shield_g_cm2 += float(part.get("shielding_g_cm2", 0.0))

		if pid == "avionics_lidar_trn" or float(part.get("max_safe_slope_deg", 0.0)) > 0.0:
			has_lidar = true
		var tol: float = float(part.get("radiation_tolerance_krad", 0.0))
		if tol > rad_tol_krad:
			rad_tol_krad = tol
		if pid == "obc_adcs_radhard" or tol >= 100.0:
			has_radhard = true

	var m0_kg: float = mf_dry_kg + propellant_kg
	var eff_isp: float = (weighted_isp / thrust_n) if thrust_n > 0.0 else 0.0
	var dv_ms: float = (eff_isp * MissionState.G0_M_S2 * log(m0_kg / mf_dry_kg)) if (mf_dry_kg > 0.0 and m0_kg > mf_dry_kg and eff_isp > 0.0) else 0.0
	var tw_lunar: float = (thrust_n / (m0_kg * MissionState.LUNAR_GRAVITY_M_S2)) if m0_kg > 0.0 else 0.0

	var shadow_occlusion: float = 1.0 if zone_solar_pct <= 0.1 else clampf(1.0 - (zone_solar_pct / 100.0), 0.0, 1.0)
	var solar_cos: float = cos(deg_to_rad(15.0))
	var pwr_gen_w: float = (solar_raw_w * solar_cos * (1.0 - shadow_occlusion)) + rtg_w
	var pwr_load_w: float = bus_obc_load_w + (comms_load_w * 0.25) + (payload_load_w * 0.20) + electric_prop_load_w
	var net_pwr_w: float = pwr_gen_w - pwr_load_w

	var pointing_eff: float = 1.0 if has_radhard else 0.75
	var downlink_gb_day: float = downlink_mbps * MissionState.MBPS_TO_GB_PER_DAY * (effective_dte_pct / 100.0) * pointing_eff
	var delivery_ratio: float = clampf(downlink_gb_day / data_gb_day, 0.0, 1.0) if data_gb_day > 0.0 else 1.0
	var science_score: float = sci_base * zone_sci_mult * delivery_ratio

	# Survival probability [0.0, 1.0]
	var can_land: bool = tw_lunar >= 1.0 and dv_ms >= req_dv
	var survival_prob: float = 0.0
	if can_land:
		var surv_prop: float = 0.99
		var surv_slope: float = 0.99 if (has_lidar or zone_slope_deg <= 15.0) else 0.35
		var surv_thermal: float = 0.98 if (has_rtg or (batt_kwh >= 45.0 and net_pwr_w >= 0.0)) else (0.55 if net_pwr_w >= 0.0 else 0.15)
		var atten: float = pow(0.5, shield_g_cm2 / 6.5)
		var transit_surface_30d_msv: float = (5.0 * 1.15 + 30.0 * 0.58) * atten
		var eff_limit_msv: float = NasaDataLoader.get_mission_dose_limit_msv() * (rad_tol_krad / 100.0)
		var surv_rad: float = 0.99 if transit_surface_30d_msv <= eff_limit_msv else clampf(eff_limit_msv / maxf(1.0, transit_surface_30d_msv), 0.10, 0.95)
		var surv_comms: float = 0.98 if delivery_ratio >= 0.85 else 0.80
		survival_prob = clampf(surv_prop * surv_slope * surv_thermal * surv_rad * surv_comms, 0.0, 1.0)

	return {
		"subsystem_ids": part_ids,
		"science_score": science_score,
		"total_mass_kg": m0_kg,
		"mf_dry_kg": mf_dry_kg,
		"cost_m_usd": cost_musd,
		"survival_prob": survival_prob,
		"delta_v_ms": dv_ms,
		"lunar_tw_ratio": tw_lunar,
		"net_power_w": net_pwr_w,
		"downlink_gb_day": downlink_gb_day,
		"data_generated_gb_day": data_gb_day,
		"feasible": can_land and net_pwr_w >= 0.0
	}


func _dominates(a: Dictionary, b: Dictionary) -> bool:
	var a_sci: float = float(a.get("science_score", 0.0))
	var b_sci: float = float(b.get("science_score", 0.0))
	var a_mass: float = float(a.get("total_mass_kg", 0.0))
	var b_mass: float = float(b.get("total_mass_kg", 0.0))
	var a_cost: float = float(a.get("cost_m_usd", 0.0))
	var b_cost: float = float(b.get("cost_m_usd", 0.0))
	var a_surv: float = float(a.get("survival_prob", 0.0))
	var b_surv: float = float(b.get("survival_prob", 0.0))

	var not_worse: bool = (a_sci >= b_sci and a_mass <= b_mass and a_cost <= b_cost and a_surv >= b_surv)
	var strictly_better: bool = (a_sci > b_sci or a_mass < b_mass or a_cost < b_cost or a_surv > b_surv)
	return not_worse and strictly_better


func evaluate_current_player_design() -> Dictionary:
	return _evaluate_candidate(
		MissionState.selected_subsystems,
		MissionState.selected_orbit_id,
		MissionState.selected_landing_zone_id
	)


func find_nearest_pareto_optimum(player_point: Dictionary) -> Dictionary:
	if cached_pareto_frontier.is_empty():
		solve_pareto_frontier_sync()
	if cached_pareto_frontier.is_empty():
		return {}

	var p_sci: float = float(player_point.get("science_score", 0.0))
	var p_mass: float = float(player_point.get("total_mass_kg", 0.0))
	var p_cost: float = float(player_point.get("cost_m_usd", 0.0))
	var p_surv: float = float(player_point.get("survival_prob", 0.0))

	var best_point: Dictionary = cached_pareto_frontier[0]
	var best_dist: float = INF

	for pt: Dictionary in cached_pareto_frontier:
		var d_sci: float = (float(pt.get("science_score", 0.0)) - p_sci) / 100.0
		var d_mass: float = (float(pt.get("total_mass_kg", 0.0)) - p_mass) / 1500.0
		var d_cost: float = (float(pt.get("cost_m_usd", 0.0)) - p_cost) / 150.0
		var d_surv: float = float(pt.get("survival_prob", 0.0)) - p_surv
		var dist: float = sqrt(d_sci * d_sci + d_mass * d_mass + d_cost * d_cost + d_surv * d_surv)
		if dist < best_dist:
			best_dist = dist
			best_point = pt

	return best_point.duplicate(true)


func generate_root_cause_report() -> Dictionary:
	var telem: Dictionary = MissionState.get_telemetry_snapshot()
	var compat: Dictionary = MissionState.validate_launch_compatibility()
	var player_pt: Dictionary = evaluate_current_player_design()
	var nearest_opt: Dictionary = find_nearest_pareto_optimum(player_pt)

	var failure_code: String = str(telem.get("failure_code", "NOMINAL"))
	var active_bottlenecks: Array[Dictionary] = []

	if not bool(telem.get("can_land_lunar", false)):
		active_bottlenecks.append({
			"code": "CRITICAL_THRUST_DEFICIT",
			"title": "Terminal Descent Propulsion Lockout (T/W < 1.0)",
			"cause": "Lunar Thrust-to-Weight ratio is %.4f (Thrust %.2f N vs Lunar Weight %.1f N)." % [float(telem.get("lunar_tw_ratio", 0.0)), float(telem.get("total_thrust_n", 0.0)), float(telem.get("lunar_weight_n", 0.0))],
			"physics_principle": "T/W_lunar = F_thrust / (m0 * 1.625 m/s^2). Values below 1.0 cannot arrest gravitational acceleration during terminal descent.",
			"recommendation": "Replace low-thrust Hall/Ion thruster with high-thrust Bipropellant Descent Engine (4500 N).",
			"citation": "NASA SP-2016-6105 Rev2 Sec 4.4 & Sec 6.1"
		})

	if not bool(telem.get("has_sufficient_dv", false)):
		active_bottlenecks.append({
			"code": "PROPELLANT_DV_SHORTFALL",
			"title": "Propellant Depletion Prior to Touchdown",
			"cause": "Available Delta-V %.1f m/s is below orbital descent requirement %.1f m/s." % [float(telem.get("delta_v_ms", 0.0)), float(telem.get("required_dv_ms", 1750.0))],
			"physics_principle": "Tsiolkovsky Equation: dV = Isp * 9.80665 * ln(m0 / mf). Excess dry mass or insufficient propellant collapses velocity margin.",
			"recommendation": "Reduce dry mass (remove heavy non-essential modules) or select LLO 100 km Polar Orbit (1750 m/s) instead of NRHO (2500 m/s).",
			"citation": "NASA SP-2016-6105 Rev2 Sec 4.2"
		})

	if not bool(compat.get("mass_ok", true)):
		active_bottlenecks.append({
			"code": "LAUNCH_VEHICLE_OVERWEIGHT",
			"title": "Launch Vehicle TLI Mass Exceeded",
			"cause": "Spacecraft wet mass %.1f kg exceeds selected launcher TLI payload limit %.1f kg." % [float(compat.get("m0_wet_kg", 0.0)), float(compat.get("max_tli_mass_kg", 0.0))],
			"physics_principle": "Trans-Lunar Injection (C3 ~ -2 km^2/s^2) fixes maximum deliverable wet mass m0 for a given launch vehicle.",
			"recommendation": "Upgrade launch vehicle (e.g. Vulcan Centaur VC6 or Falcon Heavy) or trim dry mass + MGA.",
			"citation": str(compat.get("citation", "NASA SLS / CLPS Launch Services Procurement"))
		})

	if float(telem.get("net_power_w", 0.0)) < 0.0:
		active_bottlenecks.append({
			"code": "PSR_POWER_BLACKOUT",
			"title": "Shackleton Shadow / Power Deficit Blackout",
			"cause": "Net power balance is %.1f W (Generated %.1f W vs Load %.1f W)." % [float(telem.get("net_power_w", 0.0)), float(telem.get("power_generated_w", 0.0)), float(telem.get("power_consumed_w", 0.0))],
			"physics_principle": "Solar flux obeys P = P0 * cos(theta) * (1 - shadow_occlusion). Inside Permanently Shadowed Regions, solar output drops to 0 W.",
			"recommendation": "Equip MMRTG Radioisotope Generator (110 W continuous + 2000 W thermal) or add 48 kWh Cryogenic Battery and avoid high-power electric thrusters.",
			"citation": "LRO / CLPS South Pole Illumination Constraint & NASA SP-2016-6105 Rev2 Ch 4"
		})

	if not bool(telem.get("can_survive_slope_hazard", true)):
		active_bottlenecks.append({
			"code": "SLOPE_TIPOVER_HAZARD",
			"title": "Crater Slope Tip-Over Hazard (> 15 deg)",
			"cause": "Touchdown terrain slope %.1f deg exceeds 15.0 deg stability envelope without TRN." % float(telem.get("last_touchdown_slope_deg", 0.0)),
			"physics_principle": "Without Hazard Avoidance LiDAR & Terrain Relative Navigation, landing vector falls outside footpad stability polygon on steep crater walls.",
			"recommendation": "Equip Hazard Avoidance LiDAR & TRN Sensor (avionics_lidar_trn) or target flat Connecting Ridge / PSR Floor.",
			"citation": "LRO LOLA DEM & NASA SPLICE Safe & Precise Landing Standards"
		})

	if float(telem.get("data_backlog_gb_day", 0.0)) > 0.0:
		active_bottlenecks.append({
			"code": "DSN_DOWNLINK_BOTTLENECK",
			"title": "Deep Space Network Downlink Saturation",
			"cause": "Science data rate %.2f GB/day exceeds DSN downlink capacity %.2f GB/day (backlog %.2f GB/day)." % [float(telem.get("data_generated_gb_day", 0.0)), float(telem.get("downlink_capacity_gb_day", 0.0)), float(telem.get("data_backlog_gb_day", 0.0))],
			"physics_principle": "Daily downlink volume = Mbps * 10.8 * DTE_visibility_fraction * pointing_efficiency.",
			"recommendation": "Upgrade to DSN High-Gain Ka-Band Parabolic Antenna (100 Mbps) and Rad-Hard Star Tracker ADCS.",
			"citation": "NASA Deep Space Network (DSN) Link Budget"
		})

	var dose_limit_msv: float = NasaDataLoader.get_mission_dose_limit_msv()
	if float(telem.get("total_mission_dose_msv", 0.0)) > dose_limit_msv or (not bool(telem.get("has_radhard_obc", false)) and float(telem.get("total_mission_dose_msv", 0.0)) > 15.0):
		active_bottlenecks.append({
			"code": "RADIATION_SEU_RISK",
			"title": "Unshielded / COTS Avionics Radiation Degradation",
			"cause": "Cumulative dose %.1f mSv exceeds avionics tolerance envelope (%.0f krad)." % [float(telem.get("total_mission_dose_msv", 0.0)), float(telem.get("radiation_tolerance_krad", 15.0))],
			"physics_principle": "GCR + SPE dose attenuates exponentially with shielding: D = D0 * 0.5^(t_shield / HVL).",
			"recommendation": "Equip Rad-Hard Dual Flight Computer (100 krad) and/or Polyethylene-Al Radiation Shielding (12 g/cm2).",
			"citation": NasaDataLoader.get_radiation_citation()
		})

	var primary_diag: Dictionary
	if active_bottlenecks.is_empty():
		primary_diag = {
			"code": "NOMINAL_ARTEMIS_OPTIMAL",
			"title": "Mission Nominal — All Physical Constraints Satisfied",
			"cause": "Lunar T/W >= 1.0, Delta-V margin positive, continuous power balance positive, DSN downlink unobstructed, and radiation within limits.",
			"physics_principle": "Balanced multi-objective trade across SP-2016-6105 MGA, Tsiolkovsky dV, and LRO LOLA South Pole illumination.",
			"recommendation": "Compare your telemetry against the Pareto Frontier in Phase 4 or export Engineer CSV/JSON report.",
			"citation": NasaDataLoader.get_catalog_citation()
		}
	else:
		primary_diag = active_bottlenecks[0]

	var deltas: Dictionary = {}
	if not nearest_opt.is_empty():
		deltas = {
			"delta_science": float(nearest_opt.get("science_score", 0.0)) - float(player_pt.get("science_score", 0.0)),
			"delta_mass_kg": float(nearest_opt.get("total_mass_kg", 0.0)) - float(player_pt.get("total_mass_kg", 0.0)),
			"delta_cost_musd": float(nearest_opt.get("cost_m_usd", 0.0)) - float(player_pt.get("cost_m_usd", 0.0)),
			"delta_survival_prob": float(nearest_opt.get("survival_prob", 0.0)) - float(player_pt.get("survival_prob", 0.0))
		}

	return {
		"status": failure_code,
		"nominal": active_bottlenecks.is_empty(),
		"primary_diagnosis": primary_diag,
		"all_bottlenecks": active_bottlenecks,
		"player_design": player_pt,
		"nearest_pareto_optimum": nearest_opt,
		"pareto_deltas": deltas,
		"telemetry": telem,
		"launch_compatibility": compat
	}


func export_telemetry_report(format: String = "json") -> String:
	var fmt: String = format.strip_edges().to_lower()
	var report: Dictionary = generate_root_cause_report()
	var timestamp: int = int(Time.get_unix_time_from_system())
	var filename: String = ""
	var mime_type: String = "application/json"
	var payload_str: String = ""

	if fmt == "csv":
		filename = "AstraRex_Telemetry_%d.csv" % timestamp
		mime_type = "text/csv"
		payload_str = _build_csv_report(report)
	else:
		filename = "AstraRex_Pareto_Debrief_%d.json" % timestamp
		mime_type = "application/json"
		var export_payload: Dictionary = {
			"exported_at_utc": Time.get_datetime_string_from_system(true),
			"nasa_references": [
				NasaDataLoader.get_catalog_citation(),
				NasaDataLoader.get_ephemeris_citation(),
				NasaDataLoader.get_radiation_citation(),
				str(NasaDataLoader.get_terrain_metadata().get("nasa_citation", "LRO LOLA GDR 20 m/px"))
			],
			"report": report,
			"pareto_frontier": cached_pareto_frontier
		}
		payload_str = JSON.stringify(export_payload, "\t")

	var bytes: PackedByteArray = payload_str.to_utf8_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, filename, mime_type)
		report_exported.emit(filename, fmt)
		return filename

	var user_path: String = "user://" + filename
	var file: FileAccess = FileAccess.open(user_path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()
		var abs_path: String = ProjectSettings.globalize_path(user_path)
		print("ParetoSolver: Exported %s telemetry report to %s" % [fmt.to_upper(), abs_path])
		report_exported.emit(abs_path, fmt)
		return abs_path

	push_error("ParetoSolver: Failed to write report to '%s'." % user_path)
	return ""


func _build_csv_report(report: Dictionary) -> String:
	var telem: Dictionary = report.get("telemetry", {}) as Dictionary
	var lines: PackedStringArray = PackedStringArray()
	lines.append("metric,value,unit,nasa_citation")
	lines.append("preset_index,%d,index,NASA Space Apps 2026 Judge Presets" % int(telem.get("preset_index", 1)))
	lines.append("dry_mass_nominal,%.3f,kg,NASA SP-2016-6105 Rev2 Sec 4.3" % float(telem.get("dry_mass_nominal_kg", 0.0)))
	lines.append("mga_mass,%.3f,kg,NASA SP-2016-6105 Rev2 Appendix G" % float(telem.get("mga_mass_kg", 0.0)))
	lines.append("burnout_mass_mf,%.3f,kg,NASA SP-2016-6105 Rev2" % float(telem.get("mf_dry_kg", 0.0)))
	lines.append("propellant_mass,%.3f,kg,NASA SP-2016-6105 Rev2" % float(telem.get("propellant_mass_kg", 0.0)))
	lines.append("wet_mass_m0,%.3f,kg,NASA SP-2016-6105 Rev2" % float(telem.get("m0_wet_kg", 0.0)))
	lines.append("delta_v,%.3f,m/s,Tsiolkovsky Rocket Equation" % float(telem.get("delta_v_ms", 0.0)))
	lines.append("required_delta_v,%.3f,m/s,Artemis LLO/NRHO Descent Profile" % float(telem.get("required_dv_ms", 0.0)))
	lines.append("total_thrust,%.3f,N,NASA SP-2016-6105 Rev2 Sec 4.4" % float(telem.get("total_thrust_n", 0.0)))
	lines.append("lunar_tw_ratio,%.4f,ratio,Lunar Gravity g=1.625 m/s^2" % float(telem.get("lunar_tw_ratio", 0.0)))
	lines.append("power_generated,%.3f,W,JPL Horizons Solar Cosine & Occlusion" % float(telem.get("power_generated_w", 0.0)))
	lines.append("power_consumed,%.3f,W,NASA SP-2016-6105 Rev2 Ch 4" % float(telem.get("power_consumed_w", 0.0)))
	lines.append("net_power,%.3f,W,NASA SP-2016-6105 Rev2 Ch 4" % float(telem.get("net_power_w", 0.0)))
	lines.append("battery_capacity,%.1f,Wh,CLPS Lunar Night Trade Study" % float(telem.get("battery_wh", 0.0)))
	lines.append("total_cost,%.2f,M$,NASA CLPS & SLS Mission Planner Guide" % float(telem.get("total_cost_musd", 0.0)))
	lines.append("data_generated,%.3f,GB/day,CLPS Scientific Payload Heritage" % float(telem.get("data_generated_gb_day", 0.0)))
	lines.append("downlink_capacity,%.3f,GB/day,NASA DSN Link Budget" % float(telem.get("downlink_capacity_gb_day", 0.0)))
	lines.append("data_backlog,%.3f,GB/day,NASA DSN Link Budget" % float(telem.get("data_backlog_gb_day", 0.0)))
	lines.append("science_points_effective,%.2f,pts,LRO LOLA Zone Science Multiplier" % float(telem.get("science_points_effective", 0.0)))
	lines.append("radiation_shielding,%.2f,g/cm2,NASA OSDR RadLab" % float(telem.get("shielding_g_cm2", 0.0)))
	lines.append("total_mission_dose,%.3f,mSv,NASA OSDR RadLab & LRO CRaTER" % float(telem.get("total_mission_dose_msv", 0.0)))
	lines.append("mission_lifetime,%.2f,days,SP-2016-6105 & OSDR RadLab" % float(telem.get("mission_lifetime_days", 0.0)))
	lines.append("failure_code,%s,code,Physical Diagnostics Engine" % str(telem.get("failure_code", "NOMINAL")))
	return "\n".join(lines)
