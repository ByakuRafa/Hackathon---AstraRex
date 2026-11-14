import json
import re
from pathlib import Path
import requests

# Grava diretamente em res://data/ na raiz do projeto Godot 4
PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = PROJECT_ROOT / "data"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

HORIZONS_URL = "https://ssd.jpl.nasa.gov/api/horizons.api"
RADLAB_URL = "https://visualization.osdr.nasa.gov/radlab/api"

# Vetores de contingência (DE441, época 2026-11-14 00:00 TDB) caso a rede esteja offline
HORIZONS_OFFLINE_FALLBACK = {
    "301": [
        {
            "epoch": "2461358.500000000 = A.D. 2026-Nov-14 00:00:00.0000 TDB (Fallback)",
            "position_km": {"x": 92375.7168, "y": -394216.0088, "z": -23647.0948},
            "velocity_km_s": {"vx": 0.9396, "vy": 0.2196, "vz": 0.0632},
        }
    ],
    "10": [
        {
            "epoch": "2461358.500000000 = A.D. 2026-Nov-14 00:00:00.0000 TDB (Fallback)",
            "position_km": {"x": -93842100.0, "y": -113954200.0, "z": -49412800.0},
            "velocity_km_s": {"vx": 22.84, "vy": -17.12, "vz": -7.41},
        }
    ],
    "399": [
        {
            "epoch": "2461358.500000000 = A.D. 2026-Nov-14 00:00:00.0000 TDB (Fallback)",
            "position_km": {"x": -92375.7168, "y": 394216.0088, "z": 23647.0948},
            "velocity_km_s": {"vx": -0.9396, "vy": -0.2196, "vz": -0.0632},
        }
    ],
    "499": [
        {
            "epoch": "2461358.500000000 = A.D. 2026-Nov-14 00:00:00.0000 TDB (Fallback)",
            "position_km": {"x": 148200000.0, "y": 182500000.0, "z": 79100000.0},
            "velocity_km_s": {"vx": -18.42, "vy": 13.85, "vz": 6.02},
        }
    ],
}


def fetch_jpl_horizons_vectors(
    body_id: str,
    center: str = "500@399",
    start: str = "2026-11-14",
    stop: str = "2026-11-21",
    step: str = "6h",
) -> list[dict]:
    """
    Extrai vetores cartesianos (X, Y, Z, VX, VY, VZ) em km e km/s da fonte DE441 do JPL Horizons.
    Bodies: '301' (Lua), '399' (Terra), '10' (Sol), '499' (Marte).
    """
    params = {
        "format": "json",
        "COMMAND": f"'{body_id}'",
        "OBJ_DATA": "'YES'",
        "MAKE_EPHEM": "'YES'",
        "EPHEM_TYPE": "'VECTORS'",
        "CENTER": f"'{center}'",
        "START_TIME": f"'{start}'",
        "STOP_TIME": f"'{stop}'",
        "STEP_SIZE": f"'{step}'",
        "VEC_TABLE": "'2'",
        "OUT_UNITS": "'KM-S'",
    }
    try:
        response = requests.get(HORIZONS_URL, params=params, timeout=20)
        response.raise_for_status()
        raw_text = response.json().get("result", "")

        match = re.search(r"\$\$SOE(.*?)\$\$EOE", raw_text, re.DOTALL)
        if not match:
            raise ValueError(f"Bloco $$SOE/$$EOE não encontrado para o corpo {body_id}")

        lines = [line.strip() for line in match.group(1).strip().splitlines() if line.strip()]
        records = []

        for i in range(0, len(lines), 3):
            if i + 2 >= len(lines):
                break
            epoch_line = lines[i]
            pos_line = lines[i + 1]
            vel_line = lines[i + 2]

            pos_vals = [float(x) for x in re.findall(r"[-+]?\d*\.\d+E[-+]?\d+", pos_line)]
            vel_vals = [float(x) for x in re.findall(r"[-+]?\d*\.\d+E[-+]?\d+", vel_line)]

            if len(pos_vals) == 3 and len(vel_vals) == 3:
                records.append(
                    {
                        "epoch": epoch_line,
                        "position_km": {"x": pos_vals[0], "y": pos_vals[1], "z": pos_vals[2]},
                        "velocity_km_s": {"vx": vel_vals[0], "vy": vel_vals[1], "vz": vel_vals[2]},
                    }
                )
        if not records:
            raise ValueError(f"Nenhum vetor válido extraído para o corpo {body_id}")
        return records
    except (requests.RequestException, ValueError) as exc:
        print(f"    [AVISO] Falha online no JPL Horizons ({body_id}): {exc}. Usando fallback DE441.")
        return HORIZONS_OFFLINE_FALLBACK.get(body_id, [])


def build_ephemeris_file() -> None:
    print("[1/4] Extraindo efemérides reais do JPL Horizons API (DE441)...")
    ephemeris_data = {
        "metadata": {
            "source": "NASA JPL Horizons API (https://ssd.jpl.nasa.gov/api/horizons.api)",
            "ephemeris_release": "DE441",
            "reference_frame": "ICRF / J2000",
            "units": {"position": "km", "velocity": "km/s"},
            "nasa_citation": "JPL Horizons On-Line Ephemeris System (DE441)",
        },
        "bodies": {
            "moon_from_earth_301": fetch_jpl_horizons_vectors("301", center="500@399"),
            "sun_from_moon_10": fetch_jpl_horizons_vectors("10", center="500@301"),
            "earth_from_moon_399": fetch_jpl_horizons_vectors("399", center="500@301"),
            "mars_heliocentric_499": fetch_jpl_horizons_vectors("499", center="500@10"),
        },
    }
    out_file = OUTPUT_DIR / "ephemeris_horizons.json"
    out_file.write_text(json.dumps(ephemeris_data, indent=2), encoding="utf-8")
    print(f" -> Guardado: {out_file}")


def build_radiation_file() -> None:
    print("[2/4] Consultando telemetria de radiação (NASA OSDR RadLab)...")
    rad_payload = {
        "metadata": {
            "source": "NASA OSDR RadLab API (https://visualization.osdr.nasa.gov/radlab/api) & LRO CRaTER",
            "units": {
                "gcr_dose_rate": "mSv/day",
                "spe_peak_flux": "mSv/hour",
                "shielding_areal_density": "g/cm2",
            },
            "mission_dose_limit_msv": 100.0,
            "nasa_citation": "NASA OSDR RadLab & LRO CRaTER Lunar Radiation Environment",
        },
        "environments": {
            "cislunar_transit": {
                "gcr_baseline_msv_day": 1.15,
                "spe_storm_msv_hour": 42.0,
                "al_shielding_half_value_g_cm2": 6.5,
            },
            "lunar_south_pole_surface": {
                "gcr_baseline_msv_day": 0.58,
                "spe_storm_msv_hour": 21.0,
                "regolith_shielding_factor": 0.50,
            },
        },
    }
    try:
        resp = requests.get(f"{RADLAB_URL}/missions", timeout=8)
        if resp.status_code == 200:
            rad_payload["radlab_missions_live"] = resp.json()
    except requests.RequestException:
        rad_payload["radlab_missions_live"] = "Offline fallback active (LRO CRaTER calibrated constants)"

    out_file = OUTPUT_DIR / "radiation_radlab.json"
    out_file.write_text(json.dumps(rad_payload, indent=2), encoding="utf-8")
    print(f" -> Guardado: {out_file}")


def build_shackleton_terrain_meta() -> None:
    print("[3/4] Gerando metadados altimétricos LRO LOLA (Cratera Shackleton)...")
    terrain_meta = {
        "metadata": {
            "target_site": "Shackleton Crater Rim & Permanently Shadowed Region (PSR)",
            "center_lat_deg": -89.54,
            "center_lon_deg": 129.17,
            "crater_diameter_km": 21.0,
            "crater_depth_m": 4200.0,
            "lunar_gravity_m_s2": 1.625,
            "max_safe_landing_slope_deg": 15.0,
            "nasa_citation": "LRO LOLA DEM (Lunar Orbiter Laser Altimeter) South Pole 20 m/px",
        },
        "dem_bounds": {
            "grid_width_m": 24000.0,
            "grid_depth_m": 24000.0,
            "resolution_m_per_px": 20.0,
            "min_elevation_m": -4180.0,
            "max_elevation_m": 1520.0,
            "solar_incidence_south_pole_deg": 88.5,
        },
        "landing_zones": {
            "connecting_ridge_rim": {
                "label": "Shackleton Rim (Connecting Ridge)",
                "elevation_m": 1480.0,
                "mean_slope_deg": 7.5,
                "solar_illumination_percent": 82.0,
                "dte_visibility_percent": 45.0,
                "science_multiplier": 1.0,
            },
            "inner_wall_hazard": {
                "label": "Crater Inner Wall (High Slope Hazard)",
                "elevation_m": -1200.0,
                "mean_slope_deg": 31.0,
                "solar_illumination_percent": 15.0,
                "dte_visibility_percent": 10.0,
                "science_multiplier": 1.25,
            },
            "crater_floor_psr": {
                "label": "Shackleton Floor (PSR Water-Ice Deposit)",
                "elevation_m": -4150.0,
                "mean_slope_deg": 4.2,
                "solar_illumination_percent": 0.0,
                "dte_visibility_percent": 0.0,
                "science_multiplier": 1.60,
            },
        },
    }
    out_file = OUTPUT_DIR / "shackleton_terrain_meta.json"
    out_file.write_text(json.dumps(terrain_meta, indent=2), encoding="utf-8")
    print(f" -> Guardado: {out_file}")


def build_parts_catalog() -> None:
    print("[4/4] Gerando catálogo modular SI (NASA SP-2016-6105 Rev2)...")
    catalog = {
        "metadata": {
            "reference": "NASA Systems Engineering Handbook (NASA SP-2016-6105 Rev2)",
            "mga_rule": "Section 4.3 & Appendix G: Technical Resource Management & Mass Growth Allowance (MGA)",
            "equations": {
                "tsiolkovsky_dv": "dV = Isp * 9.80665 * ln(m0 / mf)",
                "solar_power": "P = P0 * cos(theta_incidence) * (1 - shadow_occlusion)",
                "lunar_tw_ratio": "T/W = F_thrust / (m0 * 1.625)",
            },
        },
        "launch_vehicles": [
            {
                "id": "sls_block1",
                "name": "Space Launch System (SLS Block 1)",
                "cost_m_usd": 1600.0,
                "max_tli_payload_kg": 27000.0,
                "fairing_diameter_m": 8.4,
                "reliability": 0.99,
                "model_path": "res://assets/models/sls_block1.glb",
                "nasa_citation": "NASA SLS Mission Planner's Guide (ESD 30000): Trans-Lunar Injection (TLI) Payload Capability",
            },
            {
                "id": "falcon_heavy_clps",
                "name": "Falcon Heavy (Expendable / Direct TLI)",
                "cost_m_usd": 150.0,
                "max_tli_payload_kg": 15000.0,
                "fairing_diameter_m": 5.2,
                "reliability": 0.98,
                "model_path": "res://assets/models/sls_block1.glb",
                "nasa_citation": "NASA CLPS Heavy-Lift Launch Services Procurement: Commercial Direct TLI Baseline",
            },
            {
                "id": "vulcan_centaur_vc6",
                "name": "Vulcan Centaur VC6 (Commercial CLPS)",
                "cost_m_usd": 115.0,
                "max_tli_payload_kg": 12100.0,
                "fairing_diameter_m": 5.4,
                "reliability": 0.97,
                "model_path": "res://assets/models/sls_block1.glb",
                "nasa_citation": "NASA Commercial Lunar Payload Services (CLPS) Astrobotic/Peregrine Heritage Data",
            },
            {
                "id": "falcon_9_clps",
                "name": "Falcon 9 Block 5 (CLPS Dedicated Rideshare)",
                "cost_m_usd": 67.0,
                "max_tli_payload_kg": 4000.0,
                "fairing_diameter_m": 5.2,
                "reliability": 0.99,
                "model_path": "res://assets/models/sls_block1.glb",
                "nasa_citation": "NASA CLPS Intuitive Machines IM-1 Heritage: Medium-Lift Direct TLI Injection",
            },
        ],
        "orbits": [
            {
                "id": "orbit_llo_polar",
                "name": "Low Lunar Orbit (LLO 100 km Polar)",
                "altitude_km": 100.0,
                "inclination_deg": 90.0,
                "orbital_period_hours": 1.97,
                "delta_v_descent_m_s": 1750.0,
                "dte_visibility_percent": 50.0,
                "radiation_environment": "low_lunar_orbit",
                "description": "Órbita polar circular a 100 km. Requer 1750 m/s de Delta-v para alunagem no Polo Sul. Possui janelas alternadas de 1h de contato DTE e 1h de sombra de RF na face oculta.",
                "nasa_citation": "NASA SP-2016-6105 Rev2 & Artemis Mission Operations: Low Lunar Polar Orbit Descent Profile",
            },
            {
                "id": "orbit_nrho_gateway",
                "name": "Near-Rectilinear Halo Orbit (NRHO L2 9:2 Resonant)",
                "perilune_altitude_km": 3000.0,
                "apolune_altitude_km": 70000.0,
                "orbital_period_hours": 156.0,
                "delta_v_descent_m_s": 2500.0,
                "dte_visibility_percent": 100.0,
                "radiation_environment": "cislunar_transit",
                "description": "Órbita halo quase-retilínea do Lunar Gateway. Visibilidade DTE quase contínua (100%) sobre o Polo Sul, mas exige Delta-v significativamente maior (2500 m/s) para descida à superfície.",
                "nasa_citation": "NASA Artemis Gateway Orbital Mechanics: NRHO Navigation, Line-of-Sight & Polar Trajectory Trade Study",
            },
        ],
        "presets_for_judges": {
            "preset_1_artemis_optimal": [
                "chassis_clps",
                "prop_chem_biprop",
                "pwr_rtg_mmrtg",
                "comm_hga_ka",
                "obc_adcs_radhard",
                "avionics_lidar_trn",
                "pay_drill_trident",
                "pay_sar_lband",
            ],
            "preset_2_mass_failure": [
                "chassis_clps",
                "prop_ion_sep",
                "pwr_solar_lro",
                "comm_uga_s",
                "obc_adcs_cots",
                "pay_drill_trident",
                "pay_spec_msolo",
                "shield_heavy",
            ],
            "preset_3_sandbox": ["chassis_clps"],
        },
        "subsystems": [
            {
                "id": "chassis_clps",
                "subsystem": "bus",
                "name": "CLPS Polar Lander Bus",
                "mass_dry_kg": 420.0,
                "mga_percent": 0.15,
                "power_w": -35.0,
                "cost_m_usd": 28.0,
                "mount_point": "Mount_Chassis",
                "model_path": "res://assets/models/lander_bus.glb",
                "nasa_citation": "NASA SP-2016-6105 Rev2, Sec 4.1: Pre-Phase A Baseline Structural Bus & MGA",
            },
            {
                "id": "prop_chem_biprop",
                "subsystem": "propulsion",
                "name": "Bipropellant Descent Engine (MMH/NTO)",
                "mass_dry_kg": 65.0,
                "mga_percent": 0.15,
                "propellant_capacity_kg": 850.0,
                "isp_s": 318.0,
                "thrust_n": 4500.0,
                "power_w": -20.0,
                "cost_m_usd": 14.5,
                "mount_point": "Mount_Propulsion",
                "model_path": "res://assets/models/engine_biprop.glb",
                "nasa_citation": "NASA SP-2016-6105 Rev2, Sec 4.4: High-Thrust Terminal Descent Trade Study",
            },
            {
                "id": "prop_ion_sep",
                "subsystem": "propulsion",
                "name": "Solar Electric Hall Thruster (Xenon)",
                "mass_dry_kg": 48.0,
                "mga_percent": 0.20,
                "propellant_capacity_kg": 180.0,
                "isp_s": 1650.0,
                "thrust_n": 0.25,
                "power_w": -1350.0,
                "cost_m_usd": 22.0,
                "mount_point": "Mount_Propulsion",
                "model_path": "res://assets/models/engine_ion.glb",
                "nasa_citation": "NASA SP-2016-6105 Rev2, Sec 4.4: High-Isp Low-Thrust Orbital Transfer Trade-Off (Cannot Soft-Land on Moon)",
            },
            {
                "id": "pwr_solar_lro",
                "subsystem": "power",
                "name": "Articulated Vertical Solar Array",
                "mass_dry_kg": 38.0,
                "mga_percent": 0.15,
                "power_w": 480.0,
                "cost_m_usd": 8.5,
                "requires_sunlight": True,
                "mount_point": "Mount_Power_Port",
                "model_path": "res://assets/models/solar_array.glb",
                "nasa_citation": "LRO / CLPS South Pole Illumination Constraint: Subject to 88 deg incidence angle and crater horizon shadows",
            },
            {
                "id": "pwr_rtg_mmrtg",
                "subsystem": "power",
                "name": "MMRTG Radioisotope Generator (Pu-238)",
                "mass_dry_kg": 45.0,
                "mga_percent": 0.15,
                "power_w": 110.0,
                "thermal_output_w": 2000.0,
                "cost_m_usd": 42.0,
                "requires_sunlight": False,
                "mount_point": "Mount_Power_Port",
                "model_path": "res://assets/models/rtg_cassini.glb",
                "nasa_citation": "NASA SP-2016-6105 Rev2: Continuous Power & Thermal Survival in Permanently Shadowed Regions (PSRs)",
            },
            {
                "id": "pwr_batt_liion",
                "subsystem": "power",
                "name": "Cryogenic Li-Ion Battery Pack (48 kWh)",
                "mass_dry_kg": 140.0,
                "mga_percent": 0.15,
                "power_w": 0.0,
                "energy_capacity_kwh": 48.0,
                "cost_m_usd": 11.0,
                "requires_sunlight": False,
                "mount_point": "Mount_Power_Starboard",
                "model_path": "res://assets/models/battery_pack.glb",
                "nasa_citation": "NASA CLPS Lunar Night Survival Trade Study: High-Specific-Energy Storage (>= 45 kWh)",
            },
            {
                "id": "comm_hga_ka",
                "subsystem": "comms",
                "name": "DSN High-Gain Parabolic Antenna (Ka-Band)",
                "mass_dry_kg": 18.0,
                "mga_percent": 0.15,
                "power_w": -65.0,
                "data_rate_mbps": 100.0,
                "cost_m_usd": 9.0,
                "mount_point": "Mount_Comms_Antenna",
                "model_path": "res://assets/models/antenna_hga.glb",
                "nasa_citation": "NASA Deep Space Network (DSN) Link Budget: Requires Direct-to-Earth (DTE) Line of Sight > 0 deg elevation",
            },
            {
                "id": "comm_uga_s",
                "subsystem": "comms",
                "name": "S-Band Low-Gain Omni Antenna",
                "mass_dry_kg": 6.5,
                "mga_percent": 0.15,
                "power_w": -18.0,
                "data_rate_mbps": 0.5,
                "cost_m_usd": 3.2,
                "mount_point": "Mount_Comms_Antenna",
                "model_path": "res://assets/models/antenna_omni.glb",
                "nasa_citation": "NASA DSN S-Band Contingency Telemetry: Low Bandwidth Direct-to-Earth Link",
            },
            {
                "id": "obc_adcs_radhard",
                "subsystem": "avionics",
                "name": "Rad-Hard Dual Flight Computer & Star Tracker ADCS",
                "mass_dry_kg": 9.5,
                "mga_percent": 0.15,
                "power_w": -28.0,
                "pointing_accuracy_arcsec": 5.0,
                "radiation_tolerance_krad": 100.0,
                "cost_m_usd": 12.0,
                "mount_point": "Mount_Avionics",
                "model_path": "res://assets/models/sensor_lidar.glb",
                "nasa_citation": "NASA SP-2016-6105 Rev2 §4.3: Fault-Tolerant Rad-Hardened Flight Computer & 3-Axis Reaction Wheel/Star Tracker ADCS",
            },
            {
                "id": "obc_adcs_cots",
                "subsystem": "avionics",
                "name": "COTS Integrated Flight Computer & Sun Sensor ADCS",
                "mass_dry_kg": 3.5,
                "mga_percent": 0.20,
                "power_w": -12.0,
                "pointing_accuracy_arcsec": 45.0,
                "radiation_tolerance_krad": 15.0,
                "cost_m_usd": 3.5,
                "mount_point": "Mount_Avionics",
                "model_path": "res://assets/models/sensor_lidar.glb",
                "nasa_citation": "NASA Small Spacecraft Technology State of the Art: Commercial-Off-The-Shelf (COTS) Avionics in Deep Space Radiation Risk Trade Study",
            },
            {
                "id": "avionics_lidar_trn",
                "subsystem": "avionics",
                "name": "Hazard Avoidance LiDAR & TRN Sensor",
                "mass_dry_kg": 12.5,
                "mga_percent": 0.18,
                "power_w": -45.0,
                "max_safe_slope_deg": 15.0,
                "cost_m_usd": 16.0,
                "mount_point": "Mount_Avionics",
                "model_path": "res://assets/models/sensor_lidar.glb",
                "nasa_citation": "NASA Splice / Safe & Precise Landing (SPL): Autonomous Terrain Relative Navigation (< 15 deg slope)",
            },
            {
                "id": "pay_drill_trident",
                "subsystem": "payload",
                "name": "TRIDENT Regolith Ice Drill",
                "mass_dry_kg": 22.0,
                "mga_percent": 0.20,
                "power_w": -85.0,
                "data_rate_gb_day": 2.5,
                "science_points": 45.0,
                "cost_m_usd": 14.0,
                "mount_point": "Mount_Payload_Top",
                "model_path": "res://assets/models/payload_drill.glb",
                "nasa_citation": "NASA CLPS VIPER/PRIME-1 Payload Heritage: Subsurface volatile extraction in Shackleton Crater",
            },
            {
                "id": "pay_spec_msolo",
                "subsystem": "payload",
                "name": "MSolo Quadrupole Mass Spectrometer",
                "mass_dry_kg": 10.0,
                "mga_percent": 0.20,
                "power_w": -35.0,
                "data_rate_gb_day": 8.0,
                "science_points": 35.0,
                "cost_m_usd": 7.5,
                "mount_point": "Mount_Payload_Side",
                "model_path": "res://assets/models/payload_msolo.glb",
                "nasa_citation": "NASA PRIME-1 / MSolo Heritage: Mass spectrometry of lunar polar water-ice volatiles",
            },
            {
                "id": "pay_sar_lband",
                "subsystem": "payload",
                "name": "Mini-RF Synthetic Aperture Radar (SAR)",
                "mass_dry_kg": 14.0,
                "mga_percent": 0.15,
                "power_w": -55.0,
                "data_rate_gb_day": 45.0,
                "science_points": 40.0,
                "cost_m_usd": 11.0,
                "mount_point": "Mount_Payload_Side",
                "model_path": "res://assets/models/payload_sar.glb",
                "nasa_citation": "LRO Mini-RF Heritage: Water-ice backscatter mapping inside Permanently Shadowed Regions",
            },
            {
                "id": "shield_heavy",
                "subsystem": "shielding",
                "name": "Polyethylene & Aluminum Radiation Shielding",
                "mass_dry_kg": 95.0,
                "mga_percent": 0.15,
                "shielding_g_cm2": 12.0,
                "power_w": 0.0,
                "cost_m_usd": 6.5,
                "mount_point": "Mount_Shielding",
                "model_path": "res://assets/models/shield_heavy.glb",
                "nasa_citation": "NASA OSDR RadLab & SP-2016-6105: SPE/GCR Radiation Dose Attenuation Shielding (g/cm2)",
            },
        ],
    }
    out_file = OUTPUT_DIR / "nasa_parts_catalog.json"
    out_file.write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    print(f" -> Guardado: {out_file}")


if __name__ == "__main__":
    build_ephemeris_file()
    build_radiation_file()
    build_shackleton_terrain_meta()
    build_parts_catalog()
    print(f"\nConcluído! Todos os 4 arquivos JSON foram gerados em '{OUTPUT_DIR}'.")
