"""Repair and rebuild the three corrupted NASA .glb models for Godot 4 (WebGL).

Repairs:
1. sls_block1.glb   -> 18.0 m height, pivot at base Y=0 (Godot), < 2500 faces
2. vab_gantry.glb   -> 20.0 m height, pivot at base Y=0 (Godot), < 3500 faces
3. dsn_70m_dish.glb -> 8.0 m height, pivot at base Y=0 (Godot), < 2500 faces

All meshes are manifold, outward-normal consistent (normals_make_consistent(inside=False)),
double-sided (use_backface_culling = False), and exported with Y-up for Godot 4.3+.
"""

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parent.parent
INPUT_DIR = REPO_ROOT / "assets"
OUTPUT_DIR = REPO_ROOT / "space-app-challenge-2026---astra-rex" / "assets" / "models"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


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
    metallic: float = 0.25,
    roughness: float = 0.5,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = hex_to_linear_rgba(hex_color)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def get_world_bbox(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    min_v = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    max_v = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return min_v, max_v


def finalize_mesh_object(
    parts: list[bpy.types.Object],
    name: str,
    target_height: float,
    max_faces: int,
) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]

    # Clear parenting safely before joining
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if len(parts) > 1:
        bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = f"{name}_mesh"

    # Scale uniformly so height (Z in Blender -> Y in Godot) matches target_height
    min_v, max_v = get_world_bbox(obj)
    cur_h = max_v.z - min_v.z
    if cur_h > 1e-5:
        s = target_height / cur_h
        obj.scale = (s, s, s)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Center X/Y on origin and place bottom exactly at Z=0
    min_v, max_v = get_world_bbox(obj)
    cx = (min_v.x + max_v.x) * 0.5
    cy = (min_v.y + max_v.y) * 0.5
    obj.location -= Vector((cx, cy, min_v.z))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Clean normals & double-sided material flags
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=False)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    for mat in obj.data.materials:
        if mat:
            mat.use_backface_culling = False

    # Triangulate and verify face budget
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

    obj.data.validate(verbose=False)
    return obj


def add_cylinder(
    bm_list: list[bpy.types.Object],
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
    bm_list.append(obj)
    return obj


def add_box(
    bm_list: list[bpy.types.Object],
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
    bm_list.append(obj)
    return obj


def add_beam_between(
    bm_list: list[bpy.types.Object],
    name: str,
    p1: Vector,
    p2: Vector,
    thickness: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    delta = p2 - p1
    length = delta.length
    mid = (p1 + p2) * 0.5
    quat = delta.normalized().to_track_quat("Z", "Y")
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((thickness, thickness, length)), verts=bm.verts[:])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj.location = mid
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = quat
    obj.data.materials.append(mat)
    bm_list.append(obj)
    return obj


def export_glb(obj: bpy.types.Object, filename: str) -> None:
    out_path = OUTPUT_DIR / filename
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
    size_kb = out_path.stat().st_size / 1024.0
    print(f"[EXPORTED] {filename}: {len(obj.data.polygons)} tris, {size_kb:.1f} KB")


# ==============================================================================
# 1. NASA SLS Block 1 (18.0 m height, pivot at base Y=0, < 2500 faces)
# ==============================================================================
def build_sls_block1() -> None:
    print("\n--- Rebuilding sls_block1.glb ---")
    reset_scene()

    mat_orange = make_material("SLS_CoreOrange", "#D96B27", metallic=0.12, roughness=0.62)
    mat_white = make_material("SLS_White", "#E9EDF2", metallic=0.10, roughness=0.45)
    mat_dark = make_material("SLS_Charcoal", "#20242C", metallic=0.72, roughness=0.42)
    mat_steel = make_material("SLS_Steel", "#8A929E", metallic=0.88, roughness=0.30)

    parts: list[bpy.types.Object] = []

    # Real NASA SLS Block 1 proportions (total ~98.1 m, scaled down cleanly to 18.0 m)
    # 4x RS-25 Engine Bells (Z = 0.0 .. 3.2 m)
    for idx, (ex, ey) in enumerate([(1.55, 1.55), (-1.55, 1.55), (-1.55, -1.55), (1.55, -1.55)]):
        add_cylinder(parts, f"RS25_Bell_{idx}", 1.15, 0.45, 3.2, (ex, ey, 1.6), 14, mat_dark)
        add_cylinder(parts, f"RS25_Powerhead_{idx}", 0.55, 0.65, 1.0, (ex, ey, 3.4), 10, mat_steel)

    # Core Stage Engine Section + Boat-tail (Z = 3.2 .. 6.2 m)
    add_cylinder(parts, "Core_EngineSection", 3.9, 4.2, 3.0, (0.0, 0.0, 4.7), 24, mat_white)

    # Core Stage SOFI Orange Tank (Z = 6.2 .. 64.6 m, 4.2 m radius = 8.4 m diameter)
    add_cylinder(parts, "Core_OrangeTank", 4.2, 4.2, 58.4, (0.0, 0.0, 35.4), 24, mat_orange)
    # Core Stage intertank dark structural ring + top flange
    add_cylinder(parts, "Core_IntertankRing", 4.24, 4.24, 1.6, (0.0, 0.0, 48.0), 24, mat_dark)
    add_cylinder(parts, "Core_ForwardRing", 4.23, 4.23, 1.0, (0.0, 0.0, 64.1), 24, mat_dark)

    # 2x Flanking Solid Rocket Boosters (SRBs, X = +/- 6.35 m)
    for side, sx in [("Port", -6.35), ("Starboard", 6.35)]:
        # Aft skirt (Z = 0.6 .. 4.4)
        add_cylinder(parts, f"SRB_{side}_AftSkirt", 2.35, 1.88, 3.8, (sx, 0.0, 2.5), 18, mat_dark)
        # Main 5-segment white motor casing (Z = 4.4 .. 48.6)
        add_cylinder(parts, f"SRB_{side}_Body", 1.85, 1.85, 44.2, (sx, 0.0, 26.5), 18, mat_white)
        # Characteristic NASA black roll-pattern bands
        add_cylinder(parts, f"SRB_{side}_BandLow", 1.88, 1.88, 1.8, (sx, 0.0, 10.0), 18, mat_dark)
        add_cylinder(parts, f"SRB_{side}_BandHigh", 1.88, 1.88, 2.2, (sx, 0.0, 44.5), 18, mat_dark)
        # Forward skirt & Ogive nose cone (Z = 48.6 .. 55.2)
        add_cylinder(parts, f"SRB_{side}_NoseBase", 1.85, 1.45, 2.6, (sx, 0.0, 49.9), 18, mat_white)
        add_cylinder(parts, f"SRB_{side}_NoseTip", 1.45, 0.10, 4.0, (sx, 0.0, 53.2), 18, mat_white)
        add_cylinder(parts, f"SRB_{side}_Cap", 0.12, 0.02, 0.4, (sx, 0.0, 55.4), 12, mat_dark)
        # Structural attach struts to Core Stage
        sign = 1.0 if sx < 0 else -1.0
        add_box(parts, f"SRB_{side}_StrutLow", (2.6, 1.1, 0.8), (sx + sign * 1.4, 0.0, 5.2), mat_steel)
        add_box(parts, f"SRB_{side}_StrutHigh", (2.6, 0.9, 0.8), (sx + sign * 1.4, 0.0, 47.8), mat_steel)

    # LVSA Interstage Adapter (Z = 64.6 .. 72.8 m, tapers 4.2 -> 2.55 m)
    add_cylinder(parts, "LVSA_Adapter", 4.2, 2.55, 8.2, (0.0, 0.0, 68.7), 24, mat_white)
    add_cylinder(parts, "LVSA_DarkBand", 2.58, 2.58, 0.8, (0.0, 0.0, 72.4), 20, mat_dark)

    # Upper ICPS Stage (Z = 72.8 .. 79.0 m)
    add_cylinder(parts, "ICPS_Stage", 2.55, 2.55, 6.2, (0.0, 0.0, 75.9), 20, mat_white)
    add_cylinder(parts, "Orion_StageAdapter", 2.55, 2.55, 1.2, (0.0, 0.0, 79.6), 20, mat_dark)

    # Orion MPCV Service Module & Crew Fairing (Z = 80.2 .. 87.2 m)
    add_cylinder(parts, "Orion_ESM", 2.52, 2.52, 4.2, (0.0, 0.0, 82.3), 20, mat_white)
    add_cylinder(parts, "Orion_Fairing", 2.52, 1.85, 2.8, (0.0, 0.0, 85.8), 20, mat_white)

    # Launch Abort System (LAS) Ogive & Escape Tower (Z = 87.2 .. 98.1 m)
    add_cylinder(parts, "LAS_Ogive", 1.85, 0.72, 3.8, (0.0, 0.0, 89.1), 16, mat_white)
    add_cylinder(parts, "LAS_Tower", 0.58, 0.42, 5.5, (0.0, 0.0, 93.75), 14, mat_white)
    add_cylinder(parts, "LAS_NoseCone", 0.42, 0.05, 1.6, (0.0, 0.0, 97.3), 12, mat_dark)

    sls = finalize_mesh_object(parts, "sls_block1", target_height=18.0, max_faces=2450)
    export_glb(sls, "sls_block1.glb")


# ==============================================================================
# 2. VAB Mobile Launch Gantry Tower (20.0 m height, pivot at base Y=0, < 3500 faces)
# ==============================================================================
def build_vab_gantry() -> None:
    print("\n--- Rebuilding vab_gantry.glb ---")
    reset_scene()

    mat_steel = make_material("Gantry_SteelGray", "#64748B", metallic=0.78, roughness=0.42)
    mat_deck = make_material("Gantry_DeckPlate", "#283244", metallic=0.55, roughness=0.55)
    mat_orange = make_material("Gantry_SafetyOrange", "#E06319", metallic=0.35, roughness=0.45)
    mat_core = make_material("Gantry_ElevatorCore", "#1E293B", metallic=0.45, roughness=0.58)

    parts: list[bpy.types.Object] = []

    # Ground Base Launch Plinth (Z = 0.0 .. 0.8 m)
    add_box(parts, "Gantry_BasePlinth", (6.0, 6.0, 0.8), (0.0, 0.0, 0.4), mat_deck)

    # 4 Continuous Vertical Steel Corner Columns (Z = 0.0 .. 19.2 m)
    col_xy = 2.4
    for ix, cx in enumerate([-col_xy, col_xy]):
        for iy, cy in enumerate([-col_xy, col_xy]):
            add_box(parts, f"Column_{ix}_{iy}", (0.36, 0.36, 19.2), (cx, cy, 9.6), mat_steel)

    # Central Elevator Shaft Core (Z = 0.0 .. 19.2 m)
    add_box(parts, "Elevator_Shaft_Core", (1.5, 1.5, 19.2), (0.0, 0.0, 9.6), mat_core)

    # 5 Horizontal Access Decks + Perimeter Safety Railings + Bay X-Bracing Trusses
    deck_levels = [3.8, 7.6, 11.4, 15.2, 19.0]
    prev_z = 0.8

    for lvl_idx, dz in enumerate(deck_levels):
        # Solid steel floor deck connected directly to all 4 columns and elevator core
        add_box(parts, f"AccessDeck_{lvl_idx}", (5.2, 5.2, 0.26), (0.0, 0.0, dz), mat_deck)

        # Perimeter horizontal tie-beams & top safety guardrails
        rail_z = dz + 0.55
        for side_idx, (p_a, p_b) in enumerate([
            (Vector((-col_xy, -col_xy, dz)), Vector((col_xy, -col_xy, dz))),
            (Vector((col_xy, -col_xy, dz)), Vector((col_xy, col_xy, dz))),
            (Vector((col_xy, col_xy, dz)), Vector((-col_xy, col_xy, dz))),
            (Vector((-col_xy, col_xy, dz)), Vector((-col_xy, -col_xy, dz))),
        ]):
            # Guardrail bar
            add_beam_between(
                parts,
                f"Rail_{lvl_idx}_{side_idx}",
                Vector((p_a.x, p_a.y, rail_z)),
                Vector((p_b.x, p_b.y, rail_z)),
                0.08,
                mat_steel,
            )
            # X-bracing diagonals on all 4 sides between prev_z and dz
            b1 = Vector((p_a.x, p_a.y, prev_z))
            b2 = Vector((p_b.x, p_b.y, prev_z))
            t1 = Vector((p_a.x, p_a.y, dz))
            t2 = Vector((p_b.x, p_b.y, dz))
            add_beam_between(parts, f"XBraceA_{lvl_idx}_{side_idx}", b1, t2, 0.13, mat_steel)
            add_beam_between(parts, f"XBraceB_{lvl_idx}_{side_idx}", b2, t1, 0.13, mat_steel)

        prev_z = dz

    # Two NASA Crew / Umbilical Swing Arms extending +X from tower
    for arm_idx, az in enumerate([11.55, 15.35]):
        add_box(parts, f"UmbilicalArm_{arm_idx}", (3.2, 0.65, 0.45), (3.8, 0.0, az), mat_orange)

    # Roof Hammerhead Crane & Lightning Mast (Z = 19.1 .. 20.6 m)
    add_box(parts, "Roof_CraneBoom", (4.8, 1.1, 0.65), (0.8, 0.0, 19.55), mat_orange)
    add_cylinder(parts, "Roof_LightningMast", 0.14, 0.03, 1.8, (0.0, 0.0, 20.4), 8, mat_steel)

    gantry = finalize_mesh_object(parts, "vab_gantry", target_height=20.0, max_faces=3400)
    export_glb(gantry, "vab_gantry.glb")


# ==============================================================================
# 3. NASA DSN 70m Parabolic Antenna (8.0 m height, pivot at base Y=0, < 2500 faces)
# ==============================================================================
def build_parabolic_dish_mesh(
    name: str,
    radius: float,
    depth: float,
    thickness: float,
    rings: int,
    sectors: int,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    """Generates a watertight, double-walled solid parabolic dish (front + back shell)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()

    def ring_z(r: float) -> float:
        return depth * ((r / radius) ** 2)

    # Front surface vertices (from center to rim)
    front_center = bm.verts.new((0.0, 0.0, 0.0))
    back_center = bm.verts.new((0.0, 0.0, -thickness))

    front_rings: list[list[bmesh.types.BMVert]] = []
    back_rings: list[list[bmesh.types.BMVert]] = []

    for ri in range(1, rings + 1):
        frac = float(ri) / float(rings)
        r = radius * frac
        z_f = ring_z(r)
        # Slightly thicker near hub for realistic structural backing
        z_b = z_f - thickness * (1.35 - 0.55 * frac)
        f_ring = []
        b_ring = []
        for si in range(sectors):
            ang = 2.0 * math.pi * float(si) / float(sectors)
            x = r * math.cos(ang)
            y = r * math.sin(ang)
            f_ring.append(bm.verts.new((x, y, z_f)))
            b_ring.append(bm.verts.new((x, y, z_b)))
        front_rings.append(f_ring)
        back_rings.append(b_ring)

    # Center fan triangles (front faces up +Z, back faces down -Z)
    for si in range(sectors):
        si_next = (si + 1) % sectors
        bm.faces.new((front_center, front_rings[0][si], front_rings[0][si_next]))
        bm.faces.new((back_center, back_rings[0][si_next], back_rings[0][si]))

    # Concentric quads for front & back surfaces
    for ri in range(rings - 1):
        for si in range(sectors):
            si_next = (si + 1) % sectors
            bm.faces.new((
                front_rings[ri][si],
                front_rings[ri + 1][si],
                front_rings[ri + 1][si_next],
                front_rings[ri][si_next],
            ))
            bm.faces.new((
                back_rings[ri][si_next],
                back_rings[ri + 1][si_next],
                back_rings[ri + 1][si],
                back_rings[ri][si],
            ))

    # Solid rim wall connecting outer front ring to outer back ring
    f_outer = front_rings[-1]
    b_outer = back_rings[-1]
    for si in range(sectors):
        si_next = (si + 1) % sectors
        bm.faces.new((f_outer[si], b_outer[si], b_outer[si_next], f_outer[si_next]))

    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat)
    return obj


def build_dsn_70m_dish() -> None:
    print("\n--- Rebuilding dsn_70m_dish.glb ---")
    reset_scene()

    mat_dish_white = make_material("DSN_DishWhite", "#EDF2F7", metallic=0.15, roughness=0.40)
    mat_truss_steel = make_material("DSN_TrussSteel", "#64748B", metallic=0.80, roughness=0.38)
    mat_pedestal = make_material("DSN_PedestalConcrete", "#334155", metallic=0.25, roughness=0.68)
    mat_feed_gold = make_material("DSN_FeedHornGold", "#D9A426", metallic=0.88, roughness=0.25)

    parts: list[bpy.types.Object] = []

    # 1. Azimuth-Elevation Pedestal Base sitting solidly on Z = 0.0
    add_cylinder(parts, "Pedestal_Foot", 2.05, 1.85, 1.1, (0.0, 0.0, 0.55), 12, mat_pedestal)
    add_cylinder(parts, "Pedestal_Tower", 1.55, 1.30, 1.9, (0.0, 0.0, 2.05), 12, mat_pedestal)
    # Azimuth turntable & Alidade elevation yoke arms
    add_cylinder(parts, "Azimuth_Turntable", 1.45, 1.45, 0.45, (0.0, 0.0, 3.15), 16, mat_truss_steel)
    add_box(parts, "Yoke_LeftArm", (0.55, 0.75, 1.45), (-1.15, 0.0, 3.85), mat_truss_steel)
    add_box(parts, "Yoke_RightArm", (0.55, 0.75, 1.45), (1.15, 0.0, 3.85), mat_truss_steel)
    add_box(parts, "Yoke_Counterweight", (1.75, 1.35, 0.75), (0.0, -0.55, 3.85), mat_pedestal)

    # 2. Tilted Dish Assembly (tilted 38 deg forward/upward around X for dramatic DTE sky tracking)
    dish_tilt_deg = 38.0
    tilt_euler = Euler((math.radians(dish_tilt_deg), 0.0, 0.0), "XYZ")
    dish_pivot = Vector((0.0, 0.0, 4.35))

    dish_parts: list[bpy.types.Object] = []

    # Solid parabolic reflector dish (radius 3.9 m, depth 1.15 m, watertight double shell)
    dish_shell = build_parabolic_dish_mesh(
        name="Dish_ParabolicReflector",
        radius=3.9,
        depth=1.15,
        thickness=0.16,
        rings=6,
        sectors=24,
        mat=mat_dish_white,
    )
    dish_parts.append(dish_shell)

    # Rear elevation structural hub & ring truss
    add_cylinder(dish_parts, "Dish_RearHub", 1.25, 0.95, 0.85, (0.0, 0.0, -0.55), 12, mat_truss_steel)

    # Central Cassegrain Feed Horn Cone
    add_cylinder(dish_parts, "Feed_HornCone", 0.55, 0.26, 1.15, (0.0, 0.0, 0.58), 12, mat_feed_gold)

    # Quadrupod Feed-Horn Support Struts (4 legs from mid-dish to apex sub-reflector)
    apex_pos = Vector((0.0, 0.0, 3.15))
    strut_r = 2.45
    strut_z = 1.15 * ((strut_r / 3.9) ** 2)
    for leg_idx in range(4):
        ang = math.radians(45.0 + 90.0 * leg_idx)
        base_pt = Vector((strut_r * math.cos(ang), strut_r * math.sin(ang), strut_z - 0.04))
        add_beam_between(dish_parts, f"Quadrupod_Leg_{leg_idx}", base_pt, apex_pos, 0.11, mat_truss_steel)

    # Central Hyperbolic Sub-Reflector & Cap at Apex
    add_cylinder(dish_parts, "SubReflector_Dish", 0.68, 0.42, 0.32, (0.0, 0.0, 3.22), 14, mat_dish_white)
    add_cylinder(dish_parts, "SubReflector_Tip", 0.42, 0.08, 0.25, (0.0, 0.0, 3.48), 12, mat_feed_gold)

    # Transform all dish-assembly parts together by tilt + elevation pivot
    tilt_mat = Matrix.Translation(dish_pivot) @ tilt_euler.to_matrix().to_4x4()
    for dp in dish_parts:
        dp.matrix_world = tilt_mat @ dp.matrix_world
        parts.append(dp)

    dsn = finalize_mesh_object(parts, "dsn_70m_dish", target_height=8.0, max_faces=2450)
    export_glb(dsn, "dsn_70m_dish.glb")


def main() -> None:
    print(f"=== Repairing Corrupted Models -> {OUTPUT_DIR} ===")
    build_sls_block1()
    build_vab_gantry()
    build_dsn_70m_dish()
    print("=== All 3 corrupted models rebuilt successfully ===")


if __name__ == "__main__":
    main()
