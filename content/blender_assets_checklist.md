# Guia & Checklist de Preparação de Modelos 3D (Blender → Godot 4)

Este documento lista as especificações de modelagem, extração, otimização poligonal, configuração de pivôs/slots e integração no **Godot 4.3+** para exportação em `.glb` (`res://assets/models/`), respeitando o orçamento WebGL (`< 15 MB` total do pacote e `< 10.000` triângulos por subsistema).

---

## 1. Tabela Geral de Ativos 3D (NASA Space Apps 2026 - AstraRex)

| Nome do Ficheiro | Subsistema / ID Catálogo | Modelo Fonte NASA | Escala | Limite Poligonal | Resultado no Blender | Status |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| **`lander_bus.glb`** | Bus / `chassis_clps` | `Viking Lander.glb` | `3.2 m` | Máx. `3.500` | 3.488 faces (84.7 KB) + 4 Empties | Concluído |
| **`engine_biprop.glb`** | Propulsão / `prop_chem_biprop` | `Cassini-Huygens.glb` | `1.2 m` | Máx. `1.500` | 456 faces (56.4 KB), pivô no topo | Concluído |
| **`engine_ion.glb`** | Propulsão / `prop_ion_sep` | Gerador PBR Procedural NASA | `0.8 m` | Máx. `1.500` | 598 faces (85.3 KB), grade Xenon | Concluído |
| **`solar_array.glb`** | Energia / `pwr_solar_lro` | `Lunar Reconnaissance Orbiter.glb` | `4.0 m` | Máx. `2.000` | 1.958 faces (156.3 KB), pivô dobradiça | Concluído |
| **`rtg_cassini.glb`** | Energia / `pwr_rtg_mmrtg` | `Cassini-Huygens.glb` | `1.5 m` | Máx. `1.800` | 746 faces (30.8 KB), alhetas térmicas | Concluído |
| **`battery_pack.glb`** | Energia / `pwr_batt_liion` | Gerador PBR Procedural NASA | `1.1 m` | Máx. `1.200` | 6 faces (2.0 KB), MLI dourado | Concluído |
| **`antenna_hga.glb`** | Comunicações / `comm_hga_ka` | `Cassini-Huygens.glb` | `1.8 m` | Máx. `2.000` | 1.998 faces (101.8 KB), prato Ka-Band | Concluído |
| **`antenna_omni.glb`** | Comunicações / `comm_uga_s` | Gerador PBR Procedural NASA | `0.9 m` | Máx. `1.000` | 110 faces (16.9 KB), mastro S-Band | Concluído |
| **`sensor_lidar.glb`** | Aviônicos / `obc_adcs_*`, `lidar_trn`| Gerador PBR Procedural NASA | `0.7 m` | Máx. `1.200` | 24 faces (6.3 KB), ótica LiDAR | Concluído |
| **`payload_drill.glb`**| Ciência / `pay_drill_trident` | `Viking Lander.glb` | `1.4 m` | Máx. `1.500` | 1.500 faces (39.0 KB), broca polar | Concluído |
| **`payload_msolo.glb`**| Ciência / `pay_spec_msolo` | Gerador PBR Procedural NASA | `0.8 m` | Máx. `1.200` | 20 faces (5.5 KB), espectrômetro | Concluído |
| **`payload_sar.glb`**  | Ciência / `pay_sar_lband` | `Lunar Reconnaissance Orbiter.glb` | `1.6 m` | Máx. `1.500` | 1.500 faces (61.0 KB), radar Mini-RF | Concluído |
| **`shield_heavy.glb`** | Blindagem / `shield_heavy` | Gerador PBR Procedural NASA | `1.8 m` | Máx. `1.200` | 10 faces (2.9 KB), placa polietileno | Concluído |
| **`sls_block1.glb`**   | Foguete / `sls_block1` | `Block 1 (GNC markings).blend` | `18.0 m` | Máx. `5.000` | 1.780 faces (161.7 KB), fuselagem/SRB | Concluído |
| **`vab_gantry.glb`**   | Cenário VAB | `Gantry.glb` | `22.0 m` | Máx. `4.000` | 4.000 faces (250.3 KB), torre do hangar | Concluído |
| **`dsn_70m_dish.glb`** | Cenário DSN / DTE | `70 meter dish.glb` | `8.0 m` | Máx. `2.500` | 2.383 faces (145.4 KB), antena Terra | Concluído |

> **Orçamento WebGL Atual:** O total de todos os 16 modelos exportados é de **1.18 MB** (apenas 7.8% do teto máximo de 15 MB).

---

## 2. Checklist de Execução e Otimização no Blender

### 2.1 Chassi Principal
- [x] **`lander_bus.glb`** (`3.2 m` | 3.488 faces | 84.7 KB)
  - Extraído de `Viking Lander.glb` isolando corpo octogonal e trem de pouso (descartados rebites, braço e mastro alto).
  - Bounding box centrada em X/Y com a base apoiada em Z=0.
  - Exportados 4 nós **Empty (Plain Axes)** filhos para acoplamento:
    - `Slot_Propulsion` (inferior, Z = 0.30h)
    - `Slot_Power` (lateral, X = -0.65r, Z = 0.58h)
    - `Slot_Comms` (topo, Z = 0.92h)
    - `Slot_Payload` (frente/lateral, X = 0.55r, Y = -0.35r, Z = 0.55h)

### 2.2 Propulsão
- [x] **`engine_biprop.glb`** (`1.2 m` | 456 faces | 56.4 KB)
  - Tubeira química e câmara de combustão extraídas do conjunto de propulsão da Cassini.
  - Pivô (`top_center`): origem colocada na flange superior de montagem (Z=0), bocal apontado para `-Z` (Blender) / `-Y` (Godot).
- [x] **`engine_ion.glb`** (`0.8 m` | 598 faces | 85.3 KB)
  - Propulsor Hall/Xenon procedural com câmara de titânio e anel de emissão ionizada azul.
  - Pivô (`top_center`) na flange superior.

### 2.3 Energia & Armazenamento Térmico
- [x] **`solar_array.glb`** (`4.0 m` | 1.958 faces | 156.3 KB)
  - Painel solar articulado extraído do LRO (`Layer_4`).
  - Pivô (`hinge_max_x`): origem posicionada exatamente na dobradiça da haste para permitir rotação de incidência solar.
- [x] **`rtg_cassini.glb`** (`1.5 m` | 746 faces | 30.8 KB)
  - Gerador termoelétrico de radioisótopos (MMRTG) extraído da Cassini com alhetas pretas de radiação térmica.
- [x] **`battery_pack.glb`** (`1.1 m` | 6 faces | 2.0 KB)
  - Banco de baterias criogênico de Li-Ion (48 kWh) com envoltório térmico MLI dourado.

### 2.4 Telecomunicações (Comms)
- [x] **`antenna_hga.glb`** (`1.8 m` | 1.998 faces | 101.8 KB)
  - Prato parabólico de alto ganho (Ka-Band) extraído da Cassini (`dish`).
  - Pivô na base do mastro para rastreamento de vetor Direto à Terra (DTE).
- [x] **`antenna_omni.glb`** (`0.9 m` | 110 faces | 16.9 KB)
  - Antena omnidirecional de baixa potência em Banda S para contingência de telemetria.

### 2.5 Sensores & Aviônicos
- [x] **`sensor_lidar.glb`** (`0.7 m` | 24 faces | 6.3 KB)
  - Conjunto compacto de aviônicos/OBC rad-hard, Star Tracker e sensor óptico de Hazard Avoidance LiDAR (TRN).

### 2.6 Cargas Úteis Científicas (Payloads)
- [x] **`payload_drill.glb`** (`1.4 m` | 1.500 faces | 39.0 KB)
  - Perfuradora TRIDENT / braço de amostragem de regolito extraído do Viking Lander.
- [x] **`payload_msolo.glb`** (`0.8 m` | 20 faces | 5.5 KB)
  - Espectrômetro de massa quadrupolo MSolo para detecção de voláteis de água.
- [x] **`payload_sar.glb`** (`1.6 m` | 1.500 faces | 61.0 KB)
  - Antena de radar de abertura sintética Mini-RF extraída do LRO (`Layer_2`).
- [x] **`shield_heavy.glb`** (`1.8 m` | 10 faces | 2.9 KB)
  - Placa de blindagem estrutural contra radiação solar (SPE) e raios cósmicos galácticos (GCR).

### 2.7 Cenário & Estruturas de Apoio
- [x] **`sls_block1.glb`** (`18.0 m` | 1.780 faces | 161.7 KB)
  - Fuselagem externa do SLS Block 1 e boosters de propelente sólido extraídos de `Block 1 (GNC markings).blend`.
  - Mais de 4.800 componentes internos e parafusos filtrados; decimação de 1.160.948 faces para 1.780 faces com topologia validada.
- [x] **`vab_gantry.glb`** (`22.0 m` | 4.000 faces | 250.3 KB)
  - Torre de acesso e pórtico de montagem do hangar do VAB extraído de `Gantry.glb`.
- [x] **`dsn_70m_dish.glb`** (`8.0 m` | 2.383 faces | 145.4 KB)
  - Antena parabólica da Deep Space Network da NASA para visualização de linha de visada Terra-Lua.

---

## 3. Checklist de Integração no Godot 4.3+ (Próximos Passos)

### 3.1 Montagem do Chassi (`res://scenes/vab/LanderChassis.tscn`)
- [ ] Importar `res://assets/models/lander_bus.glb` como cena herdada ou nó raiz `Node3D`.
- [ ] Verificar nós `Slot_*` importados do `.glb` e instanciar nós `Marker3D` correspondentes aos `mount_point` do [nasa_parts_catalog.json](file:///c:/Users/Rafa/Desktop/Projects/Hackathon---AstraRex/data/nasa_parts_catalog.json):
  - [ ] `Mount_Propulsion` ➔ Posição de `Slot_Propulsion`
  - [ ] `Mount_Power_Port` ➔ Posição de `Slot_Power`
  - [ ] `Mount_Power_Starboard` ➔ Posição simétrica de `Slot_Power`
  - [ ] `Mount_Comms_Antenna` ➔ Posição de `Slot_Comms`
  - [ ] `Mount_Payload_Top` ➔ Topo da baia científica
  - [ ] `Mount_Payload_Side` ➔ Posição de `Slot_Payload`
  - [ ] `Mount_Avionics` ➔ Baia interna protegida
  - [ ] `Mount_Shielding` ➔ Painel externo
- [ ] Instanciar os nós `MeshInstance3D` filhos para cada subsistema e configurar `visible = false` por padrão (ativados conforme seleção no catálogo do VAB).
- [ ] Adicionar colisor primitivo leve (`CylinderShape3D`) na raiz do chassi para seleção/picking 3D.

### 3.2 Cenário do VAB (`res://scenes/vab/VABScene.tscn`)
- [ ] Instanciar `res://assets/models/vab_gantry.glb` como estrutura arquitetônica do hangar.
- [ ] Instanciar `res://assets/models/sls_block1.glb` ao fundo como referência de escala e visualizador de integração do veículo lançador.
- [ ] Configurar iluminação industrial de três pontos (Key, Fill, Rim) usando `DirectionalLight3D` + `Environment` compatível com WebGL (sem SDFGI/SSAO).

### 3.3 Visualizador Orbital e Alunagem
- [ ] Conectar a rotação do nó do `solar_array` ao vetor solar calculado a partir das efemérides DE441 (`cos(theta_incidence)`).
- [ ] Conectar a rotação da `antenna_hga` em direção ao vetor da Terra para validação de contato com a antena `dsn_70m_dish`.

---

## 4. Invariantes de Performance WebGL (`gl_compatibility`)

1. **Materiais PBR:** Todos os modelos usam `StandardMaterial3D` simples sem nós complexos de shader language, garantindo renderização instantânea no browser.
2. **Texturas:** Todas as imagens foram compactadas e limitadas a `512x512` WebP com preservação de aspect ratio.
3. **C# Proibido:** Toda a lógica de montagem e rotação deve ser estritamente em **GDScript 2.0 estaticamente tipado**.
4. **Sem Threads:** O carregamento e instanciação dos nós `.glb` devem ocorrer na thread principal ou via `await get_tree().process_frame`.
