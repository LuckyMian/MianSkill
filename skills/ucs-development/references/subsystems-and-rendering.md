# Subsystems, loading, editor extensions, and rendering

## Blueprint subclassable subsystem framework

`Plugins/UltraControlSystem/Source/UltraControlSubSystem` is separate from the UCS camera/message hub. `UCSS_Activation.h` supplies active state and activation hooks; `UCSS_TickableSubsystem.h` supplies tick enable/pause behavior.

`Public/UCSS_{Engine,GameInstance,World,LocalPlayer}Subsystem.h` define base classes with Blueprint lifecycle events. World subsystem supports Game and PIE worlds. GameInstance and LocalPlayer variants bind world lifecycle delegates; inspect matching cleanup when modifying their lifetimes. `Public/UCSS_Tickable{GameInstance,World,LocalPlayer}Subsystem.h` add `FTickableGameObject` behavior with activation and initialization checks. Their paired `Private/` files implement the lifecycle and tick forwarding.

`UUCSS_PluginProxy` loads subsystem Blueprint assets during engine-subsystem initialization through `FUCSS_SubsystemAssetFunctions`. In this snapshot `FindAllPluginsDirectory` collects candidate plugin names but adds only `/Game/` to the path set used for loading. Check that implementation before assuming Blueprint subsystem assets inside plugin mounts are discovered.

`UltraControlSubSystemEditor` provides `UUCSS_SubsystemFactory` and `FUCSS_AssetTypeActions_SubsystemTemplate` for creating/registering Blueprint subclasses in the editor's Subsystems asset menu. Module startup registers actions and shutdown unregisters them. Edit the paired Runtime and Editor module rules/descriptors if adding a new subsystem type.

## Loading screen

`LoadingScreen/Public/LoadingScreenSubsystem.h` and `Private/LoadingScreenSubsystem.cpp` implement `ULoadingScreenSubsystem`, a GameInstance subsystem. `K2_OpenLevelWithLoadScreen` takes target map, transition map, and `ULoadScreenUserWidget` class; it opens the transition map, waits for it, creates the widget, asynchronously loads the target package, opens it, then removes the widget. `LoadScreenUserWidget` polls `GetLoadPercent` from `NativeTick` and calls the Blueprint event `OnReceiveLoadPercent`. `LoadingSetting` holds soft references to transition map and widget class. Preserve the property redirects in `Config/DefaultUltraControlSystem.ini` when renaming fields.

## UCS editor module

`UltraControlSystemEditor/Private/UltraControlSystemEditor.cpp` registers `UUCS_Config` in Project Settings > Plugins > UCS and a Details customization for `AUCS_ActorBase`. `UCS_CameraDetails.cpp` currently moves the UCS category to the top. Project settings live in `Public/UCS_Config.h`. When adding Editor-only behavior, keep it out of Runtime modules unless guarded and supported by their Build.cs.

## MeshColorExclusion

`Plugins/MeshColorExclusion` is an independent Runtime rendering plugin. `MeshColorExclusionModule.h` maps `/MeshColorExclusionShaders` to its `Shaders` directory during `PostConfigInit`. `AMeshColorExclusionRegion` exposes color grading, intensity, mask expand/feather, and a set of exclusion Actors. It gathers static mesh LOD0 RHI buffers and transfers proxy state to the render thread. `FMeshColorExclusionViewExtension::PrePostProcessPass_RenderThread` builds the RDG mask, optional dilation/erosion, blur, and color-grading passes. Four `.usf` files implement mask generation, dilation, blur, and grading; see [source-inventory.md](source-inventory.md). Rendering changes require attention to game/render thread ownership and UE renderer version compatibility; this module includes Renderer private/internal headers in its Build.cs.
