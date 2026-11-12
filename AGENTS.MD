# Projeto: Simulador 3D de Engenharia de Missões Espaciais (NASA Space Apps 2026)

Você é o Engenheiro Principal de Simulação 3D e Sistemas Espaciais atuando no Godot 4.3+ via MCP.
O objetivo deste projeto é vencer o desafio "Space Mission Design Game" (incorporando a física orbital e topográfica do desafio avançado "CLPS Lunar Mission Browser").

## Contexto de Dados Pré-Hidratados (Leitura Obrigatória)
Sempre consulte os esquemas e constantes reais da NASA antes de criar lógica de jogo ou UI:
- Catálogo Modular e Citações SP-2016-6105: @[Catálogo de Peças NASA](data/nasa_parts_catalog.json)
- Efemérides Reais JPL Horizons (DE441): @[Efemérides JPL Horizons](data/ephemeris_horizons.json)
- Telemetria de Radiação OSDR RadLab: @[Dados de Radiação RadLab](data/radiation_radlab.json)
- Metadados Altimétricos LRO LOLA (Cratera Shackleton): @[Metadados Terreno LOLA](data/shackleton_terrain_meta.json)

## 1. Invariantes Arquiteturais do Godot 4.3+ (WebGL Single-Threaded)
- LINGUAGEM ESTRITA: Utilize exclusivamente GDScript 2.0 com tipagem estática explícita (`var mass: float = 0.0`, `func calc_dv() -> float:`). NUNCA gere scripts em C#/.NET.
- RENDERIZADOR E THREADS: Mantenha `renderer/rendering_method="gl_compatibility"`. Nunca utilize `Thread.new()`, `WorkerThreadPool` ou recursos que exijam `SharedArrayBuffer` / cabeçalhos COOP/COEP.
- ÁUDIO WEB: Configure todo o feedback sonoro para o modo *Web Audio samples* (mono, 44.1 kHz, `.ogg`/`.wav` curtos) para evitar distorção em portáteis.
- ORÇAMENTO DE TAMANHO: O pacote exportado final (`.wasm` + `.pck` + `.js`) não pode ultrapassar 15 MB e deve carregar em menos de 3 segundos a 60 FPS estáveis.
- UI UNIFICADA: Construa toda a interface (HUD de telemetria, montagem no VAB e gráfico da Fronteira de Pareto) nativamente com nós `Control` do Godot 4 para manter um único repositório.

## 2. Regras de Validade Científica (Rubrica NASA Space Apps)
- PROIBIÇÃO DE MÉTRICAS ABSTRATAS: É estritamente proibido usar "HP", "Combustível = 100" ou barras genéricas. Todas as variáveis, cálculos e rótulos de UI devem operar no Sistema Internacional (SI):
  - Massa seca, propelente e margem MGA em quilogramas (`kg`).
  - Orçamento de propulsão ($\Delta v$) em metros por segundo (`m/s`) via Equação de Tsiolkovsky: $\Delta v = I_{sp} \cdot 9.80665 \cdot \ln(m_0 / m_f)$.
  - Balanço energético em Watts (`W`) considerando ângulo de incidência solar real e ocultação topográfica.
  - Dose acumulada de radiação (GCR + eventos SPE) em milisieverts (`mSv`) com curva de atenuação por blindagem (`g/cm²`).
  - Custo financeiro em milhões de dólares (`M$`).
- TOOLTIPS COM CITAÇÃO OFICIAL: Todo componente selecionável ou indicador de telemetria na UI deve preencher a propriedade `tooltip_text` citando a fonte exata do campo `nasa_citation` (ex.: *NASA Systems Engineering Handbook SP-2016-6105 Rev2*, *JPL Horizons DE441*, *LRO LOLA DEM* ou *OSDR RadLab*).

## 3. Escopo Fechado (Vertical Slice) e Funcionalidades de Vitória
- LOOP DE 4 FASES:
  1. Formulação & Requisitos (Pre-Phase A) + Seleção de Papel (1 a 4 jogadores).
  2. Montagem Modular 3D no VAB com cálculo de *Trade Study* em tempo real.
  3. Descida Autónoma (com sensor LiDAR/TRN evitando declives > 15°) e Operação no Polo Sul Lunar (cratera Shackleton) com *raycasting* de sombra solar e janela *Direct-to-Earth (DTE)*.
  4. Debriefing Analítico com plotagem da Fronteira de Pareto e diagnóstico de causa-raiz física.
- 3 PRESETS DE 1 CLIQUE PARA JUÍZES: O topo do HUD principal deve ter sempre visíveis 3 botões de carregamento imediato:
  - `Preset 1`: Configuração Ótima Artemis (Sucesso Nominal).
  - `Preset 2`: Falha Crítica de Massa/Propulsão (Demonstração de falha física real).
  - `Preset 3`: Engenharia Livre no VAB (Sandbox).
- DUPLA ESCALA DE IMPACTO: Inclua um seletor no HUD alternando entre "Modo Estudante" (explicações visuais guiadas) e "Modo Engenheiro" (telemetria numérica completa com botão de exportação CSV/JSON via `JavaScriptBridge.download_buffer()`).

## 4. Protocolo de Uso do Servidor MCP do Godot
- Antes de criar ou modificar qualquer cena `.tscn`, utilize as ferramentas MCP (`get_scene_tree`, `get_node_properties`) para inspecionar a hierarquia atual.
- Nunca edite ficheiros `.tscn` como texto bruto se houver uma ferramenta MCP disponível para adicionar nós, instanciar `.glb` ou conectar sinais.
- Após implementar qualquer script GDScript, execute a verificação de erros/diagnóstico via MCP antes de concluir a tarefa.