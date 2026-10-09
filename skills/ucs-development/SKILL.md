---
name: ucs-development
description: Develop, debug, review, or extend the UCS_Core Unreal Engine project, including UltraControlSystem, its subsystem and loading modules, UEWebSocketController, MeshColorExclusion, and the companion Vue web controller. Use for requests about this UCS codebase; do not apply to unrelated Unreal projects.
---

# UCS development

Work against the live project at `F:/UnrealProject/UCS_Core` (project file `UCS_Core.uproject`). If the project moves, locate that `.uproject` and rebase all paths below. The references are a source map captured on 2026-09-25, not a replacement for reading the current implementation.

## Route the task

- Read [project-map.md](references/project-map.md) for module ownership, dependencies, assets, and build entry points.
- For cameras, Pawn, input, `FUCS_LogicStruct`, `CallMessanger`, or UMG, read [runtime-control.md](references/runtime-control.md).
- For Blueprint subclassable subsystems, loading screens, editor settings/factories, or rendering, read [subsystems-and-rendering.md](references/subsystems-and-rendering.md).
- For WebSocket, JSON protocol, Editor/Runtime connections, logging, ports, or the Vue pages, read [websocket-and-web.md](references/websocket-and-web.md).
- Use [source-inventory.md](references/source-inventory.md) to find every text source group; refresh the inventory with `rg --files` before editing. Inspect the relevant `.h`, `.cpp`, `Build.cs`, `.uplugin`, web component, and config rather than trusting the snapshot.

## Project-specific working rules

- Distinguish `UUCS_GameInstanceSubsystem` (camera/message controller) from `UUCSS_*` (Blueprint subclassable subsystem framework). Their names are similar but their jobs differ.
- Preserve the dependency direction: `UltraControlSystem` depends on `UEWebSocketController`; the WebSocket plugin locates `AUCS_Camera` by reflected class path to avoid a module cycle.
- Changes to reflected UE types, interfaces, or module dependencies need UHT and a full Editor build. If an Editor DLL is loaded, close the Editor gracefully before replacing it; never discard unsaved assets just to build. For Vue changes, run `npm run build` in `UEWebSocketControllerWeb`.
- Binary `.uasset` and `.umap` files are part of the project but cannot be learned or edited as text. Inspect them in UE when a task depends on Blueprint graphs, placed actors, widget animations, or map settings.
- Existing README files can lag behind code. Verify behavior in source and current config, especially message dispatch and which modules are present.
