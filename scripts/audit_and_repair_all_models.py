"""Comprehensive 3D Aerospace Mesh Audit, Repair & Upgrade Pipeline for AstraRex.

Runs inside headless Blender 4.4+:
    blender --background --python scripts/audit_and_repair_all_models.py

Tasks executed sequentially:
1. Pre-Repair Diagnostic Audit of all 16 .glb files in space-app-challenge-2026---astra-rex/assets/models/
2. Group A Protection (lander_bus.glb, engine_biprop.glb, antenna_hga.glb):
   Preserves original geometry & UVs; enforces consistent outward normals and double-sided materials.
3. Group B1 Rebuild (sls_block1.glb, vab_gantry.glb, dsn_70m_dish.glb):
   Rebuilds clean, manifold, multi-material environment/launcher assets with base pivot at Y=0 (< 3000 faces).
4. Group B2 Rebuild/Upgrade (all 10 remaining attachable spacecraft subsystems):
   Rebuilds realistic multi-material aerospace hardware (< 1200 faces each) with flush mount pivots.
5. Post-Repair Diagnostic Audit and WebGL 15 MB budget verification.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parent.parent
MODELS_DIR = REPO_ROOT / "space-app-challenge-2026---astra-rex" / "assets" / "models"

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


@dataclass
class MeshAuditStats:
    filename: str
    size_kb: float
    verts: int
    faces: int
    materials: int
    bbox_min: Vector
    bbox_max: Vector
    bbox_size: Vector
    non_manifold_edges: int
    boundary_edges: int
    zero_area_faces: int
    loose_verts: int
    is_primitive_box: bool
    has_torn_artifacts: bool


def srgb_to_linear(c: float) -> float:
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear_rgba(hex_str: str) -> tuple[float, float, float, float]:
    h = hex_str.lstrip("#")
    r = srgb_to_linear(int(h[0:2], 16) / 255.0)
    g = srgb_to_linear(int(h[2:4], 16) / 255.0)
    b = srgb_to_linear(int(h[4:6], 16) / 255.0)
    return (r, g, b, 1.0)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(
    name: str,
    hex_color: str,
    metallic: float = 0.3,
    roughness: float = 0.45,
    emission_hex: str | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(hex_color)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission_hex and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = hex_to_linear_rgba(emission_hex)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def get_scene_mesh_bbox(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(c) for obj in meshes for c in obj.bound_box]
    if not corners:
        return Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.0))
    min_v = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    max_v = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return min_v, max_v


def inspect_glb(filepath: Path) -> MeshAuditStats:
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    total_verts = 0
    total_faces = 0
    non_manifold = 0
    boundary = 0
    zero_area = 0
    loose_verts = 0
    mats: set[str] = set()

    for obj in meshes:
        total_verts += len(obj.data.vertices)
        total_faces += len(obj.data.polygons)
        for m in obj.data.materials:
            if m:
                mats.add(m.name)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        # glTF splits vertices across sharp edges/material boundaries; weld coincident
        # corners in this temporary inspection BMesh to check true topological manifoldness.
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
        non_manifold += sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
        boundary += sum(1 for e in bm.edges if e.is_boundary)
        zero_area += sum(1 for f in bm.faces if f.calc_area() < 1e-8)
        loose_verts += sum(1 for v in bm.verts if not v.link_edges)
        bm.free()

    min_v, max_v = get_scene_mesh_bbox(meshes)
    size_v = max_v - min_v
    is_prim = total_faces < 30
    # Only fail Group B2 models on true internal non-manifold edges, boundary holes,
    # zero-area sliver triangles, or loose vertices (note: closed boxes/cylinders have 0 boundary edges).
    has_torn = (non_manifold > 0) or (boundary > 0) or (zero_area > 0) or (loose_verts > 0)

    return MeshAuditStats(
        filename=filepath.name,
        size_kb=filepath.stat().st_size / 1024.0,
        verts=total_verts,
        faces=total_faces,
        materials=len(mats),
        bbox_min=min_v,
        bbox_max=max_v,
        bbox_size=size_v,
        non_manifold_edges=non_manifold,
        boundary_edges=boundary,
        zero_area_faces=zero_area,
        loose_verts=loose_verts,
        is_primitive_box=is_prim,
        has_torn_artifacts=has_torn,
    )


def audit_catalog(title: str) -> dict[str, MeshAuditStats]:
    print(f"\n==================== {title} ====================")
    results: dict[str, MeshAuditStats] = {}
    total_bytes = 0
    for name in ALL_16_MODELS:
        fpath = MODELS_DIR / name
        if not fpath.exists():
            print(f"[MISSING] {name}")
            continue
        total_bytes += fpath.stat().st_size
        st = inspect_glb(fpath)
        results[name] = st
        flags: list[str] = []
        if st.is_primitive_box:
            flags.append("PRIMITIVE(<30F)")
        if st.non_manifold_edges > 0:
            flags.append(f"NonManifold={st.non_manifold_edges}")
        if st.boundary_edges > 0:
            flags.append(f"Boundary={st.boundary_edges}")
        if st.zero_area_faces > 0:
            flags.append(f"ZeroArea={st.zero_area_faces}")
        if st.loose_verts > 0:
            flags.append(f"LooseV={st.loose_verts}")
        flag_str = ", ".join(flags) if flags else "CLEAN_MANIFOLD"
        print(
            f"{name:20s} | {st.size_kb:6.1f} KB | V:{st.verts:4d} F:{st.faces:4d} | Mats:{st.materials:2d} | "
            f"Size(XYZ):({st.bbox_size.x:.2f},{st.bbox_size.y:.2f},{st.bbox_size.z:.2f}) | {flag_str}"
        )
    print(f"Total 16-GLB Payload: {total_bytes / (1024.0 * 1024.0):.3f} MB (Budget: 15.000 MB)")
    return results


# ==============================================================================
# Mesh Construction Helpers (Watertight BMesh Primitives)
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
    bmesh.ops.create_cube(bm, size=1.0)
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
    bmesh.ops.create_uvsphere(bm, u_segments=u_seg, v_segments=v_seg, radius=radius)
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
    if length < 1e-6:
        raise ValueError(f"Zero-length beam {name}")
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
        )
    else:
        bmesh.ops.create_cube(bm, size=1.0)
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
    """Watertight curved cylindrical arc shell bulging toward -Y (Godot +Z)."""
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
        # Centered along -Y (angle=0 -> (0, -r))
        sx = math.sin(ang)
        cy = -math.cos(ang)
        in_bot.append(bm.verts.new((inner_r * sx, center_y_offset + inner_r * cy, z_bot)))
        in_top.append(bm.verts.new((inner_r * sx, center_y_offset + inner_r * cy, z_top)))
        out_bot.append(bm.verts.new((outer_r * sx, center_y_offset + outer_r * cy, z_bot)))
        out_top.append(bm.verts.new((outer_r * sx, center_y_offset + outer_r * cy, z_top)))

    for i in range(segments):
        # Outer wall
        bm.faces.new((out_bot[i], out_bot[i + 1], out_top[i + 1], out_top[i]))
        # Inner wall
        bm.faces.new((in_bot[i + 1], in_bot[i], in_top[i], in_top[i + 1]))
        # Top cap
        bm.faces.new((in_top[i], out_top[i], out_top[i + 1], in_top[i + 1]))
        # Bottom cap
        bm.faces.new((out_bot[i], in_bot[i], in_bot[i + 1], out_bot[i + 1]))

    # Left and right end caps
    bm.faces.new((in_bot[0], out_bot[0], out_top[0], in_top[0]))
    bm.faces.new((out_bot[-1], in_bot[-1], in_top[-1], out_top[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def finalize_and_export(
    parts: list[bpy.types.Object],
    name: str,
    max_faces: int,
    pivot_mode: str = "bottom_center",
    target_max_dim: float | None = None,
    target_height: float | None = None,
) -> bpy.types.Object:
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
    elif pivot_mode == "none":
        pivot = Vector((0.0, 0.0, 0.0))
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
        mod.angle_limit = math.radians(6.0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.normal_update()
        bm.to_mesh(obj.data)
        bm.free()

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
        export_image_format="WEBP",
        export_image_quality=80,
    )
    return obj


# ==============================================================================
# Group A: Protect Geometry, Fix Outward Normals & Double-Sided Materials
# ==============================================================================

def process_group_a() -> None:
    print("\n--- Processing Group A (Preserving Geometry, Normals & CULL_DISABLED) ---")
    for filename in GROUP_A_FILES:
        fpath = MODELS_DIR / filename
        reset_scene()
        bpy.ops.import_scene.gltf(filepath=str(fpath))

        for obj in bpy.context.scene.objects:
            if obj.type != "MESH":
                continue
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.mesh.normals_make_consistent(inside=False)
            bpy.ops.object.mode_set(mode="OBJECT")
            for mat in obj.data.materials:
                if mat:
                    mat.use_backface_culling = False

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
            export_image_format="WEBP",
            export_image_quality=80,
        )
        print(f"  [PRESERVED] {filename}")


# ==============================================================================
# Group B1: Environment & Launchers (< 3000 faces, Pivot Y=0)
# ==============================================================================

def build_sls_block1() -> None:
    reset_scene()
    mat_orange = make_material("SLS_CoreOrange", "#D96B27", metallic=0.12, roughness=0.62)
    mat_white = make_material("SLS_White", "#E9EDF2", metallic=0.10, roughness=0.45)
    mat_dark = make_material("SLS_Charcoal", "#20242C", metallic=0.72, roughness=0.42)
    mat_steel = make_material("SLS_Steel", "#8A929E", metallic=0.88, roughness=0.30)

    parts: list[bpy.types.Object] = []
    for idx, (ex, ey) in enumerate([(1.55, 1.55), (-1.55, 1.55), (-1.55, -1.55), (1.55, -1.55)]):
        add_cylinder(parts, f"RS25_Bell_{idx}", 1.15, 0.45, 3.2, (ex, ey, 1.6), 14, mat_dark)
        add_cylinder(parts, f"RS25_Powerhead_{idx}", 0.55, 0.65, 1.0, (ex, ey, 3.4), 10, mat_steel)

    add_cylinder(parts, "Core_EngineSection", 3.9, 4.18, 3.1, (0.0, 0.0, 4.7), 24, mat_white)
    add_cylinder(parts, "Core_OrangeTank", 4.2, 4.2, 58.6, (0.0, 0.0, 35.4), 24, mat_orange)
    add_cylinder(parts, "Core_IntertankRing", 4.24, 4.24, 1.6, (0.0, 0.0, 48.0), 24, mat_dark)
    add_cylinder(parts, "Core_ForwardRing", 4.23, 4.23, 1.0, (0.0, 0.0, 64.1), 24, mat_dark)

    for side, sx in [("Port", -6.35), ("Starboard", 6.35)]:
        add_cylinder(parts, f"SRB_{side}_AftSkirt", 2.35, 1.88, 3.9, (sx, 0.0, 2.5), 18, mat_dark)
        add_cylinder(parts, f"SRB_{side}_Body", 1.85, 1.85, 44.4, (sx, 0.0, 26.5), 18, mat_white)
        add_cylinder(parts, f"SRB_{side}_BandLow", 1.88, 1.88, 1.8, (sx, 0.0, 10.0), 18, mat_dark)
        add_cylinder(parts, f"SRB_{side}_BandHigh", 1.88, 1.88, 2.2, (sx, 0.0, 44.5), 18, mat_dark)
        add_cylinder(parts, f"SRB_{side}_NoseBase", 1.84, 1.44, 2.7, (sx, 0.0, 49.9), 18, mat_white)
        add_cylinder(parts, f"SRB_{side}_NoseTip", 1.43, 0.10, 4.1, (sx, 0.0, 53.2), 18, mat_white)
        add_cylinder(parts, f"SRB_{side}_Cap", 0.12, 0.02, 0.5, (sx, 0.0, 55.4), 12, mat_dark)
        sign = 1.0 if sx < 0 else -1.0
        add_box(parts, f"SRB_{side}_StrutLow", (2.6, 1.1, 0.8), (sx + sign * 1.4, 0.0, 5.2), mat_steel)
        add_box(parts, f"SRB_{side}_StrutHigh", (2.6, 0.9, 0.8), (sx + sign * 1.4, 0.0, 47.8), mat_steel)

    add_cylinder(parts, "LVSA_Adapter", 4.18, 2.54, 8.3, (0.0, 0.0, 68.7), 24, mat_white)
    add_cylinder(parts, "LVSA_DarkBand", 2.58, 2.58, 0.8, (0.0, 0.0, 72.4), 20, mat_dark)
    add_cylinder(parts, "ICPS_Stage", 2.55, 2.55, 6.3, (0.0, 0.0, 75.9), 20, mat_white)
    add_cylinder(parts, "Orion_StageAdapter", 2.57, 2.57, 1.3, (0.0, 0.0, 79.6), 20, mat_dark)
    add_cylinder(parts, "Orion_ESM", 2.52, 2.52, 4.3, (0.0, 0.0, 82.3), 20, mat_white)
    add_cylinder(parts, "Orion_Fairing", 2.51, 1.84, 2.9, (0.0, 0.0, 85.8), 20, mat_white)
    add_cylinder(parts, "LAS_Ogive", 1.83, 0.72, 3.9, (0.0, 0.0, 89.1), 16, mat_white)
    add_cylinder(parts, "LAS_Tower", 0.58, 0.42, 5.6, (0.0, 0.0, 93.75), 14, mat_white)
    add_cylinder(parts, "LAS_NoseCone", 0.43, 0.05, 1.7, (0.0, 0.0, 97.3), 12, mat_dark)

    finalize_and_export(parts, "sls_block1", max_faces=2800, pivot_mode="bottom_center", target_height=18.0)


def build_vab_gantry() -> None:
    reset_scene()
    mat_steel = make_material("Gantry_SteelGray", "#64748B", metallic=0.78, roughness=0.42)
    mat_deck = make_material("Gantry_DeckPlate", "#283244", metallic=0.55, roughness=0.55)
    mat_orange = make_material("Gantry_SafetyOrange", "#E06319", metallic=0.35, roughness=0.45)
    mat_core = make_material("Gantry_ElevatorCore", "#1E293B", metallic=0.45, roughness=0.58)

    parts: list[bpy.types.Object] = []
    add_box(parts, "Gantry_BasePlinth", (6.0, 6.0, 0.8), (0.0, 0.0, 0.4), mat_deck)

    col_xy = 2.4
    for ix, cx in enumerate([-col_xy, col_xy]):
        for iy, cy in enumerate([-col_xy, col_xy]):
            add_box(parts, f"Column_{ix}_{iy}", (0.38, 0.38, 19.2), (cx, cy, 9.6), mat_steel)

    add_box(parts, "Elevator_Shaft_Core", (1.55, 1.55, 19.2), (0.0, 0.0, 9.6), mat_core)

    deck_levels = [3.8, 7.6, 11.4, 15.2, 19.0]
    prev_z = 0.8
    for lvl_idx, dz in enumerate(deck_levels):
        add_box(parts, f"AccessDeck_{lvl_idx}", (5.2, 5.2, 0.26), (0.0, 0.0, dz), mat_deck)
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
            add_beam_between(
                parts, f"Rail_{lvl_idx}_{side_idx}",
                Vector((ca.x, ca.y, rail_z)), Vector((cb.x, cb.y, rail_z)), 0.08, mat_steel
            )
            add_beam_between(
                parts, f"XBraceA_{lvl_idx}_{side_idx}",
                Vector((ca.x, ca.y, prev_z)), Vector((cb.x, cb.y, dz)), 0.13, mat_steel
            )
            add_beam_between(
                parts, f"XBraceB_{lvl_idx}_{side_idx}",
                Vector((cb.x, cb.y, prev_z)), Vector((ca.x, ca.y, dz)), 0.13, mat_steel
            )
        prev_z = dz

    for arm_idx, az in enumerate([11.55, 15.35]):
        add_box(parts, f"UmbilicalArm_{arm_idx}", (3.2, 0.65, 0.45), (3.8, 0.0, az), mat_orange)

    add_box(parts, "Roof_CraneBoom", (4.8, 1.1, 0.65), (0.8, 0.0, 19.55), mat_orange)
    add_cylinder(parts, "Roof_LightningMast", 0.14, 0.03, 1.8, (0.0, 0.0, 20.4), 8, mat_steel)

    finalize_and_export(parts, "vab_gantry", max_faces=2900, pivot_mode="bottom_center", target_height=20.0)


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


def build_dsn_70m_dish() -> None:
    reset_scene()
    mat_dish_white = make_material("DSN_DishWhite", "#EDF2F7", metallic=0.15, roughness=0.40)
    mat_truss_steel = make_material("DSN_TrussSteel", "#64748B", metallic=0.80, roughness=0.38)
    mat_pedestal = make_material("DSN_PedestalConcrete", "#334155", metallic=0.25, roughness=0.68)
    mat_feed_gold = make_material("DSN_FeedHornGold", "#D9A426", metallic=0.88, roughness=0.25)

    parts: list[bpy.types.Object] = []
    add_cylinder(parts, "Pedestal_Foot", 2.05, 1.85, 1.1, (0.0, 0.0, 0.55), 14, mat_pedestal)
    add_cylinder(parts, "Pedestal_Tower", 1.55, 1.30, 1.9, (0.0, 0.0, 2.05), 14, mat_pedestal)
    add_cylinder(parts, "Azimuth_Turntable", 1.45, 1.45, 0.45, (0.0, 0.0, 3.15), 16, mat_truss_steel)
    add_box(parts, "Yoke_LeftArm", (0.55, 0.75, 1.45), (-1.15, 0.0, 3.85), mat_truss_steel)
    add_box(parts, "Yoke_RightArm", (0.55, 0.75, 1.45), (1.15, 0.0, 3.85), mat_truss_steel)
    add_box(parts, "Yoke_Counterweight", (1.75, 1.35, 0.75), (0.0, -0.55, 3.85), mat_pedestal)

    tilt_euler = Euler((math.radians(38.0), 0.0, 0.0), "XYZ")
    dish_pivot = Vector((0.0, 0.0, 4.35))
    dish_parts: list[bpy.types.Object] = []

    dish_shell = build_parabolic_dish_mesh("Dish_ParabolicReflector", 3.9, 1.15, 0.16, 6, 24, mat_dish_white)
    dish_parts.append(dish_shell)
    add_cylinder(dish_parts, "Dish_RearHub", 1.25, 0.95, 0.85, (0.0, 0.0, -0.55), 14, mat_truss_steel)
    add_cylinder(dish_parts, "Feed_HornCone", 0.55, 0.26, 1.15, (0.0, 0.0, 0.58), 12, mat_feed_gold)

    apex_pos = Vector((0.0, 0.0, 3.15))
    strut_r = 2.45
    strut_z = 1.15 * ((strut_r / 3.9) ** 2)
    for leg_idx in range(4):
        ang = math.radians(45.0 + 90.0 * leg_idx)
        base_pt = Vector((strut_r * math.cos(ang), strut_r * math.sin(ang), strut_z - 0.04))
        add_beam_between(dish_parts, f"Quadrupod_Leg_{leg_idx}", base_pt, apex_pos, 0.11, mat_truss_steel)

    add_cylinder(dish_parts, "SubReflector_Dish", 0.68, 0.42, 0.32, (0.0, 0.0, 3.22), 14, mat_dish_white)
    add_cylinder(dish_parts, "SubReflector_Tip", 0.42, 0.08, 0.25, (0.0, 0.0, 3.48), 12, mat_feed_gold)

    tilt_mat = Matrix.Translation(dish_pivot) @ tilt_euler.to_matrix().to_4x4()
    for dp in dish_parts:
        dp.matrix_world = tilt_mat @ dp.matrix_world
        parts.append(dp)

    finalize_and_export(parts, "dsn_70m_dish", max_faces=2800, pivot_mode="bottom_center", target_height=8.0)


# ==============================================================================
# Group B2: All 10 Attachable Aerospace Subsystems (< 1200 faces each)
# ==============================================================================

def build_solar_array() -> None:
    """3-panel GaAs solar wing extending along -X from root deployment yoke at (0,0,0)."""
    reset_scene()
    mat_pv = make_material("Solar_PV_Blue", "#112244", metallic=0.32, roughness=0.18)
    mat_alu = make_material("Solar_AluFrame", "#CBD5E1", metallic=0.86, roughness=0.28)
    mat_back = make_material("Solar_Substrate", "#1E293B", metallic=0.50, roughness=0.48)
    mat_gold = make_material("Solar_HingeGold", "#D4AF37", metallic=0.90, roughness=0.24)

    parts: list[bpy.types.Object] = []

    # Root gimbal flange & yoke at X=0 extending toward -X
    add_cylinder(
        parts, "Root_Flange", 0.14, 0.14, 0.08, (-0.04, 0.0, 0.0), 12, mat_alu,
        rotation=(0.0, math.radians(90.0), 0.0)
    )
    add_box(parts, "Root_GimbalBlock", (0.14, 0.20, 0.12), (-0.11, 0.0, 0.0), mat_gold)
    add_beam_between(parts, "Yoke_Top", Vector((-0.14, 0.06, 0.0)), Vector((-0.44, 0.46, 0.0)), 0.045, mat_alu, 8)
    add_beam_between(parts, "Yoke_Bot", Vector((-0.14, -0.06, 0.0)), Vector((-0.44, -0.46, 0.0)), 0.045, mat_alu, 8)
    add_beam_between(parts, "Yoke_Cross", Vector((-0.42, -0.46, 0.0)), Vector((-0.42, 0.46, 0.0)), 0.04, mat_alu, 8)

    panel_w = 0.88
    panel_h = 1.16
    gap = 0.06
    start_x = -0.44

    for idx in range(3):
        cx = start_x - idx * (panel_w + gap) - panel_w * 0.5
        # Aluminum perimeter frame rails (solid outer rim)
        add_box(parts, f"Frame_Top_{idx}", (panel_w, 0.045, 0.045), (cx, panel_h * 0.5 - 0.02, 0.0), mat_alu)
        add_box(parts, f"Frame_Bot_{idx}", (panel_w, 0.045, 0.045), (cx, -panel_h * 0.5 + 0.02, 0.0), mat_alu)
        add_box(parts, f"Frame_Left_{idx}", (0.045, panel_h, 0.045), (cx - panel_w * 0.5 + 0.02, 0.0, 0.0), mat_alu)
        add_box(parts, f"Frame_Right_{idx}", (0.045, panel_h, 0.045), (cx + panel_w * 0.5 - 0.02, 0.0, 0.0), mat_alu)

        # Solid composite backing + raised dark-blue PV cells on both faces (top +Z and bottom -Z)
        add_box(parts, f"Panel_Back_{idx}", (panel_w - 0.06, panel_h - 0.06, 0.024), (cx, 0.0, 0.0), mat_back)
        add_box(parts, f"Panel_Cells_{idx}", (panel_w - 0.09, panel_h - 0.09, 0.032), (cx, 0.0, 0.002), mat_pv)

        # Silver cell busbar divider ribs
        for row_y in (-0.28, 0.0, 0.28):
            add_box(parts, f"Busbar_{idx}_{row_y:.2f}", (panel_w - 0.08, 0.018, 0.038), (cx, row_y, 0.002), mat_alu)

        # Gold hinge knuckles bridging panels
        hinge_x = start_x - idx * (panel_w + gap) + (gap * 0.5 if idx > 0 else 0.0)
        for hy in (-0.36, 0.36):
            add_cylinder(
                parts, f"Hinge_{idx}_{hy:.2f}", 0.035, 0.035, 0.11, (hinge_x, hy, 0.0), 8, mat_gold,
                rotation=(math.radians(90.0), 0.0, 0.0)
            )

    finalize_and_export(parts, "solar_array", max_faces=1150, pivot_mode="root_max_x", target_max_dim=3.2)


def build_rtg_cassini() -> None:
    """Authentic cylindrical MMRTG / Cassini generator with 8 radial cooling fins & base bracket."""
    reset_scene()
    mat_core = make_material("RTG_BronzeBlack", "#262423", metallic=0.45, roughness=0.55)
    mat_fin = make_material("RTG_FinCharcoal", "#3B3532", metallic=0.58, roughness=0.45)
    mat_dome = make_material("RTG_TitaniumCap", "#8A929E", metallic=0.86, roughness=0.30)
    mat_gold = make_material("RTG_GoldCollar", "#D4AF37", metallic=0.90, roughness=0.25)
    mat_mount = make_material("RTG_MountBracket", "#64748B", metallic=0.82, roughness=0.36)

    parts: list[bpy.types.Object] = []
    # Base mounting flange + structural gusset cradle at Z=0
    add_cylinder(parts, "Base_Flange", 0.26, 0.22, 0.08, (0.0, 0.0, 0.04), 14, mat_mount)
    add_box(parts, "Side_Bracket", (0.28, 0.34, 0.24), (0.0, 0.14, 0.15), mat_mount)
    add_cylinder(parts, "Gold_SensorCollar", 0.21, 0.21, 0.12, (0.0, 0.0, 0.14), 14, mat_gold)

    # Core GPHS finned housing cylinder (Z = 0.20 .. 1.24)
    add_cylinder(parts, "RTG_CoreDrum", 0.195, 0.195, 1.04, (0.0, 0.0, 0.72), 16, mat_core)
    add_cylinder(parts, "RTG_MidBand", 0.215, 0.215, 0.07, (0.0, 0.0, 0.72), 16, mat_dome)

    # 8 radial heat-dissipation fins
    for i in range(8):
        ang = i * (math.pi / 4.0)
        fx = math.cos(ang) * 0.29
        fy = math.sin(ang) * 0.29
        add_box(parts, f"Fin_{i}", (0.22, 0.032, 0.94), (fx, fy, 0.72), mat_fin, rotation=(0.0, 0.0, ang))

    # Top dome & instrumentation cap
    add_cylinder(parts, "Top_Collar", 0.20, 0.17, 0.09, (0.0, 0.0, 1.28), 14, mat_dome)
    add_cylinder(parts, "Top_Dome", 0.16, 0.06, 0.11, (0.0, 0.0, 1.38), 12, mat_gold)

    finalize_and_export(parts, "rtg_cassini", max_faces=1100, pivot_mode="bottom_center", target_max_dim=1.45)


def build_engine_ion() -> None:
    """NASA NEXT-C / NSTAR xenon ion thruster (top_center pivot at Z=0, nozzle downward -Z)."""
    reset_scene()
    mat_ti = make_material("Ion_Titanium", "#94A3B8", metallic=0.88, roughness=0.30)
    mat_dark = make_material("Ion_DischargeBody", "#334155", metallic=0.72, roughness=0.42)
    mat_alu = make_material("Ion_ShroudSilver", "#CBD5E1", metallic=0.85, roughness=0.28)
    mat_gold = make_material("Ion_ManifoldGold", "#D4AF37", metallic=0.90, roughness=0.24)
    mat_xenon = make_material(
        "Ion_XenonGrid", "#18B4FF", metallic=0.15, roughness=0.15,
        emission_hex="#18B4FF", emission_strength=2.6
    )

    parts: list[bpy.types.Object] = []
    # Top gimbal ring & structural mount (Z = 0.0 .. -0.07)
    add_cylinder(parts, "Gimbal_MountPlate", 0.28, 0.30, 0.06, (0.0, 0.0, -0.03), 16, mat_ti)
    add_cylinder(parts, "Gimbal_Collar", 0.24, 0.34, 0.08, (0.0, 0.0, -0.10), 16, mat_gold)

    # Cylindrical discharge chamber & structural ribs
    add_cylinder(parts, "Discharge_Chamber", 0.34, 0.38, 0.24, (0.0, 0.0, -0.25), 18, mat_dark)
    add_cylinder(parts, "Outer_ShroudRing", 0.40, 0.40, 0.06, (0.0, 0.0, -0.36), 18, mat_alu)
    for i in range(6):
        ang = i * (math.pi / 3.0)
        rx, ry = math.cos(ang) * 0.37, math.sin(ang) * 0.37
        add_box(parts, f"Chamber_Rib_{i}", (0.04, 0.04, 0.20), (rx, ry, -0.25), mat_ti, rotation=(0.0, 0.0, ang))

    # Accelerator nozzle lip & recessed glowing cyan xenon extraction grid
    add_cylinder(parts, "Nozzle_Rim", 0.39, 0.36, 0.09, (0.0, 0.0, -0.43), 18, mat_ti)
    add_cylinder(parts, "Xenon_Grid_Core", 0.31, 0.31, 0.03, (0.0, 0.0, -0.46), 18, mat_xenon)
    add_cylinder(parts, "Xenon_CenterKeeper", 0.08, 0.06, 0.06, (0.0, 0.0, -0.47), 10, mat_alu)

    # External hollow-cathode neutralizer assembly on side bracket
    add_box(parts, "Neutralizer_Bracket", (0.14, 0.06, 0.06), (0.39, 0.0, -0.34), mat_ti)
    add_cylinder(
        parts, "Neutralizer_Cathode", 0.04, 0.03, 0.18, (0.45, 0.0, -0.41), 10, mat_alu,
        rotation=(0.0, math.radians(-22.0), 0.0)
    )
    add_cylinder(
        parts, "Neutralizer_Tip", 0.025, 0.015, 0.04, (0.48, 0.0, -0.49), 8, mat_xenon,
        rotation=(0.0, math.radians(-22.0), 0.0)
    )

    finalize_and_export(parts, "engine_ion", max_faces=1100, pivot_mode="top_axis", target_max_dim=0.92)


def build_battery_pack() -> None:
    """Cryogenic 48 kWh Li-Ion battery enclosure with Kapton MLI panels & radiator fins."""
    reset_scene()
    mat_chassis = make_material("Batt_Anodized", "#1E293B", metallic=0.72, roughness=0.42)
    mat_gold = make_material("Batt_KaptonMLI", "#D4AF37", metallic=0.88, roughness=0.26)
    mat_alu = make_material("Batt_RadiatorAlu", "#CBD5E1", metallic=0.86, roughness=0.28)
    mat_flange = make_material("Batt_MountFlange", "#64748B", metallic=0.82, roughness=0.35)
    mat_warn = make_material("Batt_Disconnect", "#E06319", metallic=0.30, roughness=0.45)

    parts: list[bpy.types.Object] = []
    # Base mounting flange & corner lugs (Z = 0.0 .. 0.06)
    add_box(parts, "Base_Flange", (0.98, 0.68, 0.06), (0.0, 0.0, 0.03), mat_flange)
    # Main dark anodized enclosure
    add_box(parts, "Battery_Housing", (0.88, 0.58, 0.40), (0.0, 0.0, 0.26), mat_chassis)
    # Gold Kapton thermal blanket panels on front/back and sides
    add_box(parts, "MLI_FrontBack", (0.76, 0.61, 0.28), (0.0, 0.0, 0.26), mat_gold)
    add_box(parts, "MLI_Sides", (0.91, 0.44, 0.28), (0.0, 0.0, 0.26), mat_gold)
    # Top radiator cap + 6 cooling fins
    add_box(parts, "Top_Plate", (0.86, 0.56, 0.04), (0.0, 0.0, 0.48), mat_flange)
    for idx in range(6):
        fx = -0.35 + idx * 0.14
        add_box(parts, f"Rad_Fin_{idx}", (0.03, 0.50, 0.09), (fx, 0.0, 0.545), mat_alu)
    # High-current umbilical connector & safety plug
    add_cylinder(parts, "HV_Plug", 0.06, 0.06, 0.10, (0.30, -0.32, 0.26), 10, mat_alu, rotation=(math.radians(90.0), 0.0, 0.0))
    add_box(parts, "Arm_Plug", (0.08, 0.05, 0.08), (-0.28, -0.31, 0.26), mat_warn)

    finalize_and_export(parts, "battery_pack", max_faces=900, pivot_mode="bottom_center", target_max_dim=1.0)


def build_antenna_omni() -> None:
    """S-Band low-gain omni bicone/helical mast antenna with ground-plane & dielectric radome."""
    reset_scene()
    mat_base = make_material("Omni_BaseSteel", "#64748B", metallic=0.85, roughness=0.34)
    mat_mast = make_material("Omni_MastAlu", "#CBD5E1", metallic=0.86, roughness=0.28)
    mat_gold = make_material("Omni_GoldCollar", "#D4AF37", metallic=0.90, roughness=0.24)
    mat_radome = make_material("Omni_RadomeWhite", "#F1F5F9", metallic=0.12, roughness=0.35)

    parts: list[bpy.types.Object] = []
    # Bolted circular mounting collar at Z=0
    add_cylinder(parts, "Mount_Flange", 0.14, 0.12, 0.05, (0.0, 0.0, 0.025), 14, mat_base)
    add_cylinder(parts, "Waveguide_Base", 0.08, 0.06, 0.08, (0.0, 0.0, 0.09), 12, mat_gold)
    add_cylinder(parts, "Coax_Mast", 0.042, 0.038, 0.52, (0.0, 0.0, 0.39), 12, mat_mast)

    # 4 radial ground-plane monopoles
    for i in range(4):
        ang = i * (math.pi * 0.5)
        p1 = Vector((0.04 * math.cos(ang), 0.04 * math.sin(ang), 0.16))
        p2 = Vector((0.20 * math.cos(ang), 0.20 * math.sin(ang), 0.10))
        add_beam_between(parts, f"GroundPlane_{i}", p1, p2, 0.018, mat_mast, 6)

    # Upper bicone choke & dielectric radome cap
    add_cylinder(parts, "RF_Choke", 0.085, 0.055, 0.06, (0.0, 0.0, 0.65), 12, mat_gold)
    add_cylinder(parts, "Helix_Sleeve", 0.068, 0.068, 0.13, (0.0, 0.0, 0.74), 12, mat_radome)
    add_cylinder(parts, "Radome_Tip", 0.064, 0.02, 0.10, (0.0, 0.0, 0.84), 12, mat_radome)
    add_uv_sphere(parts, "Tip_Finial", 0.024, 10, 6, (0.0, 0.0, 0.89), mat_gold)

    finalize_and_export(parts, "antenna_omni", max_faces=900, pivot_mode="bottom_center", target_max_dim=0.90)


def build_sensor_lidar() -> None:
    """NASA SPLICE Hazard Avoidance LiDAR & Star Tracker TRN unit with dual cyan lenses."""
    reset_scene()
    mat_alu = make_material("Lidar_BrushedAlu", "#94A3B8", metallic=0.86, roughness=0.28)
    mat_body = make_material("Lidar_DarkChassis", "#334155", metallic=0.72, roughness=0.40)
    mat_gold = make_material("Lidar_GoldVisor", "#D4AF37", metallic=0.90, roughness=0.24)
    mat_cyan = make_material(
        "Lidar_CyanOptics", "#0EA5E9", metallic=0.20, roughness=0.08,
        emission_hex="#0284C7", emission_strength=1.1
    )

    parts: list[bpy.types.Object] = []
    # Machined aluminum baseplate at Z=0
    add_box(parts, "Baseplate", (0.56, 0.52, 0.05), (0.0, 0.0, 0.025), mat_alu)
    # Main optical bench chassis
    add_box(parts, "Chassis_Main", (0.48, 0.44, 0.28), (0.0, 0.02, 0.19), mat_body)
    add_box(parts, "Chassis_Shell", (0.50, 0.36, 0.22), (0.0, 0.04, 0.19), mat_alu)
    # Top thermal fins
    for i in range(4):
        fx = -0.15 + i * 0.10
        add_box(parts, f"Top_Fin_{i}", (0.025, 0.34, 0.06), (fx, 0.04, 0.36), mat_alu)
    # Angled Star Tracker baffle on top rear
    add_cylinder(
        parts, "StarTracker_Baffle", 0.075, 0.055, 0.16, (-0.12, 0.12, 0.40), 12, mat_gold,
        rotation=(math.radians(-30.0), 0.0, 0.0)
    )
    # Gold thermal visor hood protruding toward -Y (Godot +Z forward)
    add_box(parts, "Thermal_Visor_Top", (0.44, 0.18, 0.03), (0.0, -0.26, 0.30), mat_gold)
    add_box(parts, "Thermal_Visor_Left", (0.03, 0.18, 0.20), (-0.205, -0.26, 0.21), mat_gold)
    add_box(parts, "Thermal_Visor_Right", (0.03, 0.18, 0.20), (0.205, -0.26, 0.21), mat_gold)
    # Dual laser emitter & receiver barrels facing -Y (Godot +Z)
    for idx, lx in enumerate((-0.11, 0.11)):
        add_cylinder(
            parts, f"Lens_Barrel_{idx}", 0.078, 0.070, 0.14, (lx, -0.24, 0.20), 14, mat_alu,
            rotation=(math.radians(90.0), 0.0, 0.0)
        )
        add_cylinder(
            parts, f"Lens_Optic_{idx}", 0.062, 0.062, 0.03, (lx, -0.305, 0.20), 14, mat_cyan,
            rotation=(math.radians(90.0), 0.0, 0.0)
        )

    finalize_and_export(parts, "sensor_lidar", max_faces=1000, pivot_mode="bottom_center", target_max_dim=0.72)


def build_payload_drill() -> None:
    """NASA TRIDENT regolith ice drill tower with twin rails, gold drive head & spiral auger."""
    reset_scene()
    mat_rail = make_material("Drill_AluRails", "#CBD5E1", metallic=0.86, roughness=0.28)
    mat_yoke = make_material("Drill_YokeDark", "#334155", metallic=0.72, roughness=0.40)
    mat_gold = make_material("Drill_MotorGold", "#D4AF37", metallic=0.90, roughness=0.25)
    mat_steel = make_material("Drill_AugerSteel", "#64748B", metallic=0.88, roughness=0.32)

    parts: list[bpy.types.Object] = []
    # Base stabilizing deck collar & rear mount struts at Z=0
    add_cylinder(parts, "Base_GuideBushing", 0.16, 0.14, 0.08, (0.0, 0.0, 0.04), 12, mat_yoke)
    add_box(parts, "Mount_Plate", (0.36, 0.22, 0.05), (0.0, 0.08, 0.025), mat_steel)
    add_beam_between(parts, "Strut_L", Vector((-0.14, 0.16, 0.05)), Vector((-0.16, 0.0, 0.65)), 0.04, mat_steel)
    add_beam_between(parts, "Strut_R", Vector((0.14, 0.16, 0.05)), Vector((0.16, 0.0, 0.65)), 0.04, mat_steel)

    # Twin vertical guide rails
    add_box(parts, "Rail_Left", (0.05, 0.06, 1.34), (-0.16, 0.0, 0.69), mat_rail)
    add_box(parts, "Rail_Right", (0.05, 0.06, 1.34), (0.16, 0.0, 0.69), mat_rail)
    add_box(parts, "Yoke_Mid", (0.38, 0.10, 0.06), (0.0, 0.0, 0.65), mat_yoke)
    add_box(parts, "Yoke_Top", (0.40, 0.12, 0.07), (0.0, 0.0, 1.36), mat_yoke)

    # Gold-wrapped rotary-percussive auger motor head
    add_box(parts, "Motor_Head", (0.26, 0.22, 0.28), (0.0, 0.0, 1.06), mat_gold)
    add_cylinder(parts, "Drive_Chuck", 0.08, 0.07, 0.10, (0.0, 0.0, 0.88), 10, mat_steel)

    # Central auger shaft + segmented spiral flute collars
    add_cylinder(parts, "Auger_Shaft", 0.036, 0.028, 0.84, (0.0, 0.0, 0.44), 10, mat_steel)
    for fi in range(9):
        fz = 0.12 + fi * 0.085
        add_cylinder(
            parts, f"Auger_Flute_{fi}", 0.072, 0.058, 0.038, (0.0, 0.0, fz), 10, mat_rail,
            rotation=(math.radians(16.0), 0.0, fi * 0.7)
        )

    finalize_and_export(parts, "payload_drill", max_faces=1050, pivot_mode="bottom_center", target_max_dim=1.40)


def build_payload_msolo() -> None:
    """MSolo quadrupole mass spectrometer with white radiator body, gold MLI & intake snorkel."""
    reset_scene()
    mat_base = make_material("MSolo_BaseAlu", "#64748B", metallic=0.84, roughness=0.34)
    mat_white = make_material("MSolo_WhiteThermal", "#F1F5F9", metallic=0.14, roughness=0.38)
    mat_gold = make_material("MSolo_GoldMLI", "#D4AF37", metallic=0.90, roughness=0.25)
    mat_steel = make_material("MSolo_Stainless", "#CBD5E1", metallic=0.88, roughness=0.24)

    parts: list[bpy.types.Object] = []
    # Deck baseplate at Z=0
    add_box(parts, "Baseplate", (0.58, 0.64, 0.05), (0.0, 0.0, 0.025), mat_base)
    # Main white spectrometer housing + gold MLI trim band
    add_box(parts, "Body_White", (0.50, 0.54, 0.34), (0.0, 0.0, 0.22), mat_white)
    add_box(parts, "Body_GoldTrim", (0.53, 0.46, 0.20), (0.0, 0.0, 0.20), mat_gold)
    # Top quadrupole analyzer barrel
    add_cylinder(parts, "Quadrupole_Barrel", 0.14, 0.14, 0.24, (0.0, 0.06, 0.48), 14, mat_base)
    add_cylinder(parts, "Quadrupole_Cap", 0.16, 0.14, 0.05, (0.0, 0.06, 0.59), 14, mat_gold)
    # Angled stainless-steel ion-source snorkel tube facing -Y (Godot +Z)
    add_cylinder(
        parts, "Snorkel_Tube", 0.05, 0.05, 0.34, (0.0, -0.22, 0.40), 12, mat_steel,
        rotation=(math.radians(65.0), 0.0, 0.0)
    )
    add_cylinder(
        parts, "Snorkel_Inlet", 0.075, 0.048, 0.08, (0.0, -0.38, 0.33), 12, mat_gold,
        rotation=(math.radians(65.0), 0.0, 0.0)
    )

    finalize_and_export(parts, "payload_msolo", max_faces=900, pivot_mode="bottom_center", target_max_dim=0.78)


def build_payload_sar() -> None:
    """Mini-RF L-Band Synthetic Aperture Radar (SAR) phased-array panel with honeycomb backing."""
    reset_scene()
    mat_frame = make_material("SAR_AluFrame", "#94A3B8", metallic=0.86, roughness=0.28)
    mat_ribs = make_material("SAR_HoneycombRibs", "#475569", metallic=0.72, roughness=0.44)
    mat_face = make_material("SAR_PhasedArray", "#1E3A5F", metallic=0.35, roughness=0.25)
    mat_patch = make_material("SAR_Microstrip", "#E2E8F0", metallic=0.65, roughness=0.28)
    mat_gold = make_material("SAR_FeedGold", "#D4AF37", metallic=0.90, roughness=0.24)

    parts: list[bpy.types.Object] = []
    # Base hinge mount bracket at Z=0
    add_box(parts, "Base_MountPlate", (0.54, 0.34, 0.06), (0.0, 0.0, 0.03), mat_ribs)
    add_cylinder(parts, "Hinge_Pin", 0.045, 0.045, 0.48, (0.0, -0.04, 0.09), 10, mat_gold, rotation=(0.0, math.radians(90.0), 0.0))

    # Tilted radar panel assembly (tilted 24 deg forward around X so active face points toward -Y / +Z_g)
    panel_parts: list[bpy.types.Object] = []
    add_box(panel_parts, "SAR_Frame", (1.10, 0.07, 0.68), (0.0, 0.0, 0.46), mat_frame)
    add_box(panel_parts, "SAR_Substrate", (1.00, 0.08, 0.58), (0.0, -0.006, 0.46), mat_face)
    # 2x4 phased-array microstrip patches on front face (-Y)
    for row in (-0.14, 0.14):
        for col in (-0.33, -0.11, 0.11, 0.33):
            add_box(panel_parts, f"Patch_{row}_{col}", (0.16, 0.02, 0.20), (col, -0.048, 0.46 + row), mat_patch)
    # Rear honeycomb stiffening ribs (+Y)
    for rx in (-0.36, 0.0, 0.36):
        add_box(panel_parts, f"Rib_Vert_{rx}", (0.04, 0.08, 0.62), (rx, 0.055, 0.46), mat_ribs)
    add_box(panel_parts, "Rib_Horiz", (1.02, 0.08, 0.04), (0.0, 0.055, 0.46), mat_ribs)

    tilt_mat = Matrix.Translation(Vector((0.0, -0.04, 0.10))) @ Euler((math.radians(-24.0), 0.0, 0.0), "XYZ").to_matrix().to_4x4()
    for pp in panel_parts:
        pp.matrix_world = tilt_mat @ pp.matrix_world
        parts.append(pp)

    # Rear diagonal deployment struts connecting base plate to rear ribs
    add_beam_between(parts, "Strut_L", Vector((-0.20, 0.12, 0.06)), Vector((-0.36, 0.18, 0.54)), 0.04, mat_frame, 6)
    add_beam_between(parts, "Strut_R", Vector((0.20, 0.12, 0.06)), Vector((0.36, 0.18, 0.54)), 0.04, mat_frame, 6)

    finalize_and_export(parts, "payload_sar", max_faces=950, pivot_mode="bottom_center", target_max_dim=1.25)


def build_shield_heavy() -> None:
    """Curved conformal Whipple radiation/thermal armor panel hugging hull bay between legs."""
    reset_scene()
    mat_ti = make_material("Shield_Titanium", "#94A3B8", metallic=0.88, roughness=0.32)
    mat_kapton = make_material("Shield_GoldKapton", "#D4AF37", metallic=0.90, roughness=0.26)
    mat_poly = make_material("Shield_PolyCore", "#334155", metallic=0.35, roughness=0.55)

    parts: list[bpy.types.Object] = []
    # Cylindrical arc centered at (0, +1.05, 0) so the curved plate sits around Y_b ~ 0 (Godot Z ~ 0),
    # bulging outward toward -Y_b (Godot +Z) while standoffs anchor inward toward +Y_b (Godot -Z).
    center_y = 1.05
    # Inner polyethylene-boron bumper layer
    add_curved_arc_plate(parts, "Inner_PolyPlate", 1.04, 1.09, 0.50, 56.0, center_y, 0.0, 12, mat_poly)
    # Middle titanium Whipple plate
    add_curved_arc_plate(parts, "Mid_TitaniumPlate", 1.11, 1.15, 0.48, 54.0, center_y, 0.0, 12, mat_ti)
    # Outer gold Kapton thermal/MLI armor overlay
    add_curved_arc_plate(parts, "Outer_KaptonPlate", 1.155, 1.18, 0.40, 48.0, center_y, 0.0, 12, mat_kapton)

    # Structural bolt ribs & inward standoffs connecting into lander bus hull wall
    for ang_deg in (-22.0, 0.0, 22.0):
        ang = math.radians(ang_deg)
        sx, cy = math.sin(ang), -math.cos(ang)
        add_box(
            parts, f"BoltRib_{ang_deg:.0f}", (0.05, 0.06, 0.52),
            (1.17 * sx, center_y + 1.17 * cy, 0.0), mat_ti, rotation=(0.0, 0.0, -ang)
        )
        for sz in (-0.15, 0.15):
            p_outer = Vector((1.05 * sx, center_y + 1.05 * cy, sz))
            p_inner = Vector((0.82 * sx, center_y + 0.82 * cy, sz))
            add_beam_between(parts, f"Standoff_{ang_deg:.0f}_{sz:.2f}", p_inner, p_outer, 0.045, mat_ti, 6)

    finalize_and_export(parts, "shield_heavy", max_faces=900, pivot_mode="center", target_max_dim=1.08)


def main() -> None:
    print(f"Models Directory: {MODELS_DIR}")
    if not MODELS_DIR.exists():
        raise FileNotFoundError(f"Missing models directory: {MODELS_DIR}")

    # Task 1: Pre-repair diagnostic audit
    audit_catalog("PRE-REPAIR DIAGNOSTIC AUDIT (ALL 16 GLB)")

    # Task 2.1: Protect Group A
    process_group_a()

    # Task 2.2: Rebuild Group B1
    print("\n--- Rebuilding Group B1 (Environment & Launchers) ---")
    build_sls_block1()
    build_vab_gantry()
    build_dsn_70m_dish()

    # Task 2.3: Rebuild/Upgrade all 10 Group B2 Subsystems
    print("\n--- Rebuilding Group B2 (10 Attachable Aerospace Subsystems) ---")
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

    # Task 5: Post-repair diagnostic audit
    post = audit_catalog("POST-REPAIR VERIFICATION AUDIT (ALL 16 GLB)")

    # Budget assertions
    for fname in GROUP_B1_FILES:
        assert post[fname].faces < 3000, f"{fname} exceeded 3000 faces: {post[fname].faces}"
    for fname in GROUP_B2_FILES:
        assert post[fname].faces < 1200, f"{fname} exceeded 1200 faces: {post[fname].faces}"
        assert not post[fname].has_torn_artifacts, f"{fname} has non-manifold/torn artifacts"
    for fname in GROUP_A_FILES:
        assert not post[fname].is_primitive_box, f"Group A {fname} corrupted"


if __name__ == "__main__":
    main()
