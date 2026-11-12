---
name: generate-pareto-debrief
description: Generates ParetoSolver.gd and DebriefPanel.tscn to calculate and render the Pareto Frontier (Science vs. Mass/Cost/Survival) in Godot 4 via custom Control._draw(). Benchmarks player lander designs against NASA Artemis optimums and outputs physical root-cause engineering debriefs. Use with /generate-pareto-debrief.
---

# Multi-Objective Pareto Frontier & Debrief System (/generate-pareto-debrief)

This skill provides an automated implementation and verification framework for `ParetoSolver.gd` and the `DebriefPanel.tscn` debriefing screen in Godot 4.3+ (`gl_compatibility`, single-threaded WebGL). It evaluates the combinatorial design space of spacecraft components from `data/nasa_parts_catalog.json`, computes non-dominated Pareto Frontier trade studies, visualizes them with pure Godot 2D canvas drawing (`_draw()`), compares the player's design against the NASA Artemis CLPS reference baseline, and generates physics-based root-cause diagnosis.

---

## 1. Mathematical & Engineering Foundations

### 1.1 Multi-Objective Optimization Space
A spacecraft design $x$ is defined by a selection of subsystems from `data/nasa_parts_catalog.json`:
$$x = \{\text{chassis}, \text{propulsion}, \text{power}, \text{avionics}, \text{comms}, \text{payload}_1 \dots \text{payload}_k\}$$

The multi-objective performance vector is:
$$\vec{f}(x) = [f_{\text{science}}(x), -f_{\text{mass}}(x), -f_{\text{cost}}(x), f_{\text{survival}}(x)]$$

Where:
- $f_{\text{science}}(x) = \sum \text{science\_points}_i$ (Maximize)
- $f_{\text{mass}}(x) = m_0$ (Total wet mass in $\text{kg}$ including MGA margin; Minimize)
- $f_{\text{cost}}(x) = \sum \text{cost\_m\_usd}_i$ (Lifecycle cost in $\text{M}\$$; Minimize)
- $f_{\text{survival}}(x) \in [0.0, 1.0]$: Probability of mission survival determined by:
  - Propulsion: Is lunar $T/W \ge 1.0$ and $\Delta v \ge 1750\text{ m/s}$?
  - Landing Hazard: If landing site slope $> 15.0^\circ$, is TRN LiDAR equipped?
  - Thermal / Night: Does power subsystem survive 14-day lunar night (RTG or battery capacity $\ge 45\text{ kWh}$)?
  - Radiation: Does total accumulated dose remain $< 100\text{ mSv}$ with shielding?

### 1.2 Pareto Dominance
A design $A$ dominates design $B$ ($A \succ B$) if and only if:
1. $A$ is no worse than $B$ in all objectives:
   $$\forall i: f_i(A) \ge f_i(B)$$
2. $A$ is strictly better than $B$ in at least one objective:
   $$\exists i: f_i(A) > f_i(B)$$

The **Pareto Frontier** $\mathcal{P}^*$ is the subset of all feasible spacecraft designs not dominated by any other design:
$$\mathcal{P}^* = \{ x \in \mathcal{X} \mid \nexists x' \in \mathcal{X}: x' \succ x \}$$

---

## 2. Architecture & File Structure

```
res://
  ├── scripts/
  │     ├── pareto/
  │     │     ├── ParetoSolver.gd       # Combinatorial evaluator & dominance engine
  │     │     └── ParetoPoint.gd        # Data model for candidate designs
  │     └── ui/
  │           ├── DebriefPanel.gd       # Controller for debrief screen
  │           └── ParetoPlotControl.gd  # Custom Control node implementing _draw()
  └── scenes/
        └── debrief/
              └── DebriefPanel.tscn     # Complete 4th phase debrief UI
```

---

## 3. Step-by-Step Implementation Protocol

### Step 1: Implement `ParetoSolver.gd`
`ParetoSolver.gd` reads `data/nasa_parts_catalog.json`, generates valid combinations, and computes the non-dominated set.

```gdscript
class_name ParetoSolver
extends RefCounted

static func solve_pareto_frontier(catalog: Dictionary) -> Array[Dictionary]:
    var candidates: Array[Dictionary] = _generate_candidate_designs(catalog)
    var pareto_set: Array[Dictionary] = []

    for i in range(candidates.size()):
        var candidate_a: Dictionary = candidates[i]
        var is_dominated: bool = false
        
        for j in range(candidates.size()):
            if i == j:
                continue
            var candidate_b: Dictionary = candidates[j]
            if _dominates(candidate_b, candidate_a):
                is_dominated = true
                break
        
        if not is_dominated:
            pareto_set.append(candidate_a)
            
    # Sort by total mass ascending for polyline drawing
    pareto_set.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return a["total_mass_kg"] < b["total_mass_kg"]
    )
    return pareto_set

static func _dominates(a: Dictionary, b: Dictionary) -> bool:
    # A dominates B if A has >= science, <= mass, <= cost, >= survival
    # and strictly better in at least one metric
    var a_sci: float = a["science_score"]
    var b_sci: float = b["science_score"]
    var a_mass: float = a["total_mass_kg"]
    var b_mass: float = b["total_mass_kg"]
    var a_cost: float = a["cost_m_usd"]
    var b_cost: float = b["cost_m_usd"]
    var a_surv: float = a["survival_prob"]
    var b_surv: float = b["survival_prob"]

    var not_worse: bool = (a_sci >= b_sci and a_mass <= b_mass and a_cost <= b_cost and a_surv >= b_surv)
    var strictly_better: bool = (a_sci > b_sci or a_mass < b_mass or a_cost < b_cost or a_surv > b_surv)
    return not_worse and strictly_better
```

### Step 2: Implement Custom `Control` Drawing in `ParetoPlotControl.gd`
Create a custom `Control` that renders the graph natively using Godot's 2D canvas drawing methods (`_draw()`). This avoids heavy third-party graphing libraries and keeps the WebGL bundle compact.

```gdscript
class_name ParetoPlotControl
extends Control

var all_points: Array[Dictionary] = []
var pareto_points: Array[Dictionary] = []
var player_point: Dictionary = {}
var nasa_optimal_point: Dictionary = {}

# Axis bounds
var min_x: float = 200.0   # Mass (kg) or Cost ($M)
var max_x: float = 2500.0
var min_y: float = 0.0     # Science Score
var max_y: float = 100.0

func _draw() -> void:
    var rect_size: Vector2 = size
    var margin: float = 40.0
    var plot_rect: Rect2 = Rect2(margin, margin, rect_size.x - margin * 2.0, rect_size.y - margin * 2.0)
    
    # 1. Background Grid & Axes
    draw_rect(plot_rect, Color(0.08, 0.1, 0.14, 0.8), true)
    draw_rect(plot_rect, Color(0.3, 0.35, 0.45, 1.0), false, 2.0)
    
    _draw_grid(plot_rect)
    
    # 2. Suboptimal Candidate Points (Dim Scatter)
    for pt in all_points:
        var screen_pos: Vector2 = _to_screen(pt["total_mass_kg"], pt["science_score"], plot_rect)
        draw_circle(screen_pos, 2.5, Color(0.4, 0.45, 0.5, 0.4))
        
    # 3. Pareto Frontier Curve
    if pareto_points.size() > 1:
        var curve_points: PackedVector2Array = PackedVector2Array()
        for pt in pareto_points:
            curve_points.append(_to_screen(pt["total_mass_kg"], pt["science_score"], plot_rect))
        draw_polyline(curve_points, Color(0.2, 0.8, 1.0, 0.9), 2.5)
        for pt_pos in curve_points:
            draw_circle(pt_pos, 4.0, Color(0.2, 0.8, 1.0, 1.0))
            
    # 4. NASA Optimal Benchmark Point (Green Diamond/Star)
    if not nasa_optimal_point.is_empty():
        var nasa_pos: Vector2 = _to_screen(nasa_optimal_point["total_mass_kg"], nasa_optimal_point["science_score"], plot_rect)
        draw_circle(nasa_pos, 7.0, Color(0.2, 1.0, 0.3, 1.0))
        draw_string(ThemeDB.fallback_font, nasa_pos + Vector2(10, 4), "NASA Artemis Optimum", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.2, 1.0, 0.3))

    # 5. Player Design Point (Bright Orange/Yellow Marker)
    if not player_point.is_empty():
        var player_pos: Vector2 = _to_screen(player_point["total_mass_kg"], player_point["science_score"], plot_rect)
        draw_circle(player_pos, 8.0, Color(1.0, 0.7, 0.1, 1.0))
        draw_circle(player_pos, 12.0, Color(1.0, 0.7, 0.1, 0.4)) # Glow ring
        draw_string(ThemeDB.fallback_font, player_pos + Vector2(14, 4), "Your Lander", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.7, 0.1))

func _to_screen(val_x: float, val_y: float, rect: Rect2) -> Vector2:
    var norm_x: float = clampf((val_x - min_x) / (max_x - min_x), 0.0, 1.0)
    var norm_y: float = clampf((val_y - min_y) / (max_y - min_y), 0.0, 1.0)
    # Invert Y for screen coordinates (0 at top)
    return Vector2(
        rect.position.x + norm_x * rect.size.x,
        rect.position.y + (1.0 - norm_y) * rect.size.y
    )
```

### Step 3: Implement Physical Root-Cause Diagnostic Engine
When a mission fails or is suboptimal, generate a structured engineering debrief with direct citations:

```gdscript
func generate_root_cause_analysis(mission_data: Dictionary) -> Dictionary:
    var failure_mode: String = mission_data.get("failure_mode", "SUCCESS")
    var report: Dictionary = {
        "status": failure_mode,
        "title": "",
        "cause": "",
        "physics_principle": "",
        "recommendation": "",
        "citation": ""
    }
    
    match failure_mode:
        "CRITICAL_FAILURE_INSUFFICIENT_THRUST":
            report["title"] = "Terminal Descent Propulsion Lockout"
            report["cause"] = "Selected propulsion engine thrust is less than total spacecraft lunar weight."
            report["physics_principle"] = "Lunar surface gravity g_moon = 1.625 m/s². Minimum Lunar T/W >= 1.0 is required for descent deceleration."
            report["recommendation"] = "Replace ion thruster with high-thrust bipropellant engine (e.g. Hyperion Hypergolic Engine, T >= 3500 N)."
            report["citation"] = "NASA Systems Engineering Handbook SP-2016-6105 Rev2 §6.1"

        "CRITICAL_FAILURE_PROPELLANT_EXHAUSTION":
            report["title"] = "Propellant Depletion Prior to Touchdown"
            report["cause"] = "Spacecraft Delta-V is lower than required landing delta-v (1750 m/s)."
            report["physics_principle"] = "Tsiolkovsky Equation: Delta-V = Isp * g0 * ln(m0 / mf). Mass growth reduced available velocity increment."
            report["recommendation"] = "Increase propellant tank capacity or reduce dry mass by removing non-essential payloads."
            report["citation"] = "NASA SP-2016-6105 Rev2 §4.2"

        "LANDING_GEAR_TIPOVER":
            report["title"] = "Terrain Landing Slope Tip-Over"
            report["cause"] = "Touchdown occurred on a 19.4° crater slope exceeding the 15° stability threshold without active hazard avoidance."
            report["physics_principle"] = "Center of mass projected vector fell outside the lander footpad polygon."
            report["recommendation"] = "Equip the Terrain Relative Navigation (TRN) LiDAR module to steer to flat terrain (< 15°)."
            report["citation"] = "LRO LOLA Shackleton Crater DEM & CLPS Autonomous Landing Standards"

        "LUNAR_NIGHT_THERMAL_FAILURE":
            report["title"] = "Cryogenic Freezing During Lunar Night"
            report["cause"] = "Lander lost thermal control during the 354-hour lunar night due to lack of non-solar power."
            report["physics_principle"] = "Solar flux drops to 0 W/m² during occultation. Battery storage alone was depleted within 36 hours."
            report["recommendation"] = "Equip an RTG (Radioisotope Thermoelectric Generator) or 50 kWh Regenerative Fuel Cell."
            report["citation"] = "NASA SP-2016-6105 Rev2 Chapter 4: Thermal & Power Balance"
            
    return report
```

### Step 4: Implement Dual Mode & Data Export
In `DebriefPanel.gd`:
- **Student Mode**: Displays simplified cards, high-contrast visual cues, and educational explanations.
- **Engineer Mode**: Displays raw multi-objective performance tables and enables one-click export:
  ```gdscript
  func export_trade_study_data() -> void:
      var export_dict: Dictionary = {
          "mission_timestamp": Time.get_datetime_string_from_system(),
          "player_design": player_point,
          "nasa_benchmark": nasa_optimal_point,
          "pareto_frontier": pareto_points,
          "root_cause": root_cause_report
      }
      var json_string: String = JSON.stringify(export_dict, "\t")
      var bytes: PackedByteArray = json_string.to_utf8_buffer()
      var filename: String = "AstraRex_Pareto_Debrief_%d.json" % Time.get_unix_time_from_system()
      
      if OS.has_feature("web"):
          JavaScriptBridge.download_buffer(bytes, filename, "application/json")
      else:
          var file: FileAccess = FileAccess.open("user://" + filename, FileAccess.WRITE)
          if file:
              file.store_buffer(bytes)
              file.close()
  ```

---

## 4. Verification & Validation Checklist

- [ ] `ParetoSolver.gd` executes non-dominated sorting across all four dimensions (Science, Mass, Cost, Survival).
- [ ] `ParetoPlotControl.gd` draws the Pareto curve cleanly using `_draw()` without external dependencies.
- [ ] NASA Artemis Optimum point is prominently plotted and labeled on the graph.
- [ ] Player's design is clearly highlighted, showing the efficiency delta to the frontier.
- [ ] Physical failures trigger accurate diagnostic reports with official NASA citations.
- [ ] Switching between "Student Mode" and "Engineer Mode" updates the UI instantly.
- [ ] JSON/CSV export works in browser via `JavaScriptBridge.download_buffer()`.

