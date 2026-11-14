class_name TelemetrySparkline
extends Control

## Lightweight 48x16 px vector sparkline rendered via Control._draw() for Power/Radiation telemetry.

@export var line_color: Color = Color(0.184, 0.827, 1.0, 1.0) # #2FD3FF
@export var max_samples: int = 16

var _samples: PackedFloat32Array = PackedFloat32Array()
var _baseline: float = 0.0
var _has_baseline: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(48.0, 16.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push_sample(value: float, col: Color, show_baseline: bool = false, baseline_val: float = 0.0) -> void:
	line_color = col
	_has_baseline = show_baseline
	_baseline = baseline_val
	_samples.append(value)
	while _samples.size() > max_samples:
		_samples.remove_at(0)
	queue_redraw()


func set_series(values: PackedFloat32Array, col: Color, show_baseline: bool = false, baseline_val: float = 0.0) -> void:
	line_color = col
	_has_baseline = show_baseline
	_baseline = baseline_val
	_samples = values.duplicate()
	queue_redraw()


func _draw() -> void:
	var w: float = maxf(24.0, size.x)
	var h: float = maxf(12.0, size.y)
	var rect: Rect2 = Rect2(Vector2.ZERO, Vector2(w, h))

	draw_rect(rect, Color(0.020, 0.031, 0.059, 0.72), true)
	draw_rect(rect, Color(0.165, 0.231, 0.333, 0.85), false, 1.0)

	if _samples.is_empty():
		return

	var min_v: float = _samples[0]
	var max_v: float = _samples[0]
	for v: float in _samples:
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)
	if _has_baseline:
		min_v = minf(min_v, _baseline)
		max_v = maxf(max_v, _baseline)
	if absf(max_v - min_v) < 1.0:
		min_v -= 10.0
		max_v += 10.0

	var pad_x: float = 3.0
	var pad_y: float = 3.0
	var inner_w: float = maxf(4.0, w - pad_x * 2.0)
	var inner_h: float = maxf(4.0, h - pad_y * 2.0)

	if _has_baseline:
		var bt: float = clampf((_baseline - min_v) / (max_v - min_v), 0.0, 1.0)
		var by: float = pad_y + (1.0 - bt) * inner_h
		draw_line(Vector2(pad_x, by), Vector2(w - pad_x, by), Color(0.310, 0.416, 0.573, 0.55), 1.0)

	var count: int = _samples.size()
	if count == 1:
		var pt: Vector2 = Vector2(w * 0.5, h * 0.5)
		draw_circle(pt, 2.0, line_color)
		return

	var pts: PackedVector2Array = PackedVector2Array()
	for idx: int in range(count):
		var tx: float = float(idx) / float(count - 1)
		var ty: float = clampf((_samples[idx] - min_v) / (max_v - min_v), 0.0, 1.0)
		pts.append(Vector2(pad_x + tx * inner_w, pad_y + (1.0 - ty) * inner_h))

	draw_polyline(pts, line_color, 1.4, true)
	draw_circle(pts[pts.size() - 1], 2.0, Color(1.0, 1.0, 1.0, 0.95))
