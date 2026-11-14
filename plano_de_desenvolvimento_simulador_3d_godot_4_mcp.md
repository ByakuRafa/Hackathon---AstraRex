# Plano de Desenvolvimento: Simulador 3D de Engenharia de Sistemas e Design de Missão (Godot 4 + MCP)

A consolidação do Enunciado Oficial do Desafio, do Dossiê Estratégico e da arquitetura base em Godot 4 + MCP estrutura o projeto como um **Simulador Interativo 3D de Engenharia de Sistemas e Design de Missão Assistido por IA**, fundindo a mecânica colaborativa do desafio *Space Mission Design Game* com o rigor físico, orbital e topográfico do desafio avançado *CLPS Lunar Mission Browser*.

---

## 1. Matriz de Alinhamento Estratégico e Requisitos do Sistema

O cruzamento dos requisitos oficiais com o dossiê técnico estabelece a gestão em tempo real dos 6 recursos mandatórios no Sistema Internacional (Massa, Potência, Orçamento, Volume de Dados, Comunicações e Vida Útil), a inclusão dos 7 subsistemas modulares (incluindo Computador de Bordo e Controlo de Atitude — ADCS) e a validação física entre Veículo Lançador, Massa Total e Órbita. A tabela abaixo relaciona cada dimensão do projeto com a implementação técnica correspondente:

| Dimensão do Projeto | Requisito do Enunciado Oficial | Diretriz do Dossiê Estratégico | Implementação no Plano Godot 4 + Agentes MCP |
| :--- | :--- | :--- | :--- |
| **Foco Pedagógico e Técnico** | Tornar tangíveis os *trade-offs* entre objetivos científicos, desenho da sonda, instrumentos, lançador e órbita do conceito à operação. | Evitar quizzes 2D amadores; construir um simulador 3D com física real em unidades SI e otimizador multiobjetivo (Fronteira de Pareto). | Simulador 3D em Godot 4.3+ (*Single-Threaded WebGL*) orquestrado no desenvolvimento via Google Antigravity + MCP com código 100% GDScript tipado. |
| **Gestão dos 6 Recursos Críticos** | Exibir e gerir em tempo real: Massa, Potência, Orçamento, Dados (*Data*), Comunicações e Tempo (Vida Útil). | Operar exclusivamente no Sistema Internacional ($\text{kg}$, $\text{W}$, $\text{M\$}$, $\text{m/s}$ de $\Delta v$, $\text{mSv}$) com *tooltips* citando fontes da NASA. | Singleton `MissionState.gd` calculando Massa + margem MGA ($\text{kg}$), Potência ($\text{W}$), Custo ($\text{M\$}$), Taxa de Dados ($\text{GB/dia}$ vs. $\text{Mbps}$ DSN), $\Delta v$ ($\text{m/s}$), Dose ($\text{mSv}$) e Vida Útil (dias). |
| **Subsistemas da Espaçonave** | Incluir estrutura, sistemas de potência, baterias, comunicações, computadores de bordo, controlo de atitude e instrumentos científicos. | Utilizar malhas `.glb` reais do *NASA 3D Resources* otimizadas no Blender e parametrizadas pelo manual *NASA SP-2016-6105*. | 7 slots `Marker3D` no chassi CLPS para acoplar estrutura/blindagem, propulsão, geração de energia (Solar/RTG), baterias, antena DSN, aviónica/ADCS e *payloads* (TRIDENT/SAR). |
| **Órbita e Veículo Lançador** | Oferecer opções orbitais, explicar características de cobertura/comunicação e validar se a massa e órbita são compatíveis com o foguetão. | Integrar vetores cartesianos reais da fonte DE441 do *JPL Horizons API* para janelas de lançamento e visibilidade *Direct-to-Earth* (DTE). | Validador pré-lançamento (`LaunchVehicleCheck`) comparando a massa total $m_0$ com a capacidade de injeção translunar do lançador (ex.: SLS Block 1 vs. comercial) para a órbita selecionada. |
| **Colaboração e Escala de Utilizador** | Suportar modo individual ou equipas de até 4 jogadores com papéis distintos negociando prioridades, além de diferentes níveis de dificuldade. | Arquitetar dupla escala de impacto ("Modo Estudante" guiado + "Modo Engenheiro" exportável em CSV/JSON) e 3 *Presets* de 1 clique para juízes. | Seletor de 1 a 4 papéis assimétricos (Planeamento, Nave, Ciência, Comunicações), botão de exportação de telemetria via `JavaScriptBridge` e 3 *Presets* fixos no topo do HUD. |
| **Eventos e Análise Pós-Missão** | Incluir eventos aleatórios/restrições inesperadas, modo *sandbox*, relatórios pós-missão e função de guardar/comparar designs. | Parametrizar eventos reais de partículas solares (SPE) via *OSDR RadLab API*, declives topográficos LRO LOLA e *debriefing* com Fronteira de Pareto. | Eventos dinâmicos de tempestade solar (SPE) e sombra na cratera Shackleton, modo *Sandbox* (Preset 3), exportação/importação de código de design e gráfico de Pareto. |

---

## 2. Arquitetura de Hidratação de Dados da NASA (3 Camadas e Pré-Auditoria)

Para integrar os conjuntos de dados oficiais da agência sem sofrer estrangulamentos de rede, limites de requisição ou bloqueios de CORS durante a execução no navegador, a camada de dados divide-se em três níveis pré-hidratados:

### Camada 1 — ETL Estático e Decimação Espacial Offline (Python & Blender)
* **JPL Horizons API** (`https://ssd.jpl.nasa.gov/api/horizons.api`): O script `nasa_data_hydrator.py` realiza consultas com `format='json'`, `EPHEM_TYPE='VECTORS'` e `'OBSERVER'` para extrair do bloco EOE os vetores cartesianos ($X, Y, Z, V_x, V_y, V_z$) e ângulos de elevação solar da efeméride DE441 para a Terra (`COMMAND='399'`), Lua (`'301'`), Sol (`'10'`) e Marte (`'499'`), gerando `ephemeris_horizons.json` para orientar a luz solar e calcular a visibilidade *Direct-to-Earth* (DTE).
* **LRO LOLA Digital Elevation Models** (`LDEM_85S_20M` / `LDEM_*S_5M` no portal Lunar ODE): O script `lola_dem_to_heightmap16.py` processa os recortes GeoTIFF das latitudes $85^\circ\text{S}$ a $90^\circ\text{S}$ (focados na cratera Shackleton, $89.9^\circ\text{S}$) com resolução de $5\text{ m/px}$ a $20\text{ m/px}$, gerando o mapa de deslocamento `shackleton_heightmap_16bit.png` ($1024 \times 1024$) e o ficheiro `shackleton_terrain_meta.json` com a escala altimétrica exata para alimentar o `HeightMapShape3D` no Godot.
* **NASA 3D Resources Repository**: O script *headless* `blender_nasa_optimizer.py` limpa a geometria interna, aplica o modificador *Decimate* (teto de $1.500\text{ a }5.000\text{ faces}$ por módulo), normaliza a escala métrica ($1\text{ unidade} = 1\text{ m}$) e exporta os modelos públicos da NASA em ficheiros `.glb` compactos com texturas WebP ($512 \times 512$).

### Camada 2 — Consumo Normalizado de Telemetria de Radiação (OSDR RadLab API)
* **NASA OSDR RadLab API** (`https://visualization.osdr.nasa.gov/radlab/api`): Hidrata o ficheiro `radiation_radlab.json` via API REST com leituras reais de radiação cósmica galáctica (GCR em $\text{mSv/dia}$) e picos de eventos de partículas solares (SPE em $\text{mSv/hora}$), parametrizando a degradação eletrónica e a exigência de blindagem durante o trânsito e operação lunar.

### Camada 3 — Modelos Físicos Analíticos Substitutos (*Physics-Informed Surrogates*)
* **NASA Systems Engineering Handbook (NASA SP-2016-6105 Rev2)**: Codifica diretamente no catálogo `nasa_parts_catalog.json` e nos Singletons GDScript as fases oficiais do ciclo de vida (*Pre-Phase A* a *Phase E*), as margens obrigatórias de crescimento de massa (*Mass Growth Allowance* — MGA), a Equação de Foguete de Tsiolkovsky ($\Delta v = I_{sp} \cdot 9.80665 \cdot \ln(m_0 / m_f)$), a relação Empuxo-Peso lunar ($T/W > 1.0$ com $g_{\text{moon}} = 1.625\text{ m/s}^2$), a curva de atenuação de radiação por blindagem ($\text{g/cm}^2$), o balanço de potência solar com ângulo de incidência ($\cos\theta$) e o orçamento de ligação de dados (*Data Generated* vs. *DSN Downlink Capacity*).

---

## 3. Design do Jogo e Loop Operacional (*Vertical Slice*: Polo Sul Lunar)

O escopo fecha um fluxo vertical completo (*Vertical Slice*) focado numa missão ao Polo Sul Lunar (Cratera Shackleton), estruturado em quatro fases contínuas e apoiado por uma barra superior de avaliação rápida:

### Barra Global Fixa (Acessibilidade de Avaliação em $< 45\text{ s}$ e Dupla Escala)
* **Preset 1 — Configuração Ótima Artemis (Sucesso Nominal):** Carrega instantaneamente uma sonda CLPS balanceada (motor químico bipropelente, gerador nuclear MMRTG, antena Ka-Band, sensor LiDAR/TRN, radar SAR e perfuradora TRIDENT) pronta para simular uma alunagem perfeita e alto retorno científico.
* **Preset 2 — Falha Crítica de Massa e Propulsão:** Carrega uma sonda sobrecarregada com propulsor iónico de baixo empuxo ($\text{Thrust} < 100\text{ N}$) e painéis solares sem bateria secundária suficiente, demonstrando a falha física na descida terminal e o apagão energético na sombra da cratera.
* **Preset 3 — Modo Sandbox / Engenharia Livre no VAB:** Desbloqueia todos os componentes sem restrições iniciais de orçamento ou lançador para experimentação livre.
* **Alternador Modo Estudante / Modo Engenheiro:** O "Modo Estudante" exibe explicações pedagógicas guiadas e indicadores visuais; o "Modo Engenheiro" apresenta telemetria numérica completa no SI e habilita a exportação de relatórios CSV/JSON via `JavaScriptBridge.download_buffer()` e códigos partilháveis de missão.

### Fase 1 — Formulação da Missão, Seleção de Órbita/Lançador e Papéis de Equipa (*Pre-Phase A*)
* O jogador individual ou equipa de até 4 participantes assume papéis especializados:
  1. Planeador de Missão/Lançador
  2. Engenheiro de Nave/Propulsão
  3. Diretor Científico/Payloads
  4. Engenheiro de Comunicações/Potência & Recursos
* A equipa define o objetivo científico, seleciona o veículo lançador (validando orçamento e massa máxima de injeção translunar) e escolhe a órbita operacional (ex.: Órbita Polar Lunar Baixa de $100\text{ km}$ vs. Órbita Halo Quase-Retilínea NRHO), observando o impacto direto no $\Delta v$ requerido, na janela de visibilidade com a Terra e na vida útil da missão.

### Fase 2 — Montagem Modular 3D e *Trade Study* no VAB (*Phase A–C*)
* No interior do *Vehicle Assembly Building* (VAB) 3D, os jogadores acoplam os 7 subsistemas nos nós `Marker3D` do chassi: Estrutura/Blindagem, Propulsão, Geração de Energia (Painel Solar vs. RTG), Baterias Secundárias, Computador de Bordo/ADCS (com sensor ótico/LiDAR TRN), Antena de Comunicações (DSN) e Instrumentos Científicos.
* Cada peça acoplada recalcula instantaneamente os 6 indicadores de recursos (Massa com MGA em $\text{kg}$, Potência líquida em $\text{W}$, Orçamento em $\text{M\$}$, Geração de Dados em $\text{GB/dia}$, Taxa de Transmissão em $\text{Mbps}$ e Vida Útil estimada em dias) e preenche a propriedade `tooltip_text` com a citação exata do manual *NASA SP-2016-6105*.

### Fase 3 — Simulação Orbital, Descida Autónoma e Operação de Superfície (*Phase D–E*)
* **Verificação de Lançamento e Trânsito Cislunar:** O motor valida se a massa total $m_0$ é suportada pelo veículo lançador selecionado, executa a queima de inserção translunar e pode disparar um Evento Aleatório Realista (tempestade solar SPE parametrizada pela RadLab API), exigindo blindagem adequada ou entrada em modo de segurança (*Safe Mode*) pelo computador de bordo.
* **Alunagem e Raycasting Topográfico na Cratera Shackleton:** A sonda desce controlada por malha fechada (PID) sobre a malha `HeightMapShape3D` real do altímetro LRO LOLA. Se o declive local exceder $15^\circ$ sem o módulo de Navegação Relativa ao Terreno (LiDAR/TRN), ocorre tombamento físico; na superfície, nós `RayCast3D` verificam continuamente a iluminação solar nos painéis e a linha de visada direta à Terra (DTE) para escoamento dos dados científicos.

### Fase 4 — Debriefing Analítico, Causa-Raiz e Fronteira de Pareto
* Ao concluir a simulação, o painel de *Post-Mortem Telemetry Debrief* plota a Fronteira de Pareto (Rendimento Científico vs. Massa/Custo vs. Probabilidade de Sobrevivência), apresenta o diagnóstico físico de causa-raiz (ex.: gargalo de transmissão por antena subdimensionada ou défice energético em região permanentemente sombreada PSR) e permite guardar, exportar (CSV/JSON) ou comparar a arquitetura com o ótimo da NASA.

---

## 4. Engenharia da Rubrica Oficial da NASA (Alinhamento Técnico)

As funcionalidades do simulador mapeiam diretamente os cinco critérios de avaliação da NASA para posicionar o projeto nas categorias *Best Mission Concept*, *Best Use of Science* e *Best Use of Technology*:

| Critério Oficial | Armadilha Eliminada | Implementação Técnica no Projeto |
| :--- | :--- | :--- |
| **1. Impacto (*Impact*)** | Declarar vagamente que o jogo "educa estudantes" sem utilidade mensurável. | **Dupla Escala:** "Modo Estudante" (ensino guiado de *trade-offs* em equipa de até 4 jogadores) + "Modo Engenheiro" com telemetria exportável em CSV/JSON para análise preliminar real (*Pre-Phase A*). |
| **2. Criatividade (*Creativity*)** | Construir um quiz 2D estático ou *dashboard* CRUD sem simulação espacial integrada. | **Fusão Interdisciplinar:** Acoplamento de um otimizador multiobjetivo (Fronteira de Pareto) dentro de um simulador 3D interativo em Godot 4 WebGL com topografia lunar LRO LOLA real. |
| **3. Validade (*Validity*)** | Usar barras fictícias ("HP = 100", "Combustível = 50") desconectadas da física. | **Rigor SI e Citações:** Equação de Tsiolkovsky, MGA do *NASA SP-2016-6105*, vetores JPL Horizons DE441 e doses OSDR RadLab com *tooltips* citando cada fonte oficial na interface. |
| **4. Relevância (*Relevance*)** | Entregar um protótipo incompleto com botões desativados ou sem elo com o enunciado. | **Vertical Slice 100% Funcional:** Ciclo completo ($\text{Formulação} \rightarrow \text{VAB} \rightarrow \text{Alunagem} \rightarrow \text{Debriefing de Pareto}$) cobrindo os 6 recursos e 7 subsistemas exigidos no enunciado. |
| **5. Apresentação Técnica & Acesso** | Submeter aplicações que exigem instalação local, falham por bloqueios COOP/COEP ou retornam erros 403/404. | **Deploy WebGL Single-Threaded Redundante:** Carregamento no *browser* em $< 3\text{ s}$ (Itch.io + Vercel/Cloudflare Pages), *Presets* de 1 clique e repositório GitHub público com os scripts Python de extração de dados. |

---

## 5. Arquitetura Técnica no Godot 4.3+ e Preparação de Assets

Para maximizar a velocidade de execução em modo Solo ou Duo sem dividir esforços entre dois repositórios distintos (React + Godot), toda a interface gráfica (`Control` nodes) e a simulação 3D (`Node3D`) são unificadas num único projeto Godot 4.3+ configurado com `renderer/rendering_method="gl_compatibility"` e exportação WebGL *Single-Threaded*.

### 5.1. Estrutura de Diretórios e Invariantes do Agente MCP (Antigravity)

A organização do repositório inclui as regras e *skills* de automação para o servidor MCP do Godot (ex.: `tugcantopaloglu/godot-mcp`, `Coding-Solo/godot-mcp` ou `hi-godot/godot-ai`) e os scripts Python de auditoria científica:

```text
space-mission-simulator/
├── AGENTS.md                           # Instruções permanentes (SI, WebGL Single-Threaded, @JSONs)
├── .agents/
│   ├── rules/
│   │   └── godot-coding-standards.md   # Regras YAML glob (*.gd, *.tscn) para GDScript tipado e 60 FPS
│   └── skills/
│       ├── verify-nasa-physics/        # Skill (/verify-nasa-physics): audita Tsiolkovsky, MGA, DTE e RadLab
│       ├── build-vab-module/           # Skill (/build-vab-module): instancia .glb e cria UI com citação NASA
│       ├── generate-pareto-debrief/    # Skill (/generate-pareto-debrief): plota curva de Pareto e causa-raiz
│       └── package-itch-webgl/         # Skill (/package-itch-webgl): valida <15MB e gera .zip Single-Threaded
├── scripts/                            # Prova de autenticidade técnica para auditoria no GitHub
│   ├── nasa_data_hydrator.py           # Extrator JPL Horizons API (DE441) + OSDR RadLab API + Catálogo
│   ├── lola_dem_to_heightmap16.py      # Conversor GeoTIFF LRO LOLA -> PNG 16 bits + metadados
│   └── blender_nasa_optimizer.py       # Automação headless do Blender (Decimate + WebP + export .glb)
├── data/                               # Camada 1 & 2: Dados da NASA Pré-Hidratados
│   ├── nasa_parts_catalog.json         # 7 categorias de subsistemas, lançadores, órbitas e citações SP-2016-6105
│   ├── ephemeris_horizons.json         # Vetores DE441 Terra/Lua/Sol/Marte (JPL Horizons API)
│   ├── radiation_radlab.json           # Taxas GCR e eventos SPE (NASA OSDR RadLab API)
│   └── shackleton_terrain_meta.json    # Escala altimétrica real do Polo Sul Lunar (LRO LOLA)
├── assets/
│   ├── models/                         # Malhas .glb otimizadas no Blender (< 2.5 MB total)
│   ├── terrain/                        # shackleton_heightmap_16bit.png + texturas WebP de regolito (< 400 KB)
│   └── audio/                          # Samples .ogg/.wav mono 44.1 kHz (< 1.5 MB total)
└── src/
    ├── autoloads/
    │   ├── NasaDataLoader.gd           # Carrega os 4 JSONs da NASA em memória no _ready() via FileAccess
    │   ├── MissionState.gd             # Gere os 6 recursos, 4 papéis da equipa, Tsiolkovsky e eventos SPE
    │   └── ParetoSolver.gd             # Calcula a Fronteira de Pareto e exporta telemetria CSV/JSON
    └── scenes/
        ├── MainHUD.tscn                # Barra superior (3 Presets de Juízes, Modo Estudante/Engenheiro, 6 Recursos)
        ├── Phase1_Planning.tscn        # Objetivos, seleção de 1-4 papéis, veículo lançador e órbita
        ├── Phase2_VAB.tscn             # Montagem modular 3D com Marker3D e tooltips científicos
        ├── Phase3_LunarSim.tscn        # Descida na cratera Shackleton, RayCast3D solar/DTE e tempestade SPE
        └── Phase4_Debrief.tscn         # Gráfico da Fronteira de Pareto, relatório pós-missão e partilha
```

#### Invariantes de Compilação e Código (`AGENTS.md`)
* **Linguagem Estrita:** Exclusivamente GDScript 2.0 com tipagem estática explícita (`var mass: float = 0.0`, `func calc_dv() -> float:`). Proibido o uso de C#/.NET para garantir compatibilidade com WebAssembly no Godot 4.
* **Single-Threaded WebGL:** Proibido instanciar `Thread.new()` ou `WorkerThreadPool`, eliminando dependências de `SharedArrayBuffer` e erros de cabeçalhos COOP/COEP no Itch.io ou Vercel.
* **Orçamento de Memória e Áudio:** Pacote final (`.wasm` + `.pck` + `.js`) estritamente abaixo de $15\text{ MB}$ (considerando $\sim 8\text{ MB}$ do motor base) e áudio configurado em modo *Web Audio samples* (mono, $44.1\text{ kHz}$) para evitar distorções no navegador.
* **Protocolo MCP:** Os agentes devem inspecionar a árvore de nós via ferramentas MCP (`get_scene_tree`, `get_node_properties`) antes de modificar cenas `.tscn` e validar diagnósticos de script após cada edição.

### 5.2. Especificação dos Modelos 3D e Terreno (Orçamento $< 2.5\text{ MB}$)

Os modelos tridimensionais devem ser extraídos dos repositórios públicos da NASA (`nasa/NASA-3D-Resources`, `science.nasa.gov/3d-resources` e `nasa3d.arc.nasa.gov/models`), orientados com a frente para $-Y$ no Blender (convertido para $-Z$ no Godot com $+Y\text{ Up}$), com transformações aplicadas (`Ctrl+A -> All Transforms`) e peso individual entre $80\text{ KB}$ e $350\text{ KB}$:

| Ficheiro Final (`.glb`) | Modelo Fonte na NASA | Escala & Limite Poligonal | Preparação Técnica no Blender |
| :--- | :--- | :--- | :--- |
| `lander_bus.glb` | Viking Lander ou LRO (Bus central) | $3.2\text{ m}$ \| Máx. $3.500\text{ faces}$ | Isolar o chassi octogonal e pernas de alunagem. Criar os nós *Empty* de acoplamento (`Slot_Structure`, `Slot_Propulsion`, `Slot_Power`, `Slot_Battery`, `Slot_Avionics`, `Slot_Comms`, `Slot_Payload`). |
| `engine_biprop.glb` | Viking Lander ou Apollo Descent Engine | $1.2\text{ m}$ \| Máx. $1.500\text{ faces}$ | Isolar a câmara de combustão e tubeira do motor químico. Posicionar a origem (pivô) no topo de encaixe apontando o bocal para $-Y$. |
| `engine_ion.glb` | Dawn Spacecraft ou Deep Space 1 (NSTAR) | $0.8\text{ m}$ \| Máx. $1.500\text{ faces}$ | Isolar o cilindro propulsor com a grelha iónica/Hall, removendo cabos internos. |
| `solar_array.glb` | Lunar Reconnaissance Orbiter (LRO) | $4.0\text{ m}$ \| Máx. $2.000\text{ faces}$ | Isolar a asa fotovoltaica e haste de ligação. Posicionar o pivô na dobradiça para rotação em direção ao vetor solar no Godot. |
| `rtg_cassini.glb` | Cassini ou Perseverance MMRTG | $1.5\text{ m}$ \| Máx. $1.800\text{ faces}$ | Isolar o cilindro termoelétrico com alhetas de radiação térmica, removendo suportes internos. |
| `antenna_hga.glb` | Cassini High-Gain Antenna ou DSN 34m | $1.8\text{ m}$ \| Máx. $2.000\text{ faces}$ | Isolar o prato parabólico e alimentador central. Posicionar o pivô na base do mastro para apontamento à Terra (DTE). |
| `payload_drill.glb` | VIPER Rover ou Phoenix Lander | $1.4\text{ m}$ \| Máx. $1.500\text{ faces}$ | Extrair a torre/broca vertical de perfuração polar (TRIDENT) e caixa do espectrómetro numa malha estática única. |
| `payload_sar.glb` | LRO (Mini-RF) ou MRO Radar | $1.6\text{ m}$ \| Máx. $1.500\text{ faces}$ | Isolar o painel retangular inclinado ou haste da antena de radar de abertura sintética (SAR). |
| `sls_block1.glb` | Space Launch System (SLS Block 1) + VAB | $18.0\text{ m}$ \| Máx. $5.000\text{ faces}$ | Unificar o veículo lançador num objeto único de fundo para a cena de montagem e validação de lançamento, apagando geometria interna. |

### 5.3. Divisão de Tarefas Pré-Hackathon (Preparação da Dupla)

A preparação prévia divide-se entre a infraestrutura lógica/MCP e o pipeline de *assets* 3D/topográficos:

* **Membro 1 (Arquiteto de Simulação 3D, Física, Dados & Agentes MCP):**
  1. Executar `nasa_data_hydrator.py` para gerar os JSONs estáticos do JPL Horizons e OSDR RadLab, parametrizando no `nasa_parts_catalog.json` os 7 subsistemas (incluindo computadores de bordo e ADCS), taxas de dados (`data_rate_gb_day` vs. `downlink_mbps`), veículos lançadores e órbitas.
  2. Configurar o ambiente Google Antigravity conectado ao servidor MCP do Godot 4, validando o ficheiro `AGENTS.md`, os padrões de código em `.agents/rules/` e as 4 *Skills* em `.agents/skills/`.
  3. Realizar um *dry run* de compilação WebGL *Single-Threaded* no Itch.io e Cloudflare Pages / Vercel, confirmando ausência de erros COOP/COEP e carregamento abaixo de 3 segundos.

* **Membro 2 (Especialista de Modelos 3D, Terreno LOLA, UI & Áudio):**
  1. Descarregar os modelos brutos do *NASA 3D Resources*, isolar os subsistemas no Blender e executar `blender_nasa_optimizer.py` para entregar a pasta `assets/models/` abaixo de $2.5\text{ MB}$ totais.
  2. Descarregar o recorte GeoTIFF do Polo Sul Lunar (`LDEM_85S_20M`) no portal Lunar ODE e executar `lola_dem_to_heightmap16.py` para gerar `shackleton_heightmap_16bit.png` ($1024 \times 1024$), `shackleton_terrain_meta.json` e as texturas PBR `regolith_albedo.webp` e `regolith_normal.webp` ($< 400\text{ KB}$).
  3. Preparar a tipografia técnica (Inter/Roboto e JetBrains Mono), os ícones SVG das grandezas do SI, os *shaders*/partículas (`GPUParticles3D` para propulsão e grelha topográfica LiDAR para declives $> 15^\circ$) e os efeitos sonoros mono $44.1\text{ kHz}$ ($< 1.5\text{ MB}$) para feedback de acoplamento no VAB, *Quindar tones* da rede DSN, propulsão e alertas de tempestade solar.

---

## 6. Cronograma Técnico de Desenvolvimento nas 48 Horas e Portões de Controlo

O plano de execução para o fim de semana do hackathon aplica três Portões de Controlo (*Quality Gates*) técnicos para impedir *scope creep* e assegurar estabilidade de produção:

| Horário | Fase Operacional | Execução no Godot 4 + Antigravity MCP | Documentação Técnica, Dados e Repositório | Portão de Controlo (*Quality Gate*) |
| :--- | :--- | :--- | :--- | :--- |
| **Sáb 09:00–11:00** | **1. Ignição & Escopo** | Inicialização do repositório Git e importação dos *assets* `.glb`, texturas, mapa de altura 16 bits e JSONs pré-auditados no esqueleto Godot 4.3+. | Criação da página oficial em `spaceappschallenge.org`, associação da equipa e definição do *Vertical Slice* do Polo Sul Lunar. | Página oficial criada; escopo fechado no fluxo de 4 fases sem *scope creep*. |
| **Sáb 11:00–15:00** | **2. Núcleo Físico & Recursos** | Acionamento da skill `/verify-nasa-physics` para implementar `NasaDataLoader.gd` e `MissionState.gd` com os 6 recursos no SI, equação de Tsiolkovsky, MGA e validador de lançador/órbita. | Documentação das equações físicas e das 5 fontes de dados (Horizons, LOLA, RadLab, NASA 3D, SP-2016-6105) para a página do projeto e `README.md`. | Singletons a calcular massa/MGA, potência, dados, $\Delta v$, radiação e iluminação a $60\text{ FPS}$. |
| **Sáb 15:00–19:00** | **3. Loop VAB & Alunagem** | Acionamento da skill `/build-vab-module` para construir `Phase1_Planning.tscn` (1–4 papéis, órbita/lançador), `Phase2_VAB.tscn` (7 subsistemas em `Marker3D`) e `Phase3_LunarSim.tscn` (`HeightMapShape3D` + `RayCast3D`). | Redação em inglês das secções técnicas *Executive Summary*, *Background*, *Mission Trade-offs* e *Scientific Validity* da página oficial. | Loop jogável completo: configurar missão $\rightarrow$ acoplar módulos $\rightarrow$ simular alunagem e eventos SPE. |
| **Sáb 19:00–23:00** | **4. Pareto & 1.º Deploy** | Acionamento de `/generate-pareto-debrief` e `/package-itch-webgl` para implementar `ParetoSolver.gd`, `Phase4_Debrief.tscn`, exportação CSV/JSON via `JavaScriptBridge` e *build* WebAssembly. | Publicação do primeiro pacote WebGL público no Itch.io e Vercel / Cloudflare Pages e validação de execução sem cabeçalhos COOP/COEP. | **PORTÃO 1 (23:00):** Simulador funcional e acessível num URL público antes da pausa de descanso. |
| **Sáb 23:00–Dom 06:30** | **5. Descanso & Estabilização** | Pausa obrigatória de 5 a 6 horas de sono para evitar regressões críticas de código na reta final. | Revisão assíncrona de ícones SVG do HUD e validação de integridade do *branch* `main`. | Código estável no *branch* `main` e equipa descansada. |
| **Dom 06:30–11:00** | **6. Polimento, UI & Presets** | Refinamento de `MainHUD.tscn`, *tooltips* com citações da NASA, *shaders* LiDAR, áudio *Web Audio samples* e calibração dos 3 *Presets* de 1 Clique no topo do ecrã. | Elaboração do diagrama de arquitetura técnica e dos gráficos comparativos para incorporar na página oficial e no `README.md` do GitHub. | **PORTÃO 2 (11:00 — HARD FEATURE FREEZE):** Proibido adicionar novas funcionalidades após as 11:00. |
| **Dom 11:00–13:30** | **7. QA, Performance & Boot** | Correção exclusiva de *bugs* visuais, auditoria de FPS na cena da cratera Shackleton e otimização do pacote `.wasm`/`.pck` ($< 15\text{ MB}$) para tempo de boot $< 3\text{ s}$. | Consolidação da documentação técnica e verificação de todos os links públicos da aplicação interativa. | *Build* final estável a $60\text{ FPS}$ com carregamento instantâneo nos dois *hosts* públicos. |
| **Dom 13:30–18:00** | **8. Demonstração Técnica & Ajustes** | Execução ao vivo da aplicação usando os *Presets* de 1 clique, o alternador Estudante/Engenheiro e a exportação CSV/JSON. | Atualização do texto técnico na página do projeto para clarificar eventuais dúvidas de engenharia ou validação científica. | Página oficial 95% finalizada e validada tecnicamente. |
| **Dom 18:00–21:00** | **9. Auditoria de Repositório & Submissão** | Limpeza final do repositório GitHub público, incluindo a diretoria `scripts/` com os extratores Python como prova de autenticidade e verificação de licenças *open-source*. | Preenchimento final dos campos em inglês na plataforma Space Apps com o link da demo interativa no topo e citação explícita dos 5 *datasets* da NASA. | **PORTÃO 3 (21:00 — SUBMISSÃO SEGURA):** Projeto submetido oficialmente 3 horas antes do prazo limite. |
| **Dom 21:00–23:59** | **10. Protocolo Zero-Trust** | Congelamento total do ambiente de produção (zero *commits* ou *deploys* destrutivos de última hora). | Teste da Janela Anónima em Rede Externa (4G/5G): abrir a página submetida num dispositivo não autenticado e testar todos os links (Itch.io, Vercel, GitHub e documentação). | Submissão 100% auditada e livre de erros 403/404 antes das 23:59. |