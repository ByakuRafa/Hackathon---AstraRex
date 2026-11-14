import bpy
import math
from pathlib import Path
from mathutils import Vector

# ==============================================================================
# Otimizador & Extrator de Ativos 3D NASA -> Godot 4 (WebGL gl_compatibility)
# Projeto: Space Mission Design Game (NASA Space Apps 2026 - AstraRex)
# ==============================================================================

# Caminhos resolvidos automaticamente a partir da raiz do repositório
REPO_ROOT = Path(__file__).resolve().parent.parent
INPUT_DIR = REPO_ROOT / "assets"
OUTPUT_DIR = REPO_ROOT / "space-app-challenge-2026---astra-rex" / "assets" / "models"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Especificações: (dimensao_maxima_metros, max_faces, modo_pivo)
# Modos de pivô:
#   "bottom_center" -> Base apoiada em Z=0, centro X/Y na origem
#   "top_center"    -> Topo (flange de encaixe) em Z=0, corpo para -Z (-Y no Godot)
#   "hinge_max_x"   -> Dobradiça na extremidade +X=0, asa estendida para -X
#   "center"        -> Centrado na origem (X=0, Y=0, Z=0)
MODEL_SPECS = {
    "lander_bus":     (3.2,  3500, "bottom_center"),
    "engine_biprop":  (1.2,  1500, "top_center"),
    "engine_ion":     (0.8,  1500, "top_center"),
    "solar_array":    (4.0,  2000, "hinge_max_x"),
    "rtg_cassini":    (1.5,  1800, "bottom_center"),
    "battery_pack":   (1.1,  1200, "bottom_center"),
    "antenna_hga":    (1.8,  2000, "bottom_center"),
    "antenna_omni":   (0.9,  1000, "bottom_center"),
    "sensor_lidar":   (0.7,  1200, "bottom_center"),
    "payload_drill":  (1.4,  1500, "bottom_center"),
    "payload_msolo":  (0.8,  1200, "bottom_center"),
    "payload_sar":    (1.6,  1500, "bottom_center"),
    "shield_heavy":   (1.8,  1200, "center"),
    "sls_block1":     (18.0, 5000, "bottom_center"),
    "vab_gantry":     (22.0, 4000, "bottom_center"),
    "dsn_70m_dish":   (8.0,  2500, "bottom_center"),
}


def reset_scene():
    """Limpa todos os objetos, malhas e materiais órfãos da memória do Blender."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_world_bbox(obj) -> tuple[Vector, Vector]:
    """Retorna os vetores mínimo e máximo da bounding box no espaço mundial."""
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    min_v = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    max_v = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return min_v, max_v


def get_bbox_center(obj) -> Vector:
    """Retorna o centro geométrico da bounding box no espaço mundial."""
    min_v, max_v = get_world_bbox(obj)
    return (min_v + max_v) * 0.5


def separate_all_meshes_by_loose():
    """Aplica transformações e separa todas as malhas da cena por ilhas geométricas conectadas."""
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in meshes:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        if len(o.data.polygons) > 0:
            bpy.ops.mesh.separate(type='LOOSE')


def join_and_clean_meshes(mesh_objs: list, target_name: str, merge_doubles: bool = True):
    """Unifica uma lista de objetos MESH num único objeto limpo e com normais consistentes."""
    valid_objs = [o for o in mesh_objs if o and o.type == 'MESH' and len(o.data.polygons) > 0]
    if not valid_objs:
        return None

    # Remove todos os outros objetos da cena para não poluir memória ou exportação
    keep_set = set(valid_objs)
    for o in list(bpy.context.scene.objects):
        if o not in keep_set:
            bpy.data.objects.remove(o, do_unlink=True)

    bpy.ops.object.select_all(action='DESELECT')
    for obj in valid_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = valid_objs[0]

    if len(valid_objs) > 1:
        bpy.ops.object.join()

    main_obj = bpy.context.active_object
    main_obj.name = target_name
    main_obj.data.name = f"{target_name}_mesh"

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if merge_doubles and len(main_obj.data.polygons) < 150000:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=0.0005)
        bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=False)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode='OBJECT')

    main_obj.data.validate(verbose=False)
    return main_obj


def normalize_scale_and_pivot(obj, target_max_dim: float, pivot_mode: str = "bottom_center"):
    """Normaliza a maior dimensão para metros e ajusta o pivô conforme a função mecânica."""
    min_vec, max_vec = get_world_bbox(obj)
    size = max_vec - min_vec
    current_max_dim = max(size.x, size.y, size.z)

    if current_max_dim > 0.0001:
        scale_factor = target_max_dim / current_max_dim
        obj.scale = (scale_factor, scale_factor, scale_factor)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    min_vec, max_vec = get_world_bbox(obj)
    cx = (min_vec.x + max_vec.x) * 0.5
    cy = (min_vec.y + max_vec.y) * 0.5
    cz = (min_vec.z + max_vec.z) * 0.5

    if pivot_mode == "top_center":
        pivot = Vector((cx, cy, max_vec.z))
    elif pivot_mode == "hinge_max_x":
        pivot = Vector((max_vec.x, cy, cz))
    elif pivot_mode == "center":
        pivot = Vector((cx, cy, cz))
    else:  # "bottom_center"
        pivot = Vector((cx, cy, min_vec.z))

    obj.location -= pivot
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def decimate_mesh(obj, max_faces: int):
    """Aplica o modificador Decimate (Collapse) apenas se exceder o orçamento WebGL."""
    current_faces = len(obj.data.polygons)
    if current_faces <= max_faces:
        print(f"   [OK] {obj.name}: {current_faces} faces (limite {max_faces})")
        return

    ratio = max(0.001, float(max_faces) / float(current_faces))
    mod = obj.modifiers.new(name="NASA_Decimate", type='DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = ratio
    mod.use_collapse_triangulate = True

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)

    # Se costuras CAD abertas impediram o Collapse de atingir max_faces, solda vértices próximos e aplica segundo passo
    if len(obj.data.polygons) > int(max_faces * 1.15):
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=0.015)
        bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=False)
        bpy.ops.object.mode_set(mode='OBJECT')

        rem_faces = len(obj.data.polygons)
        if rem_faces > max_faces:
            mod2 = obj.modifiers.new(name="NASA_Decimate_Pass2", type='DECIMATE')
            mod2.decimate_type = 'COLLAPSE'
            mod2.ratio = max(0.05, float(max_faces) / float(rem_faces))
            mod2.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod2.name)

    obj.data.validate(verbose=False)
    print(f"   [DECIMATED] {obj.name}: {current_faces} -> {len(obj.data.polygons)} faces (ratio={ratio:.4f})")


def downscale_textures(max_res: int = 512):
    """Reduz texturas preservando a proporção (aspect ratio) para respeitar o orçamento de 15 MB."""
    for img in bpy.data.images:
        try:
            w, h = img.size[0], img.size[1]
            if w <= 0 or h <= 0:
                continue
            if w > max_res or h > max_res:
                factor = float(max_res) / float(max(w, h))
                new_w = max(1, int(w * factor))
                new_h = max(1, int(h * factor))
                img.scale(new_w, new_h)
        except Exception as err:
            print(f"   [AVISO] Não foi possível redimensionar imagem '{img.name}': {err}")


def create_lander_slots(bus_obj) -> list:
    """Cria os nós Empty de acoplamento modular como filhos do chassi do lander."""
    min_v, max_v = get_world_bbox(bus_obj)
    height = max_v.z - min_v.z
    radius_x = (max_v.x - min_v.x) * 0.5
    radius_y = (max_v.y - min_v.y) * 0.5

    # Coordenadas no espaço Blender (Z-up) convertidas automaticamente para Y-up no .glb
    slot_positions = {
        "Slot_Propulsion": Vector((0.0, 0.0, height * 0.30)),
        "Slot_Power":      Vector((-radius_x * 0.65, 0.0, height * 0.58)),
        "Slot_Comms":      Vector((0.0, 0.0, height * 0.92)),
        "Slot_Payload":    Vector((radius_x * 0.55, -radius_y * 0.35, height * 0.55)),
    }

    empties = []
    for slot_name, pos in slot_positions.items():
        empty = bpy.data.objects.new(slot_name, None)
        empty.empty_display_type = 'PLAIN_AXES'
        empty.empty_display_size = 0.25
        empty.parent = bus_obj
        empty.location = pos
        bpy.context.scene.collection.objects.link(empty)
        empties.append(empty)
    return empties


def export_glb(main_obj, output_path: Path, extra_objs: list = None):
    """Exporta em formato binário .glb pronto para Godot 4 (Y-Up automático e imagens compactas)."""
    bpy.ops.object.select_all(action='DESELECT')
    main_obj.select_set(True)
    if extra_objs:
        for obj in extra_objs:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = main_obj

    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='WEBP',
        export_image_quality=75
    )
    size_kb = output_path.stat().st_size / 1024.0
    print(f"   [EXPORTADO] {output_path.name} ({size_kb:.1f} KB)")


def finalize_and_export(mesh_objs: list, part_id: str, extra_empties_fn=None):
    """Pipeline padrão pós-extração: unifica, normaliza escala/pivô, decima, reduz texturas e exporta."""
    target_dim, max_faces, pivot_mode = MODEL_SPECS[part_id]
    main_obj = join_and_clean_meshes(mesh_objs, part_id)
    if not main_obj:
        print(f"   [ERRO] Nenhuma malha válida encontrada para '{part_id}'.")
        return

    normalize_scale_and_pivot(main_obj, target_dim, pivot_mode)
    decimate_mesh(main_obj, max_faces)
    downscale_textures(max_res=512)

    extra_objs = extra_empties_fn(main_obj) if extra_empties_fn else None
    export_glb(main_obj, OUTPUT_DIR / f"{part_id}.glb", extra_objs)


# ==============================================================================
# Extratores Especializados por Modelo Fonte da NASA
# ==============================================================================

def process_viking_lander():
    filepath = INPUT_DIR / "Viking Lander.glb"
    if not filepath.exists():
        print(f"[SKIP] Não encontrado: {filepath.name}")
        return

    # 1. Chassi Principal + Pernas (lander_bus)
    print(f"\n-> Extraindo 'lander_bus' de {filepath.name}")
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    separate_all_meshes_by_loose()

    bus_parts = []
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        min_v, max_v = get_world_bbox(o)
        c = (min_v + max_v) * 0.5
        d = max_v - min_v
        max_dim = max(d.x, d.y, d.z)
        polys = len(o.data.polygons)

        # Descarta parafusos/rebites minúsculos com muitos polígonos
        if max_dim < 0.12 and polys > 150:
            continue
        # Descarta braço amostrador estendido (+X) e antena/mastro alto (+Z)
        if c.x > 4.5 and c.z > 2.0:
            continue
        if max_v.z > 5.8:
            continue
        bus_parts.append(o)

    finalize_and_export(bus_parts, "lander_bus", extra_empties_fn=create_lander_slots)

    # 2. Braço / Perfuradora Científica (payload_drill)
    print(f"\n-> Extraindo 'payload_drill' de {filepath.name}")
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    separate_all_meshes_by_loose()

    drill_parts = []
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        c = get_bbox_center(o)
        if c.x > 3.8 and c.z > 2.0:
            drill_parts.append(o)

    finalize_and_export(drill_parts, "payload_drill")


def process_cassini():
    filepath = INPUT_DIR / "Cassini-Huygens (A) (without Hyugens).glb"
    if not filepath.exists():
        print(f"[SKIP] Não encontrado: {filepath.name}")
        return

    # 1. Antena Parabólica de Alto Ganho Ka-Band (antenna_hga)
    print(f"\n-> Extraindo 'antenna_hga' de {filepath.name}")
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    dish_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name == "dish"]
    finalize_and_export(dish_objs, "antenna_hga")

    # 2. Gerador Radioisotópico MMRTG com alhetas térmicas (rtg_cassini)
    print(f"\n-> Extraindo 'rtg_cassini' de {filepath.name}")
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    for name in ["black_krinkle", "plastic_dark"]:
        o = bpy.data.objects.get(name)
        if o:
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            bpy.ops.mesh.separate(type='LOOSE')

    rtg_parts = []
    for o in bpy.context.scene.objects:
        if o.type == 'MESH' and (o.name.startswith("black_krinkle") or o.name.startswith("plastic_dark")):
            c = get_bbox_center(o)
            if -0.55 < c.x < 0.55 and 1.05 < c.y < 2.20 and -2.65 < c.z < -1.75:
                rtg_parts.append(o)
    # Alinha o cilindro do RTG na vertical para facilitar encaixe lateral
    finalize_and_export(rtg_parts, "rtg_cassini")

    # 3. Motor Químico Bipropelente R-4D (engine_biprop)
    print(f"\n-> Extraindo 'engine_biprop' de {filepath.name}")
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    separate_all_meshes_by_loose()

    engine_parts = []
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        c = get_bbox_center(o)
        if -0.28 < c.x < 0.28 and -0.46 < c.y < -0.05 and c.z < -2.75:
            engine_parts.append(o)
    finalize_and_export(engine_parts, "engine_biprop")


def process_lro():
    filepath = INPUT_DIR / "Lunar Reconnaissance Orbiter (A).glb"
    if not filepath.exists():
        print(f"[SKIP] Não encontrado: {filepath.name}")
        return

    # 1. Painel Solar Articulado (solar_array) -> Layer_4
    print(f"\n-> Extraindo 'solar_array' de {filepath.name}")
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    solar_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name == "Layer_4"]
    finalize_and_export(solar_objs, "solar_array")

    # 2. Radar Mini-RF SAR (payload_sar) -> Layer_2
    print(f"\n-> Extraindo 'payload_sar' de {filepath.name}")
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    sar_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name == "Layer_2"]
    finalize_and_export(sar_objs, "payload_sar")


def process_sls_blend():
    filepath = INPUT_DIR / "Block 1 (GNC markings).blend"
    if not filepath.exists():
        print(f"[SKIP] Não encontrado: {filepath.name}")
        return

    print(f"\n-> Extraindo 'sls_block1' de {filepath.name} (filtrando 4.800+ objetos...)")
    reset_scene()
    bpy.ops.wm.open_mainfile(filepath=str(filepath))

    # Filtra apenas peças estruturais próximas ao eixo do foguete, removendo parafusos minúsculos e lixo distante
    structural_objs = []
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        min_v, max_v = get_world_bbox(o)
        c = (min_v + max_v) * 0.5
        d = max_v - min_v
        max_dim = max(d.x, d.y, d.z)

        if abs(c.x) > 15.0 or abs(c.y) > 15.0 or c.z < -5.0 or c.z > 120.0:
            continue
        if max_dim < 0.45:
            continue
        structural_objs.append(o)

    print(f"   Selecionados {len(structural_objs)} módulos estruturais principais do SLS.")
    target_dim, max_faces, pivot_mode = MODEL_SPECS["sls_block1"]
    main_obj = join_and_clean_meshes(structural_objs, "sls_block1", merge_doubles=False)
    if main_obj:
        normalize_scale_and_pivot(main_obj, target_dim, pivot_mode)
        decimate_mesh(main_obj, max_faces)
        downscale_textures(max_res=512)
        export_glb(main_obj, OUTPUT_DIR / "sls_block1.glb")


def process_optional_vab_props():
    """Otimiza ativos extras de cenário presentes em assets/ (Gantry e Antena DSN 70m)."""
    extras = [
        ("Gantry.glb", "vab_gantry"),
        ("70 meter dish.glb", "dsn_70m_dish"),
    ]
    for filename, part_id in extras:
        filepath = INPUT_DIR / filename
        if not filepath.exists():
            continue
        print(f"\n-> Otimizando prop extra '{part_id}' de {filename}")
        reset_scene()
        bpy.ops.import_scene.gltf(filepath=str(filepath))
        meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        finalize_and_export(meshes, part_id)


# ==============================================================================
# Geradores Procedurais NASA-Style para Subsistemas sem Modelo Bruto Dedicado
# (Garante que 100% das entradas de data/nasa_parts_catalog.json existam em .glb)
# ==============================================================================

def make_pbr_material(name: str, base_color: tuple, metallic: float = 0.8, roughness: float = 0.35, emission: tuple = None):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 1.8
    return mat


def generate_missing_catalog_subsystems():
    """Gera modelos low-poly fiéis ao catálogo para peças sem arquivo fonte dedicado em assets/."""
    print("\n-> Verificando/Gerando subsistemas complementares do catálogo NASA...")

    # 1. engine_ion (Propulsor Hall Xenon com grade ionizada azul)
    if not (OUTPUT_DIR / "engine_ion.glb").exists():
        reset_scene()
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.35, depth=0.35, location=(0, 0, -0.175))
        body = bpy.context.active_object
        body.data.materials.append(make_pbr_material("Ion_Titanium", (0.55, 0.58, 0.62), 0.9, 0.3))
        bpy.ops.mesh.primitive_torus_add(major_radius=0.28, minor_radius=0.05, location=(0, 0, -0.35))
        ring = bpy.context.active_object
        ring.data.materials.append(make_pbr_material("Ion_XenonGlow", (0.2, 0.65, 1.0), 0.1, 0.2, emission=(0.15, 0.6, 1.0)))
        finalize_and_export([body, ring], "engine_ion")

    # 2. battery_pack (Banco Criogênico Li-Ion 48 kWh)
    if not (OUTPUT_DIR / "battery_pack.glb").exists():
        reset_scene()
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.35))
        box = bpy.context.active_object
        box.scale = (0.9, 0.65, 0.55)
        box.data.materials.append(make_pbr_material("Batt_FoilGold", (0.85, 0.65, 0.18), 0.9, 0.28))
        finalize_and_export([box], "battery_pack")

    # 3. antenna_omni (Antena S-Band Omnidirecional)
    if not (OUTPUT_DIR / "antenna_omni.glb").exists():
        reset_scene()
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.04, depth=0.75, location=(0, 0, 0.375))
        mast = bpy.context.active_object
        mast.data.materials.append(make_pbr_material("Omni_White", (0.88, 0.88, 0.90), 0.2, 0.4))
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.09, location=(0, 0, 0.78))
        tip = bpy.context.active_object
        tip.data.materials.append(make_pbr_material("Omni_Gold", (0.9, 0.7, 0.2), 0.9, 0.25))
        finalize_and_export([mast, tip], "antenna_omni")

    # 4. sensor_lidar (Sensor LiDAR / Star Tracker / OBC)
    if not (OUTPUT_DIR / "sensor_lidar.glb").exists():
        reset_scene()
        bpy.ops.mesh.primitive_cube_add(size=0.4, location=(0, 0, 0.2))
        box = bpy.context.active_object
        box.data.materials.append(make_pbr_material("Avionics_Alloy", (0.72, 0.74, 0.78), 0.85, 0.3))
        bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.14, radius2=0.08, depth=0.22, location=(0, 0.22, 0.22), rotation=(math.radians(90), 0, 0))
        lens = bpy.context.active_object
        lens.data.materials.append(make_pbr_material("Lidar_Optics", (0.08, 0.25, 0.45), 0.2, 0.1))
        finalize_and_export([box, lens], "sensor_lidar")

    # 5. payload_msolo (Espectrômetro de Massa Quadrupolo MSolo)
    if not (OUTPUT_DIR / "payload_msolo.glb").exists():
        reset_scene()
        bpy.ops.mesh.primitive_cube_add(size=0.5, location=(0, 0, 0.25))
        box = bpy.context.active_object
        box.scale = (1.1, 0.8, 0.9)
        box.data.materials.append(make_pbr_material("MSolo_GoldMLI", (0.88, 0.68, 0.2), 0.85, 0.35))
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.07, depth=0.35, location=(0, 0.32, 0.25), rotation=(math.radians(90), 0, 0))
        probe = bpy.context.active_object
        probe.data.materials.append(make_pbr_material("MSolo_Steel", (0.7, 0.72, 0.75), 0.95, 0.2))
        finalize_and_export([box, probe], "payload_msolo")

    # 6. shield_heavy (Blindagem de Polietileno & Alumínio contra SPE/GCR)
    if not (OUTPUT_DIR / "shield_heavy.glb").exists():
        reset_scene()
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.85, depth=0.45, location=(0, 0, 0.225))
        shell = bpy.context.active_object
        shell.data.materials.append(make_pbr_material("Shield_PolyAl", (0.35, 0.38, 0.42), 0.75, 0.45))
        finalize_and_export([shell], "shield_heavy")


def process_all_models():
    if not INPUT_DIR.exists():
        print(f"[ERRO] Diretório de entrada não encontrado: {INPUT_DIR}")
        return

    print(f"=== Otimizando Modelos NASA ({INPUT_DIR} -> {OUTPUT_DIR}) ===")
    process_viking_lander()
    process_cassini()
    process_lro()
    process_sls_blend()
    process_optional_vab_props()
    generate_missing_catalog_subsystems()

    total_kb = sum(f.stat().st_size for f in OUTPUT_DIR.glob("*.glb")) / 1024.0
    print(f"\n=== Concluído! Tamanho total dos modelos .glb: {total_kb / 1024.0:.2f} MB ===")


if __name__ == "__main__":
    process_all_models()
