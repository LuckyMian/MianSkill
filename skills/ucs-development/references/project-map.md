# UCS_Core project map

Snapshot: 2026-09-25. Root: `F:/UnrealProject/UCS_Core`.

## Ownership

| Area | Source | Role |
| --- | --- | --- |
| Project shell | `Source/UCS_Core/`, `UCS_Core.uproject`, `Config/` | Minimal game module and project targets/settings. |
| UCS runtime | `Plugins/UltraControlSystem/Source/UltraControlSystem/` | Camera actors, Pawn, Controller, UCS message dispatch, UMG widgets, global settings. |
| UCS editor | `.../UltraControlSystemEditor/` | Project Settings registration and Details customization. |
| Blueprint subsystem framework | `.../UltraControlSubSystem/` | Blueprint subclassable Engine, GameInstance, World, LocalPlayer, and tickable subsystem bases; asset loading. |
| Subsystem editor | `.../UltraControlSubSystemEditor/` | Blueprint factories and asset type actions. |
| Loading screen | `.../LoadingScreen/` | Transition map and async target map loading. |
| WebSocket runtime | `Plugins/UEWebSocketController/Source/UEWebSocketController/` | Runtime/PIE server, JSON protocol, receiver interface, camera serialization, settings, port/log helpers. |
| WebSocket editor | `Plugins/UEWebSocketController/Source/UEWebSocketControllerEditor/` | Editor server and editor-world request dispatch without PIE. |
| Web controller | `UEWebSocketControllerWeb/` | Vue 3 + Vite pages for Editor and Runtime connections. |
| Mesh Color Exclusion | `Plugins/MeshColorExclusion/Source/` and `Shaders/Private/` | Mesh-defined color-grading exclusion mask and RDG post-process passes. |

`UltraControlSystem.uplugin` currently declares five modules (three Runtime, two Editor), not the older three-module summary in its README. `UltraControlSystem.Build.cs` publicly depends on `UEWebSocketController`; the reverse dependency must not be introduced. `UEWebSocketController.uplugin` declares both Runtime and Editor modules. `MeshColorExclusion` is an independent Runtime plugin.

## Settings and content

- `Config/DefaultEngine.ini`: default/editor map `/UltraControlSystem/Maps/GameModeOverView` and `GlobalDefaultGameMode=/Script/UltraControlSystem.UCS_GameModeBase` at this snapshot. Check map overrides when debugging missing Pawn or Controller.
- `Content/Settings/GlobalSettings.json`: global movement, rotation, and zoom speeds; it exists in this checkout. `UUCS_GlobalSettings` reads it when constructed.
- `Plugins/UltraControlSystem/Config/DefaultUltraControlSystem.ini`: property redirects for renamed UCS fields.
- UCS plugin content includes `Maps/GameModeOverView.umap`, input assets in `GameMode/Input`, menu and widget Blueprints, textures, materials, and fonts. Binary assets need UE inspection for actual graphs/values.
- `Saved/Logs/UCS_Core.log` and `Saved/Logs/UEWebSocketController.log` are diagnostic outputs, not source. Avoid copying private tokens or local settings from project/user config into skill documentation.

## Build and verification

The `.uproject` EngineAssociation resolves to UE 5.4.4 at `F:/Program Files/Epic Games/UnrealEngine` on this machine; verify the installed path before using it elsewhere. Build from the project root after the Editor exits cleanly:

```powershell
& 'F:\Program Files\Epic Games\UnrealEngine\Engine\Build\BatchFiles\Build.bat' UCS_CoreEditor Win64 Development '-Project=F:\UnrealProject\UCS_Core\UCS_Core.uproject' -WaitMutex -NoHotReloadFromIDE
```

The Editor may hold plugin DLLs or have Live Coding active, blocking an external link. For web changes:

```powershell
npm run build
```

Run that in `F:/UnrealProject/UCS_Core/UEWebSocketControllerWeb`. Vite dev server is configured for `0.0.0.0:4173`; `/` is the landing page, `/Editor` and `/Runtime` are the tool pages.

## Current source discovery

Use `rg --files F:/UnrealProject/UCS_Core` with `-g` filters for `.h`, `.cpp`, `.cs`, `.ts`, `.vue`, `.usf`, `.ush`, `.ini`, `.json`, `.uplugin`, and `.uproject`. Exclude `Binaries`, `Intermediate`, `Saved`, `node_modules`, and `dist` unless investigating generated output or logs. Search symbols with `rg -n`; do not infer current behavior from this snapshot alone.
