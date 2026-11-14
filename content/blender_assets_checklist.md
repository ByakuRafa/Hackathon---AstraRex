# Guia & Checklist de Preparação de Modelos 3D (Blender → Godot 4)

Este documento lista as atividades de modelagem, limpeza, otimização poligonal e configuração de pivôs/slots no **Blender** para exportação em `.glb` (`res://assets/models/`), respeitando o orçamento WebGL (`< 15 MB` total e `< 10.000` triângulos por subsistema).

---

## Tabela Geral de Ativos

| Nome Final do Ficheiro | Modelo Fonte na NASA | Escala & Limite Poligonal | Atividade Específica no Blender |
| :--- | :--- | :--- | :--- |
| **`lander_bus.glb`** | Viking Lander ou LRO (Bus central) | `3.2 m` \| Máx. `3.500 faces` | Isolar o corpo octogonal central e as pernas de alunagem (remover antenas e painéis acoplados). Criar 4 nós **Empty (Plain Axes)** na superfície com os nomes exatos: `Slot_Propulsion` (em baixo), `Slot_Power` (lateral), `Slot_Comms` (topo) e `Slot_Payload` (frente/base). |
| **`engine_biprop.glb`** | Viking Lander (bocal inferior) ou Apollo Lunar Module Descent Engine | `1.2 m` \| Máx. `1.500 faces` | Isolar apenas a câmara de combustão e a tubeira (bocal) do motor químico. Colocar a origem (pivô) no topo do motor (ponto de encaixe no fundo do chassi) apontando o bocal para `-Y` (baixo no Godot). |
| **`engine_ion.glb`** | Dawn Spacecraft ou Deep Space 1 (NSTAR Ion Thruster) | `0.8 m` \| Máx. `1.500 faces` | Isolar o cilindro pequeno com a grelha azulada do propulsor iónico/Hall. Manter geometria simples sem cabos internos. |
| **`solar_array.glb`** | Lunar Reconnaissance Orbiter (LRO) | `4.0 m` \| Máx. `2.000 faces` | Separar apenas a asa do painel fotovoltaico e a haste de ligação. Posicionar o pivô exatamente na dobradiça da haste para rodar em direção ao Sol no Godot. |
| **`rtg_cassini.glb`** | Cassini Spacecraft ou Curiosity / Perseverance MMRTG | `1.5 m` \| Máx. `1.800 faces` | Isolar um dos cilindros pretos/dourados com alhetas de radiação térmica (gerador nuclear RTG). Remover suportes internos excessivos. |
| **`antenna_hga.glb`** | Cassini High-Gain Antenna ou DSN 34m Antenna | `1.8 m` \| Máx. `2.000 faces` | Isolar o prato parabólico principal e o alimentador central. Colocar o pivô na base do mastro da antena para permitir apontamento à Terra (DTE). |
| **`payload_drill.glb`** | VIPER Rover ou braço do Viking / Phoenix Lander | `1.4 m` \| Máx. `1.500 faces` | Extrair a torre/broca vertical de perfuração de gelo polar e a caixa do espectrómetro. Unificar numa única malha estática. |
| **`payload_sar.glb`** | LRO (Mini-RF Antenna) ou MRO Radar | `1.6 m` \| Máx. `1.500 faces` | Isolar o painel retangular inclinado ou haste da antena de radar de abertura sintética (SAR). |
| **`sls_block1.glb`** | Space Launch System (SLS Block 1) + Launch Pad / VAB | `18.0 m` \| Máx. `5.000 faces` | Unificar o foguetão num único objeto apenas para compor o fundo visual da cena de montagem (VAB). Apagar geometria interna invisível dos tanques. |

---

## Checklist de Execução (Passo a Passo)

### 1. Chassi Principal
- [ ] **`lander_bus.glb`** (`3.2 m` | Máx. `3.500 faces`)
  - Fonte: Viking Lander ou LRO (Bus central).
  - Isolar corpo octogonal central e pernas de alunagem (remover antenas e painéis).
  - Criar 4 nós **Empty (Plain Axes)** na superfície com os nomes exatos:
    - `Slot_Propulsion` (em baixo)
    - `Slot_Power` (lateral)
    - `Slot_Comms` (topo)
    - `Slot_Payload` (frente/base)

### 2. Propulsão
- [ ] **`engine_biprop.glb`** (`1.2 m` | Máx. `1.500 faces`)
  - Fonte: Viking Lander (bocal inferior) ou Apollo LMDE.
  - Isolar câmara de combustão e tubeira (bocal).
  - Origem/pivô no topo do motor (encaixe no fundo do chassi), bocal apontado para **`-Y`**.
- [ ] **`engine_ion.glb`** (`0.8 m` | Máx. `1.500 faces`)
  - Fonte: Dawn Spacecraft ou Deep Space 1 (NSTAR Ion Thruster).
  - Isolar cilindro pequeno com grelha azulada, sem cabos internos.

### 3. Energia & Térmico
- [ ] **`solar_array.glb`** (`4.0 m` | Máx. `2.000 faces`)
  - Fonte: Lunar Reconnaissance Orbiter (LRO).
  - Separar asa do painel fotovoltaico e haste de ligação.
  - Origem/pivô exatamente na dobradiça da haste para rotação solar no Godot.
- [ ] **`rtg_cassini.glb`** (`1.5 m` | Máx. `1.800 faces`)
  - Fonte: Cassini Spacecraft ou Curiosity / Perseverance MMRTG.
  - Isolar cilindro preto/dourado com alhetas de radiação térmica; remover suportes internos excessivos.

### 4. Comunicações
- [ ] **`antenna_hga.glb`** (`1.8 m` | Máx. `2.000 faces`)
  - Fonte: Cassini High-Gain Antenna ou DSN 34m Antenna.
  - Isolar prato parabólico principal e alimentador central.
  - Origem/pivô na base do mastro para apontamento à Terra (DTE).

### 5. Payloads Científicos
- [ ] **`payload_drill.glb`** (`1.4 m` | Máx. `1.500 faces`)
  - Fonte: VIPER Rover ou braço do Viking / Phoenix Lander.
  - Extrair torre/broca vertical e caixa do espectrómetro; unificar numa única malha estática.
- [ ] **`payload_sar.glb`** (`1.6 m` | Máx. `1.500 faces`)
  - Fonte: LRO (Mini-RF Antenna) ou MRO Radar.
  - Isolar painel retangular inclinado ou haste da antena SAR.

### 6. Cenário VAB
- [ ] **`sls_block1.glb`** (`18.0 m` | Máx. `5.000 faces`)
  - Fonte: Space Launch System (SLS Block 1) + Launch Pad / VAB.
  - Unificar num único objeto de fundo e apagar geometria interna invisível dos tanques.

---

## Regras de Exportação para Godot 4 (WebGL `gl_compatibility`)
- [ ] Aplicar todas as transformações antes de exportar (`Ctrl + A` → *All Transforms*).
- [ ] Exportar no formato **glTF 2.0 (`.glb`)** com `+Y Up` ativado.
- [ ] Manter texturas compactadas (máx. `512x512` ou `1024x1024` WebP/PNG) para respeitar o limite de **15 MB** do pacote WebGL.
- [ ] Salvar os ficheiros finais em `assets/models/` (`res://assets/models/`).
- [ ] *Nota de integração:* Ao montar a cena `LanderChassis.tscn` no Godot, garantir o mapeamento entre os nós `Slot_*` importados do `lander_bus.glb` e os `mount_point` definidos em [nasa_parts_catalog.json](file:///c:/Users/Rafa/Desktop/Projects/Hackathon---AstraRex/data/nasa_parts_catalog.json).
