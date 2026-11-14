class_name ParetoChartControl
extends Control

## Custom 2D Control._draw() Multi-Objective Pareto Frontier Plotter.
## Plots Science Return (pts) vs Subsystems Cost (M$) or Wet Mass m0 (kg),
## highlighting the Pareto-Optimal Frontier, NASA Preset 1 Reference, and Player Lander.

signal point_hovered(point_data: Dictionary)

enum XAxisMode {
	COST_MUSD = 0,
	WET_MASS_KG = 1
}

const COLOR_BG: Color = Color(0.039, 0.059, 0.110, 0.96)
const COLOR_BORDER: Color = Color(0.20, 0.31, 0.48, 0.90)
const COLOR_GRID: Color = Color(0.16, 0.24, 0.36, 0.55)
const COLOR_AXIS_TEXT: Color = Color(0.72, 0.80, 0.90, 1.0)
const COLOR_FEASIBLE_DOT: Color = Color(0.38, 0.54, 0.72, 0.48)
const COLOR_INFEASIBLE_DOT: Color = Color(0.82, 0.28, 0.28, 0.28)
const COLOR_PARETO_LINE: Color = Color(0.220, 0.741, 0.973, 0.95)
const COLOR_PARETO_DOT: Color = Color(0.98, 0.80, 0.25, 1.0)
const COLOR_NASA_REF: Color = Color(0.063, 0.725, 0.506, 1.0)
const COLOR_PLAYER_OK: Color = Color(0.980, 0.749, 0.141, 1.0)
const COLOR_PLAYER_FAIL: Color = Color(0.937, 0.267, 0.267, 1.0)
const COLOR_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)

var x_axis_mode: XAxisMode = XAxisMode.COST_MUSD
var all_candidates: Array[Dictionary] = []
var pareto_frontier: Array[Dictionary] = []
var player_point: Dictionary = {}
var nasa_optimal_point: Dictionary = {}
var hovered_point: Dictionary = {}

var _min_x: float = 40.0
var _max_x: float = 200.0
var _min_y: float = 0.0
var _max_y: float = 150.0
var _pulse_phase: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(420.0, 320.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not player_point.is_empty():
		_pulse_phase += delta * 3.5
		queue_redraw()


func set_chart_data(
	candidates: Array[Dictionary],
	frontier: Array[Dictionary],
	player: Dictionary,
	nasa_ref: Dictionary
) -> void:
	all_candidates = candidates.duplicate(true)
	pareto_frontier = frontier.duplicate(true)
	player_point = player.duplicate(true)
	nasa_optimal_point = nasa_ref.duplicate(true)
	hovered_point.clear()
	_recompute_bounds()
	queue_redraw()


func set_x_axis_mode(mode: XAxisMode) -> void:
	x_axis_mode = mode
	_recompute_bounds()
	queue_redraw()


func _get_x_value(pt: Dictionary) -> float:
	if x_axis_mode == XAxisMode.WET_MASS_KG:
		return float(pt.get("total_mass_kg", 0.0))
	return float(pt.get("cost_m_usd", 0.0))


func _get_y_value(pt: Dictionary) -> float:
	return float(pt.get("science_score", 0.0))


func _recompute_bounds() -> void:
	var min_x_found: float = INF
	var max_x_found: float = -INF
	var max_y_found: float = 100.0

	var combined: Array[Dictionary] = []
	combined.append_array(all_candidates)
	if not player_point.is_empty():
		combined.append(player_point)
	if not nasa_optimal_point.is_empty():
		combined.append(nasa_optimal_point)

	for pt: Dictionary in combined:
		var xv: float = _get_x_value(pt)
		var yv: float = _get_y_value(pt)
		if xv > 0.0:
			min_x_found = minf(min_x_found, xv)
			max_x_found = maxf(max_x_found, xv)
		max_y_found = maxf(max_y_found, yv)

	if min_x_found == INF or max_x_found <= min_x_found:
		if x_axis_mode == XAxisMode.WET_MASS_KG:
			_min_x = 400.0
			_max_x = 1800.0
		else:
			_min_x = 40.0
			_max_x = 200.0
	else:
		var span_x: float = maxf(20.0, max_x_found - min_x_found)
		_min_x = maxf(0.0, floor((min_x_found - span_x * 0.08) / 10.0) * 10.0)
		_max_x = ceil((max_x_found + span_x * 0.08) / 10.0) * 10.0

	_min_y = 0.0
	_max_y = maxf(100.0, ceil((max_y_found * 1.12) / 10.0) * 10.0)


func _get_plot_rect() -> Rect2:
	var m_left: float = 64.0
	var m_right: float = 24.0
	var m_top: float = 34.0
	var m_bottom: float = 46.0
	return Rect2(
		m_left,
		m_top,
		maxf(80.0, size.x - m_left - m_right),
		maxf(80.0, size.y - m_top - m_bottom)
	)


func _to_screen(val_x: float, val_y: float, plot_rect: Rect2) -> Vector2:
	var norm_x: float = clampf((val_x - _min_x) / maxf(1.0, _max_x - _min_x), 0.0, 1.0)
	var norm_y: float = clampf((val_y - _min_y) / maxf(1.0, _max_y - _min_y), 0.0, 1.0)
	return Vector2(
		plot_rect.position.x + norm_x * plot_rect.size.x,
		plot_rect.position.y + (1.0 - norm_y) * plot_rect.size.y
	)


func _draw() -> void:
	var plot_rect: Rect2 = _get_plot_rect()
	var font: Font = ThemeDB.fallback_font

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.027, 0.043, 0.082, 0.98), true)
	draw_rect(plot_rect, COLOR_BG, true)
	_draw_grid_and_axes(plot_rect, font)
	draw_rect(plot_rect, COLOR_BORDER, false, 1.5)

	# 1. All candidate architectures (scatter)
	for pt: Dictionary in all_candidates:
		var pos: Vector2 = _to_screen(_get_x_value(pt), _get_y_value(pt), plot_rect)
		var is_feas: bool = bool(pt.get("feasible", false))
		draw_circle(pos, 2.8 if is_feas else 2.0, COLOR_FEASIBLE_DOT if is_feas else COLOR_INFEASIBLE_DOT)

	# 2. Connected Pareto-Optimal Frontier sorted by active X metric
	if not pareto_frontier.is_empty():
		var sorted_frontier: Array[Dictionary] = pareto_frontier.duplicate()
		sorted_frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ax: float = _get_x_value(a)
			var bx: float = _get_x_value(b)
			if is_equal_approx(ax, bx):
				return _get_y_value(a) < _get_y_value(b)
			return ax < bx
		)

		var poly: PackedVector2Array = PackedVector2Array()
		for pt: Dictionary in sorted_frontier:
			poly.append(_to_screen(_get_x_value(pt), _get_y_value(pt), plot_rect))
		if poly.size() > 1:
			draw_polyline(poly, COLOR_PARETO_LINE, 2.5, true)
		for p_pos: Vector2 in poly:
			draw_circle(p_pos, 4.2, COLOR_PARETO_DOT)
			draw_arc(p_pos, 4.5, 0.0, TAU, 16, COLOR_PARETO_LINE, 1.2, true)

	# 3. Preset 1 (NASA Optimal Reference)
	if not nasa_optimal_point.is_empty():
		var nasa_pos: Vector2 = _to_screen(_get_x_value(nasa_optimal_point), _get_y_value(nasa_optimal_point), plot_rect)
		var diamond: PackedVector2Array = PackedVector2Array([
			nasa_pos + Vector2(0.0, -8.5),
			nasa_pos + Vector2(8.5, 0.0),
			nasa_pos + Vector2(0.0, 8.5),
			nasa_pos + Vector2(-8.5, 0.0)
		])
		draw_colored_polygon(diamond, COLOR_NASA_REF)
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), COLOR_WHITE, 1.4)
		var label_offset: Vector2 = Vector2(-126.0, -10.0) if nasa_pos.x > plot_rect.end.x - 140.0 else Vector2(12.0, -6.0)
		draw_string(font, nasa_pos + label_offset, "NASA Ref (Preset 1)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_NASA_REF)

	# 4. Hovered candidate highlight
	if not hovered_point.is_empty():
		var h_pos: Vector2 = _to_screen(_get_x_value(hovered_point), _get_y_value(hovered_point), plot_rect)
		draw_arc(h_pos, 9.0, 0.0, TAU, 24, COLOR_WHITE, 1.5, true)

	# 5. Current Mission Architecture (Pulsing Crosshair)
	if not player_point.is_empty():
		var p_pos: Vector2 = _to_screen(_get_x_value(player_point), _get_y_value(player_point), plot_rect)
		var is_nominal: bool = bool(player_point.get("feasible", false)) and MissionState.mission_failure_code == "NOMINAL"
		var p_col: Color = COLOR_PLAYER_OK if is_nominal else COLOR_PLAYER_FAIL
		var pulse_r: float = 11.0 + 4.0 * sin(_pulse_phase)
		draw_arc(p_pos, pulse_r, 0.0, TAU, 28, Color(p_col.r, p_col.g, p_col.b, 0.65), 2.0, true)
		draw_line(p_pos + Vector2(-13.0, 0.0), p_pos + Vector2(13.0, 0.0), p_col, 1.8)
		draw_line(p_pos + Vector2(0.0, -13.0), p_pos + Vector2(0.0, 13.0), p_col, 1.8)
		draw_circle(p_pos, 6.0, p_col)
		draw_circle(p_pos, 2.5, COLOR_WHITE)
		var p_label_off: Vector2 = Vector2(-92.0, 18.0) if p_pos.x > plot_rect.end.x - 110.0 else Vector2(13.0, 16.0)
		draw_string(font, p_pos + p_label_off, "Your Lander", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, p_col)

	_draw_legend(plot_rect, font)


func _draw_grid_and_axes(plot_rect: Rect2, font: Font) -> void:
	var steps: int = 5
	for i: int in range(steps + 1):
		var t: float = float(i) / float(steps)
		var x_px: float = plot_rect.position.x + t * plot_rect.size.x
		var y_px: float = plot_rect.position.y + (1.0 - t) * plot_rect.size.y

		draw_line(Vector2(x_px, plot_rect.position.y), Vector2(x_px, plot_rect.end.y), COLOR_GRID, 1.0)
		draw_line(Vector2(plot_rect.position.x, y_px), Vector2(plot_rect.end.x, y_px), COLOR_GRID, 1.0)

		var x_val: float = lerpf(_min_x, _max_x, t)
		var x_lbl: String = ("%.0f kg" % x_val) if x_axis_mode == XAxisMode.WET_MASS_KG else ("$%.0fM" % x_val)
		draw_string(font, Vector2(x_px - 22.0, plot_rect.end.y + 16.0), x_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_AXIS_TEXT)

		var y_val: float = lerpf(_min_y, _max_y, t)
		draw_string(font, Vector2(8.0, y_px + 4.0), "%.0f" % y_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_AXIS_TEXT)

	var x_title: String = "Total Wet Mass m0 (kg) -> Lower is Better" if x_axis_mode == XAxisMode.WET_MASS_KG else "Subsystems Cost (M$ USD) -> Lower is Better"
	draw_string(font, Vector2(plot_rect.position.x + plot_rect.size.x * 0.25, size.y - 10.0), x_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_WHITE)
	draw_string(font, Vector2(plot_rect.position.x, 20.0), "Effective Science Return (pts) ^", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_WHITE)


func _draw_legend(plot_rect: Rect2, font: Font) -> void:
	var lx: float = plot_rect.position.x + 12.0
	var ly: float = plot_rect.position.y + 18.0
	draw_rect(Rect2(lx - 6.0, ly - 12.0, 212.0, 70.0), Color(0.03, 0.05, 0.09, 0.84), true)
	draw_rect(Rect2(lx - 6.0, ly - 12.0, 212.0, 70.0), COLOR_BORDER, false, 1.0)

	draw_line(Vector2(lx, ly), Vector2(lx + 16.0, ly), COLOR_PARETO_LINE, 2.5)
	draw_circle(Vector2(lx + 8.0, ly), 3.5, COLOR_PARETO_DOT)
	draw_string(font, Vector2(lx + 24.0, ly + 4.0), "Pareto-Optimal Frontier", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_WHITE)

	draw_circle(Vector2(lx + 8.0, ly + 18.0), 4.5, COLOR_NASA_REF)
	draw_string(font, Vector2(lx + 24.0, ly + 22.0), "Preset 1 NASA Reference", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_NASA_REF)

	draw_circle(Vector2(lx + 8.0, ly + 36.0), 4.5, COLOR_PLAYER_OK)
	draw_string(font, Vector2(lx + 24.0, ly + 40.0), "Your Mission Architecture", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_PLAYER_OK)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var plot_rect: Rect2 = _get_plot_rect()
		var best_pt: Dictionary = {}
		var best_dist: float = 16.0

		var priority_list: Array[Dictionary] = []
		if not player_point.is_empty():
			priority_list.append(player_point)
		if not nasa_optimal_point.is_empty():
			priority_list.append(nasa_optimal_point)
		priority_list.append_array(pareto_frontier)
		priority_list.append_array(all_candidates)

		for pt: Dictionary in priority_list:
			var pos: Vector2 = _to_screen(_get_x_value(pt), _get_y_value(pt), plot_rect)
			var d: float = pos.distance_to(mm.position)
			if d < best_dist:
				best_dist = d
				best_pt = pt

		if not best_pt.is_empty():
			hovered_point = best_pt
			tooltip_text = _format_point_tooltip(best_pt)
			point_hovered.emit(best_pt)
			queue_redraw()
		elif not hovered_point.is_empty():
			hovered_point.clear()
			tooltip_text = ""
			queue_redraw()


func _format_point_tooltip(pt: Dictionary) -> String:
	var parts_arr: Array = pt.get("subsystem_ids", []) as Array
	var packed_parts: PackedStringArray = PackedStringArray()
	for part_var: Variant in parts_arr:
		packed_parts.append(str(part_var))
	var parts_str: String = ", ".join(packed_parts)
	return (
		"Science: %.1f pts | Wet Mass: %.1f kg | Subsystems Cost: $%.1fM\n"
		% [float(pt.get("science_score", 0.0)), float(pt.get("total_mass_kg", 0.0)), float(pt.get("cost_m_usd", 0.0))]
		+ "Survival: %.0f%% | Lunar T/W: %.2f | Delta-V: %.0f m/s | Net Power: %+.1f W\n"
		% [float(pt.get("survival_prob", 0.0)) * 100.0, float(pt.get("lunar_tw_ratio", 0.0)), float(pt.get("delta_v_ms", 0.0)), float(pt.get("net_power_w", 0.0))]
		+ "Parts: %s" % parts_str
	)
