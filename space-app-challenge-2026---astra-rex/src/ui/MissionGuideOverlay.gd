class_name MissionGuideOverlay
extends Control

## 1-Screen Interactive Mission Flow Guide & Aerospace Glossary ("?" Button Overlay).
## Fits cleanly inside the 1280x600 PhaseContainer using crisp custom _draw() vector icons.

signal guide_closed()

const COL_BG_SCRIM: Color = Color(0.020, 0.031, 0.059, 0.84)
const COL_CARD_BG: Color = Color(0.055, 0.086, 0.141, 0.96)
const COL_STEP_BG: Color = Color(0.070, 0.110, 0.180, 0.92)
const COL_GLOSSARY_BG: Color = Color(0.035, 0.055, 0.098, 0.94)
const COL_CYAN: Color = BrandStyle.NOMINAL_CYAN
const COL_EMERALD: Color = BrandStyle.PASS_EMERALD
const COL_AMBER: Color = BrandStyle.CAUTION_AMBER
const COL_GOLD: Color = Color(1.0, 0.82, 0.40, 1.0)
const COL_WHITE: Color = BrandStyle.TEXT_WHITE
const COL_HEADER: Color = BrandStyle.TEXT_HEADER
const COL_MUTED: Color = BrandStyle.TEXT_MUTED

var _btn_got_it: Button = null


class StepIconCanvas extends Control:
	var step_index: int = 0
	var accent_color: Color = Color(0.184, 0.827, 1.0, 1.0)

	func _init(idx: int, col: Color) -> void:
		step_index = idx
		accent_color = col
		custom_minimum_size = Vector2(52.0, 52.0)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		draw_circle(c, 23.0, Color(accent_color.r, accent_color.g, accent_color.b, 0.12))
		draw_arc(c, 23.0, 0.0, TAU, 32, Color(accent_color.r, accent_color.g, accent_color.b, 0.45), 1.5, true)

		match step_index:
			0:
				# Plan Mission: Moon + tilted orbital ellipse + trajectory marker
				draw_circle(c, 8.5, Color(0.75, 0.82, 0.92, 0.90))
				var pts: PackedVector2Array = PackedVector2Array()
				for i: int in range(37):
					var ang: float = (float(i) / 36.0) * TAU
					var ox: float = cos(ang) * 18.0
					var oy: float = sin(ang) * 7.5
					var rx: float = ox * cos(-0.42) - oy * sin(-0.42)
					var ry: float = ox * sin(-0.42) + oy * cos(-0.42)
					pts.append(c + Vector2(rx, ry))
				draw_polyline(pts, accent_color, 2.0, true)
				draw_circle(pts[6], 3.2, Color(0.918, 0.996, 0.027, 1.0))
			1:
				# 3D VAB: Hexagonal lander bus + 4 modular node sockets
				var hex: PackedVector2Array = PackedVector2Array()
				for i: int in range(7):
					var a: float = (float(i) / 6.0) * TAU - PI * 0.5
					hex.append(c + Vector2(cos(a), sin(a)) * 11.0)
				draw_polyline(hex, accent_color, 2.0, true)
				var offsets: Array[Vector2] = [
					Vector2(-15.0, -7.0), Vector2(15.0, -7.0),
					Vector2(-15.0, 7.0), Vector2(15.0, 7.0)
				]
				for off: Vector2 in offsets:
					draw_line(c + off * 0.55, c + off, accent_color, 1.6, true)
					draw_circle(c + off, 2.8, accent_color)
			2:
				# Land at Shackleton: Sloped crater terrain + lander silhouette + thruster plume
				var ground: PackedVector2Array = PackedVector2Array([
					c + Vector2(-18.0, 12.0),
					c + Vector2(-7.0, 8.0),
					c + Vector2(5.0, 11.0),
					c + Vector2(18.0, 5.0)
				])
				draw_polyline(ground, Color(0.75, 0.82, 0.92, 0.85), 2.0, true)
				draw_rect(Rect2(c + Vector2(-6.0, -13.0), Vector2(12.0, 9.0)), accent_color, false, 2.0)
				draw_line(c + Vector2(-4.0, -4.0), c + Vector2(-8.0, 3.0), accent_color, 1.6, true)
				draw_line(c + Vector2(4.0, -4.0), c + Vector2(8.0, 3.0), accent_color, 1.6, true)
				draw_line(c + Vector2(0.0, -3.0), c + Vector2(0.0, 6.0), Color(0.184, 0.827, 1.0, 1.0), 2.2, true)
				draw_line(c + Vector2(-3.0, -2.0), c + Vector2(-2.0, 5.0), Color(0.184, 0.827, 1.0, 0.7), 1.4, true)
				draw_line(c + Vector2(3.0, -2.0), c + Vector2(2.0, 5.0), Color(0.184, 0.827, 1.0, 0.7), 1.4, true)
			_:
				# Pareto Frontier: Axes + smooth curve + optimal star point
				draw_line(c + Vector2(-14.0, 13.0), c + Vector2(-14.0, -13.0), Color(0.58, 0.64, 0.72, 0.9), 1.8, true)
				draw_line(c + Vector2(-14.0, 13.0), c + Vector2(15.0, 13.0), Color(0.58, 0.64, 0.72, 0.9), 1.8, true)
				var curve: PackedVector2Array = PackedVector2Array([
					c + Vector2(-11.0, 8.0),
					c + Vector2(-6.0, -1.0),
					c + Vector2(2.0, -8.0),
					c + Vector2(13.0, -11.0)
				])
				draw_polyline(curve, Color(0.184, 0.827, 1.0, 1.0), 2.2, true)
				var star: Vector2 = c + Vector2(2.0, -8.0)
				draw_circle(star, 4.0, accent_color)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	visible = false
	_build_ui()


func _build_ui() -> void:
	var scrim: ColorRect = ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = COL_BG_SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(1040.0, 0.0)
	var card_sb: StyleBoxFlat = StyleBoxFlat.new()
	card_sb.bg_color = COL_CARD_BG
	card_sb.border_color = BrandStyle.PANEL_BORDER
	card_sb.set_border_width_all(1)
	card_sb.border_width_top = 2
	card_sb.set_corner_radius_all(8)
	card_sb.content_margin_left = 24.0
	card_sb.content_margin_right = 24.0
	card_sb.content_margin_top = 18.0
	card_sb.content_margin_bottom = 18.0
	card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(card)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	card.add_child(root_vbox)

	var hdr_row: HBoxContainer = HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 12)
	root_vbox.add_child(hdr_row)

	var title_lbl: Label = Label.new()
	title_lbl.text = "MISSION FLOW GUIDE"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", COL_WHITE)
	hdr_row.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	sub_lbl.text = "Four-phase aerospace engineering loop  •  Powered by NASA SP-2016-6105 & LRO LOLA"
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", COL_MUTED)
	hdr_row.add_child(sub_lbl)

	var steps_row: HBoxContainer = HBoxContainer.new()
	steps_row.add_theme_constant_override("separation", 12)
	root_vbox.add_child(steps_row)

	var step_defs: Array[Dictionary] = [
		{
			"title": "1. Plan Mission",
			"body": "Pick science goal, rocket, orbit (LLO vs NRHO), and Shackleton landing zone.",
			"col": COL_CYAN
		},
		{
			"title": "2. Assemble in 3D VAB",
			"body": "Equip 7 subsystem slots and clear the SIR safety gates.",
			"col": COL_EMERALD
		},
		{
			"title": "3. Land at Shackleton",
			"body": "Survive powered descent (T/W >= 1.0, slopes <= 15 deg), polar shadows, and solar storms.",
			"col": COL_AMBER
		},
		{
			"title": "4. Beat the Pareto Frontier",
			"body": "Maximize Science Return while minimizing cost ($M) and wet mass (kg).",
			"col": COL_GOLD
		}
	]

	for i: int in range(step_defs.size()):
		var sd: Dictionary = step_defs[i]
		var col: Color = sd["col"] as Color
		var step_panel: PanelContainer = PanelContainer.new()
		step_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var s_sb: StyleBoxFlat = StyleBoxFlat.new()
		s_sb.bg_color = COL_STEP_BG
		s_sb.border_color = Color(col.r, col.g, col.b, 0.65)
		s_sb.set_border_width_all(1)
		s_sb.border_width_top = 2
		s_sb.set_corner_radius_all(6)
		s_sb.content_margin_left = 14.0
		s_sb.content_margin_right = 14.0
		s_sb.content_margin_top = 14.0
		s_sb.content_margin_bottom = 14.0
		step_panel.add_theme_stylebox_override("panel", s_sb)
		steps_row.add_child(step_panel)

		var sv: VBoxContainer = VBoxContainer.new()
		sv.add_theme_constant_override("separation", 10)
		step_panel.add_child(sv)

		var icon: StepIconCanvas = StepIconCanvas.new(i, col)
		sv.add_child(icon)

		var st_title: Label = Label.new()
		st_title.text = str(sd["title"])
		st_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_title.add_theme_font_size_override("font_size", 14)
		st_title.add_theme_color_override("font_color", col)
		sv.add_child(st_title)

		var st_body: Label = Label.new()
		st_body.text = str(sd["body"])
		st_body.custom_minimum_size = Vector2(200.0, 56.0)
		st_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_body.add_theme_font_size_override("font_size", 12)
		st_body.add_theme_color_override("font_color", COL_HEADER)
		sv.add_child(st_body)

	var glossary_panel: PanelContainer = PanelContainer.new()
	var g_sb: StyleBoxFlat = StyleBoxFlat.new()
	g_sb.bg_color = COL_GLOSSARY_BG
	g_sb.border_color = BrandStyle.PANEL_BORDER
	g_sb.set_border_width_all(1)
	g_sb.set_corner_radius_all(6)
	g_sb.content_margin_left = 14.0
	g_sb.content_margin_right = 14.0
	g_sb.content_margin_top = 10.0
	g_sb.content_margin_bottom = 10.0
	glossary_panel.add_theme_stylebox_override("panel", g_sb)
	root_vbox.add_child(glossary_panel)

	var g_vbox: VBoxContainer = VBoxContainer.new()
	g_vbox.add_theme_constant_override("separation", 4)
	glossary_panel.add_child(g_vbox)

	var glossary_lines: Array[String] = [
		"SIR   — System Integration Review: Pre-launch gate checking TLI mass, dV, thrust, power, and radiation.",
		"T/W   — Lunar Thrust-to-Weight: Engine thrust vs lunar weight (1.625 m/s^2); must be >= 1.0 to soft-land.",
		"NRHO  — Near-Rectilinear Halo Orbit: Gateway polar orbit with ~100% Earth comms at higher descent dV (2500 m/s)."
	]
	for line: String in glossary_lines:
		var gl: Label = Label.new()
		gl.text = line
		gl.add_theme_font_size_override("font_size", 12)
		gl.add_theme_color_override("font_color", COL_HEADER)
		BrandStyle.bind_mono_font(gl)
		g_vbox.add_child(gl)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	root_vbox.add_child(footer)

	_btn_got_it = Button.new()
	_btn_got_it.text = "Got It"
	_btn_got_it.custom_minimum_size = Vector2(128.0, 34.0)
	_btn_got_it.focus_mode = Control.FOCUS_NONE
	_btn_got_it.add_theme_font_size_override("font_size", 13)
	var b_norm: StyleBoxFlat = StyleBoxFlat.new()
	b_norm.bg_color = Color(0.043, 0.239, 0.569, 0.96)
	b_norm.border_color = COL_CYAN
	b_norm.set_border_width_all(1)
	b_norm.set_corner_radius_all(5)
	var b_hov: StyleBoxFlat = b_norm.duplicate() as StyleBoxFlat
	b_hov.bg_color = Color(0.0, 0.259, 0.651, 1.0)
	b_hov.border_color = BrandStyle.NEON_YELLOW
	_btn_got_it.add_theme_stylebox_override("normal", b_norm)
	_btn_got_it.add_theme_stylebox_override("hover", b_hov)
	_btn_got_it.add_theme_color_override("font_color", COL_WHITE)
	_btn_got_it.add_theme_color_override("font_hover_color", BrandStyle.NEON_YELLOW)
	_btn_got_it.pressed.connect(close_guide)
	footer.add_child(_btn_got_it)


func open_guide() -> void:
	visible = true


func close_guide() -> void:
	if not visible:
		return
	visible = false
	guide_closed.emit()
