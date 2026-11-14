## Checklist do Projeto (Sem Modelos 3D)

### A. Dados, Terreno e Infraestrutura Base
- [x] Configurar `AGENTS.MD`, `.agents/rules/` e `.agents/skills/`
- [x] Gerar `ephemeris_horizons.json`, `radiation_radlab.json` e `shackleton_terrain_meta.json`
- [x] Criar `nasa_parts_catalog.json` inicial com 13 subsistemas e 3 presets
- [x] Completar `data/nasa_parts_catalog.json`: adicionar `launch_vehicles`, `orbits`, `data_rate_gb_day` nos payloads e módulo de Computador de Bordo/ADCS
- [x] Criar `lola_dem_to_heightmap16.py` e gerar `assets/terrain/shackleton_heightmap_16bit.png` (1024x1024) + texturas WebP de regolito (< 400 KB)
- [ ] Alinhar pasta `scripts/` vs `content/` para auditoria no GitHub
- [x] Inicializar projeto Godot 4.3+ (`space-app-challenge-2026---astra-rex/` com `gl_compatibility` e estrutura de pastas)
- [ ] Configurar `export_presets.cfg` para WebGL Single-Threaded (`variant/thread_support=false`)

### B. Núcleo Lógico e Física (`src/autoloads/`)
- [ ] `NasaDataLoader.gd`: carregar os 4 JSONs de `res://data/` via `FileAccess` no `_ready()`
- [ ] `MissionState.gd`: calcular os 6 recursos no SI (Massa + MGA, Potência líquida, Orçamento M$, Dados GB/dia vs Mbps, Delta-v Tsiolkovsky, Dose mSv e Vida Útil)
- [ ] `MissionState.gd`: implementar `LaunchVehicleCheck` (validação `m0` vs lançador e órbita), bloqueio `T/W < 1.0` lunar (`g = 1.625 m/s²`), gestão dos 1–4 papéis da equipa e eventos SPE (RadLab)
- [ ] `MissionState.gd`: implementar lógica dos 3 Presets de Juízes e alternador Modo Estudante / Modo Engenheiro
- [ ] `ParetoSolver.gd`: calcular Fronteira de Pareto (time-sliced com `await get_tree().process_frame`, sem `Thread`), diagnóstico de causa-raiz e exportação CSV/JSON via `JavaScriptBridge.download_buffer()`

### C. Cenas e Interface (`src/scenes/`)
- [ ] `MainHUD.tscn`: barra superior fixa com 3 Presets, alternador Estudante/Engenheiro e os 6 indicadores no SI
- [ ] `Phase1_Planning.tscn`: seleção de objetivo científico, 1–4 papéis, veículo lançador e órbita (LLO vs NRHO)
- [ ] `Phase2_VAB.tscn`: acoplamento nos 7 slots `Marker3D` (usando placeholders até os `.glb` chegarem), recálculo instantâneo e `tooltip_text` com `nasa_citation`
- [ ] `Phase3_LunarSim.tscn`: terreno `HeightMapShape3D` de Shackleton, descida em malha fechada (PID), tombamento em declive > 15° sem LiDAR/TRN, `RayCast3D` solar/DTE e evento de tempestade SPE
- [ ] `Phase4_Debrief.tscn`: gráfico da Fronteira de Pareto via `Control._draw()`, diagnóstico físico de causa-raiz, comparação com ótimo da NASA e botões de exportar/partilhar

### D. Polimento, Áudio, QA e Submissão
- [ ] Criar shader GLES3/WebGL2 para grelha LiDAR (declives > 15°) e `GPUParticles3D` de propulsão
- [ ] Adicionar samples de áudio Web Audio (mono, 44.1 kHz, `.ogg`/`.wav`, < 1.5 MB): acoplamento VAB, Quindar tones DSN, propulsão e alerta SPE
- [ ] Validar performance a 60 FPS (timers de 0.1s–0.2s para telemetria/raycasts)
- [ ] Gerar build WebGL final e auditar tamanho total (< 15 MB) e tempo de boot (< 3 s)
- [ ] Publicar no Itch.io e Vercel/Cloudflare Pages sem erros de COOP/COEP
- [ ] Atualizar `README.md` com equações, arquitetura e citação dos 5 datasets da NASA
- [ ] Teste Zero-Trust em janela anónima (4G/5G) verificando todos os links antes da submissão