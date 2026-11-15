class_name Phase4Debrief
extends Control

## Phase 4: Post-Mission Multi-Objective Pareto Analytics & Root-Cause Debriefing.
## Two-column executive dashboard:
##   Left: Interactive Control._draw() Pareto Frontier plot (Cost M$ or Wet Mass kg vs Science pts).
##   Right: Concise Status Pill, Root-Cause Bottleneck cards, SI Frontier Delta table,
##          CSV/JSON browser export, and Base64 Design Code sharing.

signal iterate_in_vab_requested()

const COLOR_PANEL_BG: Color = BrandStyle.PANEL_900
const COLOR_ROW_BG: Color = Color(0.065, 0.102, 0.175, 0.90)
const COLOR_OK: Color = BrandStyle.PASS_EMERALD
const COLOR_WARN: Color = BrandStyle.CAUTION_AMBER
const COLOR_CRIT: Color = BrandStyle.CRITICAL_RED
const COLOR_ACCENT: Color = BrandStyle.NOMINAL_CYAN
const COLOR_WHITE: Color = BrandStyle.TEXT_WHITE
const COLOR_MUTED: Color = BrandStyle.TEXT_MUTED

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
var _debrief_sparkline: TelemetrySparkline = null
var _mission_evaluated: bool = false


func _ready() -> void:
	BrandStyle.apply_brand_gradient_backdrop(get_node_or_null("BG") as ColorRect)
	_setup_fonts_and_sparkline()
	_style_panels()
	_style_cta_button(btn_iterate_vab)
	_connect_signals()
	_sync_axis_buttons(ParetoChartControl.XAxisMode.COST_MUSD)
	set_debrief_active(false)


func _setup_fonts_and_sparkline() -> void:
	BrandStyle.bind_mono_font(solver_status_label)
	BrandStyle.bind_mono_font(hover_readout_label)
	BrandStyle.bind_mono_font(status_pill_label)
	BrandStyle.bind_mono_font(design_code_edit)
	BrandStyle.bind_mono_font(export_status_label)

	for btn: Button in [btn_axis_cost, btn_axis_mass, btn_export_csv, btn_export_json, btn_copy_code, btn_load_code, btn_iterate_vab]:
		if is_instance_valid(btn):
			btn.focus_mode = Control.FOCUS_NONE

	# Inject compact 48x16 px radiation/margin vector sparkline into BenchmarkCard header row
	if is_instance_valid(benchmark_card):
		var vbox: VBoxContainer = benchmark_card.get_node_or_null("VBox") as VBoxContainer
		if vbox != null:
			var title_lbl: Label = vbox.get_node_or_null("Title") as Label
			if title_lbl != null and not (title_lbl.get_parent() is HBoxContainer):
				var hdr_row: HBoxContainer = HBoxContainer.new()
				hdr_row.name = "BenchmarkHeaderRow"
				hdr_row.add_theme_constant_override("separation", 8)
				vbox.remove_child(title_lbl)
				vbox.add_child(hdr_row)
				vbox.move_child(hdr_row, 0)
				title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hdr_row.add_child(title_lbl)

				_debrief_sparkline = TelemetrySparkline.new()
				_debrief_sparkline.name = "DebriefRadSparkline"
				_debrief_sparkline.tooltip_text = "Projected 180-Day Surface Dose Curve vs 100 mSv Mission Limit\n[NASA OSDR RadLab & LRO CRaTER]"
				hdr_row.add_child(_debrief_sparkline)


func set_debrief_active(active: bool) -> void:
	_is_debrief_active = active
	visible = active
	if active:
		design_code_edit.text = MissionState.export_design_code()
		_refresh_debrief_async()


func set_mission_evaluated(evaluated: bool) -> void:
	_mission_evaluated = evaluated
	if _is_debrief_active and not _latest_report.is_empty():
		_apply_empty_or_evaluated_status(ParetoSolver.cached_pareto_frontier)


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

	var is_unconfigured: bool = (not _mission_evaluated) or (MissionState.selected_subsystem_ids.size() <= 1)
	if is_unconfigured:
		solver_status_label.text = "Load a preset (P1/P2) to evaluate the Pareto frontier (solving...)"
		solver_status_label.add_theme_color_override("font_color", BrandStyle.GUIDE_VIOLET)
	else:
		solver_status_label.text = "Solving Pareto Frontier (cooperative frame-slicing)..."
		solver_status_label.add_theme_color_override("font_color", COLOR_MUTED)
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
	_apply_empty_or_evaluated_status(frontier)

	_render_primary_status_card(report)
	_render_bottlenecks_card(report)
	_render_benchmark_grid(report)


func _apply_empty_or_evaluated_status(frontier: Array[Dictionary]) -> void:
	var is_unconfigured: bool = (not _mission_evaluated) or (MissionState.selected_subsystem_ids.size() <= 1)
	if is_unconfigured:
		solver_status_label.text = "Load a preset (P1/P2) to evaluate the Pareto frontier  •  %d Optimal (%s)" % [
			frontier.size(),
			MissionState.selected_landing_zone_id
		]
		solver_status_label.add_theme_color_override("font_color", BrandStyle.GUIDE_VIOLET)
		hover_readout_label.text = "Load a preset (P1/P2) to evaluate the Pareto frontier or hover any point for SI specs."
		hover_readout_label.add_theme_color_override("font_color", BrandStyle.GUIDE_VIOLET)
	else:
		solver_status_label.text = "%d Evaluated • %d Pareto-Optimal (%s)" % [
			ParetoSolver.cached_candidates.size(),
			frontier.size(),
			MissionState.selected_landing_zone_id
		]
		solver_status_label.add_theme_color_override("font_color", COLOR_MUTED)
		hover_readout_label.add_theme_color_override("font_color", BrandStyle.TEXT_HEADER)


func _render_primary_status_card(report: Dictionary) -> void:
	var status_code: String = str(report.get("status", "NOMINAL"))
	var is_nominal: bool = bool(report.get("nominal", false))
	var primary_diag: Dictionary = report.get("primary_diagnosis", {}) as Dictionary

	var pill_col: Color = COLOR_OK if is_nominal else (COLOR_WARN if status_code == "DSN_DOWNLINK_BOTTLENECK" else COLOR_CRIT)
	var pill_text: String = "[OK] PASS • NOMINAL" if is_nominal else ("[!] CAUTION • %s" % status_code if status_code == "DSN_DOWNLINK_BOTTLENECK" else "[X] FAIL • %s" % status_code)
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
			"[OK] PASS • All SI constraints satisfied. Toggle Cost / Wet Mass to inspect lighter frontier variants.",
			COLOR_OK,
			"All NASA SP-2016-6105, JPL DE441, LRO LOLA, and OSDR RadLab envelopes satisfied."
		)
		bottlenecks_vbox.add_child(opt_row)
		return

	for b_var: Variant in bottlenecks:
		var b: Dictionary = b_var as Dictionary
		var is_warn: bool = str(b.get("code", "")) == "DSN_DOWNLINK_BOTTLENECK"
		var b_sym: String = "[!]" if is_warn else "[X]"
		var row_text: String = "%s [%s] %s" % [b_sym, str(b.get("code", "")), str(b.get("recommendation", ""))]
		var tip: String = (
			"%s\nCause: %s\n\nPhysics:\n%s\n\n[NASA Citation]\n%s"
			% [
				str(b.get("title", "")),
				str(b.get("cause", "")),
				str(b.get("physics_principle", "")),
				str(b.get("citation", ""))
			]
		)
		bottlenecks_vbox.add_child(_make_action_row(row_text, COLOR_WARN if is_warn else COLOR_CRIT, tip))


func _make_action_row(text_val: String, accent_col: Color, tip: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text_val
	lbl.custom_minimum_size = Vector2(460, 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.max_lines_visible = 3
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	var dose_limit: float = NasaDataLoader.get_mission_dose_limit_msv()
	_add_grid_row(
		"Rad Dose & Life",
		"%.1f mSv • %.0f d" % [dose_msv, life_d],
		"Cap %.0f mSv" % dose_limit,
		COLOR_OK if (dose_msv <= dose_limit and life_d >= 14.0) else COLOR_WARN
	)
	_update_debrief_sparkline(telem, dose_limit)
	sync_engineer_mode(MissionState.engineer_mode)


func _update_debrief_sparkline(telem: Dictionary, dose_limit: float) -> void:
	if not is_instance_valid(_debrief_sparkline):
		return
	var transit_spe: float = float(telem.get("transit_dose_msv", 5.0)) + float(telem.get("spe_dose_msv", 0.0))
	var daily_gcr: float = float(telem.get("daily_gcr_msv", 0.72))
	var series: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(10):
		var day_val: float = float(i) * 20.0
		series.append(transit_spe + daily_gcr * day_val)
	var final_dose: float = series[series.size() - 1]
	var spark_col: Color = COLOR_CRIT if final_dose > dose_limit else (COLOR_WARN if final_dose > dose_limit * 0.7 else BrandStyle.NOMINAL_CYAN)
	_debrief_sparkline.set_series(series, spark_col, true, dose_limit * 0.5)


func sync_engineer_mode(eng: bool) -> void:
	for btn_name: String in ["%BtnExportCSV", "%BtnExportJSON"]:
		var b: Button = get_node_or_null(btn_name) as Button
		if b != null:
			b.disabled = not eng
			b.modulate = Color(1.0, 1.0, 1.0, 1.0) if eng else Color(0.55, 0.62, 0.72, 0.45)
	var iterate_btn: Button = get_node_or_null("%BtnIterateVAB") as Button
	if iterate_btn != null:
		iterate_btn.visible = false
	var exp_bar: Control = get_node_or_null("%ExportBar") as Control
	if exp_bar != null:
		exp_bar.visible = false


func _add_grid_header(title: String) -> void:
	var lbl: Label = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COLOR_MUTED)
	var hdr_sb: StyleBoxFlat = StyleBoxFlat.new()
	hdr_sb.bg_color = Color(0.035, 0.055, 0.095, 0.92)
	hdr_sb.border_color = BrandStyle.PANEL_BORDER
	hdr_sb.border_width_bottom = 1
	hdr_sb.content_margin_left = 8
	hdr_sb.content_margin_right = 8
	hdr_sb.content_margin_top = 3
	hdr_sb.content_margin_bottom = 3
	lbl.add_theme_stylebox_override("normal", hdr_sb)
	benchmark_grid.add_child(lbl)


func _add_grid_row(metric: String, val_str: String, delta_str: String, col: Color) -> void:
	@warning_ignore("integer_division")
	var row_idx: int = maxi(0, (benchmark_grid.get_child_count() - 3) / 3)
	var row_bg_col: Color = Color("#16233A") if (row_idx % 2 == 0) else Color("#0E1624")
	var row_sb: StyleBoxFlat = StyleBoxFlat.new()
	row_sb.bg_color = row_bg_col
	row_sb.content_margin_left = 8
	row_sb.content_margin_right = 8
	row_sb.content_margin_top = 3
	row_sb.content_margin_bottom = 3

	var m_lbl: Label = Label.new()
	m_lbl.text = metric
	m_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_lbl.add_theme_font_size_override("font_size", 12)
	m_lbl.add_theme_color_override("font_color", COLOR_MUTED)
	m_lbl.add_theme_stylebox_override("normal", row_sb)

	var v_lbl: Label = Label.new()
	v_lbl.text = val_str
	v_lbl.add_theme_font_size_override("font_size", 12)
	v_lbl.add_theme_color_override("font_color", COLOR_WHITE)
	BrandStyle.bind_mono_font(v_lbl)
	v_lbl.add_theme_stylebox_override("normal", row_sb)

	var d_lbl: Label = Label.new()
	d_lbl.text = delta_str
	d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	d_lbl.add_theme_font_size_override("font_size", 12)
	d_lbl.add_theme_color_override("font_color", col)
	BrandStyle.bind_mono_font(d_lbl)
	d_lbl.add_theme_stylebox_override("normal", row_sb)

	benchmark_grid.add_child(m_lbl)
	benchmark_grid.add_child(v_lbl)
	benchmark_grid.add_child(d_lbl)


func _on_axis_mode_pressed(mode: ParetoChartControl.XAxisMode) -> void:
	get_tree().call_group("main_shell", "play_sfx", "quindar_beep")
	_sync_axis_buttons(mode)
	pareto_chart.set_x_axis_mode(mode)


func _sync_axis_buttons(mode: ParetoChartControl.XAxisMode) -> void:
	var cost_active: bool = (mode == ParetoChartControl.XAxisMode.COST_MUSD)
	btn_axis_cost.set_pressed_no_signal(cost_active)
	btn_axis_mass.set_pressed_no_signal(not cost_active)
	_apply_axis_btn_style(btn_axis_cost, cost_active)
	_apply_axis_btn_style(btn_axis_mass, not cost_active)


func _apply_axis_btn_style(btn: Button, active: bool) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.259, 0.651, 0.90) if active else BrandStyle.PANEL_900
	sb.border_color = BrandStyle.NEON_YELLOW if active else BrandStyle.BTN_BORDER
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2 if active else 1
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	var hover_sb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hover_sb.border_color = BrandStyle.NEON_YELLOW
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_color_override("font_color", BrandStyle.NOMINAL_CYAN if active else BrandStyle.TEXT_HEADER)
	btn.add_theme_color_override("font_pressed_color", BrandStyle.NOMINAL_CYAN)
	btn.add_theme_color_override("font_hover_color", BrandStyle.NEON_YELLOW)


func _on_chart_point_hovered(pt: Dictionary) -> void:
	hover_readout_label.text = "Hover: Sci %.1f pts • Wet Mass %.1f kg • Cost $%.1fM • Survival %.0f%% • T/W %.2f" % [
		float(pt.get("science_score", 0.0)),
		float(pt.get("total_mass_kg", 0.0)),
		float(pt.get("cost_m_usd", 0.0)),
		float(pt.get("survival_prob", 0.0)) * 100.0,
		float(pt.get("lunar_tw_ratio", 0.0))
	]


func _on_export_pressed(fmt: String) -> void:
	if not MissionState.engineer_mode:
		return
	ParetoSolver.export_telemetry_report(fmt)


func _on_report_exported(file_path_or_name: String, fmt: String) -> void:
	export_status_label.text = "Exported %s: %s" % [fmt.to_upper(), file_path_or_name.get_file()]
	export_status_label.add_theme_color_override("font_color", COLOR_OK)
	export_status_label.tooltip_text = file_path_or_name


func _on_copy_code_pressed() -> void:
	var code: String = MissionState.export_design_code()
	design_code_edit.text = code
	if DisplayServer.get_name() != "headless":
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
		BrandStyle.apply_panel_style(panel, 14.0, 8.0, 8.0)

	_ensure_wrapped_label_widths(primary_status_card)
	if is_instance_valid(bottlenecks_vbox) and not (bottlenecks_vbox.get_parent() is ScrollContainer):
		var vbox_parent: Node = bottlenecks_vbox.get_parent()
		var idx: int = bottlenecks_vbox.get_index()
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(360, 120)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox_parent.remove_child(bottlenecks_vbox)
		vbox_parent.add_child(scroll)
		vbox_parent.move_child(scroll, idx)
		scroll.add_child(bottlenecks_vbox)
		bottlenecks_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ensure_wrapped_label_widths(node: Node) -> void:
	if node is Label:
		var lbl: Label = node as Label
		if lbl.autowrap_mode != TextServer.AUTOWRAP_OFF:
			if lbl.custom_minimum_size.x < 460.0:
				lbl.custom_minimum_size = Vector2(460.0, lbl.custom_minimum_size.y)
			if lbl.name == "PrimaryCauseLabel":
				lbl.max_lines_visible = 3
				lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	for child: Node in node.get_children():
		_ensure_wrapped_label_widths(child)


func _style_cta_button(btn: Button) -> void:
	var normal_sb: StyleBoxFlat = StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.043, 0.239, 0.569, 0.96)
	normal_sb.border_color = BrandStyle.NOMINAL_CYAN
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(5)
	normal_sb.content_margin_left = 12
	normal_sb.content_margin_right = 12
	normal_sb.content_margin_top = 8
	normal_sb.content_margin_bottom = 8
	var hover_sb: StyleBoxFlat = normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.0, 0.259, 0.651, 1.0)
	hover_sb.border_color = BrandStyle.NEON_YELLOW
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_color_override("font_color", COLOR_WHITE)
	btn.add_theme_color_override("font_hover_color", BrandStyle.NEON_YELLOW)
