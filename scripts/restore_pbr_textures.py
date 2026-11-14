"""Restore and bake rich aerospace PBR materials & procedural textures across all 16 .glb models
and generate tileable Shackleton lunar regolith textures (albedo + normal .webp).

Run headless via Blender 4.4+:
    blender --background --python scripts/restore_pbr_textures.py

Key fixes over previous repair scripts:
1. Locale-agnostic shader node lookup: resolves Principled BSDF by node.type == 'BSDF_PRINCIPLED'
   and Material Output by node.type == 'OUTPUT_MATERIAL' (works on pt_BR / en_US / any locale).
2. Deterministic box-projected UVs (apply_box_uvs) ensuring every mesh has uvs >= 1.
3. Embedded 256x256 procedural aerospace PBR maps (PNG packed into .glb):
   - Gold Kapton MLI Foil (#D4AF37, metallic 0.85, roughness 0.28 + crinkle normal map)
   - Photovoltaic Solar Cell Grid (#0B1D3A navy cells + #CBD5E1 silver busbars, met 0.60, rough 0.22)
   - SLS SOFI Orange Thermal Foam (#D96B27, roughness 0.75) & White/Black SRB Roll Bands (#F8FAFC/#111827)
   - Brushed Aerospace Titanium/Aluminum & Matte Black Radiator (#1E293B)
   - Glowing Cyan Emissive (#00F0FF) for Ion Thruster xenon grid & LiDAR/TRN lenses
4. Saves 512x512 regolith_albedo.webp and regolith_normal.webp to assets/terrain/.
"""

from __future__ import annotations

import math
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = REPO_ROOT / "space-app-challenge-2026---astra-rex"
MODELS_DIR = PROJECT_ROOT / "assets" / "models"
TERRAIN_DIR = PROJECT_ROOT / "assets" / "terrain"

GROUP_A_FILES = ("lander_bus.glb", "engine_biprop.glb", "antenna_hga.glb")
GROUP_B1_FILES = ("sls_block1.glb", "vab_gantry.glb", "dsn_70m_dish.glb")
GROUP_B2_FILES = (
    "solar_array.glb",
    "rtg_cassini.glb",
    "engine_ion.glb",
    "battery_pack.glb",
    "antenna_omni.glb",
    "sensor_lidar.glb",
    "payload_drill.glb",
    "payload_msolo.glb",
    "payload_sar.glb",
    "shield_heavy.glb",
)
ALL_16_MODELS = GROUP_A_FILES + GROUP_B1_FILES + GROUP_B2_FILES

# Global runtime texture cache (reloaded cleanly per scene reset)
TEX_PATHS: dict[str, Path] = {}
TEX_CACHE: dict[str, bpy.types.Image] = {}


def srgb_to_linear_scalar(c: float) -> float:
    c = max(0.0, min(1.0, float(c)))
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def srgb_to_linear_rgb(arr_srgb: np.ndarray) -> np.ndarray:
    """Convert float32 sRGB [0..1] array (..., 3) to linear RGB for Blender image buffer."""
    out = np.empty_like(arr_srgb, dtype=np.float32)
    mask = arr_srgb <= 0.04045
    out[mask] = arr_srgb[mask] / 12.92
    out[~mask] = ((arr_srgb[~mask] + 0.055) / 1.055) ** 2.4
    return np.clip(out, 0.0, 1.0)


def hex_to_srgb_tuple(hex_str: str) -> tuple[float, float, float]:
    h = hex_str.lstrip("#")
    return (
        int(h[0:2], 16) / 255.0,
        int(h[2:4], 16) / 255.0,
        int(h[4:6], 16) / 255.0,
    )


def hex_to_linear_rgba(hex_str: str) -> tuple[float, float, float, float]:
    r, g, b = hex_to_srgb_tuple(hex_str)
    return (
        srgb_to_linear_scalar(r),
        srgb_to_linear_scalar(g),
        srgb_to_linear_scalar(b),
        1.0,
    )


def _tileable_fbm(res: int, seed: int, octaves: int = 4) -> np.ndarray:
    """Generate fast periodic 2D FBM noise in [0, 1] using numpy Fourier-free value interpolation."""
    rng = np.random.default_rng(seed)
    acc = np.zeros((res, res), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for oct_idx in range(octaves):
        grid_n = max(4, min(res, 8 * (2 ** oct_idx)))
        coarse = rng.random((grid_n, grid_n), dtype=np.float32)
        coords = np.linspace(0.0, grid_n, res, endpoint=False, dtype=np.float32)
        y_idx = np.floor(coords).astype(np.int32) % grid_n
        x_idx = np.floor(coords).astype(np.int32) % grid_n
        yf = (coords - np.floor(coords))
        xf = (coords - np.floor(coords))
        # Smoothstep interpolation
        ys = yf * yf * (3.0 - 2.0 * yf)
        xs = xf * xf * (3.0 - 2.0 * xf)
        y1 = (y_idx + 1) % grid_n
        x1 = (x_idx + 1) % grid_n

        c00 = coarse[np.ix_(y_idx, x_idx)]
        c10 = coarse[np.ix_(y_idx, x1)]
        c01 = coarse[np.ix_(y1, x_idx)]
        c11 = coarse[np.ix_(y1, x1)]

        ix0 = c00 * (1.0 - xs[None, :]) + c10 * xs[None, :]
        ix1 = c01 * (1.0 - xs[None, :]) + c11 * xs[None, :]
        val = ix0 * (1.0 - ys[:, None]) + ix1 * ys[:, None]

        acc += val * amp
        norm += amp
        amp *= 0.5
    return np.clip(acc / max(norm, 1e-6), 0.0, 1.0)


def _height_to_normal_rgba(height: np.ndarray, strength: float = 2.5) -> np.ndarray:
    """Convert periodic 2D heightmap [0..1] into tangent-space RGBA normal buffer [0..1]."""
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height, dtype=np.float32)
    length = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-8
    h, w = height.shape
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[:, :, 0] = np.clip((nx / length) * 0.5 + 0.5, 0.0, 1.0)
    rgba[:, :, 1] = np.clip((ny / length) * 0.5 + 0.5, 0.0, 1.0)
    rgba[:, :, 2] = np.clip((nz / length) * 0.5 + 0.5, 0.0, 1.0)
    return rgba


def _save_image_file(
    rgba_float: np.ndarray,
    filepath: Path,
    file_format: str,
    is_data: bool = False,
) -> None:
    """Write a float32 (H, W, 4) RGBA buffer via Blender Image API cleanly."""
    h, w, _ = rgba_float.shape
    tmp_name = f"_gen_{filepath.stem}"
    if tmp_name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[tmp_name])
    img = bpy.data.images.new(tmp_name, width=w, height=h, alpha=True, is_data=is_data)
    img.colorspace_settings.name = "Non-Color" if is_data else "sRGB"

    buf = rgba_float.copy()
    if not is_data:
        buf[:, :, :3] = srgb_to_linear_rgb(buf[:, :, :3])
    img.pixels.foreach_set(buf.ravel())
    img.filepath_raw = str(filepath)
    img.file_format = file_format
    img.save()
    bpy.data.images.remove(img)


def generate_all_procedural_textures(tmp_dir: Path) -> None:
    """Synthesize all compact 256x256 aerospace maps + 512x512 lunar regolith maps."""
    global TEX_PATHS
    TEX_PATHS = {}

    res = 256
    yy, xx = np.mgrid[0:res, 0:res]
    u = xx.astype(np.float32) / float(res)
    v = yy.astype(np.float32) / float(res)

    # 1. Gold Kapton MLI Foil Albedo + Crinkle Normal Map (256x256)
    crinkle_coarse = _tileable_fbm(res, seed=101, octaves=4)
    # Sharp metallic foil ridges via abs(sin(wave + fbm))
    ridge1 = np.abs(np.sin((u * 3.0 + v * 2.0 + crinkle_coarse * 1.4) * math.pi * 2.0))
    ridge2 = np.abs(np.cos((u * 2.0 - v * 4.0 + crinkle_coarse * 1.2) * math.pi * 2.0))
    crinkle_h = np.clip(0.55 * crinkle_coarse + 0.25 * (1.0 - ridge1) + 0.20 * (1.0 - ridge2), 0.0, 1.0)

    # Subtle quilted MLI seam stitching lines (every 64 px)
    seam_u = np.minimum(u * 4.0 % 1.0, 1.0 - (u * 4.0 % 1.0))
    seam_v = np.minimum(v * 4.0 % 1.0, 1.0 - (v * 4.0 % 1.0))
    seam_mask = ((seam_u < 0.03) | (seam_v < 0.03)).astype(np.float32)
    crinkle_h = crinkle_h * (1.0 - 0.35 * seam_mask)

    base_gold = np.array(hex_to_srgb_tuple("#D4AF37"), dtype=np.float32)
    warm_amber = np.array(hex_to_srgb_tuple("#A67C00"), dtype=np.float32)
    bright_gold = np.array(hex_to_srgb_tuple("#F5DC7A"), dtype=np.float32)
    kapton_rgb = (
        base_gold[None, None, :] * 0.65
        + warm_amber[None, None, :] * (0.35 * (1.0 - crinkle_h[:, :, None]))
        + bright_gold[None, None, :] * (0.28 * np.power(crinkle_h[:, :, None], 2.0))
    )
    kapton_rgb = kapton_rgb * (1.0 - 0.28 * seam_mask[:, :, None])
    kapton_albedo = np.ones((res, res, 4), dtype=np.float32)
    kapton_albedo[:, :, :3] = np.clip(kapton_rgb, 0.0, 1.0)
    TEX_PATHS["kapton_albedo"] = tmp_dir / "kapton_albedo.png"
    _save_image_file(kapton_albedo, TEX_PATHS["kapton_albedo"], "PNG", is_data=False)

    kapton_norm = _height_to_normal_rgba(crinkle_h, strength=3.4)
    TEX_PATHS["kapton_normal"] = tmp_dir / "kapton_normal.png"
    _save_image_file(kapton_norm, TEX_PATHS["kapton_normal"], "PNG", is_data=True)

    # 2. Photovoltaic Solar Cell Grid Texture (#0B1D3A + #CBD5E1 silver busbars, 256x256)
    cell_x = (u * 6.0) % 1.0
    cell_y = (v * 12.0) % 1.0
    border = (cell_x < 0.06) | (cell_x > 0.94) | (cell_y < 0.07) | (cell_y > 0.93)
    silver_busbar = ((np.abs(cell_x - 0.5) < 0.025) | (np.abs(cell_y - 0.5) < 0.025)) & (~border)
    fine_finger = ((np.abs((cell_y * 4.0) % 1.0 - 0.5) < 0.04) & (~border))

    navy_c = np.array(hex_to_srgb_tuple("#0B1D3A"), dtype=np.float32)
    deep_blue = np.array(hex_to_srgb_tuple("#102A54"), dtype=np.float32)
    silver_c = np.array(hex_to_srgb_tuple("#CBD5E1"), dtype=np.float32)
    gap_c = np.array(hex_to_srgb_tuple("#050A14"), dtype=np.float32)

    cell_var = _tileable_fbm(res, seed=202, octaves=2)
    solar_rgb = navy_c[None, None, :] * (0.85 + 0.30 * cell_var[:, :, None]) + deep_blue[None, None, :] * 0.20
    solar_rgb[fine_finger] = solar_rgb[fine_finger] * 0.72 + silver_c * 0.28
    solar_rgb[silver_busbar] = silver_c
    solar_rgb[border] = gap_c

    solar_rgba = np.ones((res, res, 4), dtype=np.float32)
    solar_rgba[:, :, :3] = np.clip(solar_rgb, 0.0, 1.0)
    TEX_PATHS["solar_grid"] = tmp_dir / "solar_grid.png"
    _save_image_file(solar_rgba, TEX_PATHS["solar_grid"], "PNG", is_data=False)

    # 3. SLS SOFI Orange Thermal Foam (#D96B27 + subtle intertank ribbing)
    foam_noise = _tileable_fbm(res, seed=303, octaves=4)
    sofi_c = np.array(hex_to_srgb_tuple("#D96B27"), dtype=np.float32)
    sofi_dark = np.array(hex_to_srgb_tuple("#A84B14"), dtype=np.float32)
    rib = 0.5 + 0.5 * np.cos(v * 24.0 * math.pi * 2.0)
    sofi_rgb = sofi_dark[None, None, :] * 0.25 + sofi_c[None, None, :] * (0.65 + 0.24 * foam_noise[:, :, None] + 0.08 * rib[:, :, None])
    sofi_rgba = np.ones((res, res, 4), dtype=np.float32)
    sofi_rgba[:, :, :3] = np.clip(sofi_rgb, 0.0, 1.0)
    TEX_PATHS["sls_sofi"] = tmp_dir / "sls_sofi.png"
    _save_image_file(sofi_rgba, TEX_PATHS["sls_sofi"], "PNG", is_data=False)

    # 4. SRB White with Black NASA Roll-Pattern Bands (#F8FAFC / #111827)
    srb_noise = _tileable_fbm(res, seed=404, octaves=2)
    srb_white = np.array(hex_to_srgb_tuple("#F8FAFC"), dtype=np.float32)
    srb_black = np.array(hex_to_srgb_tuple("#111827"), dtype=np.float32)
    roll_band = ((v > 0.16) & (v < 0.26)) & (((u * 6.0) % 1.0) < 0.5)
    roll_band |= ((v > 0.72) & (v < 0.80)) & (((u * 6.0) % 1.0) >= 0.5)
    ring_seam = (np.abs((v * 8.0) % 1.0 - 0.5) < 0.015)
    srb_rgb = np.broadcast_to(srb_white, (res, res, 3)).copy() * (0.94 + 0.06 * srb_noise[:, :, None])
    srb_rgb[roll_band] = srb_black
    srb_rgb[ring_seam] = srb_black * 1.4
    srb_rgba = np.ones((res, res, 4), dtype=np.float32)
    srb_rgba[:, :, :3] = np.clip(srb_rgb, 0.0, 1.0)
    TEX_PATHS["srb_roll"] = tmp_dir / "srb_roll.png"
    _save_image_file(srb_rgba, TEX_PATHS["srb_roll"], "PNG", is_data=False)

    # 5. Brushed Titanium / Aerospace Aluminum (#CBD5E1)
    brush_base = _tileable_fbm(res, seed=505, octaves=3)
    # Horizontal brushed streaks by smoothing along u and sharp variation along v
    streak = np.mean(brush_base, axis=1, keepdims=True) * 0.70 + brush_base * 0.30
    panel_seam = (np.minimum(u * 2.0 % 1.0, 1.0 - (u * 2.0 % 1.0)) < 0.012) | (
        np.minimum(v * 2.0 % 1.0, 1.0 - (v * 2.0 % 1.0)) < 0.012
    )
    alu_c = np.array(hex_to_srgb_tuple("#CBD5E1"), dtype=np.float32)
    alu_rgb = alu_c[None, None, :] * (0.86 + 0.18 * streak[:, :, None])
    alu_rgb[panel_seam] *= 0.72
    alu_rgba = np.ones((res, res, 4), dtype=np.float32)
    alu_rgba[:, :, :3] = np.clip(alu_rgb, 0.0, 1.0)
    TEX_PATHS["brushed_metal"] = tmp_dir / "brushed_metal.png"
    _save_image_file(alu_rgba, TEX_PATHS["brushed_metal"], "PNG", is_data=False)

    # 6. Matte Dark Gunmetal / Radiator Fins (#1E293B)
    rad_noise = _tileable_fbm(res, seed=606, octaves=3)
    rad_c = np.array(hex_to_srgb_tuple("#1E293B"), dtype=np.float32)
    rib_mask = ((u * 12.0) % 1.0) < 0.14
    rad_rgb = rad_c[None, None, :] * (0.88 + 0.24 * rad_noise[:, :, None])
    rad_rgb[rib_mask] *= 1.35
    rad_rgba = np.ones((res, res, 4), dtype=np.float32)
    rad_rgba[:, :, :3] = np.clip(rad_rgb, 0.0, 1.0)
    TEX_PATHS["radiator_dark"] = tmp_dir / "radiator_dark.png"
    _save_image_file(rad_rgba, TEX_PATHS["radiator_dark"], "PNG", is_data=False)

    # 7. Lunar Regolith Albedo & Normal (.webp 512x512 saved directly to assets/terrain/)
    TERRAIN_DIR.mkdir(parents=True, exist_ok=True)
    t_res = 512
    tyy, txx = np.mgrid[0:t_res, 0:t_res]
    tu = txx.astype(np.float32) / float(t_res)
    tv = tyy.astype(np.float32) / float(t_res)

    reg_h = _tileable_fbm(t_res, seed=707, octaves=5)
    # Stamp 36 subtle micro-craters tileably (wrap distances mod 1.0)
    rng = np.random.default_rng(808)
    for _ in range(36):
        cx = float(rng.random())
        cy = float(rng.random())
        cr = float(0.018 + rng.random() * 0.045)
        dx = ((tu - cx + 0.5) % 1.0) - 0.5
        dy = ((tv - cy + 0.5) % 1.0) - 0.5
        dist = np.sqrt(dx * dx + dy * dy) / cr
        bowl = np.clip(1.0 - dist * dist, 0.0, 1.0)
        rim = np.exp(-((dist - 1.05) ** 2) / 0.04) * 0.22
        reg_h = np.clip(reg_h - 0.35 * bowl + rim, 0.0, 1.0)

    # Fine regolith dust albedo (centered around ~0.80 gray so vertex slope colors multiply brightly)
    reg_val = np.clip(0.68 + 0.30 * reg_h, 0.45, 0.98)
    reg_albedo = np.ones((t_res, t_res, 4), dtype=np.float32)
    reg_albedo[:, :, 0] = reg_val
    reg_albedo[:, :, 1] = reg_val * 0.99
    reg_albedo[:, :, 2] = reg_val * 0.97
    _save_image_file(reg_albedo, TERRAIN_DIR / "regolith_albedo.webp", "WEBP", is_data=False)

    reg_norm = _height_to_normal_rgba(reg_h, strength=4.2)
    _save_image_file(reg_norm, TERRAIN_DIR / "regolith_normal.webp", "WEBP", is_data=True)
    print(f"[TERRAIN] Generated regolith_albedo.webp & regolith_normal.webp in {TERRAIN_DIR}")


def reset_scene() -> None:
    TEX_CACHE.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_packed_image(tex_key: str, is_data: bool = False) -> bpy.types.Image:
    if tex_key in TEX_CACHE and TEX_CACHE[tex_key].name in bpy.data.images:
        return TEX_CACHE[tex_key]
    fpath = TEX_PATHS[tex_key]
    img = bpy.data.images.load(str(fpath), check_existing=True)
    img.colorspace_settings.name = "Non-Color" if is_data else "sRGB"
    img.pack()
    TEX_CACHE[tex_key] = img
    return img


def get_bsdf_and_output(mat: bpy.types.Material) -> tuple[bpy.types.Node, bpy.types.Node]:
    """Locale-agnostic Principled BSDF & Material Output lookup by node.type."""
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new(type="ShaderNodeBsdfPrincipled")
    out_node = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
    if out_node is None:
        out_node = nt.nodes.new(type="ShaderNodeOutputMaterial")
    # Ensure BSDF -> Material Output link exists
    if not out_node.inputs["Surface"].is_linked:
        nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return bsdf, out_node


def make_pbr_material(
    name: str,
    hex_color: str = "#CBD5E1",
    metallic: float = 0.35,
    roughness: float = 0.40,
    tex_key: str | None = None,
    normal_tex_key: str | None = None,
    normal_strength: float = 0.65,
    emission_hex: str | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf, out_node = get_bsdf_and_output(mat)
    nt = mat.node_tree

    # Clear extra stale links on Base Color / Normal
    for link in list(nt.links):
        if link.to_node == bsdf and link.to_socket.name in ("Base Color", "Normal", "Emission Color"):
            nt.links.remove(link)

    if tex_key is not None:
        img_node = nt.nodes.new(type="ShaderNodeTexImage")
        img_node.image = get_packed_image(tex_key, is_data=False)
        img_node.interpolation = "Linear"
        nt.links.new(img_node.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(hex_color)

    if normal_tex_key is not None:
        nrm_tex = nt.nodes.new(type="ShaderNodeTexImage")
        nrm_tex.image = get_packed_image(normal_tex_key, is_data=True)
        nrm_tex.interpolation = "Linear"
        nrm_map = nt.nodes.new(type="ShaderNodeNormalMap")
        nrm_map.inputs["Strength"].default_value = normal_strength
        nt.links.new(nrm_tex.outputs["Color"], nrm_map.inputs["Color"])
        nt.links.new(nrm_map.outputs["Normal"], bsdf.inputs["Normal"])

    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    if emission_hex and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = hex_to_linear_rgba(emission_hex)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    elif "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 0.0

    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return mat


def configure_existing_material(
    mat: bpy.types.Material,
    hex_color: str = "#CBD5E1",
    metallic: float = 0.35,
    roughness: float = 0.40,
    tex_key: str | None = None,
    normal_tex_key: str | None = None,
    normal_strength: float = 0.65,
    preserve_existing_texture: bool = False,
) -> None:
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf, out_node = get_bsdf_and_output(mat)
    nt = mat.node_tree

    has_linked_tex = bsdf.inputs["Base Color"].is_linked
    if not (preserve_existing_texture and has_linked_tex):
        for link in list(nt.links):
            if link.to_node == bsdf and link.to_socket.name in ("Base Color", "Normal"):
                nt.links.remove(link)
        if tex_key is not None:
            img_node = nt.nodes.new(type="ShaderNodeTexImage")
            img_node.image = get_packed_image(tex_key, is_data=False)
            nt.links.new(img_node.outputs["Color"], bsdf.inputs["Base Color"])
        else:
            bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(hex_color)

    if normal_tex_key is not None:
        for link in list(nt.links):
            if link.to_node == bsdf and link.to_socket.name == "Normal":
                nt.links.remove(link)
        nrm_tex = nt.nodes.new(type="ShaderNodeTexImage")
        nrm_tex.image = get_packed_image(normal_tex_key, is_data=True)
        nrm_map = nt.nodes.new(type="ShaderNodeNormalMap")
        nrm_map.inputs["Strength"].default_value = normal_strength
        nt.links.new(nrm_tex.outputs["Color"], nrm_map.inputs["Color"])
        nt.links.new(nrm_map.outputs["Normal"], bsdf.inputs["Normal"])

    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if not out_node.inputs["Surface"].is_linked:
        nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])


# Preset Aerospace PBR Materials
def mat_kapton(name: str = "Mat_Kapton_MLI") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#D4AF37",
        metallic=0.85,
        roughness=0.28,
        tex_key="kapton_albedo",
        normal_tex_key="kapton_normal",
        normal_strength=0.70,
    )


def mat_solar_pv(name: str = "Mat_Solar_PV_Grid") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#0B1D3A",
        metallic=0.60,
        roughness=0.22,
        tex_key="solar_grid",
    )


def mat_sls_sofi(name: str = "Mat_SLS_SOFI") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#D96B27",
        metallic=0.06,
        roughness=0.75,
        tex_key="sls_sofi",
    )


def mat_srb_roll(name: str = "Mat_SRB_Roll") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#F8FAFC",
        metallic=0.12,
        roughness=0.38,
        tex_key="srb_roll",
    )


def mat_brushed_ti(name: str = "Mat_Brushed_Titanium") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#CBD5E1",
        metallic=0.78,
        roughness=0.30,
        tex_key="brushed_metal",
    )


def mat_radiator_dark(name: str = "Mat_Radiator_Gunmetal") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#1E293B",
        metallic=0.62,
        roughness=0.38,
        tex_key="radiator_dark",
    )


def mat_aero_white(name: str = "Mat_Aero_White") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#F8FAFC",
        metallic=0.14,
        roughness=0.34,
    )


def mat_cyan_emissive(name: str = "Mat_Cyan_Emissive", strength: float = 3.6) -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#00F0FF",
        metallic=0.15,
        roughness=0.12,
        emission_hex="#00F0FF",
        emission_strength=strength,
    )


def mat_safety_yellow(name: str = "Mat_Safety_Yellow") -> bpy.types.Material:
    return make_pbr_material(
        name,
        hex_color="#F59E0B",
        metallic=0.35,
        roughness=0.38,
    )


def apply_box_uvs(mesh: bpy.types.Mesh, scale: float = 1.2) -> None:
    """Assign clean box-projected UVs in BMesh and ensure outward normals."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x, co.y
            elif ax >= ay and ax >= az:
                u, v = co.y, co.z
            else:
                u, v = co.x, co.z
            loop[uv_layer].uv = (u * scale + 0.5, v * scale + 0.5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()


def get_scene_mesh_bbox(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(c) for obj in meshes for c in obj.bound_box]
    if not corners:
        return Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.0))
    min_v = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    max_v = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return min_v, max_v


# ==============================================================================
# BMesh Construction Helpers
# ==============================================================================

def add_box(
    parts: list[bpy.types.Object],
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.location = Vector(location)
    obj.rotation_euler = Euler(rotation, "XYZ")
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def add_cylinder(
    parts: list[bpy.types.Object],
    name: str,
    radius1: float,
    radius2: float,
    depth: float,
    location: tuple[float, float, float],
    segments: int,
    mat: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        calc_uvs=True,
    )
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.location = Vector(location)
    obj.rotation_euler = Euler(rotation, "XYZ")
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def add_uv_sphere(
    parts: list[bpy.types.Object],
    name: str,
    radius: float,
    u_seg: int,
    v_seg: int,
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u_seg, v_segments=v_seg, radius=radius, calc_uvs=True)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.location = Vector(location)
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def add_beam_between(
    parts: list[bpy.types.Object],
    name: str,
    p1: Vector,
    p2: Vector,
    thickness: float,
    mat: bpy.types.Material,
    round_segments: int = 0,
) -> bpy.types.Object:
    delta = p2 - p1
    length = delta.length
    mid = (p1 + p2) * 0.5
    quat = delta.normalized().to_track_quat("Z", "Y")
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    if round_segments >= 6:
        bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=round_segments,
            radius1=thickness * 0.5,
            radius2=thickness * 0.5,
            depth=length,
            calc_uvs=True,
        )
    else:
        bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
        bmesh.ops.scale(bm, vec=Vector((thickness, thickness, length)), verts=bm.verts[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.location = mid
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = quat
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def add_curved_arc_plate(
    parts: list[bpy.types.Object],
    name: str,
    inner_r: float,
    outer_r: float,
    height: float,
    arc_deg: float,
    center_y_offset: float,
    z_center: float,
    segments: int,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    half_rad = math.radians(arc_deg * 0.5)
    z_bot = z_center - height * 0.5
    z_top = z_center + height * 0.5

    in_bot: list[bmesh.types.BMVert] = []
    in_top: list[bmesh.types.BMVert] = []
    out_bot: list[bmesh.types.BMVert] = []
    out_top: list[bmesh.types.BMVert] = []

    for i in range(segments + 1):
        t = float(i) / float(segments)
        ang = -half_rad + t * (2.0 * half_rad)
        sx = math.sin(ang)
        cy = -math.cos(ang)
        in_bot.append(bm.verts.new((inner_r * sx, center_y_offset + inner_r * cy, z_bot)))
        in_top.append(bm.verts.new((inner_r * sx, center_y_offset + inner_r * cy, z_top)))
        out_bot.append(bm.verts.new((outer_r * sx, center_y_offset + outer_r * cy, z_bot)))
        out_top.append(bm.verts.new((outer_r * sx, center_y_offset + outer_r * cy, z_top)))

    for i in range(segments):
        bm.faces.new((out_bot[i], out_bot[i + 1], out_top[i + 1], out_top[i]))
        bm.faces.new((in_bot[i + 1], in_bot[i], in_top[i], in_top[i + 1]))
        bm.faces.new((in_top[i], out_top[i], out_top[i + 1], in_top[i + 1]))
        bm.faces.new((out_bot[i], in_bot[i], in_bot[i + 1], out_bot[i + 1]))

    bm.faces.new((in_bot[0], out_bot[0], out_top[0], in_top[0]))
    bm.faces.new((out_bot[-1], in_bot[-1], in_top[-1], out_top[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def build_parabolic_dish_mesh(
    name: str,
    radius: float,
    depth: float,
    thickness: float,
    rings: int,
    sectors: int,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    def ring_z(r: float) -> float:
        return depth * ((r / radius) ** 2)

    front_center = bm.verts.new((0.0, 0.0, 0.0))
    back_center = bm.verts.new((0.0, 0.0, -thickness))

    front_rings: list[list[bmesh.types.BMVert]] = []
    back_rings: list[list[bmesh.types.BMVert]] = []
    for ri in range(1, rings + 1):
        frac = float(ri) / float(rings)
        r = radius * frac
        z_f = ring_z(r)
        z_b = z_f - thickness * (1.35 - 0.55 * frac)
        f_ring, b_ring = [], []
        for si in range(sectors):
            ang = 2.0 * math.pi * float(si) / float(sectors)
            x, y = r * math.cos(ang), r * math.sin(ang)
            f_ring.append(bm.verts.new((x, y, z_f)))
            b_ring.append(bm.verts.new((x, y, z_b)))
        front_rings.append(f_ring)
        back_rings.append(b_ring)

    for si in range(sectors):
        sn = (si + 1) % sectors
        bm.faces.new((front_center, front_rings[0][si], front_rings[0][sn]))
        bm.faces.new((back_center, back_rings[0][sn], back_rings[0][si]))

    for ri in range(rings - 1):
        for si in range(sectors):
            sn = (si + 1) % sectors
            bm.faces.new((front_rings[ri][si], front_rings[ri + 1][si], front_rings[ri + 1][sn], front_rings[ri][sn]))
            bm.faces.new((back_rings[ri][sn], back_rings[ri + 1][sn], back_rings[ri + 1][si], back_rings[ri][si]))

    f_out, b_out = front_rings[-1], back_rings[-1]
    for si in range(sectors):
        sn = (si + 1) % sectors
        bm.faces.new((f_out[si], b_out[si], b_out[sn], f_out[sn]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat)
    return obj


def finalize_and_export(
    parts: list[bpy.types.Object],
    name: str,
    max_faces: int,
    pivot_mode: str = "bottom_center",
    target_max_dim: float | None = None,
    target_height: float | None = None,
    uv_scale: float = 1.2,
) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]

    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if len(parts) > 1:
        bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_mesh"

    min_v, max_v = get_scene_mesh_bbox([obj])
    size_v = max_v - min_v
    if target_height is not None and size_v.z > 1e-5:
        s = target_height / size_v.z
        obj.scale = (s, s, s)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    elif target_max_dim is not None:
        cur_max = max(size_v.x, size_v.y, size_v.z)
        if cur_max > 1e-5:
            s = target_max_dim / cur_max
            obj.scale = (s, s, s)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    min_v, max_v = get_scene_mesh_bbox([obj])
    cx = (min_v.x + max_v.x) * 0.5
    cy = (min_v.y + max_v.y) * 0.5
    cz = (min_v.z + max_v.z) * 0.5

    if pivot_mode == "bottom_center":
        pivot = Vector((cx, cy, min_v.z))
    elif pivot_mode == "top_center":
        pivot = Vector((cx, cy, max_v.z))
    elif pivot_mode == "top_axis":
        pivot = Vector((0.0, 0.0, max_v.z))
    elif pivot_mode == "root_max_x":
        pivot = Vector((max_v.x, cy, cz))
    elif pivot_mode == "center":
        pivot = Vector((cx, cy, cz))
    else:
        pivot = Vector((cx, cy, min_v.z))

    if pivot.length > 1e-6:
        obj.location -= pivot
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=False)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    for mat in obj.data.materials:
        if mat:
            mat.use_backface_culling = False

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()

    tri_count = len(obj.data.polygons)
    if tri_count > max_faces:
        mod = obj.modifiers.new(name="Planar_Limit", type="DECIMATE")
        mod.decimate_type = "DISSOLVE"
        mod.angle_limit = math.radians(5.0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.normal_update()
        bm.to_mesh(obj.data)
        bm.free()

    apply_box_uvs(obj.data, scale=uv_scale)
    obj.data.validate(verbose=False)

    out_path = MODELS_DIR / f"{name}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print(f"[EXPORTED] {name}.glb | tris={len(obj.data.polygons)} | mats={len(obj.data.materials)} | uvs={len(obj.data.uv_layers)} | {out_path.stat().st_size / 1024.0:.1f} KB")


# ==============================================================================
# Group A: Upgrade PBR Materials & UVs while preserving original silhouettes
# ==============================================================================

def restore_group_a() -> None:
    print("\n--- Restoring Group A PBR Textures & UVs ---")

    # 1. lander_bus.glb: Gold Kapton MLI + Brushed Aluminum/Titanium + Dark Thruster Quads
    fpath = MODELS_DIR / "lander_bus.glb"
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(fpath))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if len(obj.data.uv_layers) == 0:
            apply_box_uvs(obj.data, scale=1.4)
        for mat in obj.data.materials:
            if not mat:
                continue
            mname = mat.name
            if mname in ("blinn12SG", "blinn2SG", "blinn10SG"):
                # Gold Kapton MLI thermal blankets
                configure_existing_material(
                    mat, hex_color="#D4AF37", metallic=0.85, roughness=0.28,
                    tex_key="kapton_albedo", normal_tex_key="kapton_normal", normal_strength=0.70
                )
            elif mname in ("blinn4SG",):
                # Upper thermal deck & propellant tank covers -> Bright NASA thermal white/gold accent
                configure_existing_material(
                    mat, hex_color="#E2E8F0", metallic=0.45, roughness=0.34,
                    tex_key="brushed_metal"
                )
            elif mname in ("blinn9SG",):
                # RCS quads & thruster clusters -> Matte gunmetal
                configure_existing_material(
                    mat, hex_color="#1E293B", metallic=0.65, roughness=0.38,
                    tex_key="radiator_dark"
                )
            else:
                # Structural legs, struts, decks (blinn8SG, blinn11SG, initialShadingGr) -> Brushed Titanium
                configure_existing_material(
                    mat, hex_color="#CBD5E1", metallic=0.78, roughness=0.30,
                    tex_key="brushed_metal"
                )
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(fpath),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print(f"[EXPORTED] lander_bus.glb | {fpath.stat().st_size / 1024.0:.1f} KB")

    # 2. engine_biprop.glb: Metallic titanium, Gold Kapton valve box, Dark gunmetal nozzle
    fpath = MODELS_DIR / "engine_biprop.glb"
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(fpath))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if len(obj.data.uv_layers) == 0:
            apply_box_uvs(obj.data, scale=1.5)
        for mat in obj.data.materials:
            if not mat:
                continue
            if "gold" in mat.name.lower():
                configure_existing_material(
                    mat, hex_color="#D4AF37", metallic=0.85, roughness=0.28,
                    tex_key="kapton_albedo", normal_tex_key="kapton_normal", normal_strength=0.65
                )
            elif "dark" in mat.name.lower():
                configure_existing_material(
                    mat, hex_color="#1E293B", metallic=0.72, roughness=0.35,
                    tex_key="radiator_dark"
                )
            else:
                configure_existing_material(
                    mat, hex_color="#CBD5E1", metallic=0.80, roughness=0.28,
                    tex_key="brushed_metal"
                )
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(fpath),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print(f"[EXPORTED] engine_biprop.glb | {fpath.stat().st_size / 1024.0:.1f} KB")

    # 3. antenna_hga.glb: Crisp White Ka-band Parabolic Dish preserving UVs/AO + metallic specular
    fpath = MODELS_DIR / "antenna_hga.glb"
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(fpath))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if len(obj.data.uv_layers) == 0:
            apply_box_uvs(obj.data, scale=1.5)
        for mat in obj.data.materials:
            if not mat:
                continue
            configure_existing_material(
                mat, hex_color="#F8FAFC", metallic=0.28, roughness=0.30,
                preserve_existing_texture=True
            )
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(fpath),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print(f"[EXPORTED] antenna_hga.glb | {fpath.stat().st_size / 1024.0:.1f} KB")


# ==============================================================================
# Group B1: SLS Block 1, VAB Gantry, DSN 70m Dish
# ==============================================================================

def build_sls_block1() -> None:
    reset_scene()
    m_sofi = mat_sls_sofi("SLS_SOFI_Orange")
    m_srb = mat_srb_roll("SLS_SRB_Roll")
    m_white = mat_aero_white("SLS_AeroWhite")
    m_dark = mat_radiator_dark("SLS_RS25_Dark")
    m_metal = mat_brushed_ti("SLS_BrushedTi")

    parts: list[bpy.types.Object] = []
    for idx, (ex, ey) in enumerate([(1.55, 1.55), (-1.55, 1.55), (-1.55, -1.55), (1.55, -1.55)]):
        add_cylinder(parts, f"RS25_Bell_{idx}", 1.15, 0.45, 3.2, (ex, ey, 1.6), 14, m_dark)
        add_cylinder(parts, f"RS25_Powerhead_{idx}", 0.55, 0.65, 1.0, (ex, ey, 3.4), 10, m_metal)

    add_cylinder(parts, "Core_EngineSection", 3.9, 4.18, 3.1, (0.0, 0.0, 4.7), 24, m_white)
    add_cylinder(parts, "Core_OrangeTank", 4.2, 4.2, 58.6, (0.0, 0.0, 35.4), 24, m_sofi)
    add_cylinder(parts, "Core_IntertankRing", 4.24, 4.24, 1.6, (0.0, 0.0, 48.0), 24, m_dark)
    add_cylinder(parts, "Core_ForwardRing", 4.23, 4.23, 1.0, (0.0, 0.0, 64.1), 24, m_dark)

    for side, sx in [("Port", -6.35), ("Starboard", 6.35)]:
        add_cylinder(parts, f"SRB_{side}_AftSkirt", 2.35, 1.88, 3.9, (sx, 0.0, 2.5), 18, m_dark)
        add_cylinder(parts, f"SRB_{side}_Body", 1.85, 1.85, 44.4, (sx, 0.0, 26.5), 18, m_srb)
        add_cylinder(parts, f"SRB_{side}_BandLow", 1.88, 1.88, 1.8, (sx, 0.0, 10.0), 18, m_dark)
        add_cylinder(parts, f"SRB_{side}_BandHigh", 1.88, 1.88, 2.2, (sx, 0.0, 44.5), 18, m_dark)
        add_cylinder(parts, f"SRB_{side}_NoseBase", 1.84, 1.44, 2.7, (sx, 0.0, 49.9), 18, m_white)
        add_cylinder(parts, f"SRB_{side}_NoseTip", 1.43, 0.10, 4.1, (sx, 0.0, 53.2), 18, m_white)
        add_cylinder(parts, f"SRB_{side}_Cap", 0.12, 0.02, 0.5, (sx, 0.0, 55.4), 12, m_dark)
        sign = 1.0 if sx < 0 else -1.0
        add_box(parts, f"SRB_{side}_StrutLow", (2.6, 1.1, 0.8), (sx + sign * 1.4, 0.0, 5.2), m_metal)
        add_box(parts, f"SRB_{side}_StrutHigh", (2.6, 0.9, 0.8), (sx + sign * 1.4, 0.0, 47.8), m_metal)

    add_cylinder(parts, "LVSA_Adapter", 4.18, 2.54, 8.3, (0.0, 0.0, 68.7), 24, m_metal)
    add_cylinder(parts, "LVSA_DarkBand", 2.58, 2.58, 0.8, (0.0, 0.0, 72.4), 20, m_dark)
    add_cylinder(parts, "ICPS_Stage", 2.55, 2.55, 6.3, (0.0, 0.0, 75.9), 20, m_metal)
    add_cylinder(parts, "Orion_StageAdapter", 2.57, 2.57, 1.3, (0.0, 0.0, 79.6), 20, m_dark)
    add_cylinder(parts, "Orion_ESM", 2.52, 2.52, 4.3, (0.0, 0.0, 82.3), 20, m_metal)
    add_cylinder(parts, "Orion_Fairing", 2.51, 1.84, 2.9, (0.0, 0.0, 85.8), 20, m_white)
    add_cylinder(parts, "LAS_Ogive", 1.83, 0.72, 3.9, (0.0, 0.0, 89.1), 16, m_white)
    add_cylinder(parts, "LAS_Tower", 0.58, 0.42, 5.6, (0.0, 0.0, 93.75), 14, m_white)
    add_cylinder(parts, "LAS_NoseCone", 0.43, 0.05, 1.7, (0.0, 0.0, 97.3), 12, m_dark)

    finalize_and_export(parts, "sls_block1", max_faces=2800, pivot_mode="bottom_center", target_height=18.0, uv_scale=0.35)


def build_vab_gantry() -> None:
    reset_scene()
    m_steel = make_pbr_material("Gantry_BrushedSteel", "#64748B", metallic=0.76, roughness=0.34, tex_key="brushed_metal")
    m_deck = mat_radiator_dark("Gantry_DeckDark")
    m_safety = mat_safety_yellow("Gantry_SafetyYellow")

    parts: list[bpy.types.Object] = []
    add_box(parts, "Gantry_BasePlinth", (6.0, 6.0, 0.8), (0.0, 0.0, 0.4), m_deck)
    col_xy = 2.4
    for ix, cx in enumerate([-col_xy, col_xy]):
        for iy, cy in enumerate([-col_xy, col_xy]):
            add_box(parts, f"Column_{ix}_{iy}", (0.38, 0.38, 19.2), (cx, cy, 9.6), m_steel)
    add_box(parts, "Elevator_Shaft_Core", (1.55, 1.55, 19.2), (0.0, 0.0, 9.6), m_deck)

    deck_levels = [3.8, 7.6, 11.4, 15.2, 19.0]
    prev_z = 0.8
    for lvl_idx, dz in enumerate(deck_levels):
        add_box(parts, f"AccessDeck_{lvl_idx}", (5.2, 5.2, 0.26), (0.0, 0.0, dz), m_deck)
        rail_z = dz + 0.55
        corners = [
            Vector((-col_xy, -col_xy, 0.0)),
            Vector((col_xy, -col_xy, 0.0)),
            Vector((col_xy, col_xy, 0.0)),
            Vector((-col_xy, col_xy, 0.0)),
        ]
        for side_idx in range(4):
            ca = corners[side_idx]
            cb = corners[(side_idx + 1) % 4]
            add_beam_between(parts, f"Rail_{lvl_idx}_{side_idx}", Vector((ca.x, ca.y, rail_z)), Vector((cb.x, cb.y, rail_z)), 0.08, m_safety)
            add_beam_between(parts, f"XBraceA_{lvl_idx}_{side_idx}", Vector((ca.x, ca.y, prev_z)), Vector((cb.x, cb.y, dz)), 0.13, m_steel)
            add_beam_between(parts, f"XBraceB_{lvl_idx}_{side_idx}", Vector((cb.x, cb.y, prev_z)), Vector((ca.x, ca.y, dz)), 0.13, m_steel)
        prev_z = dz

    for arm_idx, az in enumerate([11.55, 15.35]):
        add_box(parts, f"UmbilicalArm_{arm_idx}", (3.2, 0.65, 0.45), (3.8, 0.0, az), m_safety)
    add_box(parts, "Roof_CraneBoom", (4.8, 1.1, 0.65), (0.8, 0.0, 19.55), m_safety)
    add_cylinder(parts, "Roof_LightningMast", 0.14, 0.03, 1.8, (0.0, 0.0, 20.4), 8, m_steel)

    finalize_and_export(parts, "vab_gantry", max_faces=2900, pivot_mode="bottom_center", target_height=20.0, uv_scale=0.35)


def build_dsn_70m_dish() -> None:
    reset_scene()
    m_dish = mat_aero_white("DSN_ReflectorWhite")
    m_steel = mat_brushed_ti("DSN_TrussSteel")
    m_ped = mat_radiator_dark("DSN_PedestalDark")
    m_gold = mat_kapton("DSN_FeedHornGold")

    parts: list[bpy.types.Object] = []
    add_cylinder(parts, "Pedestal_Foot", 2.05, 1.85, 1.1, (0.0, 0.0, 0.55), 14, m_ped)
    add_cylinder(parts, "Pedestal_Tower", 1.55, 1.30, 1.9, (0.0, 0.0, 2.05), 14, m_ped)
    add_cylinder(parts, "Azimuth_Turntable", 1.45, 1.45, 0.45, (0.0, 0.0, 3.15), 16, m_steel)
    add_box(parts, "Yoke_LeftArm", (0.55, 0.75, 1.45), (-1.15, 0.0, 3.85), m_steel)
    add_box(parts, "Yoke_RightArm", (0.55, 0.75, 1.45), (1.15, 0.0, 3.85), m_steel)
    add_box(parts, "Yoke_Counterweight", (1.75, 1.35, 0.75), (0.0, -0.55, 3.85), m_ped)

    tilt_euler = Euler((math.radians(38.0), 0.0, 0.0), "XYZ")
    dish_pivot = Vector((0.0, 0.0, 4.35))
    dish_parts: list[bpy.types.Object] = []
    dish_parts.append(build_parabolic_dish_mesh("Dish_ParabolicReflector", 3.9, 1.15, 0.16, 6, 24, m_dish))
    add_cylinder(dish_parts, "Dish_RearHub", 1.25, 0.95, 0.85, (0.0, 0.0, -0.55), 14, m_steel)
    add_cylinder(dish_parts, "Feed_HornCone", 0.55, 0.26, 1.15, (0.0, 0.0, 0.58), 12, m_gold)

    apex_pos = Vector((0.0, 0.0, 3.15))
    strut_r = 2.45
    strut_z = 1.15 * ((strut_r / 3.9) ** 2)
    for leg_idx in range(4):
        ang = math.radians(45.0 + 90.0 * leg_idx)
        base_pt = Vector((strut_r * math.cos(ang), strut_r * math.sin(ang), strut_z - 0.04))
        add_beam_between(dish_parts, f"Quadrupod_Leg_{leg_idx}", base_pt, apex_pos, 0.11, m_steel)

    add_cylinder(dish_parts, "SubReflector_Dish", 0.68, 0.42, 0.32, (0.0, 0.0, 3.22), 14, m_dish)
    add_cylinder(dish_parts, "SubReflector_Tip", 0.42, 0.08, 0.25, (0.0, 0.0, 3.48), 12, m_gold)

    tilt_mat = Matrix.Translation(dish_pivot) @ tilt_euler.to_matrix().to_4x4()
    for dp in dish_parts:
        dp.matrix_world = tilt_mat @ dp.matrix_world
        parts.append(dp)

    finalize_and_export(parts, "dsn_70m_dish", max_faces=2800, pivot_mode="bottom_center", target_height=8.0, uv_scale=0.6)


# ==============================================================================
# Group B2: All 10 Attachable Spacecraft Subsystems
# ==============================================================================

def build_solar_array() -> None:
    reset_scene()
    m_pv = mat_solar_pv("Solar_PV_Grid")
    m_alu = mat_brushed_ti("Solar_AluFrame")
    m_back = mat_radiator_dark("Solar_SubstrateDark")
    m_gold = mat_kapton("Solar_HingeGold")

    parts: list[bpy.types.Object] = []
    add_cylinder(parts, "Root_Flange", 0.14, 0.14, 0.08, (-0.04, 0.0, 0.0), 12, m_alu, rotation=(0.0, math.radians(90.0), 0.0))
    add_box(parts, "Root_GimbalBlock", (0.14, 0.20, 0.12), (-0.11, 0.0, 0.0), m_gold)
    add_beam_between(parts, "Yoke_Top", Vector((-0.14, 0.06, 0.0)), Vector((-0.44, 0.46, 0.0)), 0.045, m_alu, 8)
    add_beam_between(parts, "Yoke_Bot", Vector((-0.14, -0.06, 0.0)), Vector((-0.44, -0.46, 0.0)), 0.045, m_alu, 8)
    add_beam_between(parts, "Yoke_Cross", Vector((-0.42, -0.46, 0.0)), Vector((-0.42, 0.46, 0.0)), 0.04, m_alu, 8)

    panel_w = 0.88
    panel_h = 1.16
    gap = 0.06
    start_x = -0.44
    for idx in range(3):
        cx = start_x - idx * (panel_w + gap) - panel_w * 0.5
        add_box(parts, f"Frame_Top_{idx}", (panel_w, 0.045, 0.045), (cx, panel_h * 0.5 - 0.02, 0.0), m_alu)
        add_box(parts, f"Frame_Bot_{idx}", (panel_w, 0.045, 0.045), (cx, -panel_h * 0.5 + 0.02, 0.0), m_alu)
        add_box(parts, f"Frame_Left_{idx}", (0.045, panel_h, 0.045), (cx - panel_w * 0.5 + 0.02, 0.0, 0.0), m_alu)
        add_box(parts, f"Frame_Right_{idx}", (0.045, panel_h, 0.045), (cx + panel_w * 0.5 - 0.02, 0.0, 0.0), m_alu)
        add_box(parts, f"Panel_Back_{idx}", (panel_w - 0.06, panel_h - 0.06, 0.024), (cx, 0.0, 0.0), m_back)
        add_box(parts, f"Panel_Cells_{idx}", (panel_w - 0.09, panel_h - 0.09, 0.032), (cx, 0.0, 0.002), m_pv)
        for row_y in (-0.28, 0.0, 0.28):
            add_box(parts, f"Busbar_{idx}_{row_y:.2f}", (panel_w - 0.08, 0.018, 0.038), (cx, row_y, 0.002), m_alu)
        hinge_x = start_x - idx * (panel_w + gap) + (gap * 0.5 if idx > 0 else 0.0)
        for hy in (-0.36, 0.36):
            add_cylinder(parts, f"Hinge_{idx}_{hy:.2f}", 0.035, 0.035, 0.11, (hinge_x, hy, 0.0), 8, m_gold, rotation=(math.radians(90.0), 0.0, 0.0))

    finalize_and_export(parts, "solar_array", max_faces=1150, pivot_mode="root_max_x", target_max_dim=3.2, uv_scale=1.1)


def build_rtg_cassini() -> None:
    reset_scene()
    m_core = mat_radiator_dark("RTG_CoreGunmetal")
    m_fin = mat_radiator_dark("RTG_FinGunmetal")
    m_ti = mat_brushed_ti("RTG_TitaniumCap")
    m_gold = mat_kapton("RTG_GoldCollar")
    m_heat = make_pbr_material("RTG_ThermalAccent", "#FF5500", metallic=0.2, roughness=0.35, emission_hex="#FF5500", emission_strength=1.4)

    parts: list[bpy.types.Object] = []
    add_cylinder(parts, "Base_Flange", 0.26, 0.22, 0.08, (0.0, 0.0, 0.04), 14, m_ti)
    add_box(parts, "Side_Bracket", (0.28, 0.34, 0.24), (0.0, 0.14, 0.15), m_ti)
    add_cylinder(parts, "Gold_SensorCollar", 0.21, 0.21, 0.12, (0.0, 0.0, 0.14), 14, m_gold)
    add_cylinder(parts, "RTG_CoreDrum", 0.195, 0.195, 1.04, (0.0, 0.0, 0.72), 16, m_core)
    add_cylinder(parts, "RTG_MidBand", 0.215, 0.215, 0.07, (0.0, 0.0, 0.72), 16, m_ti)
    add_cylinder(parts, "RTG_PuGlowBand", 0.205, 0.205, 0.03, (0.0, 0.0, 1.18), 16, m_heat)

    for i in range(8):
        ang = i * (math.pi / 4.0)
        fx = math.cos(ang) * 0.29
        fy = math.sin(ang) * 0.29
        add_box(parts, f"Fin_{i}", (0.22, 0.032, 0.94), (fx, fy, 0.72), m_fin, rotation=(0.0, 0.0, ang))

    add_cylinder(parts, "Top_Collar", 0.20, 0.17, 0.09, (0.0, 0.0, 1.28), 14, m_ti)
    add_cylinder(parts, "Top_Dome", 0.16, 0.06, 0.11, (0.0, 0.0, 1.38), 12, m_gold)

    finalize_and_export(parts, "rtg_cassini", max_faces=1100, pivot_mode="bottom_center", target_max_dim=1.45, uv_scale=1.6)


def build_engine_ion() -> None:
    reset_scene()
    m_ti = mat_brushed_ti("Ion_Titanium")
    m_dark = mat_radiator_dark("Ion_DischargeGunmetal")
    m_gold = mat_kapton("Ion_ManifoldGold")
    m_xenon = mat_cyan_emissive("Ion_XenonGrid_Cyan", strength=4.2)

    parts: list[bpy.types.Object] = []
    add_cylinder(parts, "Gimbal_MountPlate", 0.28, 0.30, 0.06, (0.0, 0.0, -0.03), 16, m_ti)
    add_cylinder(parts, "Gimbal_Collar", 0.24, 0.34, 0.08, (0.0, 0.0, -0.10), 16, m_gold)
    add_cylinder(parts, "Discharge_Chamber", 0.34, 0.38, 0.24, (0.0, 0.0, -0.25), 18, m_dark)
    add_cylinder(parts, "Outer_ShroudRing", 0.40, 0.40, 0.06, (0.0, 0.0, -0.36), 18, m_ti)
    for i in range(6):
        ang = i * (math.pi / 3.0)
        rx, ry = math.cos(ang) * 0.37, math.sin(ang) * 0.37
        add_box(parts, f"Chamber_Rib_{i}", (0.04, 0.04, 0.20), (rx, ry, -0.25), m_ti, rotation=(0.0, 0.0, ang))

    add_cylinder(parts, "Nozzle_Rim", 0.39, 0.36, 0.09, (0.0, 0.0, -0.43), 18, m_ti)
    add_cylinder(parts, "Xenon_Grid_Core", 0.31, 0.31, 0.03, (0.0, 0.0, -0.46), 18, m_xenon)
    add_cylinder(parts, "Xenon_CenterKeeper", 0.08, 0.06, 0.06, (0.0, 0.0, -0.47), 10, m_ti)

    add_box(parts, "Neutralizer_Bracket", (0.14, 0.06, 0.06), (0.39, 0.0, -0.34), m_ti)
    add_cylinder(parts, "Neutralizer_Cathode", 0.04, 0.03, 0.18, (0.45, 0.0, -0.41), 10, m_ti, rotation=(0.0, math.radians(-22.0), 0.0))
    add_cylinder(parts, "Neutralizer_Tip", 0.025, 0.015, 0.04, (0.48, 0.0, -0.49), 8, m_xenon, rotation=(0.0, math.radians(-22.0), 0.0))

    finalize_and_export(parts, "engine_ion", max_faces=1100, pivot_mode="top_axis", target_max_dim=0.92, uv_scale=1.8)


def build_battery_pack() -> None:
    reset_scene()
    m_chassis = mat_radiator_dark("Batt_Anodized")
    m_gold = mat_kapton("Batt_KaptonMLI")
    m_alu = mat_brushed_ti("Batt_RadiatorAlu")
    m_cyan = mat_cyan_emissive("Batt_StatusLED", strength=2.4)
    m_warn = mat_safety_yellow("Batt_Disconnect")

    parts: list[bpy.types.Object] = []
    add_box(parts, "Base_Flange", (0.98, 0.68, 0.06), (0.0, 0.0, 0.03), m_alu)
    add_box(parts, "Battery_Housing", (0.88, 0.58, 0.40), (0.0, 0.0, 0.26), m_chassis)
    add_box(parts, "MLI_FrontBack", (0.76, 0.61, 0.28), (0.0, 0.0, 0.26), m_gold)
    add_box(parts, "MLI_Sides", (0.91, 0.44, 0.28), (0.0, 0.0, 0.26), m_gold)
    add_box(parts, "Top_Plate", (0.86, 0.56, 0.04), (0.0, 0.0, 0.48), m_alu)
    for idx in range(6):
        fx = -0.35 + idx * 0.14
        add_box(parts, f"Rad_Fin_{idx}", (0.03, 0.50, 0.09), (fx, 0.0, 0.545), m_alu)
    add_cylinder(parts, "HV_Plug", 0.06, 0.06, 0.10, (0.30, -0.32, 0.26), 10, m_cyan, rotation=(math.radians(90.0), 0.0, 0.0))
    add_box(parts, "Arm_Plug", (0.08, 0.05, 0.08), (-0.28, -0.31, 0.26), m_warn)

    finalize_and_export(parts, "battery_pack", max_faces=900, pivot_mode="bottom_center", target_max_dim=1.0, uv_scale=1.6)


def build_antenna_omni() -> None:
    reset_scene()
    m_base = mat_radiator_dark("Omni_BaseGunmetal")
    m_mast = mat_brushed_ti("Omni_MastAlu")
    m_gold = mat_kapton("Omni_GoldCollar")
    m_radome = mat_aero_white("Omni_RadomeWhite")

    parts: list[bpy.types.Object] = []
    add_cylinder(parts, "Mount_Flange", 0.14, 0.12, 0.05, (0.0, 0.0, 0.025), 14, m_base)
    add_cylinder(parts, "Waveguide_Base", 0.08, 0.06, 0.08, (0.0, 0.0, 0.09), 12, m_gold)
    add_cylinder(parts, "Coax_Mast", 0.042, 0.038, 0.52, (0.0, 0.0, 0.39), 12, m_mast)
    for i in range(4):
        ang = i * (math.pi * 0.5)
        p1 = Vector((0.04 * math.cos(ang), 0.04 * math.sin(ang), 0.16))
        p2 = Vector((0.20 * math.cos(ang), 0.20 * math.sin(ang), 0.10))
        add_beam_between(parts, f"GroundPlane_{i}", p1, p2, 0.018, m_mast, 6)
    add_cylinder(parts, "RF_Choke", 0.085, 0.055, 0.06, (0.0, 0.0, 0.65), 12, m_gold)
    add_cylinder(parts, "Helix_Sleeve", 0.068, 0.068, 0.13, (0.0, 0.0, 0.74), 12, m_radome)
    add_cylinder(parts, "Radome_Tip", 0.064, 0.02, 0.10, (0.0, 0.0, 0.84), 12, m_radome)
    add_uv_sphere(parts, "Tip_Finial", 0.024, 10, 6, (0.0, 0.0, 0.89), m_gold)

    finalize_and_export(parts, "antenna_omni", max_faces=900, pivot_mode="bottom_center", target_max_dim=0.90, uv_scale=2.0)


def build_sensor_lidar() -> None:
    reset_scene()
    m_alu = mat_brushed_ti("Lidar_BrushedAlu")
    m_body = mat_radiator_dark("Lidar_DarkChassis")
    m_gold = mat_kapton("Lidar_GoldVisor")
    m_cyan = mat_cyan_emissive("Lidar_CyanOptics", strength=3.8)

    parts: list[bpy.types.Object] = []
    add_box(parts, "Baseplate", (0.56, 0.52, 0.05), (0.0, 0.0, 0.025), m_alu)
    add_box(parts, "Chassis_Main", (0.48, 0.44, 0.28), (0.0, 0.02, 0.19), m_body)
    add_box(parts, "Chassis_Shell", (0.50, 0.36, 0.22), (0.0, 0.04, 0.19), m_alu)
    for i in range(4):
        fx = -0.15 + i * 0.10
        add_box(parts, f"Top_Fin_{i}", (0.025, 0.34, 0.06), (fx, 0.04, 0.36), m_alu)
    add_cylinder(parts, "StarTracker_Baffle", 0.075, 0.055, 0.16, (-0.12, 0.12, 0.40), 12, m_gold, rotation=(math.radians(-30.0), 0.0, 0.0))
    add_cylinder(parts, "StarTracker_Optic", 0.052, 0.052, 0.02, (-0.12, 0.09, 0.46), 12, m_cyan, rotation=(math.radians(-30.0), 0.0, 0.0))
    add_box(parts, "Thermal_Visor_Top", (0.44, 0.18, 0.03), (0.0, -0.26, 0.30), m_gold)
    add_box(parts, "Thermal_Visor_Left", (0.03, 0.18, 0.20), (-0.205, -0.26, 0.21), m_gold)
    add_box(parts, "Thermal_Visor_Right", (0.03, 0.18, 0.20), (0.205, -0.26, 0.21), m_gold)
    for idx, lx in enumerate((-0.11, 0.11)):
        add_cylinder(parts, f"Lens_Barrel_{idx}", 0.078, 0.070, 0.14, (lx, -0.24, 0.20), 14, m_alu, rotation=(math.radians(90.0), 0.0, 0.0))
        add_cylinder(parts, f"Lens_Optic_{idx}", 0.062, 0.062, 0.03, (lx, -0.305, 0.20), 14, m_cyan, rotation=(math.radians(90.0), 0.0, 0.0))

    finalize_and_export(parts, "sensor_lidar", max_faces=1000, pivot_mode="bottom_center", target_max_dim=0.72, uv_scale=2.0)


def build_payload_drill() -> None:
    reset_scene()
    m_rail = mat_brushed_ti("Drill_AluRails")
    m_yoke = mat_radiator_dark("Drill_YokeGunmetal")
    m_gold = mat_kapton("Drill_MotorGold")
    m_steel = mat_brushed_ti("Drill_AugerTi")

    parts: list[bpy.types.Object] = []
    add_cylinder(parts, "Base_GuideBushing", 0.16, 0.14, 0.08, (0.0, 0.0, 0.04), 12, m_yoke)
    add_box(parts, "Mount_Plate", (0.36, 0.22, 0.05), (0.0, 0.08, 0.025), m_yoke)
    add_beam_between(parts, "Strut_L", Vector((-0.14, 0.16, 0.05)), Vector((-0.16, 0.0, 0.65)), 0.04, m_steel)
    add_beam_between(parts, "Strut_R", Vector((0.14, 0.16, 0.05)), Vector((0.16, 0.0, 0.65)), 0.04, m_steel)
    add_box(parts, "Rail_Left", (0.05, 0.06, 1.34), (-0.16, 0.0, 0.69), m_rail)
    add_box(parts, "Rail_Right", (0.05, 0.06, 1.34), (0.16, 0.0, 0.69), m_rail)
    add_box(parts, "Yoke_Mid", (0.38, 0.10, 0.06), (0.0, 0.0, 0.65), m_yoke)
    add_box(parts, "Yoke_Top", (0.40, 0.12, 0.07), (0.0, 0.0, 1.36), m_yoke)
    add_box(parts, "Motor_Head", (0.26, 0.22, 0.28), (0.0, 0.0, 1.06), m_gold)
    add_cylinder(parts, "Drive_Chuck", 0.08, 0.07, 0.10, (0.0, 0.0, 0.88), 10, m_yoke)
    add_cylinder(parts, "Auger_Shaft", 0.036, 0.028, 0.84, (0.0, 0.0, 0.44), 10, m_steel)
    for fi in range(9):
        fz = 0.12 + fi * 0.085
        add_cylinder(parts, f"Auger_Flute_{fi}", 0.072, 0.058, 0.038, (0.0, 0.0, fz), 10, m_rail, rotation=(math.radians(16.0), 0.0, fi * 0.7))

    finalize_and_export(parts, "payload_drill", max_faces=1050, pivot_mode="bottom_center", target_max_dim=1.40, uv_scale=1.5)


def build_payload_msolo() -> None:
    reset_scene()
    m_base = mat_brushed_ti("MSolo_BaseTi")
    m_white = mat_aero_white("MSolo_WhiteThermal")
    m_gold = mat_kapton("MSolo_GoldMLI")
    m_cyan = mat_cyan_emissive("MSolo_IonSource", strength=2.6)

    parts: list[bpy.types.Object] = []
    add_box(parts, "Baseplate", (0.58, 0.64, 0.05), (0.0, 0.0, 0.025), m_base)
    add_box(parts, "Body_White", (0.50, 0.54, 0.34), (0.0, 0.0, 0.22), m_white)
    add_box(parts, "Body_GoldMLI", (0.53, 0.46, 0.20), (0.0, 0.0, 0.20), m_gold)
    add_cylinder(parts, "Quadrupole_Barrel", 0.14, 0.14, 0.24, (0.0, 0.06, 0.48), 14, m_base)
    add_cylinder(parts, "Quadrupole_Cap", 0.16, 0.14, 0.05, (0.0, 0.06, 0.59), 14, m_gold)
    add_cylinder(parts, "Snorkel_Tube", 0.05, 0.05, 0.34, (0.0, -0.22, 0.40), 12, m_base, rotation=(math.radians(65.0), 0.0, 0.0))
    add_cylinder(parts, "Snorkel_Inlet", 0.075, 0.048, 0.08, (0.0, -0.38, 0.33), 12, m_gold, rotation=(math.radians(65.0), 0.0, 0.0))
    add_cylinder(parts, "Ion_Indicator", 0.03, 0.03, 0.02, (0.14, -0.275, 0.28), 10, m_cyan, rotation=(math.radians(90.0), 0.0, 0.0))

    finalize_and_export(parts, "payload_msolo", max_faces=900, pivot_mode="bottom_center", target_max_dim=0.78, uv_scale=1.8)


def build_payload_sar() -> None:
    reset_scene()
    m_frame = mat_brushed_ti("SAR_AluFrame")
    m_ribs = mat_radiator_dark("SAR_HoneycombRibs")
    m_face = mat_solar_pv("SAR_PhasedArray")
    m_patch = mat_aero_white("SAR_Microstrip")
    m_gold = mat_kapton("SAR_FeedGold")

    parts: list[bpy.types.Object] = []
    add_box(parts, "Base_MountPlate", (0.54, 0.34, 0.06), (0.0, 0.0, 0.03), m_ribs)
    add_cylinder(parts, "Hinge_Pin", 0.045, 0.045, 0.48, (0.0, -0.04, 0.09), 10, m_gold, rotation=(0.0, math.radians(90.0), 0.0))

    panel_parts: list[bpy.types.Object] = []
    add_box(panel_parts, "SAR_Frame", (1.10, 0.07, 0.68), (0.0, 0.0, 0.46), m_frame)
    add_box(panel_parts, "SAR_Substrate", (1.00, 0.08, 0.58), (0.0, -0.006, 0.46), m_face)
    for row in (-0.14, 0.14):
        for col in (-0.33, -0.11, 0.11, 0.33):
            add_box(panel_parts, f"Patch_{row}_{col}", (0.16, 0.02, 0.20), (col, -0.048, 0.46 + row), m_patch)
    for rx in (-0.36, 0.0, 0.36):
        add_box(panel_parts, f"Rib_Vert_{rx}", (0.04, 0.08, 0.62), (rx, 0.055, 0.46), m_ribs)
    add_box(panel_parts, "Rib_Horiz", (1.02, 0.08, 0.04), (0.0, 0.055, 0.46), m_ribs)

    tilt_mat = Matrix.Translation(Vector((0.0, -0.04, 0.10))) @ Euler((math.radians(-24.0), 0.0, 0.0), "XYZ").to_matrix().to_4x4()
    for pp in panel_parts:
        pp.matrix_world = tilt_mat @ pp.matrix_world
        parts.append(pp)

    add_beam_between(parts, "Strut_L", Vector((-0.20, 0.12, 0.06)), Vector((-0.36, 0.18, 0.54)), 0.04, m_frame, 6)
    add_beam_between(parts, "Strut_R", Vector((0.20, 0.12, 0.06)), Vector((0.36, 0.18, 0.54)), 0.04, m_frame, 6)

    finalize_and_export(parts, "payload_sar", max_faces=950, pivot_mode="bottom_center", target_max_dim=1.25, uv_scale=1.4)


def build_shield_heavy() -> None:
    reset_scene()
    m_ti = mat_brushed_ti("Shield_Titanium")
    m_kapton = mat_kapton("Shield_GoldKapton")
    m_poly = mat_aero_white("Shield_PolyWhite")

    parts: list[bpy.types.Object] = []
    center_y = 1.05
    add_curved_arc_plate(parts, "Inner_PolyPlate", 1.04, 1.09, 0.50, 56.0, center_y, 0.0, 12, m_poly)
    add_curved_arc_plate(parts, "Mid_TitaniumPlate", 1.11, 1.15, 0.48, 54.0, center_y, 0.0, 12, m_ti)
    add_curved_arc_plate(parts, "Outer_KaptonPlate", 1.155, 1.18, 0.40, 48.0, center_y, 0.0, 12, m_kapton)

    for ang_deg in (-22.0, 0.0, 22.0):
        ang = math.radians(ang_deg)
        sx, cy = math.sin(ang), -math.cos(ang)
        add_box(parts, f"BoltRib_{ang_deg:.0f}", (0.05, 0.06, 0.52), (1.17 * sx, center_y + 1.17 * cy, 0.0), m_ti, rotation=(0.0, 0.0, -ang))
        for sz in (-0.15, 0.15):
            p_outer = Vector((1.05 * sx, center_y + 1.05 * cy, sz))
            p_inner = Vector((0.82 * sx, center_y + 0.82 * cy, sz))
            add_beam_between(parts, f"Standoff_{ang_deg:.0f}_{sz:.2f}", p_inner, p_outer, 0.045, m_ti, 6)

    finalize_and_export(parts, "shield_heavy", max_faces=900, pivot_mode="center", target_max_dim=1.08, uv_scale=1.6)


def verify_all_16_glb() -> None:
    print("\n=== VERIFYING ALL 16 GLB PBR MATERIALS & UVS ===")
    total_bytes = 0
    for fn in ALL_16_MODELS:
        fpath = MODELS_DIR / fn
        total_bytes += fpath.stat().st_size
        reset_scene()
        bpy.ops.import_scene.gltf(filepath=str(fpath))
        meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        assert meshes, f"{fn} has no meshes"
        uvs = [len(m.data.uv_layers) for m in meshes]
        assert all(u >= 1 for u in uvs), f"{fn} missing UVs: {uvs}"
        non_grey_or_tex = False
        mat_summary = []
        for m in meshes:
            for mat in m.data.materials:
                if mat and mat.use_nodes:
                    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                    assert bsdf is not None, f"{fn} missing BSDF_PRINCIPLED"
                    linked = bsdf.inputs["Base Color"].is_linked
                    bc = tuple(round(x, 2) for x in bsdf.inputs["Base Color"].default_value[:3])
                    em_str = float(bsdf.inputs["Emission Strength"].default_value)
                    if linked or em_str > 0.1 or bc != (0.8, 0.8, 0.8):
                        non_grey_or_tex = True
                    mat_summary.append(f"{mat.name}(tex={linked},em={em_str:.1f})")
        assert non_grey_or_tex, f"{fn} appears unstyled grey"
        print(f"[OK] {fn:20s} | {fpath.stat().st_size / 1024.0:6.1f} KB | UVs={uvs} | {', '.join(mat_summary[:3])}")
    print(f"Total 16-GLB Payload: {total_bytes / (1024.0 * 1024.0):.3f} MB (Budget < 15.0 MB)")


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp_dir = Path(td)
        generate_all_procedural_textures(tmp_dir)
        restore_group_a()

        print("\n--- Building Group B1 PBR Models ---")
        build_sls_block1()
        build_vab_gantry()
        build_dsn_70m_dish()

        print("\n--- Building Group B2 PBR Models (10 Subsystems) ---")
        build_solar_array()
        build_rtg_cassini()
        build_engine_ion()
        build_battery_pack()
        build_antenna_omni()
        build_sensor_lidar()
        build_payload_drill()
        build_payload_msolo()
        build_payload_sar()
        build_shield_heavy()

        verify_all_16_glb()


if __name__ == "__main__":
    main()
