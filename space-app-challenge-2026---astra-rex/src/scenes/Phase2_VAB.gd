class_name Phase2VAB
extends Control

## Phase 2: Phase A-C 3D Modular Vehicle Assembly Building (VAB).
## Allocates >= 65% of screen width to the interactive 3D spacecraft viewport,
## with a clean scrollable subsystem drawer, concise SI part cards, and tooltip citations.

signal proceed_to_descent_requested()

const CATEGORY_ORDER: Array[Dictionary] = [
	{"id": "all", "label": "All"},
	{"id": "bus", "label": "Bus"},
	{"id": "propulsion", "label": "Prop"},
	{"id": "power", "label": "Power"},
	{"id": "comms", "label": "Comms"},
	{"id": "avionics", "label": "Avionics"},
	{"id": "payload", "label": "Science"},
	{"id": "shielding", "label": "Shield"}
]

const CATEGORY_TITLES: Dictionary = {
	"bus": "STRUCTURAL BUS",
	"propulsion": "PROPULSION",
	"power": "POWER & STORAGE",
	"comms": "TELECOMMUNICATIONS",
	"avionics": "AVIONICS & TRN",
	"payload": "SCIENCE PAYLOADS",
	"shielding": "RADIATION SHIELDING"
}

const PART_SHORT_NAMES: Dictionary = {
	"chassis_clps": "CLPS Lander Bus",
	"prop_chem_biprop": "Biprop Descent Engine",
	"prop_ion_sep": "Xenon Hall Thruster",
	"pwr_solar_lro": "Vertical Solar Array",
	"pwr_rtg_mmrtg": "MMRTG (Pu-238)",
	"pwr_batt_liion": "Cryo Li-Ion Battery",
	"comm_hga_ka": "Ka-Band HGA Dish",
	"comm_uga_s": "S-Band Omni Antenna",
	"obc_adcs_radhard": "Rad-Hard OBC & ADCS",
	"obc_adcs_cots": "COTS OBC & Sensor",
	"avionics_lidar_trn": "Hazard LiDAR & TRN",
	"pay_drill_trident": "TRIDENT Ice Drill",
	"pay_spec_msolo": "MSolo Mass Spec",
	"pay_sar_lband": "Mini-RF L-Band SAR",
	"shield_heavy": "Poly-Al Rad Shield"
}

const COLOR_DRAWER_BG: Color = BrandStyle.PANEL_900                   # #0E1624 @ 88%
const COLOR_CARD_NORMAL: Color = Color(0.055, 0.086, 0.141, 0.92)
const COLOR_CARD_EQUIPPED: Color = Color(0.043, 0.239, 0.569, 0.48)  # #0B3D91 tint
const COLOR_OK: Color = BrandStyle.PASS_EMERALD                     # #35E0A1
const COLOR_WARN: Color = BrandStyle.CAUTION_AMBER                  # #FFB224
const COLOR_CRIT: Color = BrandStyle.CRITICAL_RED                   # #FF4560
const COLOR_ACCENT: Color = BrandStyle.NOMINAL_CYAN                 # #2FD3FF
const COLOR_NEON_YELLOW: Color = BrandStyle.NEON_YELLOW             # #EAFE07
const COLOR_WHITE: Color = BrandStyle.TEXT_WHITE
const COLOR_MUTED: Color = BrandStyle.TEXT_MUTED

@onready var vab_world: Node3D = %VABWorld
@onready var camera_pivot: Node3D = %CameraPivot
@onready var vab_camera: Camera3D = %VABCamera
@onready var lander_chassis: LanderChassis = %LanderChassis
@onready var viewport_catcher: Control = %ViewportInputCatcher

@onready var left_drawer: PanelContainer = %LeftDrawer
@onready var bottom_bar: PanelContainer = %BottomBar
@onready var category_tabs: GridContainer = %CategoryTabs
@onready var catalog_vbox: VBoxContainer = %CatalogVBox

@onready var btn_reset_cam: Button = %BtnResetCam
@onready var btn_turntable: Button = %BtnTurntable
@onready var btn_proceed_sim: Button = %BtnProceedSim

@onready var trade_summary_label: Label = %TradeSummaryLabel
@onready var hover_delta_label: Label = %HoverDeltaLabel
@onready var diegetic_pin_overlay: Control = %DiegeticPinOverlay
@onready var design_code_edit: LineEdit = %DesignCodeEdit
@onready var btn_export_code: Button = %BtnExportCode
@onready var btn_import_code: Button = %BtnImportCode

const DIEGETIC_PIN_DEFS: Array[Dictionary] = [
	{"marker": "Mount_Chassis", "cat": "bus", "label": "BUS"},
	{"marker": "Mount_Propulsion", "cat": "propulsion", "label": "PROP"},
	{"marker": "Mount_Power_Port", "cat": "power", "label": "PWR"},
	{"marker": "Mount_Comms_Antenna", "cat": "comms", "label": "COMM"},
	{"marker": "Mount_Avionics", "cat": "avionics", "label": "AVN"},
	{"marker": "Mount_Payload_Top", "cat": "payload", "label": "PAY"},
	{"marker": "Mount_Shielding", "cat": "shielding", "label": "SHLD"},
]

var _active_category: String = "all"
var _category_buttons: Dictionary = {}
var _part_buttons: Dictionary = {}
var _latest_slots: Array[Dictionary] = []
var _diegetic_pins: Array[Dictionary] = []
var _pin_update_accum: float = 0.0
var _hovered_part_id: String = ""

var _cam_yaw: float = 0.65
var _cam_pitch: float = -0.34
var _cam_distance: float = 5.8
var _target_yaw: float = 0.65
var _target_pitch: float = -0.34
var _target_distance: float = 5.8
var _is_dragging: bool = false
var _auto_turntable: bool = false


func _ready() -> void:
	_enforce_double_sided_materials(vab_world)
	_style_panels()
	_style_cta_button()
	BrandStyle.bind_mono_font(hover_delta_label)
	BrandStyle.bind_mono_font(trade_summary_label)
	BrandStyle.bind_mono_font(design_code_edit)
	btn_reset_cam.focus_mode = Control.FOCUS_NONE
	btn_turntable.focus_mode = Control.FOCUS_NONE
	_build_category_tabs()
	_rebuild_catalog_list()
	_connect_signals()
	_update_camera_transform(true)

	_latest_slots = lander_chassis.get_active_slot_records()
	_refresh_equipped_states(MissionState.get_telemetry_snapshot())


func _enforce_double_sided_materials(root_node: Node) -> void:
	if not is_instance_valid(root_node):
		return
	if root_node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = root_node as MeshInstance3D
		if mesh_inst.material_override is BaseMaterial3D:
			var dup_override: BaseMaterial3D = (mesh_inst.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
			dup_override.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_inst.material_override = dup_override
		if mesh_inst.mesh != null:
			var surf_count: int = mesh_inst.mesh.get_surface_count()
			for surface_idx: int in range(surf_count):
				var active_mat: Material = mesh_inst.get_active_material(surface_idx)
				if active_mat is BaseMaterial3D:
					var dup: BaseMaterial3D = (active_mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dup.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_inst.set_surface_override_material(surface_idx, dup)
				elif active_mat == null:
					var fallback_mat: StandardMaterial3D = StandardMaterial3D.new()
					fallback_mat.albedo_color = Color(0.76, 0.78, 0.82, 1.0)
					fallback_mat.metallic = 0.2
					fallback_mat.roughness = 0.55
					fallback_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_inst.set_surface_override_material(surface_idx, fallback_mat)
	for child: Node in root_node.get_children():
		_enforce_double_sided_materials(child)


func _process(delta: float) -> void:
	if not visible:
		return

	if _auto_turntable and not _is_dragging:
		_target_yaw += delta * 0.25

	var lerp_weight: float = clampf(delta * 10.0, 0.0, 1.0)
	_cam_yaw = lerpf(_cam_yaw, _target_yaw, lerp_weight)
	_cam_pitch = lerpf(_cam_pitch, _target_pitch, lerp_weight)
	_cam_distance = lerpf(_cam_distance, _target_distance, lerp_weight)
	_update_camera_transform(false)

	_pin_update_accum += delta
	if _pin_update_accum >= 0.05:
		_pin_update_accum = 0.0
		_update_diegetic_pins()


func set_vab_active(active: bool) -> void:
	visible = active
	if is_instance_valid(vab_world):
		vab_world.visible = active
	if is_instance_valid(vab_camera):
		vab_camera.current = active
	if active:
		_update_camera_transform(true)
		_update_diegetic_pins()


func _style_panels() -> void:
	BrandStyle.apply_panel_style(left_drawer, 12.0, 10.0, 10.0)
	BrandStyle.apply_panel_style(bottom_bar, 12.0, 6.0, 6.0)


func _style_cta_button() -> void:
	btn_proceed_sim.focus_mode = Control.FOCUS_NONE
	var normal_sb: StyleBoxFlat = StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.043, 0.239, 0.569, 0.96)
	normal_sb.border_color = COLOR_ACCENT
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(5)
	normal_sb.content_margin_left = 14
	normal_sb.content_margin_right = 14
	normal_sb.content_margin_top = 8
	normal_sb.content_margin_bottom = 8

	var hover_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.0, 0.259, 0.651, 1.0)
	hover_sb.border_color = COLOR_NEON_YELLOW
	btn_proceed_sim.add_theme_stylebox_override("normal", normal_sb)
	btn_proceed_sim.add_theme_stylebox_override("hover", hover_sb)
	btn_proceed_sim.add_theme_color_override("font_color", COLOR_WHITE)
	btn_proceed_sim.add_theme_color_override("font_hover_color", COLOR_NEON_YELLOW)


func _connect_signals() -> void:
	viewport_catcher.gui_input.connect(_on_viewport_gui_input)
	btn_reset_cam.pressed.connect(_on_reset_camera_pressed)
	btn_turntable.toggled.connect(_on_turntable_toggled)
	btn_proceed_sim.pressed.connect(_on_proceed_sim_pressed)
	btn_export_code.pressed.connect(_on_export_code_pressed)
	btn_import_code.pressed.connect(_on_import_code_pressed)

	if not lander_chassis.meshes_updated.is_connected(_on_chassis_meshes_updated):
		lander_chassis.meshes_updated.connect(_on_chassis_meshes_updated)
	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)

	_build_diegetic_pins()


func _build_category_tabs() -> void:
	for cat_def: Dictionary in CATEGORY_ORDER:
		var cat_id: String = str(cat_def.get("id", "all"))
		var cat_label: String = str(cat_def.get("label", cat_id))
		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = cat_label
		btn.add_theme_font_size_override("font_size", 11)
		var tab_style: StyleBoxFlat = StyleBoxFlat.new()
		tab_style.bg_color = COLOR_CARD_NORMAL
		tab_style.border_color = BrandStyle.BTN_BORDER
		tab_style.set_border_width_all(1)
		tab_style.set_corner_radius_all(4)
		tab_style.content_margin_left = 4
		tab_style.content_margin_right = 4
		tab_style.content_margin_top = 4
		tab_style.content_margin_bottom = 4
		var tab_hover: StyleBoxFlat = tab_style.duplicate() as StyleBoxFlat
		tab_hover.border_color = COLOR_NEON_YELLOW
		var tab_pressed: StyleBoxFlat = tab_style.duplicate() as StyleBoxFlat
		tab_pressed.bg_color = Color(0.043, 0.239, 0.569, 0.92)
		tab_pressed.border_color = COLOR_ACCENT
		tab_pressed.border_width_bottom = 2
		btn.add_theme_stylebox_override("normal", tab_style)
		btn.add_theme_stylebox_override("hover", tab_hover)
		btn.add_theme_stylebox_override("pressed", tab_pressed)
		btn.pressed.connect(_on_category_selected.bind(cat_id))
		category_tabs.add_child(btn)
		_category_buttons[cat_id] = btn
	_sync_category_tab_buttons()


func _on_category_selected(cat_id: String) -> void:
	_play_vab_sfx("ui_hover_tick")
	_active_category = cat_id
	_sync_category_tab_buttons()
	_sync_diegetic_pin_styles()
	_rebuild_catalog_list()
	_refresh_equipped_states(MissionState.get_telemetry_snapshot())


func _sync_category_tab_buttons() -> void:
	for cat_var: Variant in _category_buttons.keys():
		var cat_key: String = str(cat_var)
		var btn: Button = _category_buttons[cat_key] as Button
		btn.set_pressed_no_signal(cat_key == _active_category)


func _rebuild_catalog_list() -> void:
	for child: Node in catalog_vbox.get_children():
		child.queue_free()
	_part_buttons.clear()

	var categories_to_show: Array[String] = []
	if _active_category == "all":
		categories_to_show = ["bus", "propulsion", "power", "comms", "avionics", "payload", "shielding"]
	else:
		categories_to_show = [_active_category]

	var snap: Dictionary = MissionState.get_telemetry_snapshot()
	for cat: String in categories_to_show:
		var parts: Array[Dictionary] = NasaDataLoader.get_subsystems_by_category(cat)
		if parts.is_empty():
			continue

		var header: Label = Label.new()
		header.text = str(CATEGORY_TITLES.get(cat, cat.to_upper()))
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", COLOR_MUTED)
		catalog_vbox.add_child(header)

		for part_data: Dictionary in parts:
			var card_btn: Button = _create_part_card_button(part_data, snap)
			catalog_vbox.add_child(card_btn)


func _create_part_card_button(part_data: Dictionary, snap: Dictionary) -> Button:
	var part_id: String = str(part_data.get("id", ""))
	var btn: Button = Button.new()
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 50)
	btn.add_theme_font_size_override("font_size", 12)
	BrandStyle.bind_mono_font(btn)
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.tooltip_text = _build_part_tooltip(part_data)
	_update_part_card_text(btn, part_data, snap)
	btn.pressed.connect(_on_part_card_pressed.bind(part_id))
	btn.mouse_entered.connect(_on_part_hovered.bind(part_id))
	btn.focus_entered.connect(_on_part_hovered.bind(part_id))
	_part_buttons[part_id] = btn
	return btn


func _update_part_card_text(btn: Button, part_data: Dictionary, snap: Dictionary) -> void:
	var part_id: String = str(part_data.get("id", ""))
	var short_name: String = str(PART_SHORT_NAMES.get(part_id, part_data.get("name", part_id)))
	var stat_line: String = _format_compact_stat_line(part_data)
	var deltas: Dictionary = _compute_part_trade_deltas(part_data, snap)
	var badge: String = _format_compact_delta_badge(deltas)
	btn.text = "%s\n%s | %s" % [short_name, stat_line, badge]


func _eval_part_list_metrics(part_ids: Array[String]) -> Dictionary:
	var dry_eff: float = 0.0
	var prop_kg: float = 0.0
	var thrust_n: float = 0.0
	var isp_denom: float = 0.0
	var power_w: float = 0.0
	var cost_musd: float = 0.0

	for pid: String in part_ids:
		var part: Dictionary = NasaDataLoader.get_subsystem(pid)
		if part.is_empty():
			continue
		var base_mass: float = float(part.get("mass_dry_kg", 0.0))
		var mga: float = float(part.get("mga_percent", 0.15))
		dry_eff += base_mass * (1.0 + mga)
		prop_kg += float(part.get("propellant_capacity_kg", 0.0))
		var p_thrust: float = float(part.get("thrust_n", 0.0))
		var p_isp: float = float(part.get("isp_s", 0.0))
		if p_thrust > 0.0 and p_isp > 0.0:
			thrust_n += p_thrust
			isp_denom += p_thrust / p_isp
		power_w += float(part.get("power_w", 0.0))
		cost_musd += float(part.get("cost_m_usd", 0.0))

	var eff_isp: float = (thrust_n / isp_denom) if isp_denom > 0.0 else 0.0
	var m0: float = dry_eff + prop_kg
	var mf: float = dry_eff + prop_kg * MissionState.RESIDUAL_PROPELLANT_FRACTION
	var dv_ms: float = 0.0
	if mf > 0.0 and m0 > mf and eff_isp > 0.0:
		dv_ms = eff_isp * MissionState.G0_M_S2 * log(m0 / mf)
	var tw: float = (thrust_n / (m0 * MissionState.LUNAR_GRAVITY_M_S2)) if m0 > 0.0 else 0.0

	return {
		"dry_eff_kg": dry_eff,
		"m0_wet_kg": m0,
		"dv_ms": dv_ms,
		"tw": tw,
		"power_w": power_w,
		"cost_musd": cost_musd,
	}


func _compute_part_trade_deltas(part_data: Dictionary, snap: Dictionary) -> Dictionary:
	var part_id: String = str(part_data.get("id", ""))
	if part_id == "chassis_clps":
		return {
			"action": "CORE",
			"d_mass_kg": 0.0,
			"d_dv_ms": 0.0,
			"d_tw": 0.0,
			"d_power_w": 0.0,
			"d_cost_musd": 0.0,
		}

	var cur_ids: Array[String] = []
	var raw_ids: Array = snap.get("subsystem_ids", []) as Array
	for id_var: Variant in raw_ids:
		cur_ids.append(str(id_var))

	var hyp_ids: Array[String] = []
	var action: String = "EQUIP"
	if cur_ids.has(part_id):
		action = "REMOVE"
		for pid: String in cur_ids:
			if pid != part_id:
				hyp_ids.append(pid)
	else:
		var cat: String = str(part_data.get("subsystem", ""))
		var mount_pt: String = str(part_data.get("mount_point", ""))
		var replaced_any: bool = false
		for pid: String in cur_ids:
			var existing: Dictionary = NasaDataLoader.get_subsystem(pid)
			var ex_cat: String = str(existing.get("subsystem", ""))
			var ex_mount: String = str(existing.get("mount_point", ""))
			var should_remove: bool = false
			if cat == "propulsion" and ex_cat == "propulsion":
				should_remove = true
			elif cat == "comms" and ex_cat == "comms":
				should_remove = true
			elif mount_pt == "Mount_Power_Port" and ex_mount == "Mount_Power_Port":
				should_remove = true
			elif (part_id == "obc_adcs_radhard" or part_id == "obc_adcs_cots") and (pid == "obc_adcs_radhard" or pid == "obc_adcs_cots"):
				should_remove = true
			if should_remove:
				replaced_any = true
			else:
				hyp_ids.append(pid)
		hyp_ids.append(part_id)
		if replaced_any:
			action = "REPLACE"

	var cur_m: Dictionary = _eval_part_list_metrics(cur_ids)
	var hyp_m: Dictionary = _eval_part_list_metrics(hyp_ids)

	return {
		"action": action,
		"d_mass_kg": float(hyp_m["dry_eff_kg"]) - float(cur_m["dry_eff_kg"]),
		"d_wet_kg": float(hyp_m["m0_wet_kg"]) - float(cur_m["m0_wet_kg"]),
		"d_dv_ms": float(hyp_m["dv_ms"]) - float(cur_m["dv_ms"]),
		"d_tw": float(hyp_m["tw"]) - float(cur_m["tw"]),
		"d_power_w": float(hyp_m["power_w"]) - float(cur_m["power_w"]),
		"d_cost_musd": float(hyp_m["cost_musd"]) - float(cur_m["cost_musd"]),
	}


func _format_compact_delta_badge(deltas: Dictionary) -> String:
	var action: String = str(deltas.get("action", "EQUIP"))
	if action == "CORE":
		return "CORE BUS"

	var d_mass: float = float(deltas.get("d_mass_kg", 0.0))
	var d_dv: float = float(deltas.get("d_dv_ms", 0.0))
	var d_pwr: float = float(deltas.get("d_power_w", 0.0))
	var d_cost: float = float(deltas.get("d_cost_musd", 0.0))

	var tag: String = "REM" if action == "REMOVE" else ("SWAP" if action == "REPLACE" else "+")
	var dv_part: String = (" %+.0fm/s" % d_dv) if absf(d_dv) >= 1.0 else ""
	var pwr_part: String = (" %+.0fW" % d_pwr) if absf(d_pwr) >= 1.0 else ""
	var cost_sign: String = "+" if d_cost >= 0.0 else "-"
	return "%s %+.0fkg%s%s %s$%.0fM" % [tag, d_mass, dv_part, pwr_part, cost_sign, absf(d_cost)]


func _on_part_hovered(part_id: String) -> void:
	if _hovered_part_id != part_id and visible:
		_play_vab_sfx("ui_hover_tick")
	_hovered_part_id = part_id
	if not is_instance_valid(hover_delta_label):
		return
	var part_data: Dictionary = NasaDataLoader.get_subsystem(part_id)
	if part_data.is_empty():
		return
	var deltas: Dictionary = _compute_part_trade_deltas(part_data, MissionState.get_telemetry_snapshot())
	var action: String = str(deltas.get("action", "EQUIP"))
	var short_name: String = str(PART_SHORT_NAMES.get(part_id, part_data.get("name", part_id)))
	if action == "CORE":
		hover_delta_label.text = "[CORE] %s is the permanent structural spacecraft bus." % short_name
		hover_delta_label.add_theme_color_override("font_color", COLOR_ACCENT)
		return

	var d_mass: float = float(deltas.get("d_mass_kg", 0.0))
	var d_dv: float = float(deltas.get("d_dv_ms", 0.0))
	var d_pwr: float = float(deltas.get("d_power_w", 0.0))
	var d_cost: float = float(deltas.get("d_cost_musd", 0.0))
	var cost_sign: String = "+" if d_cost >= 0.0 else "-"
	hover_delta_label.text = "[%s %s] Mass %+.1f kg | Δv %+.0f m/s | Pwr %+.0f W | Cost %s$%.1fM" % [
		action, short_name, d_mass, d_dv, d_pwr, cost_sign, absf(d_cost)
	]
	var is_caution: bool = (action == "REMOVE") or (d_dv < -50.0) or (d_pwr < -20.0) or (d_mass > 50.0)
	var col: Color = COLOR_WARN if is_caution else COLOR_ACCENT
	hover_delta_label.add_theme_color_override("font_color", col)


func _is_category_equipped(cat_id: String) -> bool:
	if cat_id == "all":
		return true
	for pid: String in MissionState.selected_subsystem_ids:
		var pdata: Dictionary = NasaDataLoader.get_subsystem(pid)
		if str(pdata.get("subsystem", "")) == cat_id:
			return true
	return false


func _on_diegetic_pin_draw(btn: Button) -> void:
	if not is_instance_valid(btn) or not bool(btn.get_meta("is_empty_slot", false)):
		return
	var is_sel: bool = bool(btn.get_meta("is_selected_slot", false))
	var border_col: Color = COLOR_NEON_YELLOW if is_sel else Color(BrandStyle.BTN_BORDER.r, BrandStyle.BTN_BORDER.g, BrandStyle.BTN_BORDER.b, 0.85)
	var r: Rect2 = Rect2(Vector2(1.0, 1.0), btn.size - Vector2(2.0, 2.0))
	var tl: Vector2 = r.position
	var tr: Vector2 = Vector2(r.end.x, r.position.y)
	var br: Vector2 = r.end
	var bl: Vector2 = Vector2(r.position.x, r.end.y)
	btn.draw_dashed_line(tl, tr, border_col, 1.2, 4.0, true)
	btn.draw_dashed_line(tr, br, border_col, 1.2, 4.0, true)
	btn.draw_dashed_line(br, bl, border_col, 1.2, 4.0, true)
	btn.draw_dashed_line(bl, tl, border_col, 1.2, 4.0, true)


func _build_diegetic_pins() -> void:
	if not is_instance_valid(diegetic_pin_overlay) or not is_instance_valid(lander_chassis):
		return
	for child: Node in diegetic_pin_overlay.get_children():
		child.queue_free()
	_diegetic_pins.clear()

	for def_rec: Dictionary in DIEGETIC_PIN_DEFS:
		var marker_name: String = str(def_rec.get("marker", ""))
		var cat_id: String = str(def_rec.get("cat", "all"))
		var pin_label: String = str(def_rec.get("label", ""))
		var marker_node: Marker3D = lander_chassis.find_child(marker_name, true, false) as Marker3D

		var pin_btn: Button = Button.new()
		pin_btn.focus_mode = Control.FOCUS_NONE
		pin_btn.text = pin_label
		pin_btn.custom_minimum_size = Vector2(64, 22)
		pin_btn.size = Vector2(64, 22)
		pin_btn.add_theme_font_size_override("font_size", 11)
		BrandStyle.bind_mono_font(pin_btn)
		pin_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		pin_btn.tooltip_text = "Click to filter catalog to %s\nMount: %s" % [
			str(CATEGORY_TITLES.get(cat_id, cat_id)),
			marker_name
		]
		pin_btn.pressed.connect(_on_category_selected.bind(cat_id))
		pin_btn.mouse_entered.connect(func() -> void: _play_vab_sfx("ui_hover_tick"))
		pin_btn.draw.connect(_on_diegetic_pin_draw.bind(pin_btn))
		diegetic_pin_overlay.add_child(pin_btn)
		_diegetic_pins.append({
			"button": pin_btn,
			"cat": cat_id,
			"label": pin_label,
			"marker_name": marker_name,
			"marker_node": marker_node,
		})

	_sync_diegetic_pin_styles()
	_update_diegetic_pins()


func _sync_diegetic_pin_styles() -> void:
	for pin_rec: Dictionary in _diegetic_pins:
		var btn: Button = pin_rec["button"] as Button
		var cat_id: String = str(pin_rec["cat"])
		var base_label: String = str(pin_rec.get("label", cat_id.to_upper()))
		var is_selected: bool = (_active_category == cat_id)
		var is_equipped: bool = _is_category_equipped(cat_id)
		btn.set_meta("is_empty_slot", not is_equipped)
		btn.set_meta("is_selected_slot", is_selected)
		btn.text = ("● %s" if is_equipped else "◌ %s") % base_label

		var sb: StyleBoxFlat = StyleBoxFlat.new()
		if is_equipped:
			sb.bg_color = Color(0.043, 0.239, 0.569, 0.92) if is_selected else BrandStyle.PANEL_900
			sb.border_color = COLOR_NEON_YELLOW if is_selected else COLOR_OK
			sb.set_border_width_all(2 if is_selected else 1)
		else:
			sb.bg_color = Color(0.055, 0.086, 0.141, 0.42)
			sb.set_border_width_all(0)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2

		var sb_hover: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
		sb_hover.border_color = COLOR_NEON_YELLOW
		sb_hover.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_color_override("font_color", COLOR_NEON_YELLOW if is_selected else (COLOR_ACCENT if is_equipped else COLOR_MUTED))
		btn.queue_redraw()


func _update_diegetic_pins() -> void:
	if not is_instance_valid(vab_camera) or not is_instance_valid(lander_chassis) or not is_instance_valid(diegetic_pin_overlay):
		return
	var area_size: Vector2 = diegetic_pin_overlay.size
	if area_size.x < 10.0 or area_size.y < 10.0:
		area_size = Vector2(920.0, 520.0)
	var overlay_origin: Vector2 = diegetic_pin_overlay.global_position

	for pin_rec: Dictionary in _diegetic_pins:
		var btn: Button = pin_rec["button"] as Button
		var marker: Marker3D = pin_rec.get("marker_node") as Marker3D
		if not is_instance_valid(marker):
			marker = lander_chassis.find_child(str(pin_rec["marker_name"]), true, false) as Marker3D
			pin_rec["marker_node"] = marker
		if not is_instance_valid(marker):
			btn.visible = false
			continue
		var world_pos: Vector3 = marker.global_position
		if vab_camera.is_position_behind(world_pos):
			btn.visible = false
			continue
		var screen_pos: Vector2 = vab_camera.unproject_position(world_pos)
		var local_pos: Vector2 = screen_pos - overlay_origin
		var clamped_x: float = clampf(local_pos.x - btn.size.x * 0.5, 8.0, maxf(8.0, area_size.x - btn.size.x - 8.0))
		var clamped_y: float = clampf(local_pos.y - btn.size.y * 0.5, 8.0, maxf(8.0, area_size.y - btn.size.y - 8.0))
		btn.position = Vector2(clamped_x, clamped_y)
		btn.visible = true


func _format_compact_stat_line(part_data: Dictionary) -> String:
	var mass_kg: float = float(part_data.get("mass_dry_kg", 0.0))
	var cost_m: float = float(part_data.get("cost_m_usd", 0.0))
	var cat: String = str(part_data.get("subsystem", ""))

	match cat:
		"propulsion":
			var thrust_n: float = float(part_data.get("thrust_n", 0.0))
			var thrust_str: String = ("%.1f kN" % (thrust_n / 1000.0)) if thrust_n >= 100.0 else ("%.2f N" % thrust_n)
			return "%.0fkg %s $%.0fM" % [mass_kg, thrust_str, cost_m]
		"power":
			var kwh: float = float(part_data.get("energy_capacity_kwh", 0.0))
			if kwh > 0.0:
				return "%.0fkg %.0fkWh $%.0fM" % [mass_kg, kwh, cost_m]
			return "%.0fkg %+.0fW $%.0fM" % [mass_kg, float(part_data.get("power_w", 0.0)), cost_m]
		"comms":
			return "%.0fkg %.1fMbps $%.0fM" % [mass_kg, float(part_data.get("data_rate_mbps", 0.0)), cost_m]
		"avionics":
			var slope: float = float(part_data.get("max_safe_slope_deg", 0.0))
			if slope > 0.0:
				return "%.0fkg %.0fdeg $%.0fM" % [mass_kg, slope, cost_m]
			return "%.0fkg %.0fkr $%.0fM" % [mass_kg, float(part_data.get("radiation_tolerance_krad", 0.0)), cost_m]
		"payload":
			return "%.0fkg +%.0fSci $%.0fM" % [mass_kg, float(part_data.get("science_points", 0.0)), cost_m]
		"shielding":
			return "%.0fkg %.0fg/cm2 $%.0fM" % [mass_kg, float(part_data.get("shielding_g_cm2", 0.0)), cost_m]

	return "%.0fkg %+.0fW $%.0fM" % [mass_kg, float(part_data.get("power_w", 0.0)), cost_m]


func _build_part_tooltip(part_data: Dictionary) -> String:
	var name_str: String = str(part_data.get("name", ""))
	var cat: String = str(part_data.get("subsystem", "")).capitalize()
	var mass: float = float(part_data.get("mass_dry_kg", 0.0))
	var mga: float = float(part_data.get("mga_percent", 0.15)) * 100.0
	var eff_mass: float = mass * (1.0 + mga / 100.0)
	var power: float = float(part_data.get("power_w", 0.0))
	var cost: float = float(part_data.get("cost_m_usd", 0.0))
	var mount_pt: String = str(part_data.get("mount_point", ""))
	var citation: String = str(part_data.get("nasa_citation", NasaDataLoader.get_catalog_citation()))

	var tip: String = "%s\n" % name_str
	tip += "Subsystem: %s | Mount: %s\n" % [cat, mount_pt]
	tip += "Nominal Dry Mass: %.2f kg (+%.1f%% MGA -> %.2f kg)\n" % [mass, mga, eff_mass]
	tip += "Operating Power: %+.1f W | Cost: $%.2f M\n" % [power, cost]

	if float(part_data.get("thrust_n", 0.0)) > 0.0:
		tip += "Thrust: %.2f N | Isp: %.1f s | Propellant: %.1f kg\n" % [
			float(part_data.get("thrust_n", 0.0)),
			float(part_data.get("isp_s", 0.0)),
			float(part_data.get("propellant_capacity_kg", 0.0))
		]
	if float(part_data.get("thermal_output_w", 0.0)) > 0.0:
		tip += "Thermal Output: %.0f W\n" % float(part_data.get("thermal_output_w", 0.0))
	if float(part_data.get("science_points", 0.0)) > 0.0:
		tip += "Science Return: +%.0f pts | Telemetry: %.1f GB/day\n" % [
			float(part_data.get("science_points", 0.0)),
			float(part_data.get("data_rate_gb_day", 0.0))
		]
	if float(part_data.get("data_rate_mbps", 0.0)) > 0.0:
		tip += "DSN Downlink Rate: %.1f Mbps\n" % float(part_data.get("data_rate_mbps", 0.0))
	if float(part_data.get("shielding_g_cm2", 0.0)) > 0.0:
		tip += "Shielding Density: %.1f g/cm^2\n" % float(part_data.get("shielding_g_cm2", 0.0))

	tip += "\n[NASA Citation]\n%s" % citation
	return tip


func _on_part_card_pressed(part_id: String) -> void:
	_on_part_hovered(part_id)
	_play_vab_sfx("vab_snap")
	if part_id == "chassis_clps":
		_refresh_equipped_states(MissionState.get_telemetry_snapshot())
		return
	MissionState.toggle_subsystem(part_id)


func _play_vab_sfx(sfx_name: String) -> void:
	if not is_inside_tree():
		return
	var shell: Node = get_tree().get_first_node_in_group("main_shell")
	if is_instance_valid(shell) and shell.has_method("play_sfx"):
		shell.call("play_sfx", sfx_name)


func _on_state_updated(snap: Dictionary) -> void:
	_refresh_equipped_states(snap)


func _on_chassis_meshes_updated(active_slots: Array[Dictionary]) -> void:
	_latest_slots = active_slots
	_update_trade_summary(MissionState.get_telemetry_snapshot())
	_update_diegetic_pins()


func _refresh_equipped_states(snap: Dictionary) -> void:
	if snap.is_empty():
		return

	var raw_ids: Array = snap.get("subsystem_ids", []) as Array
	var equipped: Array[String] = []
	for id_var: Variant in raw_ids:
		equipped.append(str(id_var))

	for part_var: Variant in _part_buttons.keys():
		var part_id: String = str(part_var)
		var btn: Button = _part_buttons[part_id] as Button
		var is_on: bool = equipped.has(part_id)
		var part_data: Dictionary = NasaDataLoader.get_subsystem(part_id)
		if not part_data.is_empty():
			_update_part_card_text(btn, part_data, snap)
		btn.set_pressed_no_signal(is_on)
		_apply_part_btn_style(btn, is_on)

	if not _hovered_part_id.is_empty():
		_on_part_hovered(_hovered_part_id)
	_sync_diegetic_pin_styles()
	_update_trade_summary(snap)


func _apply_part_btn_style(btn: Button, equipped: bool) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_CARD_EQUIPPED if equipped else COLOR_CARD_NORMAL
	style.border_color = COLOR_OK if equipped else BrandStyle.BTN_BORDER
	style.set_border_width_all(1)
	if equipped:
		style.border_width_left = 4
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	var hover_sb: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover_sb.border_color = COLOR_NEON_YELLOW
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("hover", hover_sb)


func _update_trade_summary(snap: Dictionary) -> void:
	if snap.is_empty():
		return

	var eng: bool = bool(snap.get("engineer_mode", false))
	var tw: float = float(snap.get("lunar_tw_ratio", 0.0))
	var dv: float = float(snap.get("delta_v_ms", 0.0))
	var req_dv: float = float(snap.get("required_dv_ms", 1750.0))
	var m0_wet: float = float(snap.get("m0_wet_kg", 0.0))
	var dry_nom: float = float(snap.get("dry_mass_nominal_kg", 0.0))
	var mga_kg: float = float(snap.get("mga_mass_kg", 0.0))
	var net_p: float = float(snap.get("net_power_w", 0.0))
	var life_d: float = float(snap.get("mission_lifetime_days", 0.0))
	var fail_code: String = str(snap.get("failure_code", "NOMINAL"))

	var status_sym: String = "✔" if fail_code == "NOMINAL" else ("⚠" if fail_code == "DSN_DOWNLINK_BOTTLENECK" else "✖")
	var status_color: Color = COLOR_OK if fail_code == "NOMINAL" else (COLOR_WARN if fail_code == "DSN_DOWNLINK_BOTTLENECK" else COLOR_CRIT)
	if eng:
		trade_summary_label.text = "%s %d Mounted  •  T/W %.2f  •  Δv %.0f/%.0f m/s  •  m0 %.0f kg  •  %s" % [
			status_sym, _latest_slots.size(), tw, dv, req_dv, m0_wet, fail_code
		]
	else:
		var student_tag: String = "SAFE LANDING T/W" if tw >= 1.0 else "THRUST DEFICIT"
		trade_summary_label.text = "%s %d Mounted  •  %s  •  Δv %.0f m/s  •  %+.0f W" % [
			status_sym, _latest_slots.size(), student_tag, dv, net_p
		]
	trade_summary_label.add_theme_color_override("font_color", status_color)

	var slot_lines: Array[String] = []
	for slot_rec: Dictionary in _latest_slots:
		slot_lines.append("• %s -> %s (%s)" % [
			str(slot_rec.get("mount_point", "Mount")),
			str(slot_rec.get("name", "")),
			str(slot_rec.get("model_path", "")).get_file()
		])

	trade_summary_label.tooltip_text = (
		"Real-Time MGA & Trade Study\n"
		+ "Dry Mass: %.1f kg (+%.1f kg MGA) | Wet Mass (m0): %.1f kg\n" % [dry_nom, mga_kg, m0_wet]
		+ "Lunar T/W: %.3f | Delta-V: %.0f / %.0f m/s | Net Power: %+.1f W\n" % [tw, dv, req_dv, net_p]
		+ "Surface Lifetime: %.1f days | Status: %s\n\n" % [life_d, fail_code]
		+ "Mounted 3D Slots (%d):\n%s" % [_latest_slots.size(), "\n".join(slot_lines)]
	)


func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_distance = clampf(_target_distance - 0.5, 2.8, 14.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_distance = clampf(_target_distance + 0.5, 2.8, 14.0)
	elif event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_target_yaw -= mm.relative.x * 0.008
		_target_pitch = clampf(_target_pitch - mm.relative.y * 0.008, -1.25, 0.20)


func _update_camera_transform(snap_now: bool) -> void:
	if not is_instance_valid(camera_pivot) or not is_instance_valid(vab_camera):
		return
	if snap_now:
		_cam_yaw = _target_yaw
		_cam_pitch = _target_pitch
		_cam_distance = _target_distance
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	vab_camera.position = Vector3(0.0, 0.0, _cam_distance)
	vab_camera.look_at(camera_pivot.global_position, Vector3.UP)


func _on_reset_camera_pressed() -> void:
	_target_yaw = 0.65
	_target_pitch = -0.34
	_target_distance = 5.8


func _on_turntable_toggled(toggled_on: bool) -> void:
	_auto_turntable = toggled_on


func _on_proceed_sim_pressed() -> void:
	proceed_to_descent_requested.emit()


func _on_export_code_pressed() -> void:
	var code: String = MissionState.export_design_code()
	design_code_edit.text = code
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(code)


func _on_import_code_pressed() -> void:
	var code: String = design_code_edit.text.strip_edges()
	if not code.is_empty():
		MissionState.import_design_code(code)
