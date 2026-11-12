---
trigger: glob
globs: "**/*.gd, **/*.tscn, **/project.godot, **/export_presets.cfg"
description: GDScript 2.0 coding standards, SI physical units, and WebGL architecture rules for Godot 4.
---

# Godot 4 GDScript & Scene Coding Standards

All Godot 4 code and scenes within this project must strictly comply with the following standards:

## 1. GDScript 2.0 Typing & Performance
- **Static Typing**: All variables, function parameters, and return types must be explicitly typed (e.g., `var mass: float = 0.0`, `func calc_dv() -> float:`). Never use untyped dynamic declarations.
- **Class Declarations**: Explicitly define `class_name` on reusable data models, singletons, and custom UI components (e.g., `class_name ParetoSolver`, `class_name VABPartCard`).
- **Process Loop Optimization**: Never perform heavy calculations, raycasting, or dictionary lookups inside `_process(delta)` or `_physics_process(delta)`. Throttle UI telemetry and celestial raycasts via a dedicated `Timer` (0.1s to 0.2s interval) or signal events.

## 2. Scientific Units & Telemetry Invariants
- **Strict SI Units**: All code variables, math operations, and UI labels must operate strictly in the International System of Units (SI):
  - Mass in kilograms (`kg`).
  - Velocity / Delta-V in meters per second (`m/s`).
  - Force / Thrust in newtons (`N`).
  - Power in watts (`W`).
  - Radiation dose in millisieverts (`mSv`).
  - Cost in millions of USD (`M$`).
- **Prohibition of Abstract Stats**: Never use generic "HP", fuel percentages without kilograms, or arbitrary progress bars.
- **Official Citations**: Interactive UI elements and telemetry readouts must populate `tooltip_text` citing authoritative NASA documentation (`NASA SP-2016-6105 Rev2`, `JPL Horizons DE441`, `LRO LOLA DEM`, or `OSDR RadLab`).

## 3. Terrain Descent & Hazard Avoidance (TRN)
- When simulating descent across the Shackleton crater DEM (`HeightMapShape3D`), sample the surface normal at the touchdown point.
- If the terrain slope exceeds $15.0^\circ$ and the spacecraft does not have the `TRN LiDAR` subsystem active, trigger structural tip-over failure and record the root-cause diagnostic in `MissionState`.

## 4. Browser File Export
- For telemetry and Pareto debrief export in "Engineer Mode":
  - Check `OS.has_feature("web")`.
  - Use `JavaScriptBridge.download_buffer(bytes, filename, "application/json")` in web builds.
  - Maintain a local file fallback: `FileAccess.open("user://" + filename, FileAccess.WRITE)` when running in desktop editor mode.

