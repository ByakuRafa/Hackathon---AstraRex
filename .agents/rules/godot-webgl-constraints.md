---
trigger: always_on
globs: "**/*.gd, **/*.cs, **/*.tscn, **/project.godot, **/export_presets.cfg"
description: Strict WebGL single-threaded constraints (prohibits C# and SharedArrayBuffer threads, mandates gl_compatibility renderer and 60 FPS budget).
---

# WebGL Single-Threaded Constraints & Performance Invariants

This rule defines mandatory technical constraints for Godot 4.3+ targeting the web browser (Itch.io, Vercel, and Cloudflare Pages). These constraints are non-negotiable architectural requirements.

---

## 1. Absolute Prohibition of C# / .NET
- **GDScript 2.0 Only**: All game logic, mathematical models, UI controllers, and physics singletons must be implemented in statically-typed GDScript 2.0.
- **No C# or .NET Assemblies**:
  - Never generate `.cs` source files, `.csproj` project files, or recommend C# libraries.
  - Exporting Godot 4 Web builds with C# requires the Mono/.NET WebAssembly runtime, which adds over 30 MB to the package, exceeding the strict 15 MB hackathon budget and causing browser runtime failures.

---

## 2. Single-Threaded Architecture (No `SharedArrayBuffer`)
- **No Threading Constructs**:
  - Never instantiate `Thread.new()` or `WorkerThreadPool`.
  - Never use `Mutex`, `Semaphore`, or thread-based background workers.
- **Browser Compatibility Invariant**:
  - Multi-threaded WebAssembly requires `SharedArrayBuffer`, which mandates `Cross-Origin-Opener-Policy: same-origin` (COOP) and `Cross-Origin-Embedder-Policy: require-corp` (COEP) HTTP response headers.
  - Platform hosts (such as Itch.io `<iframe>` embeds and mobile Safari) block or fail when COOP/COEP isolation is required.
  - In `export_presets.cfg`, ensure:
    ```ini
    variant/thread_support=false
    ```
- **Asynchronous Task Handling**:
  - Long-running calculations (such as combinatorial Pareto search in `ParetoSolver.gd`) must be executed either synchronously on small datasets or cooperatively time-sliced across frames using:
    ```gdscript
    await get_tree().process_frame
    ```

---

## 3. Renderer & 60 FPS Budget on `gl_compatibility`
- **Rendering Engine**:
  - Keep `rendering/renderer/rendering_method="gl_compatibility"` in `project.godot`.
  - Do not use Forward+ or Mobile renderers (unsupported or unstable on WebGL).
- **Shader & Feature Restrictions**:
  - Do not use compute shaders, volumetric fog, SDFGI, SSAO, or screen-space reflections.
  - Keep custom spatial shaders compatible with standard OpenGL ES 3.0 / WebGL 2.0 shading language.
- **Frame Rate & Processing Budget**:
  - Maintain a steady 60 FPS on typical laptop integrated graphics.
  - Throttle UI telemetry updates and celestial raycasts via timer (0.1s – 0.2s) instead of every frame in `_process(delta)`.
  - Mesh budget: under 10,000 triangles per subsystem model; use primitive collision shapes (`CylinderShape3D`, `BoxShape3D`, `SphereShape3D`) or lightweight `HeightMapShape3D` for terrain.

---

## 4. Package Size Budget (< 15 MB) & Audio Safe Mode
- **Bundle Size**: Total exported web payload (`.wasm` + `.pck` + `.js` + `index.html`) must remain strictly under **15 MB** to ensure sub-3-second load times.
- **Audio Output**: Configure all audio to Web Audio samples (mono, 44.1 kHz, short `.ogg` or `.wav`) to avoid buffer starvation and audio distortion on mobile and desktop browsers.

