"""
LRO LOLA DEM to 16-bit Heightmap Converter for Godot 4.3+
Projeto: AstraRex (NASA Space Apps Challenge)
Módulo: Topografia Física da Cratera Shackleton (Polo Sul Lunar)
"""

import argparse
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

# Permite leitura de imagens de ultra-alta resolução da NASA sem limite de descompressão
Image.MAX_IMAGE_PIXELS = None

# Importação condicional para suporte opcional a TIFF com tiffile
try:
    import tifffile
except ImportError:
    tifffile = None

# Caminhos padrão alinhados com a estrutura do projeto Godot 4
OUTPUT_PNG = Path("assets/terrain/shackleton_heightmap_16bit.png")
OUTPUT_META = Path("data/shackleton_terrain_meta.json")

# Diretórios de busca automática
SEARCH_DIRS = [Path("assets"), Path("assets/terrain"), Path("raw_terrain"), Path("."), Path("scripts")]
SUPPORTED_EXTS = {".jp2", ".tif", ".tiff", ".img"}


def find_lola_file() -> Path:
    """
    Localiza automaticamente o arquivo DEM da NASA.
    Prioriza arquivos contendo 'ldem' (Model) em relação a 'ldec' (Count).
    """
    candidates = []
    for folder in SEARCH_DIRS:
        if not folder.exists():
            continue
        for file in sorted(folder.iterdir()):
            if file.suffix.lower() in SUPPORTED_EXTS and "shackleton_heightmap" not in file.name.lower():
                candidates.append(file)

    if not candidates:
        raise FileNotFoundError(
            "Nenhum arquivo .jp2, .tif, .tiff ou .img do LRO LOLA foi encontrado em assets/, raw_terrain/ ou na raiz."
        )

    # Prioriza 'ldem' sobre qualquer outro arquivo
    ldem_candidates = [f for f in candidates if "ldem" in f.name.lower()]
    if ldem_candidates:
        return ldem_candidates[0]

    return candidates[0]


def crop_dem_patch(
    filepath: Path,
    crop_size: int = 1024,
    offset_x: int = 0,
    offset_y: int = 0
) -> tuple[np.ndarray, int, int]:
    """
    Recorta eficientemente uma região de crop_size x crop_size diretamente via Pillow,
    evitando carregar os ~230 milhões de pixels na RAM como float32.
    """
    ext = filepath.suffix.lower()

    if ext in {".tif", ".tiff"} and tifffile is not None:
        # Se tifffile estiver disponível e for TIFF
        raw = tifffile.imread(str(filepath))
        h, w = raw.shape[:2]
        cx = (w // 2) + offset_x
        cy = (h // 2) + offset_y
        half = crop_size // 2
        y0 = max(0, min(h - crop_size, cy - half))
        x0 = max(0, min(w - crop_size, cx - half))
        return raw[y0 : y0 + crop_size, x0 : x0 + crop_size], w, h

    with Image.open(filepath) as img:
        w, h = img.size
        cx = (w // 2) + offset_x
        cy = (h // 2) + offset_y
        half = crop_size // 2

        x0 = max(0, min(w - crop_size, cx - half))
        y0 = max(0, min(h - crop_size, cy - half))
        box = (x0, y0, x0 + crop_size, y0 + crop_size)

        cropped_img = img.crop(box)
        patch = np.array(cropped_img)
        return patch, w, h


def process_shackleton_heightmap(
    input_path: Path | None = None,
    crop_size: int = 1024,
    offset_x: int = 0,
    offset_y: int = 0,
    lola_scale_factor: float = 0.5,
    pixel_resolution_m: float = 20.0
) -> None:
    """
    Processa o DEM lunar oficial da NASA (LRO LOLA), normaliza para PNG 16-bit mono
    e atualiza data/shackleton_terrain_meta.json com parâmetros físicos exatos.
    """
    input_file = input_path if input_path else find_lola_file()
    print(f"[1/4] Arquivo LRO LOLA selecionado: {input_file} ({input_file.stat().st_size / (1024*1024):.1f} MB)")

    # Alerta caso o usuário acidentalmente forneça um LDEC
    if "ldec" in input_file.name.lower():
        print("!" * 78)
        print("AVISO: O arquivo selecionado parece ser LDEC (contagem de disparos laser),")
        print("não LDEM (modelo de elevação digital). Para relevo físico real, use LDEM.")
        print("!" * 78)

    # Recorte otimizado
    patch, orig_w, orig_h = crop_dem_patch(input_file, crop_size=crop_size, offset_x=offset_x, offset_y=offset_y)
    print(f"[2/4] Recorte de {crop_size}x{crop_size} px extraído da imagem {orig_w}x{orig_h} px (tipo: {patch.dtype})")

    # Conversão dos Digital Numbers (DN) para elevação em metros
    # No formato JPEG2000 decodificado pelo Pillow em modo I;16:
    # inteiros com sinal de 16-bit (-32768 a 32767) são decodificados como uint16 com offset 32768.
    if np.issubdtype(patch.dtype, np.unsignedinteger) and np.median(patch) > 20000:
        dn = patch.astype(np.float32) - 32768.0
    else:
        dn = patch.astype(np.float32)

    # Máscara de pixels válidos (exclui NoData padrão NASA PDS: -32768)
    valid_mask = dn > -30000.0
    if not np.any(valid_mask):
        raise ValueError("O recorte selecionado não contém dados topográficos válidos.")

    # Se houver pixels inválidos/nulos na borda, preenche com o valor mínimo válido
    if not np.all(valid_mask):
        fill_val = float(np.min(dn[valid_mask]))
        dn[~valid_mask] = fill_val

    # Aplicação do fator de escala oficial NASA LOLA (0.5 m por DN)
    elevation_m = dn * lola_scale_factor

    min_elev_m = float(np.min(elevation_m))
    max_elev_m = float(np.max(elevation_m))
    height_range_m = max_elev_m - min_elev_m

    print(f"[3/4] Calibração Física do Relevo:")
    print(f"      - Elevação Mínima: {min_elev_m:.2f} m (Fundo da Cratera / PSR)")
    print(f"      - Elevação Máxima: {max_elev_m:.2f} m (Cume / Borda Iluminada)")
    print(f"      - Amplitude Total: {height_range_m:.2f} m")

    # Normalização estrita para o intervalo uint16 [0, 65535]
    norm_01 = (elevation_m - min_elev_m) / max(height_range_m, 1.0)
    uint16_map = np.clip(norm_01 * 65535.0, 0, 65535).astype(np.uint16)

    # Criação dos diretórios de saída
    OUTPUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_META.parent.mkdir(parents=True, exist_ok=True)

    # Salva o PNG 16-bit monocromático
    img_out = Image.fromarray(uint16_map)
    img_out.save(str(OUTPUT_PNG))

    # Atualiza shackleton_terrain_meta.json preservando landing_zones e constantes existentes
    meta = {}
    if OUTPUT_META.exists():
        try:
            meta = json.loads(OUTPUT_META.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"      (Aviso ao ler meta existente: {e})")

    meta.setdefault("metadata", {})
    meta["metadata"]["source_file"] = input_file.name
    meta["metadata"]["lola_resolution"] = f"{pixel_resolution_m:.1f} m/px"
    meta["metadata"]["nasa_citation"] = "LRO LOLA GDR (Lunar Orbiter Laser Altimeter) Polar Stereographic 20 m/px"

    terrain_span_m = crop_size * pixel_resolution_m
    meta.setdefault("dem_bounds", {})
    meta["dem_bounds"].update({
        "grid_width_m": terrain_span_m,
        "grid_depth_m": terrain_span_m,
        "resolution_m_per_px": pixel_resolution_m,
        "min_elevation_m": round(min_elev_m, 2),
        "max_elevation_m": round(max_elev_m, 2),
        "total_vertical_amplitude_m": round(height_range_m, 2),
        "godot_heightmap_note": "Escalar Y do HeightMapShape3D por total_vertical_amplitude_m e X/Z por resolution_m_per_px. Offset Y no Godot = min_elevation_m"
    })

    OUTPUT_META.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    png_size_kb = OUTPUT_PNG.stat().st_size / 1024
    print(f"[4/4] Processamento concluído com sucesso!")
    print(f"      -> Heightmap 16-bit: {OUTPUT_PNG} ({png_size_kb:.1f} KB)")
    print(f"      -> Metadados JSON:   {OUTPUT_META}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Converte DEM LRO LOLA em Heightmap 16-bit para Godot 4")
    parser.add_argument("--input", "-i", type=Path, default=None, help="Caminho do arquivo JP2/TIF")
    parser.add_argument("--crop-size", "-c", type=int, default=1024, help="Resolução da grade (padrão: 1024)")
    parser.add_argument("--offset-x", "-x", type=int, default=0, help="Offset X em pixels a partir do centro")
    parser.add_argument("--offset-y", "-y", type=int, default=0, help="Offset Y em pixels a partir do centro")
    parser.add_argument("--scale", "-s", type=float, default=0.5, help="Fator de escala LOLA em m/DN (padrão: 0.5)")
    parser.add_argument("--res", "-r", type=float, default=20.0, help="Resolução em m/pixel (padrão: 20.0)")

    args = parser.parse_args()
    process_shackleton_heightmap(
        input_path=args.input,
        crop_size=args.crop_size,
        offset_x=args.offset_x,
        offset_y=args.offset_y,
        lola_scale_factor=args.scale,
        pixel_resolution_m=args.res
    )
