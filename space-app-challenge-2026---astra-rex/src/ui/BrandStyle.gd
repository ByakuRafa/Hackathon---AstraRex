class_name BrandStyle
extends RefCounted

## Harmonized Space Apps Brand Guide + Mission Control 60-30-10 Design Tokens & Helpers.

# 60% Structural & Background Layer
const SPACE_950: Color = Color(0.020, 0.031, 0.059, 1.0)         # #05080F
const DEEP_BLUE: Color = Color(0.027, 0.090, 0.247, 1.0)         # #07173F
const PANEL_900: Color = Color(0.055, 0.086, 0.141, 0.88)        # #0E1624 @ 88%
const PANEL_SOLID: Color = Color(0.055, 0.086, 0.141, 0.96)      # #0E1624 @ 96%
const PANEL_BORDER: Color = Color(0.165, 0.231, 0.333, 1.0)      # #2A3B55
const BTN_BORDER: Color = Color(0.310, 0.416, 0.573, 1.0)        # #4F6A92

# 30% Identity & Interactive Layer
const NOMINAL_CYAN: Color = Color(0.184, 0.827, 1.0, 1.0)        # #2FD3FF
const BRAND_BLUE: Color = Color(0.0, 0.259, 0.651, 1.0)          # #0042A6
const BRAND_BLUE_DEEP: Color = Color(0.043, 0.239, 0.569, 1.0)   # #0B3D91
const NEON_YELLOW: Color = Color(0.918, 0.996, 0.027, 1.0)       # #EAFE07

# 10% Semantic Telemetry & Exclusive Guide Layer
const PASS_EMERALD: Color = Color(0.208, 0.878, 0.631, 1.0)      # #35E0A1
const CAUTION_AMBER: Color = Color(1.0, 0.698, 0.141, 1.0)       # #FFB224
const CRITICAL_RED: Color = Color(1.0, 0.271, 0.376, 1.0)        # #FF4560
const GUIDE_VIOLET: Color = Color(0.545, 0.424, 1.0, 1.0)        # #8B6CFF

const TEXT_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)
const TEXT_HEADER: Color = Color(0.902, 0.945, 1.0, 1.0)
const TEXT_MUTED: Color = Color(0.580, 0.639, 0.722, 1.0)

const FONT_UI_PATH: String = "res://src/ui/FontUI_Barlow.tres"
const FONT_MONO_PATH: String = "res://src/ui/FontMono_Tabular.tres"

static var _cached_ui_font: Font = null
static var _cached_mono_font: Font = null
static var _cached_bg_shader: Shader = null


static func get_ui_font() -> Font:
	if _cached_ui_font == null and ResourceLoader.exists(FONT_UI_PATH):
		_cached_ui_font = ResourceLoader.load(FONT_UI_PATH) as Font
	return _cached_ui_font


static func get_mono_font() -> Font:
	if _cached_mono_font == null and ResourceLoader.exists(FONT_MONO_PATH):
		var fv: FontVariation = ResourceLoader.load(FONT_MONO_PATH) as FontVariation
		if fv != null:
			var feats: Dictionary = fv.opentype_features.duplicate()
			feats[1953396077] = 1
			fv.opentype_features = feats
			_cached_mono_font = fv
	return _cached_mono_font


static func bind_mono_font(ctrl: Control) -> void:
	if not is_instance_valid(ctrl):
		return
	var mono: Font = get_mono_font()
	if mono != null:
		ctrl.add_theme_font_override("font", mono)


static func apply_panel_style(panel: PanelContainer, pad_x: float = 14.0, pad_top: float = 10.0, pad_bottom: float = 10.0) -> void:
	if not is_instance_valid(panel):
		return
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PANEL_900
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_top
	sb.content_margin_bottom = pad_bottom
	panel.add_theme_stylebox_override("panel", sb)


static func apply_brand_gradient_backdrop(bg_rect: ColorRect) -> void:
	if not is_instance_valid(bg_rect):
		return
	if _cached_bg_shader == null:
		_cached_bg_shader = Shader.new()
		_cached_bg_shader.code = """shader_type canvas_item;

void fragment() {
	vec2 uv = UV;
	float diag = clamp((uv.x + uv.y) * 0.5, 0.0, 1.0);
	vec3 col_electric = vec3(0.0, 0.165, 0.420); // Attenuated Electric Blue #0042A6
	vec3 col_deep = vec3(0.027, 0.090, 0.247);     // Deep Blue #07173F
	vec3 col_space = vec3(0.020, 0.031, 0.059);    // Space-950 #05080F

	vec3 grad = mix(col_electric, col_deep, smoothstep(0.0, 0.52, diag));
	grad = mix(grad, col_space, smoothstep(0.45, 1.0, diag));

	// Subtle 25%-opacity coordinate & orbital vector grid
	vec2 px = uv * vec2(1280.0, 600.0);
	vec2 cell = abs(fract(px / 48.0 - 0.5) - 0.5) * 48.0;
	float grid_line = 1.0 - smoothstep(0.0, 1.15, min(cell.x, cell.y));

	float r1 = abs(length(uv - vec2(0.14, 0.16)) - 0.55);
	float r2 = abs(length(uv - vec2(0.88, 0.88)) - 0.62);
	float arc = (1.0 - smoothstep(0.001, 0.0035, r1)) + (1.0 - smoothstep(0.001, 0.0035, r2));

	vec3 grid_col = vec3(0.184, 0.827, 1.0); // #2FD3FF subtle vector trace
	vec3 final_col = mix(grad, grid_col, clamp(grid_line * 0.065 + arc * 0.085, 0.0, 0.25));
	COLOR = vec4(final_col, 1.0);
}
"""
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _cached_bg_shader
	bg_rect.material = mat
