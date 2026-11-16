# AstraRex — Lunar South Pole Space Mission Engineering Simulator (NASA Space Apps Challenge 2026)

**AstraRex** is an interactive 3D space mission engineering simulator built in **Godot 4.7.2** (`GL Compatibility` / single-threaded WebGL2) targeting **NASA Space Apps Challenge 2026** (*Space Mission Design Game* & *CLPS Lunar Mission Browser*). Players and systems engineers design, validate, land, and benchmark a Lunar South Pole lander against authentic **SI physics** and **5 pre-hydrated NASA datasets**—running at 60 FPS directly in any desktop or mobile browser.

---

## 1. 45-Second Judge Quick-Start (Keyboard & One-Click Flow)

AstraRex uses a strict **One Frame, Four Phases** spatial console (`1280×720` viewport = `84 px` TopHUD + `600 px` PhaseContainer + `36 px` BottomActionBar):

1. **Instant Presets (`P1` / `P2` / `P3` in TopHUD)**:
   - **`P1` (`Artemis Optimal`)**: Equips `CLPS Bus + Bipropellant Descent Engine + MMRTG (Pu-238) + Ka-Band HGA + Rad-Hard ADCS + Hazard LiDAR TRN + TRIDENT Drill + Mini-RF SAR`. Demonstrates a valid Shackleton PSR mission architecture.
   - **`P2` (`Mass/Physics Failure`)**: Equips the high-Isp Solar Electric Hall Thruster (`0.25 N` thrust) + COTS Avionics. Immediately triggers hard physics lockouts (`T/W = 0.00 < 1.0`, solar blackout, radiation hazard) with root-cause diagnostics.
   - **`P3` (`Sandbox`)**: Resets to the base CLPS Lander Bus (`420 kg` nominal dry mass + 15% MGA) for custom trade studies.
2. **45-Second Walkthrough (`Space` / `Enter`, Stepper & `Skip >>` Flow)**:
   - Track progress via the **3-State Numbered Stepper** in the TopHUD (`•` upcoming, `>` current in `#2FD3FF` cyan with `#EAFE07` underline, `[OK]` completed in `#35E0A1` emerald) plus `4 px` margin progress bars across all 6 top telemetry cards (`MASS`, `PROP`, `POWER`, `COST`, `COMMS`, `LIFE`).
   - Press **`Space`** or **`Enter`** (or click the pulsing `#8B6CFF` / `#2FD3FF` **`Next Step`** CTA in the `36 px` BottomActionBar) to step deterministically through all four engineering phases — or click the non-intrusive **`Skip >>`** ghost button (visible during Phase 2 & Phase 3) to jump straight to Phase 4 Pareto Debrief:
     - **Phase 1 — Mission Planning (`Phase1_Planning`)**: Select launch vehicle (`SLS Block 1`, `Falcon Heavy`, `Vulcan Centaur VC6`, `Falcon 9 Block 5`), transfer orbit (`LLO 100 km Polar` vs `NRHO L2 9:2 Resonant`), and landing zone (`Shackleton Rim`, `Crater Inner Wall`, or `Shackleton Floor PSR`), with tiered `STUDENT` vs `ENGINEER (SI)` card density.
     - **Phase 2 — Vehicle Assembly Building (`Phase2_VAB`)**: Inspect non-mutating hover delta badges (`±Mass kg`, `±Power W`, `±Δv m/s`, `±Cost $M`) on the TopHUD and dedicated drawer comparison bar, trigger a single non-stacking **`1.5s` Feedback Chip** above HUD telemetry, click subsystem parts (`[MOUNTED]` / `[CORE]` badges) or screen-spaced 3D diegetic slot pins (`>= 28px` separation, dashed `-` indicators for empty mounts), view WebGL PBR spacecraft materials under 3-point studio lighting, and clear the **NASA SIR (`System Integration Review`)** readiness gate (`3. SIR: Launch Descent ->` / `[OK] SIR APPROVED`).
     - **Phase 3 — 3D Lunar South Pole Operations (`Phase3_LunarSim`)**: Execute an accelerated **`~4.0s`** powered terminal descent over LRO LOLA 16-bit terrain (`HeightMapShape3D`), monitor live `RayCast3D` solar grazing shadows (`88.5°` polar incidence) and Earth DTE line-of-sight, inject a **24h Solar Particle Event (`⚠ Solar Storm (SPE)`)**, engage **`Safe Mode`** load shedding, and advance `+30 Surface Days`.
     - **Phase 4 — Pareto Optimization & Root-Cause Debrief (`Phase4_Debrief`)**: Toggle X-axis between **Subsystems Cost ($M)** and **Wet Mass `m0` (kg)** on the custom 2D `_draw()` **Pareto Frontier** curve (`ParetoSolver`), inspect root-cause bottlenecks, compare against Preset 1, export **CSV/JSON**, or copy/load a compact **Base64 Design Code**. If opened before a configuration is evaluated, AstraRex surfaces a smart empty-state prompt and gently pulses `P1`/`P2` in `#8B6CFF` after **`3.0s`** of inactivity.
3. **Isomorphic Dual-Mode (`Student` vs. `Engineer SI`)**: Toggle live in the TopHUD with **`0.0 px` layout shift**; reveals full SI telemetry units and unlocks CSV/JSON telemetry report export in Engineer Mode.
4. **Audio Control (`MUTE`)**: Procedural 44.1 kHz NASA telemetry & Quindar audio can be muted cleanly from the utility bar.

---

## 2. Alignment with the 5 NASA Space Apps Judging Criteria

| Judging Criterion | How AstraRex Addresses It |
| :--- | :--- |
| **Impact** | Teaches authentic NASA pre-Phase A systems engineering trade-offs (mass growth allowance, thrust-to-weight, PSR power survival, and multi-objective Pareto optimization) in a zero-install WebGL2 simulator. |
| **Creativity** | Combines an industrial Mission Control HUD, clickable 3D VAB mount callouts, real-time South Pole raycast shadowing on 16-bit LOLA DEM terrain, procedural Apollo Quindar/telemetric Web Audio synthesis, and an interactive Pareto Frontier solver in one coherent 4-phase flow. |
| **Validity** | Strictly enforces **SI physics formulas** from `NASA SP-2016-6105 Rev2`, `JPL Horizons DE441`, `LRO LOLA 20 m/px`, and `OSDR RadLab`. Physically impossible designs (e.g., landing with a Hall thruster `T/W < 1.0`, solar panels inside a PSR crater, or exceeding fairing mass caps) are explicitly locked out with root-cause citations. |
| **Relevance** | Directly models current NASA Artemis & Commercial Lunar Payload Services (**CLPS**) mission architectures targeting **Shackleton Crater** water-ice deposits (`-89.54° S, 129.17° E`) with TRIDENT, MSolo, and Mini-RF payloads. |
| **Presentation** | Built around a disciplined 60-30-10 Space Apps brand hierarchy, WCAG 2.0 redundant encoding (`Symbol + Color + Text`), tabular `tnum` monospace telemetry readouts, dataset hover citations, and a `Space`/`Enter` 45-second flow tailored for live hackathon demos. |

---

## 3. Exact SI Physics Equations, NASA SP-2016-6105 Rev2 & Hard Lockouts

Core calculations live inside the locked Godot Autoloads (`src/autoloads/NasaDataLoader.gd`, `MissionState.gd`, and `ParetoSolver.gd`), applying *NASA Systems Engineering Handbook (`NASA SP-2016-6105 Rev2`)*, *NASA — Design and Develop Science Missions (2025)*, and *NASA/JPL Concept Maturity Levels (`CMLs, hdl:2014/44299`)* disciplines:
- **Four NASA Mission Segments (*Design and Develop Science Missions*)**: `MissionState.evaluate_mission_segments()` continuously audits readiness across the **Launch Segment** (launch vehicle TLI capacity & budget), **Space Segment** (CLPS bus, propulsion `T/W`, power, ADCS/TRN, radiation), **Ground Segment** (DSN Ka/S-Band antenna, DTE `%`, downlink bandwidth), and **User Segment** (science objective, payload return, and CSV/JSON data delivery), surfaced in Phase 1, HUD tooltips, Phase 4 Debrief, and telemetry exports.
- **Concept Maturity Levels (`CML 1–4`, NASA/JPL `hdl:2014/44299`)**: `MissionState.evaluate_concept_maturity_level()` tracks design progression from **CML 1 (Initial Concept)** → **CML 2 (Feasibility)** → **CML 3 (Trade Space)** → **CML 4 (Point Design)**, tying `SP-2016-6105` **MGA (`15%–20%`)** directly to early-CML design uncertainty.
- **MGA (`Mass Growth Allowance`, Sec 4.3 & Appendix G)**: Every subsystem carries a discrete design maturity growth reserve (`15%–20%`) added on top of nominal dry mass before computing Tsiolkovsky wet mass ratios and launch vehicle fairing/TLI limits.
- **SIR (`System Integration Review`)**: Before authorizing powered descent from Phase 2 (`VAB`) to Phase 3 (`Lunar Sim`), `MissionState` evaluates propellant/Δv margin, `T/W >= 1.0`, launch vehicle TLI cap, net power balance, DTE communications link, and ionizing dose — surfacing `[OK] SIR APPROVED` or locking out unsafe configurations with exact failure codes.
- **TMA & TRL (`Technical Margin Assessment` & `Technology Readiness Level`)**: Contrasts high-TRL flight-proven hardware (e.g., `TRL 9` Apollo/MMRTG/Bipropellant heritage, rad-hardened flight computers rated to `100 krad`) against lower-margin commercial `COTS` avionics (`15 krad`) and high-Isp low-thrust SEP architectures (`0.25 N` Hall thrusters) that violate terminal landing margins.

1. **Mass Growth Allowance (`NASA SP-2016-6105 Rev2, Sec 4.3 & Appendix G`)**:
   $$m_{\text{dry,total}} = \sum_i m_{\text{dry},i}\,(1 + \text{MGA}_i), \qquad m_0 = m_{\text{dry,total}} + m_{\text{prop}}$$
2. **Tsiolkovsky Rocket Equation**:
   $$\Delta v = I_{\text{sp}} \cdot g_0 \cdot \ln\!\left(\frac{m_0}{m_{\text{dry,total}}}\right), \qquad g_0 = 9.80665\ \text{m/s}^2$$
3. **Lunar Thrust-to-Weight (`T/W >= 1.0` Soft-Landing Lockout)**:
   $$\left(\frac{T}{W}\right)_{\text{lunar}} = \frac{F_{\text{thrust}}}{m_0 \cdot g_{\text{moon}}}, \qquad g_{\text{moon}} = 1.625\ \text{m/s}^2$$
   *(Designs with `T/W < 1.0`—such as Xenon Hall Ion thrusters—are physically blocked from lunar touchdown.)*
4. **Solar Power & Polar Grazing Occlusion**:
   $$P_{\text{solar}} = P_0 \cdot \max(0, \cos\theta_{\text{inc}}) \cdot (1 - \text{occlusion})$$
   Evaluated statically in telemetry (`88.5°` polar incidence / PSR `0%` sunlight) and dynamically in Phase 3 via 3D `RayCast3D` terrain horizon checks driven by `DE441` solar vectors.
5. **Terrain Slope Stability (`LRO LOLA` & SPLICE TRN)**:
   - Safe landing slope requires `<= 15.0°` (higher-slope crater walls risk tip-over without Hazard Avoidance LiDAR & TRN).
6. **Deep Space Network (DSN) & Direct-to-Earth (DTE) Line-of-Sight**:
   - Compares daily science payload generation (`GB/day`) against Ka-Band (`100 Mbps`) vs. S-Band (`0.5 Mbps`) downlink rate and `DE441` Earth line-of-sight (`RayCast3D`).
7. **Ionizing Radiation Attenuation & Mission Dose Limit (`OSDR RadLab & LRO CRaTER`)**:
   - Half-value aluminum/polyethylene shielding thickness: `HVL = 6.5 g/cm²` (`dose_attenuation = 0.5^(shielding / 6.5)`).
   - Evaluates transit GCR (`1.15 mSv/day`), South Pole surface GCR (`0.58 mSv/day` with `0.5` regolith factor), `24h` Solar Particle Event (SPE) storms (`42.0 mSv/h` transit / `21.0 mSv/h` surface), `100 mSv` mission dose limit, and COTS (`15 krad`) vs. Rad-Hard (`100 krad`) avionics resilience.

---

## 4. The 5 Official Pre-Hydrated NASA Datasets

All datasets are stored locally in `space-app-challenge-2026---astra-rex/` for deterministic, offline, single-threaded WebGL execution:

1. [`nasa_parts_catalog.json`](space-app-challenge-2026---astra-rex/data/nasa_parts_catalog.json) — `NASA SP-2016-6105 Rev2`, `Design and Develop Science Missions (2025)` 4-Segment definitions, `NASA/JPL Concept Maturity Levels (CML 1–4, hdl:2014/44299)`, `SLS ESD 30000`, `CLPS` Launch Vehicles (`SLS Block 1`, `Falcon Heavy`, `Vulcan Centaur VC6`, `Falcon 9`), `LLO Polar (1750 m/s)` vs. `NRHO Gateway (2500 m/s)` orbits, 15 modular spacecraft subsystems with exact citations, and judge presets (`P1`, `P2`, `P3`).
2. [`ephemeris_horizons.json`](space-app-challenge-2026---astra-rex/data/ephemeris_horizons.json) — **NASA JPL Horizons System (`DE441`)** `ICRF / J2000` ephemeris state vectors (`moon_from_earth_301`, Sun vectors) driving real-time solar illumination angle and Earth DTE visibility.
3. [`radiation_radlab.json`](space-app-challenge-2026---astra-rex/data/radiation_radlab.json) — **NASA OSDR RadLab API & LRO CRaTER** GCR baseline rates, SPE storm peak flux, aluminum half-value shielding constants, and `100.0 mSv` mission limit.
4. [`shackleton_terrain_meta.json`](space-app-challenge-2026---astra-rex/data/shackleton_terrain_meta.json) — **LRO LOLA GDR 20 m/px** metadata (`20480 × 20480 m` DEM bounds, `-2872.5 m` to `+1738.5 m`, `4611.0 m` vertical amplitude, `88.5°` polar solar incidence) and target landing zone envelopes.
5. [`shackleton_heightmap_16bit.png`](space-app-challenge-2026---astra-rex/assets/terrain/shackleton_heightmap_16bit.png) (+ `regolith_albedo.webp` & `regolith_normal.webp`) — **LRO LOLA 16-bit Digital Elevation Model** powering Phase 3's 3D South Pole terrain mesh, `HeightMapShape3D` physics surface, slope computation, and raycast crater shadows.

---

## 5. Space Apps Brand Guide, Mission Control UI, Audio & WebGL2 Architecture

- **60-30-10 Space Apps Brand Harmony (`BrandStyle.gd` & `MissionControlTheme.tres`)**:
  - **60% Structural**: Deep Space `#05080F` (`space-950`) on 3D viewports, Deep Blue `#07173F` + `45°` linear gradient (`#0042A6 -> #07173F -> #05080F`) + `25%`-opacity coordinate vector grid behind 2D planning/debrief screens, and `#0E1624` (`88%` opacity) panels with crisp `1px` `#2A3B55` borders (zero `BackBufferCopy` / blur passes, zero NASA "Meatball" logos).
  - **30% Identity**: Electric Brand Blue `#0042A6` / `#0B3D91`, Nominal Telemetry Cyan `#2FD3FF`, and strict interactive Neon Yellow `#EAFE07` (hover borders, active phase tab bottom underline, frontier highlight markers).
  - **10% Semantic & Exclusive Guide**: WCAG 2.0 redundant encoding on every alert/badge (`[OK]` `#35E0A1` Pass, `[!]` `#FFB224` Caution, `[X]` `#FF4560` Critical) with 100% WebGL-safe glyphs in `Barlow Semi Condensed` and `JetBrains Mono`. Violet `#8B6CFF` is reserved exclusively for the **Pareto Upper-Envelope Frontier curve** (`ParetoChartControl.gd`) and the **single 1.2s smooth guidance pulse** on the active next-step CTA (`Main.gd`).
  - **Tabular Typography & Vector Sparklines**: `Barlow Semi Condensed` (`FontUI_Barlow.tres`) for UI headers and `JetBrains Mono` (`FontMono_Tabular.tres`, OpenType `tnum`) for zero-jitter numeric SI telemetry, plus compact `48×16 px` `TelemetrySparkline.gd` `_draw()` trendlines in the HUD Power card and Debrief Radiation card.
- **Procedural 44.1 kHz NASA Web Audio (`scripts/generate_nasa_audio_samples.py`)**:
  - Six lightweight 16-bit mono `.wav` assets (`212,824 bytes` / `207.84 KB` total, strictly `< 400 KB` budget) in `space-app-challenge-2026---astra-rex/assets/audio/`: `vab_snap.wav`, `quindar_beep.wav` (`2525 / 2475 Hz`), `ui_hover_tick.wav`, `thruster_burn.wav` (looping descent rumble), `spe_alarm.wav` (dual-tone Master Caution), and `touchdown_confirm.wav`, with `audio/driver/enable_input=false`.
- **Single-Threaded WebGL2 Release & Dual-Host Deployment (Itch.io + Vercel)**:
  - Strict `gl_compatibility` renderer, GDScript 2.0 only (no C#/.NET, no `Thread`/`WorkerThreadPool`, `variant/thread_support=false`, `GODOT_THREADS_ENABLED = false`).
  - Exported WebGL2 artifacts in `space-app-challenge-2026---astra-rex/build/web/`: `index.wasm` (`39,514,754 B`), `index.pck` (`5,495,008 B`), `index.js` (`279,815 B`), `index.html` (`5,463 B`), audio worklets, icons, and `vercel.json` (`924 B`).
  - Pre-packaged `space-app-challenge-2026---astra-rex/build/astra_rex_itch_webgl.zip` (`13,660,897 bytes` / `13.03 MB`, strictly `< 15.0 MB` budget) for direct Itch.io HTML5 upload (`1280×720` embedded canvas, **SharedArrayBuffer OFF**, zero COOP-COEP requirement). See [`ITCH_IO_SETUP.md`](./ITCH_IO_SETUP.md) for full dashboard settings and copy-paste description.
  - Includes `space-app-challenge-2026---astra-rex/build/web/vercel.json` for 1-command deployment to Vercel (`cd space-app-challenge-2026---astra-rex/build/web && vercel --prod`) or Cloudflare Pages with `application/wasm` MIME type and zero cross-origin isolation lockout.

---

## 6. Local Verification & Build Commands (Godot 4.7.2)

```powershell
# 1. Regenerate procedural NASA telemetry audio assets
python scripts/generate_nasa_audio_samples.py

# 2. Run automated 3D PBR, layout, physics, audio, font, and WebGL bundle verification
& "godot" --headless --path "space-app-challenge-2026---astra-rex" "res://scripts/VerifyBlueprintAndPBR.tscn"

# 3. Export single-threaded WebGL2 release build
& "godot" --headless --path "space-app-challenge-2026---astra-rex" --export-release "Web" "build/web/index.html"
```
