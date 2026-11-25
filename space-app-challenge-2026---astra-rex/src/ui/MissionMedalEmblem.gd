class_name MissionMedalEmblem
extends Control

## Custom _draw() Vector Emblem for Phase 4 Mission Classification Medals.
## Renders crisp geometric rank badges without relying on external image assets or Unicode dingbats.

enum MedalTier {
	PARETO_OPTIMAL = 0,
	FLIGHT_CERTIFIED = 1,
	SUBOPTIMAL = 2,
	MISSION_LOSS = 3,
}

const COL_GOLD: Color = Color(1.0, 0.82, 0.40, 1.0)
const COL_CYAN: Color = BrandStyle.NOMINAL_CYAN
const COL_EMERALD: Color = BrandStyle.PASS_EMERALD
const COL_AMBER: Color = BrandStyle.CAUTION_AMBER
const COL_CRIMSON: Color = BrandStyle.CRITICAL_RED

var _tier: MedalTier = MedalTier.FLIGHT_CERTIFIED


func _ready() -> void:
	custom_minimum_size = Vector2(54.0, 54.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_tier(tier: MedalTier) -> void:
	_tier = tier
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.44

	match _tier:
		MedalTier.PARETO_OPTIMAL:
			var oct: PackedVector2Array = _polygon_points(c, r, 8, PI * 0.125)
			draw_colored_polygon(oct, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.16))
			draw_polyline(oct + PackedVector2Array([oct[0]]), COL_GOLD, 2.2, true)
			draw_arc(c, r * 0.68, 0.0, TAU, 32, COL_CYAN, 1.6, true)
			var star: PackedVector2Array = PackedVector2Array()
			for i: int in range(8):
				var ang: float = (float(i) / 8.0) * TAU - PI * 0.5
				var rad: float = (r * 0.52) if (i % 2 == 0) else (r * 0.20)
				star.append(c + Vector2(cos(ang), sin(ang)) * rad)
			draw_colored_polygon(star, COL_GOLD)

		MedalTier.FLIGHT_CERTIFIED:
			var hex: PackedVector2Array = _polygon_points(c, r, 6, -PI * 0.5)
			draw_colored_polygon(hex, Color(COL_EMERALD.r, COL_EMERALD.g, COL_EMERALD.b, 0.16))
			draw_polyline(hex + PackedVector2Array([hex[0]]), COL_EMERALD, 2.2, true)
			var chk: PackedVector2Array = PackedVector2Array([
				c + Vector2(-r * 0.34, 0.0),
				c + Vector2(-r * 0.08, r * 0.28),
				c + Vector2(r * 0.38, -r * 0.26)
			])
			draw_polyline(chk, COL_EMERALD, 3.0, true)

		MedalTier.SUBOPTIMAL:
			var dia: PackedVector2Array = _polygon_points(c, r, 4, -PI * 0.5)
			draw_colored_polygon(dia, Color(COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 0.16))
			draw_polyline(dia + PackedVector2Array([dia[0]]), COL_AMBER, 2.2, true)
			draw_line(c + Vector2(0.0, -r * 0.36), c + Vector2(0.0, r * 0.10), COL_AMBER, 3.0, true)
			draw_circle(c + Vector2(0.0, r * 0.30), 2.2, COL_AMBER)

		MedalTier.MISSION_LOSS:
			var oct_loss: PackedVector2Array = _polygon_points(c, r, 8, PI * 0.125)
			draw_colored_polygon(oct_loss, Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, 0.18))
			draw_polyline(oct_loss + PackedVector2Array([oct_loss[0]]), COL_CRIMSON, 2.2, true)
			var off: float = r * 0.32
			draw_line(c + Vector2(-off, -off), c + Vector2(off, off), COL_CRIMSON, 2.8, true)
			draw_line(c + Vector2(-off, off), c + Vector2(off, -off), COL_CRIMSON, 2.8, true)


func _polygon_points(center: Vector2, radius: float, sides: int, angle_offset: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(sides):
		var ang: float = angle_offset + (float(i) / float(sides)) * TAU
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return pts
