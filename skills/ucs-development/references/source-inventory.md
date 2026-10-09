# Complete text-source inventory

Snapshot: 2026-09-25. Project root: `F:/UnrealProject/UCS_Core`. This lists every current source group in the project; `Foo.{h,cpp}` means both files. `Public/Foo.h + Private/Foo.cpp` means the corresponding files in those folders. Re-run `rg --files` for additions or moves before acting. Generated files under `Intermediate/`, binaries, `node_modules/`, `dist/`, and `Saved/` are not maintained source.

## Project shell

- `Source/UCS_Core/UCS_Core.{h,cpp}`, `Source/UCS_Core/UCS_Core.Build.cs`
- `Source/UCS_Core.Target.cs`, `Source/UCS_CoreEditor.Target.cs`
- `UCS_Core.uproject`, `Config/Default{Engine,Editor,Game,Input}.ini`
- `Content/Settings/GlobalSettings.json`

## UltraControlSystem plugin

Base: `Plugins/UltraControlSystem/Source/`. Descriptor: `Plugins/UltraControlSystem/UltraControlSystem.uplugin`. Config: `Plugins/UltraControlSystem/Config/DefaultUltraControlSystem.ini`.

**UltraControlSystem Runtime module (35 source files):**

- `UltraControlSystem/UltraControlSystem.Build.cs`
- `UltraControlSystem/Public/UltraControlSystem.h` + `Private/UltraControlSystem.cpp`
- `UltraControlSystem/Public/UCS_Interface.h` + `Private/UCS_Interface.cpp`
- `UltraControlSystem/Public/UCS_GameModeBase.h` + `Private/UCS_GameModeBase.cpp`
- `UltraControlSystem/Public/UCS_GameInstanceSubsystem.h` + `Private/UCS_GameInstanceSubsystem.cpp`
- `UltraControlSystem/Public/UCS_FunctionLibrary.h` + `Private/UCS_FunctionLibrary.cpp`
- `UltraControlSystem/Public/UCS_PawnBase.h` + `Private/UCS_PawnBase.cpp`
- `UltraControlSystem/Public/UCS_PlayerController.h` + `Private/UCS_PlayerController.cpp`
- `UltraControlSystem/Actor/UCS_ActorBase.{h,cpp}`
- `UltraControlSystem/Actor/UCS_Camera.{h,cpp}`
- `UltraControlSystem/Actor/UCS_Widget.{h,cpp}`
- `UltraControlSystem/Slate/UCS_ButtonBase.{h,cpp}`
- `UltraControlSystem/Slate/UCS_MenuBase.{h,cpp}`
- `UltraControlSystem/Slate/UCS_WidgetBase.{h,cpp}`
- `UltraControlSystem/Slate/UCS_WidgetSwitcher.{h,cpp}`
- `UltraControlSystem/Slate/SBlackScreen.{h,cpp}`
- `UltraControlSystem/Support/UCS_LogicStruct.{h,cpp}`
- `UltraControlSystem/Support/UCS_Settings.{h,cpp}`

**LoadingScreen Runtime module (9 files):** `LoadingScreen/LoadingScreen.Build.cs`; `Public/LoadingScreen.h + Private/LoadingScreen.cpp`; `Public/LoadingScreenSubsystem.h + Private/LoadingScreenSubsystem.cpp`; `Public/LoadingSetting.h + Private/LoadingSetting.cpp`; `Public/LoadScreenUserWidget.h + Private/LoadScreenUserWidget.cpp`.

**UltraControlSystemEditor module (7 files):** `UltraControlSystemEditor.Build.cs`; `Public/UltraControlSystemEditor.h + Private/UltraControlSystemEditor.cpp`; `Public/UCS_Config.h + Private/UCS_Config.cpp`; `Public/UCS_CameraDetails.h + Private/UCS_CameraDetails.cpp`.

**UltraControlSubSystem Runtime module (25 files):**

- `UltraControlSubSystem.Build.cs`, `UCSS_Activation.h`, `UCSS_TickableSubsystem.h`, `UCSS_SubsystemType.h`, `UCSS_SubsystemTypes.cpp`
- `Public/UltraControlSubSystem.h + Private/UltraControlSubSystem.cpp`
- `Public/UCSS_EngineSubsystem.h + Private/UCSS_EngineSubsystem.cpp`
- `Public/UCSS_GameInstanceSubsystem.h + Private/UCSS_GameInstanceSubsystem.cpp`
- `Public/UCSS_LocalPlayerSubsystem.h + Private/UCSS_LocalPlayerSubsystem.cpp`
- `Public/UCSS_WorldSubsystem.h + Private/UCSS_WorldSubsystem.cpp`
- `Public/UCSS_TickableGameInstanceSubsystem.h + Private/UCSS_TickableGameInstanceSubsystem.cpp`
- `Public/UCSS_TickableLocalPlayerSubsystem.h + Private/UCSS_TickableLocalPlayerSubsystem.cpp`
- `Public/UCSS_TickableWorldSubsystem.h + Private/UCSS_TickableWorldSubsystem.cpp`
- `Public/UCSS_SubsystemAssetFunctions.h + Private/UCSS_SubsystemAssetFunctions.cpp`
- `Public/UCSS_PluginProxy.h + Private/UCSS_PluginProxy.cpp`

**UltraControlSubSystemEditor module (7 files):** `UltraControlSubSystemEditor.Build.cs`; `Public/UltraControlSubSystemEditor.h + Private/UltraControlSubSystemEditor.cpp`; `Public/UCSS_SubsystemFactory.h + Private/UCSS_SubsystemFactory.cpp`; `Public/UCSS_AssetTypeActions_Subsystem.h + Private/UCSS_AssetTypeActions_Subsystem.cpp`.

Plugin binary assets include the overview map, Enhanced Input actions/context, menu and widget Blueprints, materials, textures, and fonts. Inspect asset internals in UE rather than assuming them from filenames.

## UEWebSocketController plugin

Base: `Plugins/UEWebSocketController/Source/`. Descriptor: `Plugins/UEWebSocketController/UEWebSocketController.uplugin`.

**UEWebSocketController Runtime module (18 files):** `UEWebSocketController.Build.cs`; `Public/UEWebSocketController.h + Private/UEWebSocketController.cpp`; `Public/WebSocketJsonReceiver.h + Private/WebSocketJsonReceiver.cpp`; `Public/WebSocketJsonProtocol.h + Private/WebSocketJsonProtocol.cpp`; `Public/WebSocketControllerSubsystem.h + Private/WebSocketControllerSubsystem.cpp`; `Public/WebSocketControllerSettings.h + Private/WebSocketControllerSettings.cpp`; `Public/WebSocketControllerPortUtils.h + Private/WebSocketControllerPortUtils.cpp`; `Public/WebSocketControllerFileLog.h + Private/WebSocketControllerFileLog.cpp`; `Public/WebSocketControlFunctionLibrary.h + Private/WebSocketControlFunctionLibrary.cpp`; `Private/Tests/WebSocketJsonProtocolTests.cpp`.

**UEWebSocketControllerEditor module (5 files):** `UEWebSocketControllerEditor.Build.cs`; `Public/UEWebSocketControllerEditor.h + Private/UEWebSocketControllerEditor.cpp`; `Public/WebSocketControllerEditorSubsystem.h + Private/WebSocketControllerEditorSubsystem.cpp`.

## MeshColorExclusion plugin

Base: `Plugins/MeshColorExclusion/`. Descriptor: `MeshColorExclusion.uplugin`.

- `Source/MeshColorExclusion/MeshColorExclusion.Build.cs`
- `Source/MeshColorExclusion/Public/MeshColorExclusionModule.h + Private/MeshColorExclusionModule.cpp`
- `Source/MeshColorExclusion/Public/MeshColorExclusionRegion.h + Private/MeshColorExclusionRegion.cpp`
- `Source/MeshColorExclusion/Public/MeshColorExclusionViewExtension.h + Private/MeshColorExclusionViewExtension.cpp`
- `Shaders/Private/MCEMaskGen.usf`, `MCEDilate.usf`, `MCEBlur.usf`, `MCEColorGrade.usf`

## Vue/Vite controller

Base: `UEWebSocketControllerWeb/`.

- `src/main.ts`, `src/vite-env.d.ts`, `src/style.css`
- `src/HomePage.vue`, `src/App.vue` (Runtime), `src/EditorPage.vue`
- `src/InstanceIdentity.vue`, `src/instanceIdentity.ts`
- `vite.config.ts`, `package.json`, `package-lock.json`, `tsconfig.json`, `tsconfig.app.json`, `tsconfig.node.json`, `index.html`

## Refresh command

```powershell
rg --files 'F:\UnrealProject\UCS_Core' -g '*.h' -g '*.cpp' -g '*.cs' -g '*.ts' -g '*.vue' -g '*.usf' -g '*.ush' -g '*.ini' -g '*.json' -g '*.uplugin' -g '*.uproject' -g '!**/Intermediate/**' -g '!**/Binaries/**' -g '!**/Saved/**' -g '!**/node_modules/**' -g '!**/dist/**'
```
