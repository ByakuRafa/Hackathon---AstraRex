---
name: verify-nasa-physics
description: Audits and enforces NASA physical validity (SP-2016-6105, JPL Horizons DE441, OSDR RadLab, LRO LOLA) in Godot 4 GDScript Singletons (NasaDataLoader.gd, MissionState.gd). Confirms Mass Growth Allowance (MGA), Tsiolkovsky rocket equation with lunar thrust-to-weight (T/W >= 1.0) lockout, solar vector illumination, direct-to-Earth visibility, and radiation dose limits. Use with /verify-nasa-physics.
---

# NASA Physical Validity Verification Workflow (/verify-nasa-physics)

This skill provides an automated audit and implementation protocol for space mission physics calculations in Godot 4.3+ (`gl_compatibility`, single-threaded WebGL). It ensures that all telemetry, mass budgets, propulsion dynamics, power balance, and orbital ephemerides strictly adhere to NASA System Engineering standards and real scientific datasets.

---

## 1. Scientific Principles & NASA Standards Reference

### 1.1 Mass Budget & Mass Growth Allowance (MGA)
Under **NASA Systems Engineering Handbook SP-2016-6105 Rev2 (Section 6.1)**:
- Spacecraft subsystems during formulation and preliminary design carry an inherent design maturity uncertainty.
- Every subsystem dry mass must apply an MGA margin (typically 15% to 30% depending on TRL).
- **Formulas**:
  $$\text{Dry Mass Nominal} = \sum m_{i,\text{dry}}$$
  $$\text{Dry Mass with MGA} = \sum m_{i,\text{dry}} \cdot (1.0 + \text{MGA}_i)$$
  $$m_0 (\text{Wet Mass}) = \text{Dry Mass with MGA} + m_{\text{propellant}}$$
  $$m_f (\text{Burnout Mass}) = \text{Dry Mass with MGA} + m_{\text{unusable\_residuals}}$$

### 1.2 Propulsion & Tsiolkovsky Rocket Equation
- **Ideal Velocity Increment ($\Delta v$)**:
  $$\Delta v = I_{sp} \cdot g_0 \cdot \ln\left(\frac{m_0}{m_f}\right)$$
  where standard Earth gravity $g_0 = 9.80665 \text{ m/s}^2$ and $I_{sp}$ is specific impulse in seconds ($s$).
- **Lunar Surface Gravity**:
  $$g_{\text{moon}} = 1.625 \text{ m/s}^2$$
  $$\text{Lunar Weight } W_{\text{lunar}} = m \cdot g_{\text{moon}}$$
- **Thrust-to-Weight Ratio ($T/W_{\text{lunar}}$) & Descent Lockout**:
  $$\left(\frac{T}{W}\right)_{\text{lunar}} = \frac{F_{\text{thrust}}}{m \cdot 1.625}$$
  - **Terminal Descent Requirement**: $\left(\frac{T}{W}\right)_{\text{lunar}} \ge 1.0$ (typically $\ge 1.3$ for safe touchdown).
  - **Physical Abort Condition**: If total thrust is insufficient ($F_{\text{thrust}} < m \cdot 1.625$, such as ion engines with $F \approx 0.09\text{ N} - 0.25\text{ N}$), soft landing is physically impossible. The simulation must block or fail the descent phase with:
    `"CRITICAL FAILURE: Insufficient Lunar Thrust-to-Weight Ratio (T/W < 1.0). Engine cannot decelerate spacecraft against lunar gravity."`
  - **Propellant Depletion Condition**: If $\Delta v_{\text{budget}} < \Delta v_{\text{required}}$ ($\approx 1750\text{ m/s}$ from Low Lunar Orbit to touchdown), engines flame out prior to touchdown resulting in high-velocity surface impact.

### 1.3 Solar Radiation, Illumination & Thermal Balance
- **JPL Horizons Ephemeris DE441**:
  - Solar and Earth vectors are parsed from `data/ephemeris_horizons.json` as normalized Cartesian 3D vectors: $\hat{s} = (x_s, y_s, z_s)$ and $\hat{e} = (x_e, y_e, z_e)$.
- **DirectionalLight3D Alignment**:
  - The scene's `DirectionalLight3D` representing the Sun must have its basis oriented to match $-\hat{s}$.
- **Solar Power Generation**:
  $$P_{\text{gen}} = \Phi_{\text{solar}} \cdot A_{\text{panels}} \cdot \eta_{\text{solar}} \cdot \max(0, \hat{n}_{\text{panel}} \cdot \hat{s}) \cdot (1.0 - \text{shadow\_factor})$$
  where $\Phi_{\text{solar}} \approx 1361 \text{ W/m}^2$ at 1 AU, and $\text{shadow\_factor}$ is evaluated via `RayCast3D` against lunar crater topography.
- **Direct-to-Earth (DTE) Communication**:
  - Direct line-of-sight to Earth vector $\hat{e}$ checked against terrain geometry via `RayCast3D`. If occluded by the rim of Shackleton crater, comms throughput drops to 0 kbps unless a relay satellite is in view.

### 1.4 Radiation Accumulation (OSDR RadLab)
- Cumulative equivalent dose (GCR + SPE events) in $\text{mSv}$:
  $$D = D_{\text{ambient}} \cdot e^{-\alpha \cdot t_{\text{shield}}}$$
  where $t_{\text{shield}}$ is areal density in $\text{g/cm}^2$. Dose exceeding mission thresholds ($> 100 \text{ mSv}$) triggers avionics single-event upsets (SEU) or instrument degradation.

---

## 2. Audit & Verification Step-by-Step Procedure

When `/verify-nasa-physics` is executed, perform the following verification workflow:

### Step 1: Data Source Verification
Check that the required NASA JSON data files exist and are syntactically valid:
1. `data/nasa_parts_catalog.json` - Subsystem specifications and `nasa_citation` strings.
2. `data/ephemeris_horizons.json` - JPL Horizons solar and Earth vectors for the Shackleton South Pole epoch.
3. `data/radiation_radlab.json` - Radiation flux and attenuation constants.
4. `data/shackleton_terrain_meta.json` - LOLA DEM elevation scale and coordinate bounds.

### Step 2: Audit `NasaDataLoader.gd` Singleton
Ensure `NasaDataLoader.gd` implements robust JSON loading without worker threads:
- Verify that data is parsed synchronously in `_ready()`.
- Validate that each part dictionary contains required SI keys:
  - `mass_dry_kg` (float)
  - `mga_percent` (float)
  - `power_w` (float)
  - `cost_m_usd` (float)
  - `thrust_n` (float, for propulsion)
  - `isp_s` (float, for propulsion)
  - `nasa_citation` (string)

### Step 3: Audit `MissionState.gd` Physics Calculations
Inspect `MissionState.gd` to ensure:
1. **Dry Mass with MGA**:
   ```gdscript
   func calculate_total_dry_mass() -> float:
       var total_dry: float = 0.0
       for part in selected_subsystems:
           var base_mass: float = part.get("mass_dry_kg", 0.0)
           var mga: float = part.get("mga_percent", 0.15) # Default 15% SP-2016-6105
           total_dry += base_mass * (1.0 + mga)
       return total_dry
   ```
2. **Wet Mass and Burnout Mass**:
   ```gdscript
   func calculate_wet_mass() -> float:
       return calculate_total_dry_mass() + propellant_mass_kg

   func calculate_burnout_mass() -> float:
       return calculate_total_dry_mass() + residual_propellant_kg
   ```
3. **Tsiolkovsky $\Delta v$ Calculation**:
   ```gdscript
   func calculate_delta_v() -> float:
       var m0: float = calculate_wet_mass()
       var mf: float = calculate_burnout_mass()
       if mf <= 0.0 or m0 <= mf:
           return 0.0
       return engine_isp_s * 9.80665 * log(m0 / mf)
   ```
4. **Lunar Thrust-to-Weight Ratio ($T/W$) Check**:
   ```gdscript
   const LUNAR_GRAVITY: float = 1.625 # m/s^2

   func calculate_lunar_tw_ratio() -> float:
       var m0: float = calculate_wet_mass()
       if m0 <= 0.0:
           return 0.0
       var lunar_weight: float = m0 * LUNAR_GRAVITY
       return total_thrust_n / lunar_weight

   func can_safely_land_on_moon() -> Dictionary:
       var tw: float = calculate_lunar_tw_ratio()
       var dv: float = calculate_delta_v()
       const REQUIRED_DESCENT_DV: float = 1750.0 # m/s LLO to surface
       
       if tw < 1.0:
           return {
               "can_land": false,
               "reason": "CRITICAL_FAILURE_INSUFFICIENT_THRUST",
               "message": "Lunar T/W is %.2f (< 1.0). Engine thrust (%d N) cannot overcome lunar weight (%.1f N). Soft landing impossible." % [tw, total_thrust_n, calculate_wet_mass() * LUNAR_GRAVITY],
               "citation": "NASA SP-2016-6105 Rev2 §6.1"
           }
       if dv < REQUIRED_DESCENT_DV:
           return {
               "can_land": false,
               "reason": "CRITICAL_FAILURE_PROPELLANT_EXHAUSTION",
               "message": "Available Delta-V is %.1f m/s (< %.1f m/s required). Descent fuel will be exhausted prior to touchdown." % [dv, REQUIRED_DESCENT_DV],
               "citation": "NASA SP-2016-6105 Rev2 §4.2"
           }
       return {"can_land": true, "tw_ratio": tw, "margin_dv": dv - REQUIRED_DESCENT_DV}
   ```

### Step 4: Audit JPL Horizons Vector Application & Solar Shadowing
Ensure lighting and DTE in the lunar terrain scene:
```gdscript
func update_celestial_vectors(sun_light: DirectionalLight3D, sun_vec: Vector3, earth_vec: Vector3) -> void:
    # sun_vec is unit vector towards the Sun from JPL Horizons DE441
    var normalized_sun: Vector3 = sun_vec.normalized()
    # DirectionalLight illuminates towards -Z in its local transform
    sun_light.look_at_from_position(Vector3.ZERO, -normalized_sun, Vector3.UP)
```

Raycasting terrain occlusion check:
```gdscript
func is_in_solar_shadow(lander_pos: Vector3, sun_vec: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
        lander_pos + Vector3(0, 0.5, 0),
        lander_pos + sun_vec.normalized() * 50000.0
    )
    var result: Dictionary = space_state.intersect_ray(query)
    return not result.is_empty()
```

### Step 5: Test Judge Presets
Verify the 3 judge presets produce the exact physical outcomes:
1. **Preset 1 (Optimal Artemis CLPS)**:
   - High $I_{sp}$ bipropellant engine ($T/W > 1.4$).
   - Total $\Delta v \ge 2100\text{ m/s}$ (including 20% margin).
   - Solar + Secondary RTG/Fuel Cell or battery storage.
   - LiDAR TRN module attached (slope $> 15^\circ$ avoided).
   - Expected outcome: **Nominal Success**; high science return.
2. **Preset 2 (Mass / Propulsion Failure)**:
   - Ion thruster selected for landing ($T = 0.25\text{ N}$, $T/W \approx 0.0003$).
   - Expected outcome: **Catastrophic Failure / Lockout**; clear root cause: "Lunar T/W < 1.0 (NASA SP-2016-6105)".
3. **Preset 3 (Sandbox Mode)**:
   - Dynamic real-time calculation update upon any part addition/removal.

---

## 3. Verification Checklist

- [ ] All variables and UI telemetry labels use strict SI units (`kg`, `m/s`, `N`, `s`, `W`, `mSv`, `M$`).
- [ ] No abstract HP or fuel percentage bars exist.
- [ ] Subsystem mass calculation applies explicit `mga_percent`.
- [ ] Tsiolkovsky equation properly calculated using static float typing.
- [ ] Lunar $T/W < 1.0$ condition strictly triggers mission abort / crash with educational diagnostic.
- [ ] JPL Horizons vector properly rotates `DirectionalLight3D`.
- [ ] Solar and DTE line-of-sight checks use `RayCast3D` or `PhysicsDirectSpaceState3D`.
- [ ] Tooltips on all telemetry readouts cite authoritative NASA documentation.
