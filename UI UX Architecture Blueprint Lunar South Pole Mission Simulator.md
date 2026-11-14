# UI/UX Architecture Blueprint: Lunar South Pole Mission Simulator

*Godot 4.3+ · WebGL 2 single-threaded · 1280×720 · 2026 NASA Space Apps Challenge*

**Note on sources.** The benchmark observations in §1 come from established knowledge of these products, not from freshly retrieved pages. Verify any screenshot-level claim before citing it in your submission. The pixel budgets, flows, and tokens in §2–§5 are original design proposals built on those patterns.

## 0. Design thesis: five rules that govern everything

1. **One frame, four phases.** The Top HUD (84 px) and Action Bar (36 px) never move or resize. Only the 600 px Phase Canvas changes. This is what protects spatial muscle memory.
2. **3D first.** Clear 3D width is 70.6% in Phase 2 and 76.3% in Phase 3, above the 65% floor. Panels dock to edges; nothing floats over the hero object.
3. **Glance, Select, Hover.** Three information tiers, each with one trigger (nothing, click, hover).
4. **Modes change content, never geometry.** Student and Engineer Mode reuse identical slots and widths.
5. **One pulse at a time.** Only one element on screen may animate for attention, and it uses a color reserved for guidance (violet), never a status color.

## 1. Executive Benchmark Matrix

| Source | Pattern worth adopting | Pitfall to avoid | Maps to |
| --- | --- | --- | --- |
| NASA OpenMCT | Fixed-width tabular telemetry; limit-based color conditions; tree-to-inspector drill-down | Table density overwhelms first-timers | HUD gauges; Phase 4 Engineer tables |
| Artemis-style mission consoles | Role-based consoles; strict caution/warning color discipline (color is rare, so alarms pop) | Color used decoratively | Phase 1 roles; all status pills |
| JPL Eyes on the Solar System | Near-chromeless 3D, time slider along the bottom, info panel only on selection | Little guidance for novices | Phase 3 time dock; Phase 2 selection |
| SpaceX Dragon touchscreen HMI | Few large targets, one primary action, screens that follow flight phase | Too sparse for trade-off work | Action Bar; phase stepper |
| Kerbal Space Program 1 & 2 | Category rail, part catalog, live Δv and TWR readout while building | Key numbers scattered across panels | Phase 2 |
| Mars Horizon | Big card choices for mission planning; agency framing | Menu-heavy, weakly spatial | Phase 1 |
| Ixion | Resource strip along the top with alert icons; urgent event callouts | Stacked alerts | HUD; solar storm event |
| Terra Invicta | Nested tooltips carrying deep detail | Tooltip depth gets unwieldy | Tier 3 |
| Children of a Dead Earth | Spreadsheet-grade stat panels for physical design | Steep for casual players | Engineer Mode; Phase 4 |
| Deliver Us The Moon | Diegetic, minimal HUD; world-anchored hints | Low information density | Slot pins; Phase 3 |

**Transferable layout patterns**

- **Edge-docked rails around a free center** (KSP, OpenMCT): category rail left, inspector right, catalog bottom.
- **Top resource strip with status pills** (Ixion, mission consoles): six fixed cells, always the same order.
- **Selection-driven detail** (JPL Eyes): nothing detailed is shown until the player selects or hovers.
- **Delta-on-hover** (KSP VAB): hovering a candidate part previews its effect on the HUD gauges before commitment.
- **Role consoles** (Artemis): in team play, each role gets a highlighted subsystem set, not a different layout.

## 2. Spatial Wireframes (1280×720)

### 2.1 Master frame and pixel budget

```
 0                                                         1280
 ┌─────────────────────────────────────────────────────────────┐ y=0
 │ ROW A (36): LOGO │ PRESETS │ ~spacer~ │ STEPPER │ MODE      │
 │ ROW B (36): [MASS][Δv·T/W][POWER][BUDGET][DATA][LIFE]       │ HUD 84
 ├─────────────────────────────────────────────────────────────┤ y=84
 │                                                             │
 │              PHASE CANVAS   1280 × 600                      │
 │                                                             │
 ├─────────────────────────────────────────────────────────────┤ y=684
 │ ACTION BAR (36): ◀ Back │ context hint │        Primary ▶  │
 └─────────────────────────────────────────────────────────────┘ y=720
```

| Zone | Size | Anchor rule |
| --- | --- | --- |
| Top HUD | 1280 × 84 | Full-width top, `custom_minimum_size.y = 84`, never collapses |
| Phase Canvas | 1280 × 600 | `size_flags_vertical = EXPAND_FILL`; one persistent child per phase, toggled by visibility |
| Action Bar | 1280 × 36 | Full-width bottom; Back is far left, Primary CTA is far right in every phase |

Suggested node tree:

```
MainHUD (VBoxContainer, full rect)
├─ TopHUD (PanelContainer, min_h 84)
│  └─ VBox: RowA (HBox, 36) / RowB (HBox, 36)
├─ PhaseHost (Control, expand)  → Phase1 / Phase2 / Phase3 / Phase4
└─ ActionBar (PanelContainer, min_h 36)
```

### 2.2 Top HUD detail (84 px: 4 + 36 + 4 + 36 + 4)

**Row A (36 px).** Logo mark 96 · Presets 3 × 112 + 2 × 8 gaps · flexible spacer · Phase stepper 4 × 136 + 3 × 8 · Mode toggle 136. Fixed items total about 1,200 px with the 8 px margins, and the spacer absorbs the rest.

**Row B (36 px).** Six identical gauge cells of **204 × 36** with 8 px gaps (6 × 204 + 5 × 8 = 1,264, plus 8 px outer margins).

Gauge cell internals: 8 padding · 16 icon · 6 gap · 104 text block (label 11 px above value 15 px mono) · 6 gap · 56 status pill · 8 padding.

| # | Gauge | Value slot | Pill codes |
| --- | --- | --- | --- |
| 1 | Wet Mass | `kg` + MGA % | OK / HIGH / OVER |
| 2 | Propulsion | Δv `m/s`, lunar T/W | OK / LOW / FAIL |
| 3 | Net Power | `W` and `Wh` | OK / LOW / FAIL |
| 4 | Budget | `M$` | OK / TIGHT / OVER |
| 5 | Data & Comms | `GB/day` vs `Mbps` | OK / BACKLOG / LOSS |
| 6 | Lifetime / Radiation | `days` / `mSv` | OK / WATCH / LIMIT |

Gauges 2, 3, and 5 carry two quantities. Show the primary value in the large slot and the second value in a compact `Value-S` suffix; cut the label to fit rather than shrinking the cell.

### 2.3 Phase 1: Mission Formulation

Three columns inside 8 px margins: **384 | 480 | 384** (+ 2 × 8 gaps = 1,248). Card heights fill 584 px.

```
┌─ TEAM & ROLES 384 ───┬─ MISSION DEFINITION 480 ───┬─ PREVIEW & CHECKS 384 ─┐
│ Solo|2|3|4 (seg, 32) │ OBJECTIVE  [card][card]    │ ┌──────────────────┐   │
│ ┌ Mission Planner ┐  │            [card][card]    │ │ 3D Earth-Moon    │   │
│ ├ Propulsion/GNC  ┤  │ LAUNCH VEHICLE  ‹ chips ›  │ │ transfer preview │   │
│ ├ Science Director┤  │ TARGET ORBIT    ‹ chips ›  │ │ 384 × 232        │   │
│ └ Comms & Power   ┘  │ (selected = 2px cyan edge) │ └──────────────────┘   │
│  role cards 4 × 88   │                            │ ✔ Payload ≤ capacity   │
│                      │                            │ ✔ TLI Δv reachable     │
│                      │                            │ ✖ Orbit lighting       │
└──────────────────────┴────────────────────────────┴────────────────────────┘
```

- Role cards: icon, role name, one 12 px line naming owned subsystems. In solo mode all four are merged into a single "All roles" card.
- Compatibility checks: five rows of 28 px, each with an icon, a short label, and a PASS/FAIL pill. A failing row is clickable and flashes the selector that caused it.
- The 3D preview is a small `SubViewportContainer`; it is decorative, not interactive, so it never competes with later 3D phases.

### 2.4 Phase 2: 3D Vehicle Assembly Building

```
 x: 0   56                            960                  1280
    ┌────┬────────────────────────────┬─────────────────────┐ y=84
    │ R  │  3D VIEWPORT   904 × 600   │ INSPECTOR  320×600  │
    │ A  │       (70.6% width)        │ ┌ Selected part ──┐ │
    │ I  │     ◉1        ◉2           │ │ name · 3 stats  │ │
    │ L  │        [ LANDER ]          │ ├ Trade-offs ─────┤ │
    │    │     ◉3        ◉4 ◉5        │ │ 7 delta rows    │ │
    │ 56 │        ◉6   ◉7            │ ├ Actions ────────┤ │
    │    │ ┌ PART DOCK 904 × 112 ───┐ │ │ Equip | Remove  │ │
    │    │ │ [card][card][card] ‹ › │ │ └─────────────────┘ │
    └────┴─┴────────────────────────┴─┴─────────────────────┘
```

- **Rail (56 px):** seven 56 × 56 icon buttons for Structure/Shielding, Propulsion, Power Generation, Batteries, Avionics/ADCS/LiDAR, DSN Comms, Scientific Payloads. Each shows a tiny fill-state dot (empty, filled, conflict).
- **Part dock (112 px, collapsible):** overlays the bottom of the 3D area. Cards are 168 × 96; about five are visible with horizontal scroll. Collapsing (`C` key or chevron) returns the full 600 px.
- **Camera framing:** offset the lander's pivot upward by half the dock height (`Camera3D.v_offset` or a shifted orbit target) so the chassis is centered in the unobstructed region rather than behind the dock.
- **Inspector (320 px):** collapsible to a 48 px strip, which raises clear 3D width to 1,176 px (91.9%).
- **Slot pins:** seven `Marker3D` nodes projected to screen space (see §3.3).

### 2.5 Phase 3: Lunar Descent & Surface Operations

```
 x: 0                                  976               1280
    ┌──────────────────────────────────┬──────────────────────┐ y=84
    │ [ Shackleton Rim | Crater PSR ]  │ TELEMETRY  304×600   │
    │  (top-center seg, 288 × 32)      │ ┌ DESCENT (PID) ───┐ │
    │                                  │ │ ALT  VV  VH  THR │ │
    │      3D LRO LOLA TERRAIN         │ │ 3 sparklines     │ │
    │      976 × 600 (76.3% width)     │ ├ LINKS ───────────┤ │
    │                                  │ │ Sun LOS · Earth  │ │
    │ ┌ TIME DOCK 976 × 56 ──────────┐ │ │ DTE · pills      │ │
    │ │ ⏸ 1× 10× 100× [+30 Days] SPE │ │ ├ EVENTS ──────────┤ │
    │ └──────────────────────────────┘ │ │ SPE trigger·dose │ │
    └──────────────────────────────────┴──────────────────────┘
```

- The landing-target toggle is locked after descent begins; show a lock glyph instead of hiding it.
- Time dock: during powered descent only Pause and 1× are enabled (the others show a disabled style with a tooltip saying why). After touchdown, 10×, 100×, and **+30 Days** unlock.
- Telemetry panel: each descent channel uses a fixed-width mono value plus a 48 × 16 sparkline drawn in `_draw()` from a 64-sample ring buffer.
- The SPE button is a distinct amber ghost button with a warning glyph; its result appears first as a HUD radiation gauge change and a 3-second banner at the top of the 3D area.

### 2.6 Phase 4: Pareto Debrief

```
 x: 8                             752 760                1272
    ┌─ PARETO FRONTIER 744×584 ───┬─ DIAGNOSIS 512 × 584 ───────┐
    │ X: [Cost | Mass] seg        │ ROOT CAUSE (3 cards × ~96)  │
    │ Y: Science Return           │ ┌ icon · title · 1 line ──┐ │
    │  ▲   ◆                      │ │ chip: affected gauge    │ │
    │  │  ◆  ·  ·                 │ └─────────────────────────┘ │
    │  │ ◆ ★                      │ RECOMMENDED TRADE-OFFS (2-3)│
    │  │◆  ·   ·                  │ [ Swap X → Y  −340 kg ]     │
    │  └──────────────▶           │ SHARE: [ code........ ][Copy]│
    │ plot area 680 × 480         │ [ Try Again ]  [ CSV | JSON ]│
    └─────────────────────────────┴─────────────────────────────┘
```

## 3. Widget & Tool Accommodation Playbook

### 3.1 Choosing a pattern for each need

| Pattern | Verdict | Use for | Cost |
| --- | --- | --- | --- |
| Collapsible side drawer | **Use** (inspector only) | Selected-item detail, trade-offs | Eats width; capped at 320 px |
| Bottom tactical dock | **Use** (Phase 2 catalog, Phase 3 time dock) | Horizontally browsable cards, time controls | Eats height; collapsible |
| Diegetic `Marker3D` pins | **Use** | Slot status and selection on the vehicle | Needs overlap handling |
| Radial / contextual menu | **Avoid for catalogs** | At most a 3-option Equip/Swap/Remove on a pin | Small targets, hover precision |
| Tabbed inspector cards | **Avoid inside the inspector** | Reserve tabs for Phase 4 only | Hides numbers behind clicks |
| Modal popups | **Banned** | None | Blocks camera orbit and zoom |

### 3.2 Buttons

- **Three classes only.** Primary (filled cyan, 36 px high, only in the Action Bar), Secondary (outlined, 32 px), Ghost (text plus icon, 32 px).
- **One CTA per phase**, always bottom-right: *Next · 2 VAB*, *Next · 3 Sim*, *Launch Descent*, *Next · Debrief*, *Try Again*.
- **Labels:** at most three words plus an optional icon. Explanations belong in Tier 3 tooltips, never in button text.
- **Disabled** buttons stay visible and carry a tooltip stating the unmet condition.

### 3.3 Diegetic slot pins

- Project each `Marker3D` with `Camera3D.unproject_position()`; skip it when `is_position_behind()` is true; clamp to the viewport margin.
- Pins are 24 px circles inside a `Control` overlay whose `mouse_filter` is IGNORE; only the pins themselves use STOP, so orbit and zoom keep working everywhere else.
- States: **empty** (dashed ring, number), **filled** (solid cyan, category icon), **conflict** (amber ring), **fatal** (crimson ring plus ✖). Never rely on color alone.
- Labels appear on hover only. If two pins are within 28 px on screen, nudge the later one along a leader line.
- Click selects the category in the rail and opens its cards in the dock.
- Fade pins by depth (alpha 1.0 to 0.5) so the far side of the chassis does not clutter the view.

### 3.4 SI gauges

- **Fixed slots.** Value text uses a mono font with right alignment inside a fixed-width label. Never size a gauge to its content.
- **Update rate.** Throttle readouts to 10 Hz with a `Timer`; do not rewrite text every frame (Web is single-threaded, and text layout is not free).
- **Ghost deltas.** While a candidate part is hovered, the affected gauges show a small `+120 kg` or `−340 m/s` chip in amber (worse) or cyan (better) next to the value. The chip clears on mouse-out.
- **Change feedback.** On commit, the value flashes the semantic color for 150 ms, then returns to primary text.
- **Click** a gauge for its Tier 2 popover: a 204 px wide non-modal panel just under the cell with a breakdown (for example mass by subsystem) and the active margin.

### 3.5 Tooltips and reference drawer (Tier 3)

- Use Godot's `tooltip_text` plus `_make_custom_tooltip()` to return a styled `PanelContainer`. Set `gui/timers/tooltip_delay_sec` to about 0.4.
- Tooltip anatomy, max 320 px wide: title (H2), up to three body lines, and a source chip such as `LRO LOLA`.
- Clicking the ⓘ glyph opens a **Reference Drawer**: a 320 × 240 non-modal panel anchored bottom-right of the Phase Canvas, listing full citations (NASA SP-2016-6105 Rev2, JPL DE441, LRO LOLA, OSDR RadLab) with the equation or dataset used. It never covers the central 3D region.
- Citations never appear in primary labels or buttons.

### 3.6 Pareto chart (custom `Control._draw()`)

- **Axes.** X toggles between Cost (M$) and Mass (kg); Y is Science Return (0–100 index). Plot area inset 48 px left, 16 right, 16 top, 40 bottom.
- **Layers, in order:** gridlines (`#2A3B55`, 1 px); frontier as a stepped `draw_polyline` in violet with a faint filled region beneath it; dominated designs as small dim circles; frontier designs as diamonds; the player's design as a large star with a 2 px halo.
- **Redundant encoding:** shape plus color, so the chart survives color-vision deficiencies.
- **Interaction:** `_gui_input` finds the nearest point within 12 px and shows a Tier 3 tooltip with design name, mass, cost, and science score. Redraw only when the data or hover target changes (`queue_redraw()`).
- **Student Mode** annotates two things only: "You" and "Better designs are up and to the left." **Engineer Mode** adds axis tick values, a dominated-by list, and CSV/JSON export.
- **Base64 design code:** show it as a single-line read-only field with Copy. Truncate with an ellipsis and keep the full string in the clipboard.

## 4. Student vs. Engineer Mode & the 45-Second Judge Flow

### 4.1 What changes between modes (geometry never does)

| Element | Student Mode | Engineer Mode |
| --- | --- | --- |
| Gauge value | Rounded, friendly units (`1.3 t`) | Full SI precision (`1,284.6 kg`) |
| Gauge pill | Plain words: GOOD / CAREFUL / TOO MUCH | Codes: OK / HIGH / OVER |
| Gauge label line | `WET MASS` | `WET MASS · MGA 22%` |
| Part cards | Icon, name, one-line benefit, effect badges (▲ ▼) | Icon, name, Isp / thrust / W / kg / M$ in a mono row |
| Tooltips (Tier 3) | One plain-language sentence | Equation, parameters, source chip |
| Reference Drawer | Hidden behind a small "Learn more" | Open by default, full citations |
| Phase 4 | Two annotations plus a "what to try next" card | Axis ticks, dominated-by list, CSV/JSON export |
| Layout, slot widths, button positions | Identical | Identical |

**Implementation:** one `ModeBus` autoload emits `mode_changed`. Every widget implements `apply_mode(is_engineer)` and may only swap text, visibility inside a reserved area, and tooltip content. Reserved areas keep `custom_minimum_size` constant, so toggling never shifts neighbors.

### 4.2 Judge flow

Target: Preset 1 (success) and Preset 2 (failure) both completed across all four phases in under 45 seconds, with no text tutorial.

**Mechanics that make it possible**

- Presets load the full configuration for all four phases instantly (one frame), then the stepper shows steps 1–4 pre-checked as "configured".
- Phase 3 runs in **demo speed**: powered descent compressed to about 6 seconds of wall-clock time, with the Preset 2 fault and solar storm scripted at fixed points.
- Space or Enter triggers the Primary CTA, so a judge can tap one key to advance.
- Guidance pulse (violet, 1.2 s loop) is allowed on exactly one element at a time: first the presets, then the Primary CTA, and in Phase 3 the **+30 Days** button.

**Timeline**

| Time | Run A: Optimal Artemis | Run B: Critical Failure |
| --- | --- | --- |
| 0–3 s | Land on Phase 1; the three presets pulse. Click *Optimal Artemis*. | Click *Critical Failure* (the three presets stay visible in every phase). |
| 3–6 s | Compatibility rows tick to PASS in 80 ms staggers; gauges go cyan; CTA pulses. | Rows show FAIL on a few checks; two gauges go amber and crimson. |
| 6–10 s | Phase 2: slow idle orbit; all seven pins filled; ghost deltas visible on hover. Press CTA. | Phase 2: one pin pulses crimson (the culprit); the inspector shows the offending delta. Press CTA. |
| 10–17 s | Phase 3: nominal descent at demo speed; touchdown banner; **+30 Days** pulses; click it. | Phase 3: PID overshoot, then a solar storm banner; radiation gauge climbs. |
| 17–22 s | Phase 4: star lands on the frontier; root-cause card reads "No critical failures". | Phase 4: star sits well inside the frontier; root-cause cards name the physical causes. |
| About 22 s | Run A total | Run B total |

Two runs sum to roughly 44 s with no margin, so also provide a **Skip ⏭** ghost button that jumps to Phase 4 from Phase 2 or 3. A judge who skips still sees the configured gauges and the final diagnosis. Trim the Phase 3 demo to 4 s if user testing shows judges linger.

**Non-intrusive affordances**

- **Numbered stepper** with three states: ○ upcoming, ● current (cyan fill), ✔ done. The current step is also what the Primary CTA's label names.
- **Instant feedback badges:** a 1.5 s "PASS · Δv margin +312 m/s" chip fades in above the HUD gauge that changed, then slides into the gauge's pill. No toast stack; only one badge at a time.
- **Smart empty states:** an empty slot pin shows a dashed ring plus a ghost silhouette of the missing part. Phase 4 with no completed run shows "Load a preset to see the frontier" with the presets pulsing.
- **No modal tutorial.** If the judge does nothing for 3 s, the currently pulsing element is the entire hint.

## 5. Godot 4 Visual Design Tokens

### 5.1 Color

Contrast ratios are computed against `panel-900` (`#0E1624`) at full opacity. Keep panel alpha at or above 0.88 so text stays AA when sitting over bright regolith. Avoid backdrop blur (it needs `BackBufferCopy`, which is costly in single-threaded Web builds); use alpha and a 1 px border instead.

| Token | Hex | Use | Contrast on panel |
| --- | --- | --- | --- |
| `space-950` | `#05080F` | Clear color, deep canvas | n/a |
| `panel-900` | `#0E1624E0` | Panel fill (alpha 0.88) | n/a |
| `panel-800` | `#16233A` | Raised rows, hover fill | n/a |
| `panel-700` | `#1F3050` | Pressed, selected fill | n/a |
| `border-subtle` | `#2A3B55` | Decorative dividers | decorative |
| `border-control` | `#4F6A92` | Button and input outlines | about 3.3:1 |
| `text-primary` | `#E6EEF8` | Values, titles | about 15:1 |
| `text-secondary` | `#9FB3CC` | Labels, hints | about 8.5:1 |
| `text-disabled` | `#5E7089` | Disabled controls only | exempt |
| `state-nominal` | `#2FD3FF` | Nominal, selected, info (NASA cyan) | about 10:1 |
| `state-caution` | `#FFB224` | Caution, tight margin (amber) | about 10:1 |
| `state-critical` | `#FF4560` | Fail, over limit (crimson) | about 5.4:1 |
| `state-pass` | `#35E0A1` | PASS pills only | about 10:1 |
| `accent-guide` | `#8B6CFF` | Judge pulse, Pareto frontier | about 4.9:1 |
| `brand-blue` | `#0B3D91` | Header rule, large fills (not text) | n/a |

Rules: status colors always pair with an icon shape and a text code. The violet guide color is never used for status. Do not use the NASA insignia; use your own mark and credit NASA and JPL data sources in the Reference Drawer.

### 5.2 Typography

Use two open-licensed families, both under the SIL OFL: **Barlow Semi Condensed** (headers and labels; the condensed width saves pixels) and **JetBrains Mono** (all live values; tabular by construction). Subset both to Latin and the needed glyphs to keep the exported `.pck` small.

| Style | Font | Size / line | Weight | Use |
| --- | --- | --- | --- | --- |
| Display | Barlow SC | 20 / 24 | SemiBold | Phase titles, outcome headline |
| H1 | Barlow SC | 16 / 20 | SemiBold | Card titles |
| H2 | Barlow SC | 14 / 16 | Medium | Section and tooltip titles |
| Body | Barlow SC | 13 / 16 | Regular | Descriptions |
| Label | Barlow SC | 11 / 12 | Medium, caps | Gauge labels, units, pills |
| Value-L | JetBrains Mono | 15 / 16 | Medium | HUD gauges, telemetry |
| Value-S | JetBrains Mono | 12 / 16 | Regular | Tables, chart axes |

Minimum text size is 11 px. For tracking on Label, use a `FontVariation` with `spacing_glyph = 1`. If you ever use a proportional face for numbers, enable `opentype_features = {"tnum": 1}` on the `FontVariation`.

### 5.3 Spacing, shape, elevation

| Token | Value | Use |
| --- | --- | --- |
| `space-half` | 4 px | Icon-to-text gap only |
| `space-1` | 8 px | Default padding and gap |
| `space-2` | 16 px | Panel margin, section gap |
| `space-3` | 24 px | Rare; large gutters |
| Row heights | 28 / 32 / 36 | List rows / controls / Primary CTA |
| Corner radius | 4 px (controls and panels), 9 px (pills) |  |
| Border | 1 px default; 2 px cyan, inset, for selected |  |
| E1 panel | Fill `panel-900`, border `border-subtle`, no shadow |  |
| E2 popover/tooltip | Fill `#121C2E`, border `#3A4F70`, `shadow_size 8`, offset (0, 4), `#000000A0` |  |
| E3 drawer | As E2 with `shadow_size 12` |  |

### 5.4 Motion and iconography

- Hover: 100 ms to `panel-800`. Press: 60 ms to `panel-700`. Phase change: 120 ms cross-fade via a `Tween` on `modulate:a`. Nothing exceeds 300 ms. Provide a Reduced Motion toggle that disables pulses and cross-fades.
- Icons: monoline, 1.5–2 px stroke, authored as SVG and imported at 16, 20, and 24 px. You need 6 gauge icons, 7 category icons, and a small set of status glyphs (✔ ✖ ▲ ▼ lock, info).

### 5.5 Godot setup snippets

Create one `nasa_dark.tres` Theme with type variations: `PanelE1`, `PanelE2`, `GaugeCell`, `PillOK`, `PillCaution`, `PillCritical`, `ButtonPrimary`, `ButtonSecondary`, `ButtonGhost`.

```gdscript
func make_panel_e1() -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color("0E1624E0")
    sb.border_color = Color("2A3B55")
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(4)
    sb.set_content_margin_all(8)
    return sb

func make_popover_e2() -> StyleBoxFlat:
    var sb := make_panel_e1()
    sb.bg_color = Color("121C2E")
    sb.border_color = Color("3A4F70")
    sb.shadow_size = 8
    sb.shadow_offset = Vector2(0, 4)
    sb.shadow_color = Color("000000A0")
    return sb

func make_pill(c: Color) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(c, 0.18)
    sb.border_color = c
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(9)
    sb.content_margin_left = 8
    sb.content_margin_right = 8
    return sb
```

Pareto point drawing, in outline:

```gdscript
func _draw():
    for p in dominated: draw_circle(to_px(p), 3.0, DIM)
    draw_polyline(frontier_px, GUIDE_VIOLET, 2.0)
    for p in frontier: draw_colored_polygon(diamond(to_px(p), 6.0), GUIDE_VIOLET)
    draw_star(to_px(player), 10.0, CYAN)  # custom helper
```

## 6. Build order and risks

1. Theme, HUD, and the Phase host first. Everything else hangs from them.
2. Phase 2 next; it is the make-or-break screen for the 65% rule. Test it with the dock open and the inspector expanded.
3. Phase 4's chart is self-contained `_draw()` code and can be built in parallel.
4. Risks: pin overlap on a small chassis; tooltip delay feeling slow to judges (consider a 250 ms delay in Judge mode); text relayout cost on Web (hence the 10 Hz cap); itch.io embeds that scale the canvas non-uniformly. Set the Godot window stretch to `canvas_items` with aspect `keep` so the 16:9 layout never distorts.
