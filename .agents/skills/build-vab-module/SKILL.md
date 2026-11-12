---
name: build-vab-module
description: Automates adding a new 3D subsystem (.glb) into the Vehicle Assembly Building (VAB) via Godot MCP. Reads part attributes from data/nasa_parts_catalog.json, instances the mesh at the designated chassis Marker3D, builds the SI-compliant UI card, and injects the authoritative nasa_citation into the tooltip. Use with /build-vab-module.
---

# VAB Modular Subsystem Integration Workflow (/build-vab-module)

This skill guides the automated integration of modular 3D spacecraft subsystems (`.glb` assets) into the Vehicle Assembly Building (VAB) using the Godot Model Context Protocol (MCP) server. It enforces real NASA specifications from `data/nasa_parts_catalog.json`, mounts 3D meshes to dedicated `Marker3D` anchors on the chassis, creates standard SI telemetry UI cards, and embeds `nasa_citation` metadata into UI tooltips.

---

## 1. Architecture & Integration Pipeline

```
[data/nasa_parts_catalog.json]
             │
             ▼
   [Parse Subsystem Data]
     • id, name, subsystem
     • mass_dry_kg, mga_percent
     • power_w, cost_m_usd
     • thrust_n, isp_s
     • mount_point, model_path
     • nasa_citation
             │
      ┌──────┴─────────────────────────────────┐
      ▼                                        ▼
[3D Viewport / Chassis]                 [VAB UI Catalog]
  • Locate Marker3D mount point           • Create VABPartCard (Control)
  • Instance .glb under Marker3D          • Set SI labels (kg, W, N, M$)
  • Toggle visibility on select           • Set tooltip_text with citation
  • Recalculate center of mass            • Connect signal to MissionState
```

---

## 2. Godot MCP Protocol Rules

When adding or modifying VAB nodes and scenes via MCP:
1. **Scene Inspection First**:
   - Always call `get_scene_tree` on `res://scenes/vab/VABScene.tscn` or `res://scenes/vab/LanderChassis.tscn` before modifying nodes.
   - Inspect existing mount markers with `get_node_properties` to verify transform coordinates and naming.
2. **No Raw Text Modification of `.tscn`**:
   - Use the MCP server to instantiate nodes, add children, and assign properties. Never attempt regex text edits on `.tscn` files when the Godot editor or MCP server is running.
3. **Static Typing & Conventions**:
   - All generated GDScript handlers must use explicit GDScript 2.0 static typing (`var part_id: String = ""`, `func _on_part_toggled(toggled: bool) -> void:`).
4. **WebGL / Single-Threaded Safe**:
   - Mesh instantiations and materials must run on the main thread using standard `Compatibility` (GLES3/WebGL1) shading (avoid compute shaders or unsupported WebGL extensions).

---

## 3. Step-by-Step Implementation Procedure

### Step 1: Subsystem Schema Validation
Read the target subsystem entry in `data/nasa_parts_catalog.json`. Verify that all required NASA engineering fields are present:
```json
{
  "id": "prop_hypergolic_hyperion",
  "name": "Hyperion Hypergolic Descent Engine",
  "subsystem": "propulsion",
  "mass_dry_kg": 45.0,
  "mga_percent": 0.15,
  "thrust_n": 3500.0,
  "isp_s": 318.0,
  "power_w": -25.0,
  "cost_m_usd": 12.5,
  "mount_point": "Mount_Propulsion",
  "model_path": "res://assets/models/subsystems/prop_hypergolic.glb",
  "nasa_citation": "NASA SP-2016-6105 Rev2 §4.2; Apollo LM Descent Engine (LMDE) heritage data"
}
```

### Step 2: 3D Chassis Mount Integration
1. Open or inspect the chassis scene (`res://scenes/vab/LanderChassis.tscn`).
2. Identify or instantiate the target `Marker3D` matching `mount_point` (e.g., `Mount_Propulsion`, `Mount_Power_Port`, `Mount_Avionics`, `Mount_Payload_Top`, `Mount_Comms_Antenna`, `Mount_Landing_Gear_1`).
3. Instantiate the `.glb` model under the designated `Marker3D`:
   - Node name: `Mesh_<part_id>` (e.g. `Mesh_prop_hypergolic_hyperion`).
   - Configure collision if raycast picking in 3D VAB is required.
   - Set `visible = false` by default, toggled when the player equips or un-equips the part in the VAB catalog.

### Step 3: UI Card Creation (`VABPartCard.tscn`)
Create or instantiate a UI Card node under `VAB/SubsystemPanel/ScrollContainer/VBoxContainer`:
- Root Node: `Button` or `PanelContainer` with custom theme styling.
- Structure:
  - `HBoxContainer`
    - `TextureRect` (Icon / Subsystem Badge)
    - `VBoxContainer` (Labels)
      - `LabelTitle` (`text = part.name`)
      - `HBoxContainer` (Telemetry Badges in SI Units):
        - Mass: `LabelMass` (`text = "%.1f kg (+%.0f%% MGA)" % [part.mass_dry_kg, part.mga_percent * 100.0]`)
        - Power: `LabelPower` (`text = "%+d W" % [part.power_w]`)
        - Cost: `LabelCost` (`text = "$%.1f M" % [part.cost_m_usd]`)
        - If propulsion:
          - Thrust: `LabelThrust` (`text = "%.0f N" % [part.thrust_n]`)
          - Isp: `LabelIsp` (`text = "%.0f s" % [part.isp_s]`)
- **Prohibition of Abstract Stats**: Never use health points, generic progress bars, or level values. Everything must display physical SI units.

### Step 4: Inject `nasa_citation` into Tooltip
Set the `tooltip_text` property of the root card and interactive elements. Format the tooltip as a structured NASA engineering specification card:

```gdscript
func configure_card(part_data: Dictionary) -> void:
    part_id = part_data.get("id", "")
    label_title.text = part_data.get("name", "Unknown Subsystem")
    
    var mass: float = part_data.get("mass_dry_kg", 0.0)
    var mga: float = part_data.get("mga_percent", 0.15) * 100.0
    var power: float = part_data.get("power_w", 0.0)
    var cost: float = part_data.get("cost_m_usd", 0.0)
    var citation: String = part_data.get("nasa_citation", "NASA Systems Engineering Handbook SP-2016-6105")

    label_mass.text = "Mass: %.1f kg (MGA: +%.0f%%)" % [mass, mga]
    label_power.text = "Power: %+d W" % [power]
    label_cost.text = "Cost: $%.2f M" % [cost]

    # Tooltip with authoritative citation
    var tooltip: String = ""
    tooltip += "=== %s ===\n" % part_data.get("name", "")
    tooltip += "Subsystem: %s\n" % part_data.get("subsystem", "").capitalize()
    tooltip += "Nominal Dry Mass: %.2f kg\n" % mass
    tooltip += "Mass Growth Allowance (MGA): +%.1f%%\n" % mga
    tooltip += "Effective Dry Mass: %.2f kg\n" % (mass * (1.0 + (mga / 100.0)))
    tooltip += "Operating Power: %+d W\n" % power
    tooltip += "Lifecycle Cost: $%.2f M\n" % cost
    
    if part_data.has("thrust_n"):
        tooltip += "Vacuum Thrust: %.1f N\n" % part_data.get("thrust_n", 0.0)
        tooltip += "Specific Impulse (Isp): %.1f s\n" % part_data.get("isp_s", 0.0)
    if part_data.has("science_points"):
        tooltip += "Science Return Value: +%d pts\n" % part_data.get("science_points", 0)

    tooltip += "\n[Authoritative Reference]:\n%s" % citation
    
    self.tooltip_text = tooltip
```

### Step 5: Signal Connection to Real-Time Trade Study
Connect the card's `toggled(bool)` or `pressed` signal to the VAB controller and `MissionState.gd`:
```gdscript
func _on_card_toggled(is_selected: bool) -> void:
    if is_selected:
        MissionState.equip_subsystem(part_id)
        _set_3d_mesh_visible(part_id, true)
    else:
        MissionState.unequip_subsystem(part_id)
        _set_3d_mesh_visible(part_id, false)
    
    # Broadcast trade study recalculation event to HUD
    MissionState.recalculate_trade_study()
```

---

## 4. Quality Checklist

- [ ] Subsystem `.glb` file located in `res://assets/models/subsystems/`.
- [ ] Part record in `data/nasa_parts_catalog.json` contains valid SI values and non-empty `nasa_citation`.
- [ ] Chassis contains designated `Marker3D` matching `mount_point`.
- [ ] Mesh node is parented to the `Marker3D` and positioned with correct scale/rotation.
- [ ] UI Card displays mass in `kg`, power in `W`, cost in `M$`, and propulsion in `N` / `s`.
- [ ] Tooltip clearly displays the exact `nasa_citation`.
- [ ] Equipping/unequipping updates wet mass, Tsiolkovsky $\Delta v$, and $T/W_{\text{lunar}}$ in real time on the HUD.

