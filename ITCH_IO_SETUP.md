# AstraRex — Guia de Configuração e README para Itch.io (NASA Space Apps 2026)

Este documento reúne todas as configurações exatas do painel do **Itch.io** compatíveis com o build WebGL2 single-thread gerado pelo Godot 4.7.2 (`gl_compatibility`) e um texto pronto para copiar e colar na descrição da página do projeto.

---

## 1. Arquivo para Upload

- **Arquivo exato a enviar:** `space-app-challenge-2026---astra-rex/build/astra_rex_itch_webgl.zip`
- **Tamanho verificado:** `13.660.897 bytes` (**13,03 MB** — dentro do limite de 15 MB)
- **Conteúdo do pacote (`build/web/`):** `index.html`, `index.js`, `index.wasm`, `index.pck`, `index.audio.worklet.js`, `index.audio.position.worklet.js`, ícones PNG e `vercel.json`.

> **Importante:** Utilize o arquivo dentro de `space-app-challenge-2026---astra-rex/build/astra_rex_itch_webgl.zip` (não a pasta `build/` antiga na raiz do repositório, se existir).

---

## 2. Configurações do Painel no Itch.io (`Edit Project`)

### Informações Gerais
- **Title:** `AstraRex — Lunar South Pole Mission Designer (NASA Space Apps 2026)`
- **URL slug sugerido:** `astrarex-lunar-mission-designer`
- **Short description or tagline:**
  `3D Lunar South Pole spacecraft engineering simulator powered by real NASA JPL, LRO & Artemis datasets.`
- **Classification:** `Games` *(ou `Game assets` / `Tools` — recomendado `Games` para aparecer na vitrine padrão do hackathon)*
- **Kind of project:** **`HTML`** *(obrigatório para rodar no navegador)*
- **Release status:** `Released`
- **Pricing:** `No payments` (`Free`)

### Uploads & Embed Options (`astra_rex_itch_webgl.zip`)
1. Após fazer o upload de `astra_rex_itch_webgl.zip`, marque a opção:
   - `[x]` **This file will be played in the browser**
2. Em **Embed options**:
   - **Viewport dimensions:** **`1280` x `720`** *(corresponde exatamente a `viewport_width=1280` e `viewport_height=720` em `project.godot`, com `stretch/mode="canvas_items"` e `stretch/aspect="expand"`)*
   - **Embed in page** *(recomendado em vez de "Click to launch in fullscreen", pois preserva o layout `1280x720` diretamente na página; ative também o botão de tela cheia abaixo)*
   - **Frame Options:**
     - `[x]` **Fullscreen button** *(recomendado — permite aos juízes expandir caso a tela seja menor que 1280px)*
     - `[ ]` **Mobile friendly** *(opcional; compressão mobile `vram_texture_compression/for_mobile=true` está ativa, porém a interface foi projetada para mouse/teclado desktop `1280x720`)*
     - `[ ]` **Automatically start on page load** *(opcional; deixar desmarcado melhora o desbloqueio de Web Audio após o clique em "Run game")*
     - `[ ]` **Enable scrollbars** *(desmarcar — o canvas escala via `canvas_resize_policy=2`)*
   - **Experimental / Advanced:**
     - `[ ]` **SharedArrayBuffer support** -> **DEIXAR DESMARCADO (OFF)!**
       - **Motivo técnico:** `export_presets.cfg` define `variant/thread_support=false` (build WebGL2 single-thread). Marcar `SharedArrayBuffer` ativa cabeçalhos `COOP/COEP` estritos que quebram embeds/iframes em navegadores como Safari e podem bloquear recursos externos sem ganho algum.

### Metadados, Gênero e Tags
- **Genre:** `Simulation` *(ou `Educational`)*
- **Tags (até 10):** `nasa`, `space`, `lunar`, `simulation`, `3d`, `godot`, `educational`, `sci-fi`, `engineering`, `space-apps`
- **Inputs / Accessibility:** `Mouse`, `Keyboard`

### Deploy Espelho na Vercel (Opcional — Sem COOP/COEP)
O arquivo `space-app-challenge-2026---astra-rex/build/web/vercel.json` já inclui cabeçalhos `Content-Type` (`application/wasm`, `application/octet-stream`, `application/javascript`) e `X-Content-Type-Options: nosniff` sem restrições de `SharedArrayBuffer`:
```bash
cd space-app-challenge-2026---astra-rex/build/web
vercel --prod
```

---

## 3. Descrição Pronta para Copiar e Colar no Itch.io

Copie o bloco Markdown abaixo diretamente para o campo **Description** da página do projeto no Itch.io:

```markdown
# AstraRex — 3D Lunar South Pole Mission Engineering Simulator

**AstraRex** is an interactive 3D spacecraft mission engineering and trade-space simulator built in **Godot 4.7 (WebGL2 `gl_compatibility`)** for the **NASA Space Apps Challenge**, combining the **Space Mission Design Game** and **CLPS Lunar Mission Browser** challenges.

Design a lunar South Pole lander, assemble real modular subsystems in a 3D Vehicle Assembly Building (VAB), pass NASA's System Integration Review (SIR), fly a physics-driven powered descent over **Shackleton Crater**, and evaluate your design against the mathematical **Pareto Frontier**.

---

## 45-Second Judge Quick-Start

1. Click **Run game** (press **Fullscreen** if viewing on a smaller laptop screen).
2. In the top-right bar, click **`P1 OPTIMAL`** (Artemis Optimal preset), **`P2 FAIL`** (Mass / Thrust-to-Weight Failure demo), or **`P3 SANDBOX`**.
   - Prefer to explore by yourself? Press **`Space`** or **`Enter`** (or click the pulsing **`Next Step`** CTA in the bottom-right bar) to advance step-by-step across all 4 phases.
   - Want to inspect the trade-space graph immediately? Click **`Skip >>`** in Phase 2 or Phase 3 to jump straight to **Phase 4: Pareto Debrief**.
3. Switch anytime between **`STUDENT`** (concise guided metrics) and **`ENGINEER (SI)`** (full SI parameters + telemetry CSV/JSON export) in the top bar.

---

## Controls

| Input | Action |
| :--- | :--- |
| **`Space`** / **`Enter`** | Advance to the next phase / primary CTA |
| **Left Mouse Drag** | Orbit 3D camera (VAB & Lunar Surface) |
| **Mouse Wheel** | Zoom camera in / out |
| **Click 3D Pins / Part Cards** | Equip or inspect spacecraft subsystems in Phase 2 (VAB) |
| **`P1` / `P2` / `P3`** | Load Judge Demonstration Presets |
| **`STUDENT` / `ENGINEER (SI)`** | Toggle progressive telemetry detail & engineering exports |
| **`Skip >>`** | Jump from Phase 2 or Phase 3 directly to Phase 4 Pareto Debrief |
| **`MUTE`** | Mute / unmute synthesized procedural Web Audio |

---

## The 4 Engineering Phases

1. **Phase 1 — Mission Planning:** Choose your Launch Vehicle (`SLS Block 1`, `Falcon Heavy`, `Vulcan Centaur VC6`, `Falcon 9 Block 5`), Lunar Transfer Orbit (`LLO 100 km Polar` vs. `NRHO L2 9:2 Resonant`), and Shackleton South Pole Landing Site (`Shackleton Rim`, `Crater Inner Wall`, or `Shackleton Floor PSR`).
2. **Phase 2 — 3D Vehicle Assembly Building (VAB):** Inspect live `±Mass`, `±Δv`, `±Power`, and `±Cost` trade-offs in the 6-card Top HUD margin bars before equipping parts across 7 subsystem slots (`Bus`, `Propulsion`, `Power`, `Comms`, `Avionics`, `Payload`, `Shielding`). Clear the **SIR (`System Integration Review`)** safety lockouts (`T/W >= 1.0`, launch vehicle TLI capacity, Δv budget, power balance, DTE comms, radiation limit) to unlock launch.
3. **Phase 3 — Powered Descent & Surface Ops:** Watch real-time Tsiolkovsky descent dynamics, Hazard Avoidance LiDAR/TRN slope checks, grazing `~2°` South Pole solar illumination & crater shadowing, Direct-to-Earth (DTE) line-of-sight windows, and cumulative ionizing dose (`mSv`) across **FLIGHT & TOUCHDOWN** and **SURFACE ENVIRONMENT** telemetry groups.
4. **Phase 4 — Pareto Frontier Debrief:** Compare your mission's **Science Score** vs. **Total Cost ($M)** against the computed **Non-Dominated Upper-Envelope Pareto Frontier**, review physical root-cause trade-off explanations, and export mission telemetry (in `ENGINEER (SI)` mode).

---

## Grounded in Real NASA Engineering Models & Datasets

- **Systems Engineering & MGA:** *NASA Systems Engineering Handbook (`SP-2016-6105 Rev2`)* — Subsystem Mass Growth Allowance (MGA), Tsiolkovsky Rocket Equation ($\Delta v = I_{sp} \cdot g_0 \cdot \ln(m_0 / m_f)$), and Lunar Thrust-to-Weight ratio ($T/W = F / (m_0 \cdot 1.625)$).
- **Ephemerides & DTE Geometry:** *NASA JPL Horizons (`DE441`)* real Earth-Moon ICRF state vectors.
- **Topography & PSR Illumination:** *LRO LOLA* South Pole terrain slope and crater horizon shadow modeling around Shackleton Crater.
- **Radiation Environment:** *NASA OSDR RadLab* GCR / SPE dose limits (`100 mSv` mission threshold) & polyethylene/aluminum shielding attenuation (`g/cm²`).
- **Launch & Payload Heritage:** *NASA CLPS* & *SLS ESD 30000* launch capabilities and heritage payloads (`TRIDENT` drill, `MSolo` spectrometer, `Mini-RF SAR`).

---

## Technical Architecture

- **Engine:** Godot 4.7.2 (`gl_compatibility` / WebGL 2.0, GDScript 2.0 only)
- **Compatibility:** Single-threaded WebAssembly (`variant/thread_support=false`) — runs directly in browser iframes with **zero `SharedArrayBuffer` / COOP-COEP requirement**.
- **Web Payload:** `13.03 MB` compressed (`< 15 MB` budget).
```
