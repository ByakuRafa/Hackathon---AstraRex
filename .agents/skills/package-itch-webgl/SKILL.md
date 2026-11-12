---
name: package-itch-webgl
description: Executes the hackathon Control Gate checklist (Saturday 23:00 and Sunday 11:00). Verifies export_presets.cfg for single-threaded WebGL (variant/thread_support=false), compiles via Godot CLI to build/web/index.html, audits file sizes against the strict 15 MB budget, and bundles the production .zip for Itch.io and Vercel/Cloudflare Pages. Use with /package-itch-webgl.
---

# WebGL Packaging & Control Gate Deployment Workflow (/package-itch-webgl)

This skill executes the release build automation and deployment verification for the NASA Space Apps Challenge hackathon. It enforces strict hackathon Control Gates (Saturday 23:00 Alpha Freeze and Sunday 11:00 Final Submission Lock), audits single-threaded WebGL export presets, builds the project via the Godot 4 CLI, validates that the total payload is strictly under **15 MB** for <3-second load times at 60 FPS, and produces the finalized `.zip` archive for Itch.io, Vercel, and Cloudflare Pages.

---

## 1. Hackathon Control Gate Schedule

| Control Gate | Deadline | Objective | Critical Checks |
|---|---|---|---|
| **Gate 1: Alpha Vertical Slice** | Saturday 23:00 | Playable end-to-end loop (Phases 1–4) | Single-threaded WebGL runs in browser; 3 judge presets work; < 15 MB package |
| **Gate 2: Final Release Lock** | Sunday 11:00 | Submission freeze & itch.io upload | Zero console errors; strict SI units; Pareto debrief working; package verified |

---

## 2. Invariant Rules for WebGL Compatibility

1. **Single-Threaded Operation (`thread_support = false`)**:
   - WebGL multithreading requires `SharedArrayBuffer` with `Cross-Origin-Opener-Policy: same-origin` (COOP) and `Cross-Origin-Embedder-Policy: require-corp` (COEP) headers.
   - Itch.io and many web platforms embed games in cross-origin `<iframe>` contexts where COOP/COEP are blocked or fail on mobile Safari.
   - Therefore, `variant/thread_support=false` is **mandatory**.
2. **Compatibility Renderer**:
   - `project.godot` must have `rendering/renderer/rendering_method="gl_compatibility"`.
3. **Asset Size Budget**:
   - Total exported bundle (`.wasm` + `.pck` + `.js` + `.html`) must be **< 15 MB**.
4. **Web Audio Safe**:
   - All sound effects must be mono 44.1 kHz, compressed `.ogg` or short `.wav`, avoiding Web Audio buffer underruns.

---

## 3. Automated Packaging Protocol

When `/package-itch-webgl` is executed, perform the following 5 phases:

### Phase 1: Pre-Flight Configuration Audit
Inspect `export_presets.cfg` and `project.godot` to verify settings:

```ini
; In export_presets.cfg under [preset.0.options]
variant/thread_support=false
vram_texture_compression/for_desktop=false
vram_texture_compression/for_mobile=true
html/export_icon=true
```

In `project.godot`:
```ini
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.web="gl_compatibility"
```

Verify that no scripts contain:
- `Thread.new()`
- `WorkerThreadPool`
- `Semaphore` or `Mutex`

### Phase 2: Headless Export via CLI
Ensure the output directory exists and trigger Godot's headless CLI export.

#### On Windows (PowerShell):
```powershell
# Create destination directory
New-Item -ItemType Directory -Force -Path "build/web"

# Locate Godot 4 executable (or use godot alias if in PATH)
$godot_cmd = "godot"
if (-not (Get-Command $godot_cmd -ErrorAction SilentlyContinue)) {
    # Check common install locations or scooped/steam paths
    if (Test-Path "$env:LOCALAPPDATA/Programs/Godot/Godot.exe") {
        $godot_cmd = "$env:LOCALAPPDATA/Programs/Godot/Godot.exe"
    }
}

# Run headless export
& $godot_cmd --headless --export-release "Web" "build/web/index.html"
```

#### On Linux / macOS (Bash):
```bash
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
```

### Phase 3: Size Budget Audit (< 15 MB)
Compute individual and total file sizes inside `build/web/`:

```powershell
$files = Get-ChildItem -Path "build/web"
$totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
$totalMB = [math]::Round($totalBytes / 1MB, 2)

Write-Host "=========================================="
Write-Host "WebGL Bundle Size Audit"
Write-Host "=========================================="
foreach ($f in $files) {
    $sizeKB = [math]::Round($f.Length / 1KB, 1)
    Write-Host ("{0,-30} : {1,8} KB" -f $f.Name, $sizeKB)
}
Write-Host "------------------------------------------"
Write-Host ("TOTAL EXPORT SIZE: {0} MB / 15.0 MB limit" -f $totalMB)

if ($totalMB -gt 15.0) {
    Write-Error "BUDGET EXCEEDED! Bundle is $totalMB MB. Must reduce assets below 15.0 MB."
    # Trigger Asset Optimization Analysis
} else {
    Write-Host "BUDGET VERIFIED: Package is within the 15 MB limit!" -ForegroundColor Green
}
```

#### Asset Optimization Remediation (if > 15 MB):
If the size exceeds 15 MB:
1. **Textures**:
   - Re-import textures as VRAM Compressed (`ETC2/ASTC` for mobile/web) or convert raw PNGs to WebP.
   - Max texture size: 1024x1024 for terrain textures; 512x512 for UI / decals.
2. **3D Models**:
   - Run glTF/GLB models through Draco mesh compression or simplify polygon count in Blender (< 10,000 tris per lander subsystem).
3. **Audio**:
   - Re-encode all `.ogg` music/sound at 96 kbps mono 44.1 kHz.

### Phase 4: Generate Web Hosting Package (`.zip`)
Compress `build/web/*` into a zip archive ready for instant upload.

#### On Windows (PowerShell):
```powershell
$zipPath = "build/AstraRex-LunarMission-Web.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "build/web/*" -DestinationPath $zipPath
Write-Host "Created deployment archive: $zipPath" -ForegroundColor Green
```

### Phase 5: Verification & Local Testing
Start a local web server to verify that the export boots cleanly without COOP/COEP errors:

```powershell
# Test locally with Python or Node
python -m http.server 8080 --directory build/web
# Or: npx serve build/web
```

Open `http://localhost:8080` in Chrome/Edge and check Developer Tools Console (`F12`):
- Confirm **0 uncaught WebAssembly exceptions**.
- Confirm no `SharedArrayBuffer` warnings.
- Confirm loading time is $< 3$ seconds.
- Confirm 60 FPS stable in VAB and Shackleton descent views.

---

## 4. Control Gate Checklist

### Gate 1: Saturday 23:00 (Alpha Vertical Slice)
- [ ] Single-Threaded setting confirmed (`variant/thread_support=false`).
- [ ] `export_presets.cfg` contains valid Web template configuration.
- [ ] Build compiles via CLI without errors to `build/web/index.html`.
- [ ] Export size is $\le 15.0\text{ MB}$.
- [ ] `AstraRex-LunarMission-Web.zip` generated and tested in local HTTP server.
- [ ] All 3 Judge Presets are functional in the browser.

### Gate 2: Sunday 11:00 (Final Release Lock)
- [ ] Final package size re-audited and strictly $< 15\text{ MB}$.
- [ ] No debug prints or debug overlays in release build.
- [ ] Full 4-phase loop plays without browser console errors.
- [ ] Telemetry tooltips display official NASA citations.
- [ ] Pareto debrief downloads JSON correctly via `JavaScriptBridge`.
- [ ] Uploaded to Itch.io with checkbox **"This file will be played in the browser"** and resolution set to **1280 x 720** (responsive).

