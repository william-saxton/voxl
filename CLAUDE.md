# VOXL - Voxel Terrain & Physics Simulation

A Godot 4.6 project with a C++ GDExtension for voxel-based destructible terrain with Noita-inspired material physics.

## Project Structure

- `scripts/` — GDScript game logic
- `native/src/` — C++ GDExtension source (material simulator, voxel editor)
- `native/godot-cpp/` — Git submodule for Godot C++ bindings
- `scenes/` — Godot scene files (.tscn)
- `shaders/` — GLSL shaders
- `bin/` — Compiled native library output (not committed)
- `addons/` — Third-party Godot plugins (zylann.voxel, CSS theme, world map editor)
- `docs/` — Design documents

## Building

### Native C++ library (GDExtension)

```bash
cd native
scons platform=linux target=template_debug -j$(nproc)    # Linux debug
scons platform=linux target=template_release -j$(nproc)   # Linux release
scons platform=windows target=template_debug -j$(nproc)   # Windows debug
scons platform=windows target=template_release -j$(nproc)  # Windows release
```

Requires: Python 3, SCons, C++ compiler (gcc/clang on Linux, MSVC on Windows).

Output goes to `bin/libvoxl_native.<platform>.<target>.<arch>.<ext>`.

### Godot project

```bash
godot --headless --import        # Import/validate project
godot --headless --export-debug "Windows Desktop" build/VOXL.exe  # Export
```

## Key files

- `project.godot` — Godot project config (4.6, Forward Plus renderer, Jolt Physics)
- `voxl_native.gdextension` — GDExtension manifest mapping platforms to native libs
- `export_presets.cfg` — Export preset for Windows Desktop
- `native/SConstruct` — SCons build script for the native library

## Conventions

- GDScript follows Godot style (snake_case functions, PascalCase classes)
- C++ follows godot-cpp conventions
- Commit messages should be concise and descriptive
