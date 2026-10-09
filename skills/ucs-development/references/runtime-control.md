# UCS runtime control and UMG

Source base: `F:/UnrealProject/UCS_Core/Plugins/UltraControlSystem/Source/UltraControlSystem`. Read the current files before changing behavior.

## Message contract

`Support/UCS_LogicStruct.h` defines `FUCS_LogicStruct` with two `TMap<FString,FString>` fields. `InfoMap` defaults to `CnName` and `EnName`; `LogicMap` defaults to `Key`. The actual dispatch key is `LogicMap["Key"]`. Menu/widget metadata can add other entries. `Public/UCS_Interface.h` declares BlueprintNativeEvents for movement, rotation, zoom, camera focus, logic messages, and widget display; its `ShowPage` is a plain virtual method. Use `IUCS_Interface::Execute_*` when Blueprint overrides must run.

`Public/UCS_GameInstanceSubsystem.h` and `Private/UCS_GameInstanceSubsystem.cpp` implement the message hub:

1. `CallMessanger` suppresses a repeated `Key` unless `LogicMap["Retrigger"]` opts out. It saves the logic then calls `FocusCamera`, `CallInterfaceMessanger`, and `ShowWidgetByMessanger` in that order.
2. `FocusCamera` matches registered `AUCS_Camera` Actor Tags and focuses through `AUCS_PawnBase`; it returns safely when no UCS Pawn exists.
3. `CallInterfaceMessanger` broadcasts `LogicInterface` to Actors implementing `IUCS_Interface`.
4. `ShowWidgetByMessanger` matches registered `AUCS_Widget` tags and calls `ShowSelf`.
5. `CallMasterMenuByMessanger` is a separate method. `CallMessanger` currently does **not** invoke it. `UUCS_ButtonBase::HandleOnPressed` calls both. The WebSocket `camera_info` path invokes only `CallMessanger`.

`UUCS_GameInstanceSubsystem` also implements `IWebSocketJsonReceiver`. It only handles `command: "camera_info"`, converts the nested `Info` object to `FUCS_LogicStruct`, requires a nonempty `LogicMap.Key`, and forwards it to `CallMessanger`. The WebSocket plugin dispatches to GameInstance-owned receiver objects as well as Actor receivers.

## Camera and input

`Actor/UCS_Camera.{h,cpp}`: `AUCS_Camera` owns SceneRoot, SpringArm, Camera, motion flags, `TargetLocation`, clamp ranges, `ECameraType`, and `Info`. `PostEditChangeProperty` reacts to `TargetLocation` and updates spring-arm direction/length. `BeginPlay` adds `Info.LogicMap.Key` as a Tag and registers the Actor in the GameInstance subsystem. `CallInEditor` methods are `SetCameraActive` and `TEST`.

`Public/UCS_PawnBase.h` and `Private/UCS_PawnBase.cpp`: `AUCS_PawnBase` implements input/focus interfaces, caches controller and global settings in `BeginPlay`, registers itself as `UCS_Pawn`, and interpolates location, rotation, and arm length in `Tick`. Focusing copies flags, clamp values, camera type, transform target, and arm length from `AUCS_Camera`. Flash mode asks `AUCS_PlayerController` for the black-screen transition.

`Public/UCS_PlayerController.h` and `Private/UCS_PlayerController.cpp`: loads plugin Enhanced Input assets, adds mapping context, forwards actions to the Pawn, creates the configured `UUCS_MenuBase` at runtime, and owns the Slate `SBlackScreen` effect. `UCS_GameModeBase.cpp` selects UCS Pawn and Controller defaults. `DefaultEngine.ini` currently selects `UCS_GameModeBase` globally, but a map may override it.

When changing this path, verify pointer assumptions in current code. In this snapshot `AUCS_Camera::TEST`, `AUCS_PawnBase::BeginPlay`, and `UUCS_GlobalSettings` access dependent objects without full validity checks. `AUCS_PlayerController::SetupInputComponent` tests `RotationAction` before binding `ZoomAction`; inspect that condition when touching input.

## Widget and settings path

- `Actor/UCS_Widget.{h,cpp}`: screen-space Widget Actor, configured `WidgetClass`, tag groups, `Info`, registration in `BeginPlay`, `ShowSelf`, and scale/pivot helper.
- `Slate/UCS_ButtonBase.{h,cpp}`: `Logic`, `OnPressed` binding, `CallMessanger` plus explicit master-menu dispatch. Editor `SetName` updates widget labels.
- `Slate/UCS_MenuBase.{h,cpp}`: stores `Logic`, restarts bound `PageAnimation`, with fallback `StartPageAnimation` Blueprint event.
- `Slate/UCS_WidgetSwitcher.{h,cpp}`: finds menu children using exact case-sensitive `LogicMap.Key` and optionally calls `ShowPage`.
- `Slate/UCS_WidgetBase.{h,cpp}`: generic UMG base and `InitWidget` BlueprintNativeEvent. Preserve existing public `bCanChili` spelling if changing its API.
- `Slate/SBlackScreen.{h,cpp}`: Slate transition effect used by PlayerController.
- `Support/UCS_Settings.{h,cpp}`: speed settings object loaded from project `Content/Settings/GlobalSettings.json`.
- `Public/UCS_FunctionLibrary.h` and `Private/UCS_FunctionLibrary.cpp`: Blueprint accessors, JSON loading, configured menu class loading, optional debug logging, and comma-separated key parsing/matching.

Configuration keys for UCS menu behavior are read from `/Script/UltraControlSystemEditor.UCS_Config` in `GGameIni`; `UltraControlSystemEditor/Public/UCS_Config.h` declares `bIsCreateWidget`, `WidgetPath`, and `bIsDebugPrint`.
