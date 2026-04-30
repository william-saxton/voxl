# VOXL - Voxel Terrain & Physics Simulation

A Godot 4.6 game project with a C++ GDExtension for voxel-based destructible terrain with Noita-inspired material physics.

The voxel/tile editor lives in a separate sibling project at [`../voxl-editor`](../voxl-editor) and ships its own builds. This repo contains the game runtime + the native library that both projects share.

## Project Structure

- `scripts/` — GDScript game logic (player, camera, voxel interaction, world manager, stress tests)
- `scripts/wfc/` — WFC tile/biome/world-map definitions (also used by `voxl-editor`)
- `scripts/material_registry.gd` — voxel material catalogue (also used by `voxl-editor`)
- `native/src/` — C++ GDExtension source (material simulator, chunk store, mesher)
- `native/godot-cpp/` — Git submodule for Godot C++ bindings
- `scenes/` — Godot scene files (entry point: `scenes/voxel_world.tscn`)
- `shaders/` — GLSL shaders for terrain, water, gas, portals
- `resources/` — fluid material resources
- `bin/` — Compiled native library output (not committed)

## Building

### Native C++ library (GDExtension)

```bash
cd native
scons platform=linux target=template_debug -j$(nproc)
scons platform=linux target=template_release -j$(nproc)
scons platform=windows target=template_debug -j$(nproc)
scons platform=windows target=template_release -j$(nproc)
```

Requires: Python 3, SCons, C++ compiler (gcc/clang on Linux, MSVC on Windows).

Output goes to `bin/libvoxl_native.<platform>.<target>.<arch>.<ext>`.

### Godot project

```bash
godot --headless --import
godot --headless --export-release "Windows Desktop" build/VOXL.exe
godot --headless --export-release "Linux" build/VOXL.x86_64
```

## Native library distribution

This repo's `release.yml` workflow publishes the native lib as standalone GitHub Release assets:
- `libvoxl_native-linux-x86_64.tar.gz`
- `libvoxl_native-windows-x86_64.zip`

The `voxl-editor` project consumes these in its own CI to build the editor without duplicating the native source. See `voxl-editor/tools/fetch_native_lib.sh`.

## Key files

- `project.godot` — Godot project config (4.6, Forward Plus, Jolt Physics, main_scene = voxel_world.tscn)
- `voxl_native.gdextension` — GDExtension manifest mapping platforms to native libs
- `export_presets.cfg` — Export presets for Windows Desktop + Linux
- `native/SConstruct` — SCons build script
- `.github/workflows/release.yml` — Builds + publishes the native lib on PR merge. Does NOT export the Godot game (the game is WIP; add a separate workflow when it's ready to ship).

## Conventions

- GDScript follows Godot style (snake_case functions, PascalCase classes)
- C++ follows godot-cpp conventions
- Commit messages should be concise and descriptive
- Shared GDScript files (`scripts/wfc/`, `scripts/material_registry.gd`, `resources/`) are duplicated in `voxl-editor`. When changing either, mirror the change in the other repo.
