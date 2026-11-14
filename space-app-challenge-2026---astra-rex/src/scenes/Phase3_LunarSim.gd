class_name Phase3LunarSim
extends Control

## Phase 3: Phase D-E Shackleton Crater Descent & Surface Simulation.
## Aligns a 128x128 HeightMapShape3D and SurfaceTool ArrayMesh from the 16-bit LRO LOLA DEM,
## executes closed-loop PID terminal descent with lunar T/W lockout and slope tip-over,
## and drives DE441 solar/Earth 0.2s RayCast3D telemetry plus RadLab SPE storm events.

signal return_to_vab_requested()
signal proceed_to_debrief_requested()
signal descent_completed(survived: bool)

enum SimPhase {
	PRE_DESCENT = 0,
	DESCENDING = 1,
	ABORTED_LOCKOUT = 2,
	LANDED_NOMINAL = 3,
	LANDED_TIPOVER = 4
}

const HEIGHTMAP_PATH: String = "res://assets/terrain/shackleton_heightmap_16bit.png"
const GRID_RES: int = 128
const GRID_HALF_SPAN: float = 63.5
const START_AGL_METERS: float = 26.0
const RAYCAST_LENGTH: float = 95.0

# Calibrated grid coordinates (ix, iz) on the 128x128 LRO LOLA DEM
const ZONE_GRID_COORDS: Dictionary = {
	"connecting_ridge_rim": Vector2i(53, 80),
	"inner_wall_hazard": Vector2i(77, 75),
	"crater_floor_psr": Vector2i(109, 95)
}

const ZONE_LABELS: Dictionary = {
	"connecting_ridge_rim": "Shackleton Rim",
	"inner_wall_hazard": "Crater Wall (>15 deg)",
	"crater_floor_psr": "Crater Floor (PSR)"
}

const COLOR_PANEL_BG: Color = Color(0.055, 0.082, 0.145, 0.92)
const COLOR_BOTTOM_BG: Color = Color(0.043, 0.067, 0.125, 0.94)
const COLOR_OK: Color = Color(0.063, 0.725, 0.506, 1.0)
const COLOR_WARN: Color = Color(0.961, 0.620, 0.043, 1.0)
const COLOR_CRIT: Color = Color(0.937, 0.267, 0.267, 1.0)
const COLOR_ACCENT: Color = Color(0.220, 0.741, 0.973, 1.0)
const COLOR_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_MUTED: Color = Color(0.580, 0.639, 0.722, 1.0)

@onready var lunar_world: Node3D = %LunarWorld
@onready var terrain_body: StaticBody3D = %TerrainBody
@onready var terrain_mesh: MeshInstance3D = %TerrainMesh
@onready var terrain_collision_shape: CollisionShape3D = %TerrainCollisionShape
@onready var zone_markers_root: Node3D = %ZoneMarkers

@onready var sun_light: DirectionalLight3D = %SunLight
@onready var earth_fill_light: DirectionalLight3D = %EarthFillLight

@onready var lander_pivot: Node3D = %LanderPivot
@onready var lander_chassis: LanderChassis = %LanderChassis
@onready var thruster_plume: MeshInstance3D = %ThrusterPlume
@onready var landing_raycast: RayCast3D = %LandingRayCast
@onready var solar_raycast: RayCast3D = %SolarRayCast
@onready var earth_dte_raycast: RayCast3D = %EarthDTERayCast

@onready var camera_pivot: Node3D = %CameraPivot
@onready var lunar_camera: Camera3D = %LunarCamera
@onready var raycast_timer: Timer = %RaycastTimer

@onready var left_panel: PanelContainer = %LeftPanel
@onready var bottom_bar: PanelContainer = %BottomBar
@onready var viewport_catcher: Control = %ViewportInputCatcher

@onready var sim_status_pill: Label = %SimStatusPill
@onready var telemetry_zone_label: Label = %TelemetryZoneLabel
@onready var telemetry_agl_label: Label = %TelemetryAGLLabel
@onready var telemetry_vel_label: Label = %TelemetryVelLabel
@onready var telemetry_slope_label: Label = %TelemetrySlopeLabel
@onready var telemetry_solar_label: Label = %TelemetrySolarLabel
@onready var telemetry_dte_label: Label = %TelemetryDITELabel
@onready var telemetry_rad_label: Label = %TelemetryRadLabel
@onready var telemetry_day_label: Label = %TelemetryDayLabel

@onready var btn_zone_rim: Button = %BtnZoneRim
@onready var btn_zone_wall: Button = %BtnZoneWall
@onready var btn_zone_psr: Button = %BtnZonePSR
@onready var btn_lidar_overlay: Button = %BtnLidarOverlay
@onready var btn_reset_cam: Button = %BtnResetCam

@onready var btn_back_vab: Button = %BtnBackVAB
@onready var btn_restart_descent: Button = %BtnRestartDescent
@onready var btn_spe_storm: Button = %BtnSPEStorm
@onready var btn_safe_mode: Button = %BtnSafeMode
@onready var btn_advance_days: Button = %BtnAdvanceDays
@onready var btn_proceed_debrief: Button = %BtnProceedDebrief

var _height_grid: PackedFloat32Array = PackedFloat32Array()
var _heightmap_rf_image: Image = null
var _terrain_pbr_mat: StandardMaterial3D = null
var _terrain_shader_mat: ShaderMaterial = null
var _zone_marker_meshes: Dictionary = {}

var _sim_phase: SimPhase = SimPhase.PRE_DESCENT
var _is_sim_active: bool = false
var _lander_vel_y: float = 0.0
var _pid_integral: float = 0.0
var _pid_prev_error: float = 0.0
var _sim_propellant_remaining_kg: float = 0.0
var _sim_elapsed_s: float = 0.0
var _current_throttle: float = 0.0
var _touchdown_slope_deg: float = 0.0
var _tipover_target_roll_deg: float = 0.0
var _trn_divert_applied: bool = false

var _elapsed_surface_days: float = 0.0
var _ephemeris_epoch_index: int = 0
var _sun_dir_world: Vector3 = Vector3(-0.95, 0.032, -0.31).normalized()
var _earth_dir_world: Vector3 = Vector3(-0.92, 0.114, -0.38).normalized()
var _solar_occluded: bool = false
var _dte_occluded: bool = false
var _spe_active: bool = false
var _safe_mode_active: bool = false

var _cam_yaw: float = 0.72
var _cam_pitch: float = -0.46
var _cam_distance: float = 18.5
var _target_yaw: float = 0.72
var _target_pitch: float = -0.46
var _target_distance: float = 18.5
var _is_dragging: bool = false
var _debrief_highlight_pulse: float = 0.0


func _ready() -> void:
	_style_panels()
	_enforce_double_sided_materials(lunar_world)
	_build_shackleton_terrain()
	_build_zone_markers()
	_setup_raycast_exceptions()
	_connect_signals()
	_update_ephemeris_vectors()
	_refresh_zone_buttons()
	_refresh_ui_labels()
	set_lunar_sim_active(false)


func _enforce_double_sided_materials(root_node: Node) -> void:
	if not is_instance_valid(root_node):
		return
	if root_node == terrain_mesh or root_node == thruster_plume:
		return
	if root_node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = root_node as MeshInstance3D
		if mesh_inst.material_override is BaseMaterial3D:
			var override_dup: BaseMaterial3D = (mesh_inst.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
			override_dup.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_inst.material_override = override_dup
		elif mesh_inst.mesh != null:
			var surf_count: int = mesh_inst.mesh.get_surface_count()
			for surface_idx: int in range(surf_count):
				var mat: Material = mesh_inst.get_active_material(surface_idx)
				if mat == null:
					mat = mesh_inst.mesh.surface_get_material(surface_idx)
				if mat is BaseMaterial3D:
					var dup: BaseMaterial3D = (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dup.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_inst.set_surface_override_material(surface_idx, dup)
	for child: Node in root_node.get_children():
		_enforce_double_sided_materials(child)


func set_lunar_sim_active(active: bool) -> void:
	_is_sim_active = active
	visible = active
	if is_instance_valid(lunar_world):
		lunar_world.visible = active
	if is_instance_valid(lunar_camera):
		lunar_camera.current = active
	if is_instance_valid(raycast_timer):
		if active:
			raycast_timer.start()
		else:
			raycast_timer.stop()

	if active:
		_spe_active = MissionState.spe_storm_active
		_safe_mode_active = MissionState.safe_mode_active
		btn_spe_storm.set_pressed_no_signal(_spe_active)
		btn_safe_mode.set_pressed_no_signal(_safe_mode_active)
		_refresh_zone_buttons()
		start_or_restart_descent()
		_perform_celestial_raycasts()
		_update_camera_transform(true)


func _process(delta: float) -> void:
	if not _is_sim_active:
		return

	var lerp_w: float = clampf(delta * 9.0, 0.0, 1.0)
	_cam_yaw = lerpf(_cam_yaw, _target_yaw, lerp_w)
	_cam_pitch = lerpf(_cam_pitch, _target_pitch, lerp_w)
	_cam_distance = lerpf(_cam_distance, _target_distance, lerp_w)
	_update_camera_transform(false)

	if _sim_phase == SimPhase.LANDED_TIPOVER:
		lander_pivot.rotation_degrees.z = lerpf(lander_pivot.rotation_degrees.z, _tipover_target_roll_deg, clampf(delta * 4.0, 0.0, 1.0))

	if _sim_phase == SimPhase.ABORTED_LOCKOUT or _sim_phase == SimPhase.LANDED_TIPOVER:
		_debrief_highlight_pulse += delta * 4.0
		var glow: float = 0.5 + 0.5 * sin(_debrief_highlight_pulse)
		_style_cta_button(btn_proceed_debrief, Color(0.75 + 0.25 * glow, 0.24, 0.24, 1.0), Color(0.35 + 0.20 * glow, 0.08, 0.10, 0.98))
	else:
		_style_cta_button(btn_proceed_debrief, COLOR_ACCENT, Color(0.06, 0.28, 0.44, 0.98))


func _physics_process(delta: float) -> void:
	if not _is_sim_active or _sim_phase != SimPhase.DESCENDING:
		return

	_sim_elapsed_s += delta
	var target_xz: Vector2 = _get_zone_world_xz(MissionState.selected_landing_zone_id)
	var ground_y: float = _sample_ground_y(lander_pivot.position.x, lander_pivot.position.z)
	var agl_m: float = maxf(0.0, lander_pivot.position.y - ground_y)

	var can_land_info: Dictionary = MissionState.can_safely_land_on_moon()
	var can_land: bool = bool(can_land_info.get("can_land", false))
	var reason: String = str(can_land_info.get("reason", "NOMINAL"))
	var m0_kg: float = maxf(1.0, MissionState.m0_wet_kg)
	var max_thrust_n: float = MissionState.total_thrust_n

	if not can_land and (reason == "CRITICAL_THRUST_DEFICIT" or reason == "NO_PROPULSION_MODULE"):
		# Unarrested descent under lunar gravity: thrust cannot overcome lunar weight
		var accel_y: float = (max_thrust_n / m0_kg) - MissionState.LUNAR_GRAVITY_M_S2
		_lander_vel_y += accel_y * delta * 3.5
		lander_pivot.position.y += _lander_vel_y * delta
		_current_throttle = 1.0 if max_thrust_n > 0.0 else 0.0
		_update_plume_visual(_current_throttle > 0.0, 0.35)

		if _sim_elapsed_s >= 2.2 or lander_pivot.position.y <= ground_y + 1.5:
			lander_pivot.position.y = maxf(lander_pivot.position.y, ground_y + 1.5)
			_sim_phase = SimPhase.ABORTED_LOCKOUT
			_lander_vel_y = 0.0
			_update_plume_visual(false, 0.0)
			_apply_status_pill("ABORT: T/W < 1.0 — Insufficient Lunar Thrust", COLOR_CRIT)
			MissionState.recalculate_all_telemetry(true)
			_refresh_ui_labels()
			descent_completed.emit(false)
		else:
			_refresh_ui_labels()
		return

	if not can_land and reason == "PROPELLANT_DV_SHORTFALL":
		# Burns until propellant exhaustion mid-descent, then aborts
		if _sim_elapsed_s < 1.6 and _sim_propellant_remaining_kg > 0.0:
			_sim_propellant_remaining_kg = maxf(0.0, _sim_propellant_remaining_kg - 220.0 * delta)
			_lander_vel_y = lerpf(_lander_vel_y, -2.5, delta * 2.0)
			lander_pivot.position.y += _lander_vel_y * delta
			_update_plume_visual(true, 0.8)
		else:
			_sim_phase = SimPhase.ABORTED_LOCKOUT
			_lander_vel_y = 0.0
			_update_plume_visual(false, 0.0)
			_apply_status_pill("ABORT: Δv SHORTFALL — Propellant Depleted", COLOR_CRIT)
			MissionState.recalculate_all_telemetry(true)
			descent_completed.emit(false)
		_refresh_ui_labels()
		return

	# Nominal closed-loop PID terminal descent (scaled visually so 26m completes in ~5.5s)
	if MissionState.selected_landing_zone_id == "inner_wall_hazard" and MissionState.has_lidar_trn and agl_m < 13.0:
		if not _trn_divert_applied:
			_trn_divert_applied = true
			_apply_status_pill("TRN ACTIVE: Diverting to <15° Pad", COLOR_ACCENT)
		# Lateral hazard avoidance micro-divert
		lander_pivot.position.x = lerpf(lander_pivot.position.x, target_xz.x - 1.4, delta * 1.8)
		lander_pivot.position.z = lerpf(lander_pivot.position.z, target_xz.y + 0.8, delta * 1.8)

	var v_ref: float = -clampf(sqrt(2.0 * 0.72 * MissionState.LUNAR_GRAVITY_M_S2 * agl_m), 0.75, 7.5)
	var vel_err: float = v_ref - _lander_vel_y
	_pid_integral = clampf(_pid_integral + vel_err * delta, -4.0, 4.0)
	var vel_deriv: float = (vel_err - _pid_prev_error) / maxf(0.001, delta)
	_pid_prev_error = vel_err

	var hover_accel: float = MissionState.LUNAR_GRAVITY_M_S2
	var cmd_accel: float = hover_accel + (2.6 * vel_err) + (0.25 * _pid_integral) + (0.35 * vel_deriv)
	var max_accel: float = maxf(MissionState.LUNAR_GRAVITY_M_S2 * 1.1, max_thrust_n / m0_kg)
	_current_throttle = clampf(cmd_accel / max_accel, 0.12, 1.0)

	var net_accel_y: float = (_current_throttle * max_accel) - MissionState.LUNAR_GRAVITY_M_S2
	_lander_vel_y += net_accel_y * delta
	lander_pivot.position.y += _lander_vel_y * delta

	var mass_flow: float = (max_thrust_n * _current_throttle) / maxf(100.0, MissionState.effective_isp_s * MissionState.G0_M_S2)
	_sim_propellant_remaining_kg = maxf(0.0, _sim_propellant_remaining_kg - mass_flow * delta * 8.0)

	_update_plume_visual(true, _current_throttle)

	var post_ground_y: float = _sample_ground_y(lander_pivot.position.x, lander_pivot.position.z)
	if lander_pivot.position.y <= post_ground_y + 0.04:
		lander_pivot.position.y = post_ground_y
		_on_touchdown()
	else:
		_refresh_ui_labels()


func _on_touchdown() -> void:
	_lander_vel_y = 0.0
	_current_throttle = 0.0
	_update_plume_visual(false, 0.0)

	landing_raycast.global_position = lander_pivot.global_position + Vector3(0.0, 2.0, 0.0)
	landing_raycast.target_position = Vector3(0.0, -25.0, 0.0)
	landing_raycast.force_raycast_update()
	var sampled_slope: float = _compute_terrain_slope_deg(lander_pivot.position.x, lander_pivot.position.z)
	if landing_raycast.is_colliding():
		var hit_normal: Vector3 = landing_raycast.get_collision_normal().normalized()
		var ray_slope: float = rad_to_deg(acos(clampf(hit_normal.dot(Vector3.UP), -1.0, 1.0)))
		sampled_slope = maxf(sampled_slope, ray_slope)

	var zone_id: String = MissionState.selected_landing_zone_id
	var zone_data: Dictionary = NasaDataLoader.get_landing_zone(zone_id)
	var zone_mean_slope: float = float(zone_data.get("mean_slope_deg", 7.5))

	if zone_id == "inner_wall_hazard":
		if MissionState.has_lidar_trn:
			_touchdown_slope_deg = 11.8
			_sim_phase = SimPhase.LANDED_NOMINAL
			lander_pivot.rotation_degrees = Vector3.ZERO
			_apply_status_pill("TOUCHDOWN: TRN Stabilized (11.8° <= 15°)", COLOR_OK)
		else:
			_touchdown_slope_deg = maxf(zone_mean_slope, sampled_slope)
			_sim_phase = SimPhase.LANDED_TIPOVER
			_tipover_target_roll_deg = 58.0
			_apply_status_pill("FAILURE: SLOPE TIP-OVER (>15° NO TRN)", COLOR_CRIT)
	else:
		_touchdown_slope_deg = zone_mean_slope if sampled_slope < 2.0 else clampf(sampled_slope, 1.0, 14.5)
		_sim_phase = SimPhase.LANDED_NOMINAL
		lander_pivot.rotation_degrees = Vector3.ZERO
		_apply_status_pill("TOUCHDOWN NOMINAL • SURFACE OPS", COLOR_OK)

	MissionState.record_touchdown_slope(_touchdown_slope_deg)
	_perform_celestial_raycasts()
	_refresh_ui_labels()
	descent_completed.emit(_sim_phase == SimPhase.LANDED_NOMINAL)


func start_or_restart_descent() -> void:
	var zone_id: String = MissionState.selected_landing_zone_id
	var target_xz: Vector2 = _get_zone_world_xz(zone_id)
	var ground_y: float = _sample_ground_y(target_xz.x, target_xz.y)

	lander_pivot.position = Vector3(target_xz.x, ground_y + START_AGL_METERS, target_xz.y)
	lander_pivot.rotation_degrees = Vector3.ZERO
	_lander_vel_y = -2.2
	_pid_integral = 0.0
	_pid_prev_error = 0.0
	_sim_elapsed_s = 0.0
	_current_throttle = 0.0
	_trn_divert_applied = false
	_sim_propellant_remaining_kg = MissionState.propellant_mass_kg
	_touchdown_slope_deg = float(NasaDataLoader.get_landing_zone(zone_id).get("mean_slope_deg", 7.5))
	_sim_phase = SimPhase.DESCENDING

	var can_land_info: Dictionary = MissionState.can_safely_land_on_moon()
	if bool(can_land_info.get("can_land", false)):
		_apply_status_pill("PID TERMINAL DESCENT ACTIVE", COLOR_ACCENT)
	else:
		_apply_status_pill("PRE-DESCENT WARNING: %s" % str(can_land_info.get("reason", "LOCKOUT")), COLOR_WARN)

	camera_pivot.position = Vector3(target_xz.x, ground_y + 2.5, target_xz.y)
	_update_zone_marker_highlights()
	_update_plume_visual(MissionState.total_thrust_n > 0.0, 0.5)
	_refresh_ui_labels()


func _build_shackleton_terrain() -> void:
	var bounds: Dictionary = NasaDataLoader.get_terrain_bounds()
	var span_m: float = maxf(1.0, float(bounds.get("grid_width_m", 20480.0)))
	var min_elev_m: float = float(bounds.get("min_elevation_m", -2872.5))
	var amp_m: float = float(bounds.get("total_vertical_amplitude_m", 4611.0))

	# Scale vertical elevation cleanly into Godot world units (128x128 grid = 1:1 slope ratio)
	var world_scale: float = float(GRID_RES) / span_m
	var world_min_y: float = min_elev_m * world_scale
	var world_amp_y: float = amp_m * world_scale

	var src_img: Image = null
	if ResourceLoader.exists(HEIGHTMAP_PATH):
		var res: Resource = ResourceLoader.load(HEIGHTMAP_PATH)
		if res is Texture2D:
			src_img = (res as Texture2D).get_image()
		elif res is Image:
			src_img = (res as Image).duplicate() as Image

	if src_img != null and not src_img.is_empty():
		if src_img.is_compressed():
			src_img.decompress()
		src_img.resize(GRID_RES, GRID_RES, Image.INTERPOLATE_BILINEAR)
		src_img.convert(Image.FORMAT_RF)

	_heightmap_rf_image = Image.create(GRID_RES, GRID_RES, false, Image.FORMAT_RF)
	_height_grid.resize(GRID_RES * GRID_RES)

	for iz: int in range(GRID_RES):
		for ix: int in range(GRID_RES):
			var norm_h: float = 0.0
			if src_img != null and not src_img.is_empty():
				norm_h = clampf(src_img.get_pixel(ix, iz).r, 0.0, 1.0)
			else:
				# Deterministic fallback Shackleton bowl if image unavailable
				var dx: float = (float(ix) - GRID_HALF_SPAN) / GRID_HALF_SPAN
				var dz: float = (float(iz) - GRID_HALF_SPAN) / GRID_HALF_SPAN
				norm_h = clampf(sqrt(dx * dx + dz * dz) * 0.85, 0.0, 1.0)

			var world_h: float = world_min_y + norm_h * world_amp_y
			_height_grid[iz * GRID_RES + ix] = world_h
			_heightmap_rf_image.set_pixel(ix, iz, Color(world_h, 0.0, 0.0, 1.0))

	var hm_shape: HeightMapShape3D = HeightMapShape3D.new()
	hm_shape.map_width = GRID_RES
	hm_shape.map_depth = GRID_RES
	hm_shape.map_data = _height_grid
	terrain_collision_shape.shape = hm_shape
	terrain_collision_shape.transform = Transform3D.IDENTITY

	# Build synchronized SurfaceTool ArrayMesh from exact same _height_grid
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	var slopes_deg: PackedFloat32Array = PackedFloat32Array()
	slopes_deg.resize(GRID_RES * GRID_RES)
	for iz: int in range(GRID_RES):
		for ix: int in range(GRID_RES):
			var ix0: int = maxi(0, ix - 1)
			var ix1: int = mini(GRID_RES - 1, ix + 1)
			var iz0: int = maxi(0, iz - 1)
			var iz1: int = mini(GRID_RES - 1, iz + 1)
			var h_l: float = _height_grid[iz * GRID_RES + ix0]
			var h_r: float = _height_grid[iz * GRID_RES + ix1]
			var h_u: float = _height_grid[iz0 * GRID_RES + ix]
			var h_d: float = _height_grid[iz1 * GRID_RES + ix]
			var span_x: float = maxf(1.0, float(ix1 - ix0))
			var span_z: float = maxf(1.0, float(iz1 - iz0))
			var n: Vector3 = Vector3((h_l - h_r) / span_x, 1.0, (h_u - h_d) / span_z).normalized()
			slopes_deg[iz * GRID_RES + ix] = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))

	var add_v: Callable = func(gx: int, gz: int) -> void:
		var idx: int = gz * GRID_RES + gx
		var pos: Vector3 = Vector3(float(gx) - GRID_HALF_SPAN, _height_grid[idx], float(gz) - GRID_HALF_SPAN)
		var u: float = float(gx) / float(GRID_RES)
		var v: float = float(gz) / float(GRID_RES)
		var col: Color = _regolith_color(_height_grid[idx], world_min_y, world_amp_y, slopes_deg[idx])
		st.set_color(col)
		st.set_uv(Vector2(u, v) * 16.0)
		st.add_vertex(pos)

	for iz: int in range(GRID_RES - 1):
		for ix: int in range(GRID_RES - 1):
			# Clockwise winding from +Y facing up
			add_v.call(ix, iz)
			add_v.call(ix + 1, iz)
			add_v.call(ix, iz + 1)

			add_v.call(ix + 1, iz)
			add_v.call(ix + 1, iz + 1)
			add_v.call(ix, iz + 1)

	st.index()
	st.generate_normals()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	terrain_mesh.mesh = mesh

	_terrain_pbr_mat = StandardMaterial3D.new()
	_terrain_pbr_mat.vertex_color_use_as_albedo = true
	_terrain_pbr_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_terrain_pbr_mat.roughness = 0.92
	_terrain_pbr_mat.metallic = 0.02
	if ResourceLoader.exists("res://assets/terrain/regolith_albedo.webp"):
		_terrain_pbr_mat.albedo_texture = ResourceLoader.load("res://assets/terrain/regolith_albedo.webp") as Texture2D
	if ResourceLoader.exists("res://assets/terrain/regolith_normal.webp"):
		_terrain_pbr_mat.normal_enabled = true
		_terrain_pbr_mat.normal_texture = ResourceLoader.load("res://assets/terrain/regolith_normal.webp") as Texture2D
		_terrain_pbr_mat.normal_scale = 0.85

	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform float lidar_overlay : hint_range(0.0, 1.0) = 1.0;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base_col = COLOR.rgb;
	float grain = fract(sin(dot(floor(v_world_pos.xz * 4.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 regolith = base_col * (0.92 + 0.16 * grain);
	float cos_slope = clamp(dot(normalize(v_world_normal), vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	float slope_deg = degrees(acos(cos_slope));
	float hazard = smoothstep(14.5, 16.0, slope_deg);
	vec2 grid_f = abs(fract(v_world_pos.xz * 0.5 - 0.5) - 0.5);
	float grid_line = 1.0 - smoothstep(0.02, 0.06, min(grid_f.x, grid_f.y));
	vec3 lidar_col = mix(vec3(0.10, 0.72, 0.55), vec3(0.95, 0.22, 0.22), hazard);
	vec3 final_albedo = mix(regolith, mix(regolith, lidar_col, 0.55 + 0.25 * grid_line), lidar_overlay);
	ALBEDO = final_albedo;
	ROUGHNESS = 0.94;
	METALLIC = 0.02;
}
"""
	_terrain_shader_mat = ShaderMaterial.new()
	_terrain_shader_mat.shader = shader
	_terrain_shader_mat.set_shader_parameter("lidar_overlay", 1.0)
	terrain_mesh.material_override = _terrain_pbr_mat


func _regolith_color(world_h: float, world_min_y: float, world_amp_y: float, slope_deg: float = 0.0) -> Color:
	var t: float = clampf((world_h - world_min_y) / maxf(0.1, world_amp_y), 0.0, 1.0)
	var c_low: Color = Color(0.22, 0.25, 0.30, 1.0)
	var c_mid: Color = Color(0.46, 0.48, 0.52, 1.0)
	var c_high: Color = Color(0.68, 0.70, 0.74, 1.0)
	var base_col: Color = c_low.lerp(c_mid, t * 2.0) if t < 0.5 else c_mid.lerp(c_high, (t - 0.5) * 2.0)
	if slope_deg > 15.0:
		var hazard_t: float = clampf((slope_deg - 15.0) / 14.0, 0.18, 0.72)
		var hazard_col: Color = Color(0.88, 0.42, 0.32, 1.0)
		base_col = base_col.lerp(hazard_col, hazard_t)
	return base_col


func _build_zone_markers() -> void:
	for child: Node in zone_markers_root.get_children():
		child.queue_free()
	_zone_marker_meshes.clear()

	for zone_id_var: Variant in ZONE_GRID_COORDS.keys():
		var zone_id: String = str(zone_id_var)
		var xz: Vector2 = _get_zone_world_xz(zone_id)
		var y_val: float = _sample_ground_y(xz.x, xz.y)

		var ring: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 1.6
		torus.outer_radius = 2.05
		ring.mesh = torus
		ring.position = Vector3(xz.x, y_val + 0.18, xz.y)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = COLOR_ACCENT
		ring.material_override = mat

		zone_markers_root.add_child(ring)
		_zone_marker_meshes[zone_id] = ring

	_update_zone_marker_highlights()


func _update_zone_marker_highlights() -> void:
	var active_id: String = MissionState.selected_landing_zone_id
	for zone_id_var: Variant in _zone_marker_meshes.keys():
		var zone_id: String = str(zone_id_var)
		var ring: MeshInstance3D = _zone_marker_meshes[zone_id] as MeshInstance3D
		if not is_instance_valid(ring):
			continue
		var mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
		if zone_id == active_id:
			ring.scale = Vector3(1.25, 1.25, 1.25)
			if mat != null:
				mat.albedo_color = COLOR_WARN if zone_id == "inner_wall_hazard" else COLOR_OK
		else:
			ring.scale = Vector3(0.85, 0.85, 0.85)
			if mat != null:
				mat.albedo_color = Color(0.45, 0.55, 0.68, 0.65)


func _setup_raycast_exceptions() -> void:
	var collider: CollisionObject3D = lander_chassis.get_node_or_null("ChassisCollider") as CollisionObject3D
	if collider != null:
		landing_raycast.add_exception(collider)
		solar_raycast.add_exception(collider)
		earth_dte_raycast.add_exception(collider)


func _get_zone_world_xz(zone_id: String) -> Vector2:
	var grid_pt: Vector2i = ZONE_GRID_COORDS.get(zone_id, ZONE_GRID_COORDS["connecting_ridge_rim"]) as Vector2i
	return Vector2(float(grid_pt.x) - GRID_HALF_SPAN, float(grid_pt.y) - GRID_HALF_SPAN)


func _sample_ground_y(world_x: float, world_z: float) -> float:
	if _height_grid.is_empty():
		return 0.0
	var gx: float = clampf(world_x + GRID_HALF_SPAN, 0.0, float(GRID_RES - 1))
	var gz: float = clampf(world_z + GRID_HALF_SPAN, 0.0, float(GRID_RES - 1))
	var ix0: int = clampi(int(floor(gx)), 0, GRID_RES - 1)
	var iz0: int = clampi(int(floor(gz)), 0, GRID_RES - 1)
	var ix1: int = mini(GRID_RES - 1, ix0 + 1)
	var iz1: int = mini(GRID_RES - 1, iz0 + 1)
	var tx: float = gx - float(ix0)
	var tz: float = gz - float(iz0)

	var h00: float = _height_grid[iz0 * GRID_RES + ix0]
	var h10: float = _height_grid[iz0 * GRID_RES + ix1]
	var h01: float = _height_grid[iz1 * GRID_RES + ix0]
	var h11: float = _height_grid[iz1 * GRID_RES + ix1]
	var hx0: float = lerpf(h00, h10, tx)
	var hx1: float = lerpf(h01, h11, tx)
	return lerpf(hx0, hx1, tz)


func _compute_terrain_slope_deg(world_x: float, world_z: float) -> float:
	var h_l: float = _sample_ground_y(world_x - 1.0, world_z)
	var h_r: float = _sample_ground_y(world_x + 1.0, world_z)
	var h_u: float = _sample_ground_y(world_x, world_z - 1.0)
	var h_d: float = _sample_ground_y(world_x, world_z + 1.0)
	var dh_dx: float = (h_r - h_l) * 0.5
	var dh_dz: float = (h_d - h_u) * 0.5
	var grad_mag: float = sqrt(dh_dx * dh_dx + dh_dz * dh_dz)
	return rad_to_deg(atan(grad_mag))


func _update_ephemeris_vectors() -> void:
	# Anchor epoch 0 DE441 Sun azimuth onto WNW grazing Shackleton vector so Rim stays sunlit and PSR stays occluded
	var sun0: Vector3 = NasaDataLoader.get_sun_direction_unit(0)
	var sun_now: Vector3 = NasaDataLoader.get_sun_direction_unit(_ephemeris_epoch_index)
	var az0: float = atan2(sun0.z, sun0.x)
	var az_now: float = atan2(sun_now.z, sun_now.x)
	var delta_az: float = az_now - az0

	var base_sun_az: float = atan2(-0.31, -0.95)
	var cur_sun_az: float = base_sun_az + delta_az
	var sun_elev_rad: float = deg_to_rad(1.85)
	_sun_dir_world = Vector3(
		cos(sun_elev_rad) * cos(cur_sun_az),
		sin(sun_elev_rad),
		cos(sun_elev_rad) * sin(cur_sun_az)
	).normalized()

	var earth0: Vector3 = NasaDataLoader.get_earth_direction_unit(0)
	var earth_now: Vector3 = NasaDataLoader.get_earth_direction_unit(_ephemeris_epoch_index)
	var e_az0: float = atan2(earth0.z, earth0.x)
	var e_az_now: float = atan2(earth_now.z, earth_now.x)
	var e_delta_az: float = e_az_now - e_az0

	var base_earth_az: float = atan2(-0.38, -0.92)
	var cur_earth_az: float = base_earth_az + e_delta_az
	var earth_elev_rad: float = deg_to_rad(6.5)
	_earth_dir_world = Vector3(
		cos(earth_elev_rad) * cos(cur_earth_az),
		sin(earth_elev_rad),
		cos(earth_elev_rad) * sin(cur_earth_az)
	).normalized()

	if is_instance_valid(sun_light):
		# DirectionalLight3D shines along its -Z basis axis
		sun_light.look_at(sun_light.global_position - _sun_dir_world, Vector3.UP)
	if is_instance_valid(earth_fill_light):
		earth_fill_light.look_at(earth_fill_light.global_position - _earth_dir_world, Vector3.UP)


func _on_raycast_timer_timeout() -> void:
	if not _is_sim_active:
		return
	_perform_celestial_raycasts()


func _perform_celestial_raycasts() -> void:
	if not is_instance_valid(solar_raycast) or not is_instance_valid(earth_dte_raycast):
		return

	# Raycast from spacecraft antenna/array height (+1.2m above footpads)
	var origin: Vector3 = lander_pivot.global_position + Vector3(0.0, 1.2, 0.0)
	solar_raycast.global_position = origin
	solar_raycast.target_position = _sun_dir_world * RAYCAST_LENGTH
	solar_raycast.force_raycast_update()
	_solar_occluded = solar_raycast.is_colliding()

	earth_dte_raycast.global_position = origin
	earth_dte_raycast.target_position = _earth_dir_world * RAYCAST_LENGTH
	earth_dte_raycast.force_raycast_update()
	var earth_blocked_by_rim: bool = earth_dte_raycast.is_colliding()

	# NRHO L2 9:2 orbital geometry provides high-elevation polar relay even when low-elevation horizon is masked
	var effective_dte_occluded: bool = earth_blocked_by_rim and not MissionState.orbit_id_is_nrho()
	_dte_occluded = effective_dte_occluded

	var incidence_deg: float = 90.0 if _solar_occluded else 88.15
	if _solar_occluded != MissionState.in_psr_shadow or absf(incidence_deg - MissionState.solar_incidence_deg) > 0.5:
		MissionState.set_solar_environment(_solar_occluded, incidence_deg)
	if _dte_occluded != MissionState.dte_occluded:
		MissionState.set_dte_occluded(_dte_occluded)

	_refresh_ui_labels()


func _update_plume_visual(active: bool, throttle: float) -> void:
	if not is_instance_valid(thruster_plume):
		return
	thruster_plume.visible = active and throttle > 0.05
	if thruster_plume.visible:
		var scale_y: float = clampf(0.45 + throttle * 1.15, 0.4, 1.8)
		var scale_xz: float = clampf(0.65 + throttle * 0.45, 0.5, 1.2)
		thruster_plume.scale = Vector3(scale_xz, scale_y, scale_xz)
		thruster_plume.position.y = 0.25 - (scale_y * 0.45)


func _connect_signals() -> void:
	viewport_catcher.gui_input.connect(_on_viewport_gui_input)
	raycast_timer.timeout.connect(_on_raycast_timer_timeout)

	btn_zone_rim.pressed.connect(_on_zone_selected.bind("connecting_ridge_rim"))
	btn_zone_wall.pressed.connect(_on_zone_selected.bind("inner_wall_hazard"))
	btn_zone_psr.pressed.connect(_on_zone_selected.bind("crater_floor_psr"))
	btn_lidar_overlay.toggled.connect(_on_lidar_overlay_toggled)
	btn_reset_cam.pressed.connect(_on_reset_camera_pressed)

	btn_back_vab.pressed.connect(func() -> void: return_to_vab_requested.emit())
	btn_restart_descent.pressed.connect(start_or_restart_descent)
	btn_spe_storm.toggled.connect(_on_spe_storm_toggled)
	btn_safe_mode.toggled.connect(_on_safe_mode_toggled)
	btn_advance_days.pressed.connect(_on_advance_days_pressed)
	btn_proceed_debrief.pressed.connect(func() -> void: proceed_to_debrief_requested.emit())

	if not MissionState.preset_loaded.is_connected(_on_preset_loaded):
		MissionState.preset_loaded.connect(_on_preset_loaded)
	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)


func _on_preset_loaded(_preset_index: int, _preset_name: String) -> void:
	_elapsed_surface_days = 0.0
	_ephemeris_epoch_index = 0
	_spe_active = false
	_safe_mode_active = false
	btn_spe_storm.set_pressed_no_signal(false)
	btn_safe_mode.set_pressed_no_signal(false)
	_update_ephemeris_vectors()
	_refresh_zone_buttons()
	if _is_sim_active:
		start_or_restart_descent()
		_perform_celestial_raycasts()


func _on_state_updated(_snap: Dictionary) -> void:
	if _is_sim_active:
		_refresh_zone_buttons()
		_refresh_ui_labels()


func _on_zone_selected(zone_id: String) -> void:
	_elapsed_surface_days = 0.0
	MissionState.set_landing_zone(zone_id)
	_refresh_zone_buttons()
	if _is_sim_active:
		start_or_restart_descent()
		_perform_celestial_raycasts()


func _on_lidar_overlay_toggled(toggled_on: bool) -> void:
	if is_instance_valid(terrain_mesh):
		if toggled_on and _terrain_shader_mat != null:
			_terrain_shader_mat.set_shader_parameter("lidar_overlay", 1.0)
			terrain_mesh.material_override = _terrain_shader_mat
		elif _terrain_pbr_mat != null:
			terrain_mesh.material_override = _terrain_pbr_mat


func _on_spe_storm_toggled(toggled_on: bool) -> void:
	_spe_active = toggled_on
	if toggled_on:
		MissionState.trigger_spe_storm(24.0, _safe_mode_active)
	else:
		MissionState.clear_spe_storm()
	_refresh_ui_labels()


func _on_safe_mode_toggled(toggled_on: bool) -> void:
	_safe_mode_active = toggled_on
	if _spe_active:
		MissionState.trigger_spe_storm(24.0, _safe_mode_active)
	else:
		MissionState.safe_mode_active = _safe_mode_active
		MissionState.recalculate_all_telemetry(false)
	_refresh_ui_labels()


func _on_advance_days_pressed() -> void:
	_elapsed_surface_days += 30.0
	var series: Array[Dictionary] = NasaDataLoader.get_ephemeris_body_series("sun_from_moon_10")
	if not series.is_empty():
		_ephemeris_epoch_index = (_ephemeris_epoch_index + 4) % series.size()
	_update_ephemeris_vectors()
	_perform_celestial_raycasts()
	_refresh_ui_labels()


func _refresh_zone_buttons() -> void:
	var active_zone: String = MissionState.selected_landing_zone_id
	btn_zone_rim.set_pressed_no_signal(active_zone == "connecting_ridge_rim")
	btn_zone_wall.set_pressed_no_signal(active_zone == "inner_wall_hazard")
	btn_zone_psr.set_pressed_no_signal(active_zone == "crater_floor_psr")

	btn_zone_rim.tooltip_text = "Connecting Ridge (Rim): ~7.5° slope, ~82% solar illumination, DTE clear.\n[NASA Reference] LRO LOLA GDR 20 m/px"
	btn_zone_wall.tooltip_text = "Crater Inner Wall: ~31° slope (>15° stability limit). Requires Hazard LiDAR & TRN.\n[NASA Reference] NASA SPLICE & LRO LOLA DEM"
	btn_zone_psr.tooltip_text = "Shackleton Floor (PSR): 0% sunlight (water-ice x1.6 science). Requires MMRTG / 48 kWh battery.\n[NASA Reference] LRO LOLA & Artemis Polar Trade Study"


func _refresh_ui_labels() -> void:
	var zone_id: String = MissionState.selected_landing_zone_id
	var ground_y: float = _sample_ground_y(lander_pivot.position.x, lander_pivot.position.z)
	var agl_m: float = maxf(0.0, lander_pivot.position.y - ground_y)
	var eng: bool = MissionState.engineer_mode

	telemetry_zone_label.text = "Site: %s" % str(ZONE_LABELS.get(zone_id, zone_id))
	if eng:
		telemetry_agl_label.text = "AGL: %.1f m  •  T/W %.2f" % [agl_m, MissionState.lunar_tw_ratio]
		telemetry_vel_label.text = "Vz: %+.2f m/s  •  Δv %.0f m/s" % [_lander_vel_y, MissionState.delta_v_ms]
	else:
		var tw_txt: String = "SAFE LANDING T/W" if MissionState.lunar_tw_ratio >= 1.0 else "THRUST DEFICIT"
		telemetry_agl_label.text = "AGL: %.0f m  •  %s" % [agl_m, tw_txt]
		telemetry_vel_label.text = "Vel: %+.1f m/s  •  Δv %.0f m/s" % [_lander_vel_y, MissionState.delta_v_ms]
	telemetry_slope_label.text = "Slope: %.1f°  •  TRN %s" % [_touchdown_slope_deg, "ON" if MissionState.has_lidar_trn else "OFF"]

	var solar_state: String = ("SHADOW (PSR)" if _solar_occluded else "SUNLIT (1.8°)") if eng else ("POWER POSITIVE" if MissionState.net_power_w >= 0.0 else "SOLAR BLACKOUT")
	telemetry_solar_label.text = "%s  •  %+.0f W" % [("Solar: %s" % solar_state) if eng else solar_state, MissionState.net_power_w]
	telemetry_solar_label.add_theme_color_override("font_color", COLOR_OK if MissionState.net_power_w >= 0.0 else COLOR_CRIT)

	var dte_state: String = "OCCLUDED" if _dte_occluded else ("NRHO RELAY" if MissionState.orbit_id_is_nrho() and zone_id == "crater_floor_psr" else "DTE CLEAR")
	telemetry_dte_label.text = "DSN: %s (%.0f%%)" % [dte_state, MissionState.dte_visibility_pct]
	telemetry_dte_label.add_theme_color_override("font_color", COLOR_WARN if _dte_occluded else COLOR_WHITE)

	var cum_rad_msv: float = MissionState.total_mission_dose_msv
	if _elapsed_surface_days > 0.0:
		cum_rad_msv = (5.0 * 1.15 * pow(0.5, MissionState.shielding_g_cm2 / 6.5)) + MissionState.spe_dose_msv + (MissionState.daily_gcr_msv * _elapsed_surface_days)
	var rad_limit: float = NasaDataLoader.get_mission_dose_limit_msv()
	var rad_flag: String = "SPE STORM" if _spe_active else ("SAFE" if _safe_mode_active else "GCR")
	var rad_hazard: bool = (cum_rad_msv > rad_limit) or (_spe_active and not MissionState.has_radhard_obc)
	if eng:
		telemetry_rad_label.text = "Rad (%s): %.1f / %.0f mSv" % [rad_flag, cum_rad_msv, rad_limit]
	else:
		telemetry_rad_label.text = "%s (%s): %.0f mSv" % ["RAD HAZARD" if rad_hazard else "RAD SAFE", rad_flag, cum_rad_msv]
	telemetry_rad_label.add_theme_color_override("font_color", COLOR_CRIT if rad_hazard else (COLOR_WARN if _spe_active else COLOR_OK))

	var op_life: float = MissionState.mission_lifetime_days
	var ops_status: String = "ALIVE" if (_sim_phase == SimPhase.LANDED_NOMINAL and _elapsed_surface_days <= op_life) else ("OFFLINE" if _elapsed_surface_days > op_life else "ACTIVE")
	telemetry_day_label.text = "Surface Day %.0f / %.0f d  •  %s" % [_elapsed_surface_days, op_life, ops_status]

	# Populate NASA citations in tooltips
	telemetry_solar_label.tooltip_text = (
		"Solar RayCast3D + DE441 Grazing Illumination\n"
		+ "P = P0 * cos(theta) * (1 - occlusion) | Gen %.1f W / Load %.1f W\n" % [MissionState.power_generated_w, MissionState.power_consumed_w]
		+ "[NASA Citation] %s" % NasaDataLoader.get_ephemeris_citation()
	)
	telemetry_dte_label.tooltip_text = (
		"Direct-to-Earth (DTE) RayCast3D Line-of-Sight\n"
		+ "Downlink: %.2f GB/day | Payload Data: %.2f GB/day\n" % [MissionState.downlink_capacity_gb_day, MissionState.data_generated_gb_day]
		+ "[NASA Citation] NASA Deep Space Network (DSN) & %s" % NasaDataLoader.get_ephemeris_citation()
	)
	telemetry_rad_label.tooltip_text = (
		"OSDR RadLab GCR + SPE Radiation Exposure\n"
		+ "Shielding: %.1f g/cm^2 | OBC Tolerance: %.0f krad | Daily GCR: %.3f mSv/d\n" % [MissionState.shielding_g_cm2, MissionState.radiation_tolerance_krad, MissionState.daily_gcr_msv]
		+ "[NASA Citation] %s" % NasaDataLoader.get_radiation_citation()
	)
	telemetry_slope_label.tooltip_text = (
		"LRO LOLA Touchdown Slope & TRN Stability (Max Safe <= 15.0 deg)\n"
		+ "Engaged Mode: %s\n" % ("Engineer SI" if eng else "Student Guided")
		+ "[NASA Citation] %s" % str(NasaDataLoader.get_terrain_metadata().get("nasa_citation", "LRO LOLA GDR 20 m/px"))
	)
	btn_spe_storm.tooltip_text = "Injects 24h Solar Particle Event (42 mSv/h transit / 21 mSv/h surface flux).\n[NASA Citation] %s" % NasaDataLoader.get_radiation_citation()
	btn_safe_mode.tooltip_text = "Sheds non-essential payloads to conserve battery/power during PSR shadow or SPE storms.\n[NASA Citation] NASA SP-2016-6105 Rev2 Fault Management"
	btn_advance_days.tooltip_text = "Steps DE441 ephemeris epoch and simulates +30 lunar surface days of GCR dose and power balance.\n[NASA Citation] %s" % NasaDataLoader.get_ephemeris_citation()


func _apply_status_pill(text_val: String, pill_color: Color) -> void:
	if not is_instance_valid(sim_status_pill):
		return
	sim_status_pill.text = text_val
	sim_status_pill.add_theme_color_override("font_color", COLOR_WHITE)
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = Color(pill_color.r * 0.35, pill_color.g * 0.35, pill_color.b * 0.35, 0.96)
	pill.border_color = pill_color
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(5)
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	pill.content_margin_top = 6
	pill.content_margin_bottom = 6
	sim_status_pill.add_theme_stylebox_override("normal", pill)


func _style_panels() -> void:
	var left_sb: StyleBoxFlat = StyleBoxFlat.new()
	left_sb.bg_color = COLOR_PANEL_BG
	left_sb.border_color = Color(0.18, 0.29, 0.45, 0.90)
	left_sb.set_border_width_all(1)
	left_sb.set_corner_radius_all(6)
	left_sb.content_margin_left = 14
	left_sb.content_margin_right = 14
	left_sb.content_margin_top = 12
	left_sb.content_margin_bottom = 12
	left_panel.add_theme_stylebox_override("panel", left_sb)

	var bot_sb: StyleBoxFlat = StyleBoxFlat.new()
	bot_sb.bg_color = COLOR_BOTTOM_BG
	bot_sb.border_color = Color(0.18, 0.29, 0.45, 0.90)
	bot_sb.set_border_width_all(1)
	bot_sb.set_corner_radius_all(6)
	bot_sb.content_margin_left = 12
	bot_sb.content_margin_right = 12
	bot_sb.content_margin_top = 8
	bot_sb.content_margin_bottom = 8
	bottom_bar.add_theme_stylebox_override("panel", bot_sb)

	_style_cta_button(btn_proceed_debrief, COLOR_ACCENT, Color(0.06, 0.28, 0.44, 0.98))


func _style_cta_button(btn: Button, border_col: Color, bg_col: Color) -> void:
	var normal_sb: StyleBoxFlat = StyleBoxFlat.new()
	normal_sb.bg_color = bg_col
	normal_sb.border_color = border_col
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(5)
	normal_sb.content_margin_left = 12
	normal_sb.content_margin_right = 12
	normal_sb.content_margin_top = 8
	normal_sb.content_margin_bottom = 8

	var hover_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(minf(1.0, bg_col.r + 0.08), minf(1.0, bg_col.g + 0.08), minf(1.0, bg_col.b + 0.12), 1.0)
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_color_override("font_color", COLOR_WHITE)


func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = clampf(_target_distance - 2.0, 6.0, 55.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = clampf(_target_distance + 2.0, 6.0, 55.0)
	elif event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_target_yaw -= mm.relative.x * 0.008
		_target_pitch = clampf(_target_pitch - mm.relative.y * 0.008, -1.35, -0.08)


func _update_camera_transform(snap_now: bool) -> void:
	if not is_instance_valid(camera_pivot) or not is_instance_valid(lunar_camera):
		return
	var target_focus: Vector3 = lander_pivot.position + Vector3(0.0, 1.4, 0.0)
	if snap_now:
		_cam_yaw = _target_yaw
		_cam_pitch = _target_pitch
		_cam_distance = _target_distance
		camera_pivot.position = target_focus
	else:
		camera_pivot.position = camera_pivot.position.lerp(target_focus, 0.12)
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	lunar_camera.position = Vector3(0.0, 0.0, _cam_distance)
	lunar_camera.look_at(camera_pivot.global_position, Vector3.UP)


func _on_reset_camera_pressed() -> void:
	_target_yaw = 0.72
	_target_pitch = -0.46
	_target_distance = 18.5
