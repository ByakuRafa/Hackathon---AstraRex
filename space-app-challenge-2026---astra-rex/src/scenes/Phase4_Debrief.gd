class_name Phase4Debrief
extends Control

## Phase 4: Post-Mission Multi-Objective Pareto Analytics & Root-Cause Debriefing.
## Two-column executive dashboard:
##   Left: Interactive Control._draw() Pareto Frontier plot (Cost M$ or Wet Mass kg vs Science pts).
##   Right: Concise Status Pill, Root-Cause Bottleneck cards, SI Frontier Delta table,
##          CSV/JSON browser export, and Base64 Design Code sharing.

signal iterate_in_vab_requested()

const COLOR_PANEL_BG: Color = Color(0.055, 0.082, 0.145, 0.96)
const COLOR_ROW_BG: Color = Color(0.075, 0.110, 0.184, 0.96)
const COLOR_OK: Color = Color(0.063, 0.725, 0.506, 1.0)
const COLOR_WARN: Color = Color(0.961, 0.620, 0.043, 1.0)
const COLOR_CRIT: Color = Color(0.937, 0.267, 0.267, 1.0)
const COLOR_ACCENT: Color = Color(0.220, 0.741, 0.973, 1.0)
const COLOR_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_MUTED: Color = Color(0.580, 0.639, 0.722, 1.0)

@onready var chart_card: PanelContainer = %ChartCard
@onready var pareto_chart: ParetoChartControl = %ParetoChart
@onready var btn_axis_cost: Button = %BtnAxisCost
@onready var btn_axis_mass: Button = %BtnAxisMass
@onready var solver_status_label: Label = %SolverStatusLabel
@onready var hover_readout_label: Label = %HoverReadoutLabel

@onready var primary_status_card: PanelContainer = %PrimaryStatusCard
@onready var status_pill_label: Label = %StatusPillLabel
@onready var primary_title_label: Label = %PrimaryTitleLabel
@onready var primary_cause_label: Label = %PrimaryCauseLabel

@onready var bottlenecks_card: PanelContainer = %BottlenecksCard
@onready var bottlenecks_vbox: VBoxContainer = %BottlenecksVBox

@onready var benchmark_card: PanelContainer = %BenchmarkCard
@onready var benchmark_grid: GridContainer = %BenchmarkGrid

@onready var export_bar: PanelContainer = %ExportBar
@onready var btn_export_csv: Button = %BtnExportCSV
@onready var btn_export_json: Button = %BtnExportJSON
@onready var export_status_label: Label = %ExportStatusLabel
@onready var design_code_edit: LineEdit = %DesignCodeEdit
@onready var btn_copy_code: Button = %BtnCopyCode
@onready var btn_load_code: Button = %BtnLoadCode
@onready var btn_iterate_vab: Button = %BtnIterateVAB

var _is_debrief_active: bool = false
var _refresh_queued: bool = false
var _latest_report: Dictionary = {}


func _ready() -> void:
	_style_panels()
	_style_cta_button(btn_iterate_vab)
	_connect_signals()
	_sync_axis_buttons(ParetoChartControl.XAxisMode.COST_MUSD)
	set_debrief_active(false)


func set_debrief_active(active: bool) -> void:
	_is_debrief_active = active
	visible = active
	if active:
		design_code_edit.text = MissionState.export_design_code()
		_refresh_debrief_async()


func _connect_signals() -> void:
	btn_axis_cost.pressed.connect(_on_axis_mode_pressed.bind(ParetoChartControl.XAxisMode.COST_MUSD))
	btn_axis_mass.pressed.connect(_on_axis_mode_pressed.bind(ParetoChartControl.XAxisMode.WET_MASS_KG))
	pareto_chart.point_hovered.connect(_on_chart_point_hovered)

	btn_export_csv.pressed.connect(_on_export_pressed.bind("csv"))
	btn_export_json.pressed.connect(_on_export_pressed.bind("json"))
	btn_copy_code.pressed.connect(_on_copy_code_pressed)
	btn_load_code.pressed.connect(_on_load_code_pressed)
	btn_iterate_vab.pressed.connect(func() -> void: iterate_in_vab_requested.emit())

	if not MissionState.state_updated.is_connected(_on_state_updated):
		MissionState.state_updated.connect(_on_state_updated)
	if not MissionState.preset_loaded.is_connected(_on_preset_loaded):
		MissionState.preset_loaded.connect(_on_preset_loaded)
	if not ParetoSolver.report_exported.is_connected(_on_report_exported):
		ParetoSolver.report_exported.connect(_on_report_exported)


func _on_preset_loaded(_preset_index: int, _preset_name: String) -> void:
	if _is_debrief_active:
		design_code_edit.text = MissionState.export_design_code()
		_refresh_debrief_async()


func _on_state_updated(_snap: Dictionary) -> void:
	if _is_debrief_active:
		design_code_edit.text = MissionState.export_design_code()
		_refresh_debrief_async()


func _refresh_debrief_async() -> void:
	if ParetoSolver.is_solving:
		_refresh_queued = true
		return

	solver_status_label.text = "Solving Pareto Frontier (cooperative frame-slicing)..."
	var frontier: Array[Dictionary] = await ParetoSolver.solve_pareto_frontier_async(64)

	if _refresh_queued:
		_refresh_queued = false
		frontier = await ParetoSolver.solve_pareto_frontier_async(64)

	var report: Dictionary = ParetoSolver.generate_root_cause_report()
	_latest_report = report

	var p1_preset: Dictionary = NasaDataLoader.get_preset("1")
	var p1_parts: Array = p1_preset.get("subsystems", []) as Array
	var nasa_ref: Dictionary = ParetoSolver._evaluate_candidate(
		p1_parts,
		MissionState.selected_orbit_id,
		MissionState.selected_landing_zone_id
	)
	var player_pt: Dictionary = report.get("player_design", {}) as Dictionary

	pareto_chart.set_chart_data(ParetoSolver.cached_candidates, frontier, player_pt, nasa_ref)
	solver_status_label.text = "%d Evaluated • %d Pareto-Optimal (%s)" % [
		ParetoSolver.cached_candidates.size(),
		frontier.size(),
		MissionState.selected_landing_zone_id
	]

	_render_primary_status_card(report)
	_render_bottlenecks_card(report)
	_render_benchmark_grid(report)


func _render_primary_status_card(report: Dictionary) -> void:
	var status_code: String = str(report.get("status", "NOMINAL"))
	var is_nominal: bool = bool(report.get("nominal", false))
	var primary_diag: Dictionary = report.get("primary_diagnosis", {}) as Dictionary

	var pill_col: Color = COLOR_OK if is_nominal else (COLOR_WARN if status_code == "DSN_DOWNLINK_BOTTLENECK" else COLOR_CRIT)
	var pill_text: String = "MISSION SUCCESS • NOMINAL" if is_nominal else ("WARN • %s" % status_code if status_code == "DSN_DOWNLINK_BOTTLENECK" else "FAILURE • %s" % status_code)
	_apply_status_pill(pill_text, pill_col)

	primary_title_label.text = str(primary_diag.get("title", "Mission Engineering Review"))
	primary_cause_label.text = str(primary_diag.get("cause", ""))
	primary_status_card.tooltip_text = (
		"Physics Principle:\n%s\n\nRecommended Action:\n%s\n\n[NASA Reference]\n%s"
		% [
			str(primary_diag.get("physics_principle", "")),
			str(primary_diag.get("recommendation", "")),
			str(primary_diag.get("citation", NasaDataLoader.get_catalog_citation()))
		]
	)


func _render_bottlenecks_card(report: Dictionary) -> void:
	for child: Node in bottlenecks_vbox.get_children():
		child.queue_free()

	var bottlenecks: Array = report.get("all_bottlenecks", []) as Array
	if bottlenecks.is_empty():
		var opt_row: Label = _make_action_row(
			"-> All SI constraints passed. Toggle Cost / Wet Mass to inspect lighter frontier variants.",
			COLOR_OK,
			"All NASA SP-2016-6105, JPL DE441, LRO LOLA, and OSDR RadLab envelopes satisfied."
		)
		bottlenecks_vbox.add_child(opt_row)
		return

	for b_var: Variant in bottlenecks:
		var b: Dictionary = b_var as Dictionary
		var row_text: String = "-> [%s] %s" % [str(b.get("code", "")), str(b.get("recommendation", ""))]
		var tip: String = (
			"%s\nCause: %s\n\nPhysics:\n%s\n\n[NASA Citation]\n%s"
			% [
				str(b.get("title", "")),
				str(b.get("cause", "")),
				str(b.get("physics_principle", "")),
				str(b.get("citation", ""))
			]
		)
		var is_warn: bool = str(b.get("code", "")) == "DSN_DOWNLINK_BOTTLENECK"
		bottlenecks_vbox.add_child(_make_action_row(row_text, COLOR_WARN if is_warn else COLOR_CRIT, tip))


func _make_action_row(text_val: String, accent_col: Color, tip: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text_val
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", COLOR_WHITE)
	lbl.tooltip_text = tip
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_ROW_BG
	sb.border_color = accent_col
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	lbl.add_theme_stylebox_override("normal", sb)
	return lbl


func _render_benchmark_grid(report: Dictionary) -> void:
	for child: Node in benchmark_grid.get_children():
		child.queue_free()

	var player_pt: Dictionary = report.get("player_design", {}) as Dictionary
	var deltas: Dictionary = report.get("pareto_deltas", {}) as Dictionary
	var telem: Dictionary = report.get("telemetry", {}) as Dictionary

	_add_grid_header("SI Metric")
	_add_grid_header("Your Lander")
	_add_grid_header("vs Pareto Ref")

	var d_sci: float = float(deltas.get("delta_science", 0.0))
	_add_grid_row(
		"Science Return",
		"%.1f pts" % float(player_pt.get("science_score", 0.0)),
		"Opt %+.1f pts" % d_sci,
		COLOR_OK if d_sci <= 0.1 else COLOR_WARN
	)

	var d_mass: float = float(deltas.get("delta_mass_kg", 0.0))
	_add_grid_row(
		"Wet Mass (m0)",
		"%.1f kg" % float(telem.get("m0_wet_kg", 0.0)),
		"Opt %+.1f kg" % d_mass,
		COLOR_OK if d_mass >= -0.5 else COLOR_WARN
	)

	var d_cost: float = float(deltas.get("delta_cost_musd", 0.0))
	_add_grid_row(
		"Subsystems Cost",
		"$%.1fM" % float(player_pt.get("cost_m_usd", 0.0)),
		"Opt %+.1fM" % d_cost,
		COLOR_OK if d_cost >= -0.1 else COLOR_WARN
	)

	var surv_pct: float = float(player_pt.get("survival_prob", 0.0)) * 100.0
	var d_surv: float = float(deltas.get("delta_survival_prob", 0.0)) * 100.0
	_add_grid_row(
		"Survival Prob",
		"%.0f%%" % surv_pct,
		"Opt %+.0f%%" % d_surv,
		COLOR_OK if surv_pct >= 85.0 else COLOR_CRIT
	)

	var tw: float = float(telem.get("lunar_tw_ratio", 0.0))
	var dv: float = float(telem.get("delta_v_ms", 0.0))
	var req_dv: float = float(telem.get("required_dv_ms", 1750.0))
	_add_grid_row(
		"Lunar T/W & Δv",
		"%.2f • %.0f m/s" % [tw, dv],
		"Req >= %.0f m/s" % req_dv,
		COLOR_OK if (tw >= 1.0 and dv >= req_dv) else COLOR_CRIT
	)

	var dose_msv: float = float(telem.get("total_mission_dose_msv", 0.0))
	var life_d: float = float(telem.get("mission_lifetime_days", 0.0))
	_add_grid_row(
		"Rad Dose & Life",
		"%.1f mSv • %.0f d" % [dose_msv, life_d],
		"Cap %.0f mSv" % NasaDataLoader.get_mission_dose_limit_msv(),
		COLOR_OK if (dose_msv <= NasaDataLoader.get_mission_dose_limit_msv() and life_d >= 14.0) else COLOR_WARN
	)


func _add_grid_header(title: String) -> void:
	var lbl: Label = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", COLOR_MUTED)
	benchmark_grid.add_child(lbl)


func _add_grid_row(metric: String, val_str: String, delta_str: String, col: Color) -> void:
	var m_lbl: Label = Label.new()
	m_lbl.text = metric
	m_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_lbl.add_theme_font_size_override("font_size", 12)
	m_lbl.add_theme_color_override("font_color", COLOR_MUTED)

	var v_lbl: Label = Label.new()
	v_lbl.text = val_str
	v_lbl.add_theme_font_size_override("font_size", 12)
	v_lbl.add_theme_color_override("font_color", COLOR_WHITE)

	var d_lbl: Label = Label.new()
	d_lbl.text = delta_str
	d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	d_lbl.add_theme_font_size_override("font_size", 12)
	d_lbl.add_theme_color_override("font_color", col)

	benchmark_grid.add_child(m_lbl)
	benchmark_grid.add_child(v_lbl)
	benchmark_grid.add_child(d_lbl)


func _on_axis_mode_pressed(mode: ParetoChartControl.XAxisMode) -> void:
	_sync_axis_buttons(mode)
	pareto_chart.set_x_axis_mode(mode)


func _sync_axis_buttons(mode: ParetoChartControl.XAxisMode) -> void:
	btn_axis_cost.set_pressed_no_signal(mode == ParetoChartControl.XAxisMode.COST_MUSD)
	btn_axis_mass.set_pressed_no_signal(mode == ParetoChartControl.XAxisMode.WET_MASS_KG)


func _on_chart_point_hovered(pt: Dictionary) -> void:
	hover_readout_label.text = "Hover: Sci %.1f pts • Wet Mass %.1f kg • Cost $%.1fM • Survival %.0f%% • T/W %.2f" % [
		float(pt.get("science_score", 0.0)),
		float(pt.get("total_mass_kg", 0.0)),
		float(pt.get("cost_m_usd", 0.0)),
		float(pt.get("survival_prob", 0.0)) * 100.0,
		float(pt.get("lunar_tw_ratio", 0.0))
	]


func _on_export_pressed(fmt: String) -> void:
	ParetoSolver.export_telemetry_report(fmt)


func _on_report_exported(file_path_or_name: String, fmt: String) -> void:
	export_status_label.text = "Exported %s: %s" % [fmt.to_upper(), file_path_or_name.get_file()]
	export_status_label.add_theme_color_override("font_color", COLOR_OK)
	export_status_label.tooltip_text = file_path_or_name


func _on_copy_code_pressed() -> void:
	var code: String = MissionState.export_design_code()
	design_code_edit.text = code
	DisplayServer.clipboard_set(code)
	export_status_label.text = "Design code copied to clipboard."
	export_status_label.add_theme_color_override("font_color", COLOR_ACCENT)


func _on_load_code_pressed() -> void:
	var code: String = design_code_edit.text.strip_edges()
	if code.is_empty():
		return
	if MissionState.import_design_code(code):
		export_status_label.text = "Design code loaded."
		export_status_label.add_theme_color_override("font_color", COLOR_OK)
	else:
		export_status_label.text = "Invalid design code."
		export_status_label.add_theme_color_override("font_color", COLOR_CRIT)


func _apply_status_pill(text_val: String, pill_color: Color) -> void:
	status_pill_label.text = text_val
	status_pill_label.add_theme_color_override("font_color", COLOR_WHITE)
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = Color(pill_color.r * 0.35, pill_color.g * 0.35, pill_color.b * 0.35, 0.96)
	pill.border_color = pill_color
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(5)
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	pill.content_margin_top = 6
	pill.content_margin_bottom = 6
	status_pill_label.add_theme_stylebox_override("normal", pill)


func _style_panels() -> void:
	for panel: PanelContainer in [chart_card, primary_status_card, bottlenecks_card, benchmark_card, export_bar]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = COLOR_PANEL_BG
		sb.border_color = Color(0.18, 0.29, 0.45, 0.90)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", sb)


func _style_cta_button(btn: Button) -> void:
	var normal_sb: StyleBoxFlat = StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.06, 0.28, 0.44, 0.98)
	normal_sb.border_color = COLOR_ACCENT
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(5)
	normal_sb.content_margin_left = 12
	normal_sb.content_margin_right = 12
	normal_sb.content_margin_top = 8
	normal_sb.content_margin_bottom = 8
	var hover_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.08, 0.36, 0.56, 1.0)
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_color_override("font_color", COLOR_WHITE)
