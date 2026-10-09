# WebSocket bridge and Vue controller

Source roots: `F:/UnrealProject/UCS_Core/Plugins/UEWebSocketController/Source` and `F:/UnrealProject/UCS_Core/UEWebSocketControllerWeb/src`. Verify current code when changing a message shape or port.

## Server ownership and dependency

`UEWebSocketController/Private/WebSocketControllerSubsystem.cpp` is a `UGameInstanceSubsystem` server for each Runtime or PIE instance. `UEWebSocketControllerEditor/Private/WebSocketControllerEditorSubsystem.cpp` is a `UEditorSubsystem` server available without PIE. Both tick `IWebSocketServer`, validate JSON, send responses, and restrict incoming IP/origin to loopback/private LAN. The Runtime server dispatches unknown commands to Actor receivers and `IWebSocketJsonReceiver` objects owned by its GameInstance. The Editor server dispatches to Actor receivers in the Editor world.

Default settings in `WebSocketControllerSettings.cpp`: bind `0.0.0.0`, Runtime base port `11378`, Editor base port `21378`, 100 port attempts, auto start, max incoming message size 1 MiB. `WebSocketControllerPortUtils.cpp` probes TCP binds; a system-wide lock serializes port allocation. Actual ports may advance when occupied. `WebSocketControllerFileLog.cpp` appends port, connection, receive, and send events to `Saved/Logs/UEWebSocketController.log` with a cross-process file lock. Use the actual endpoint from logs or `GetBoundEndpoint`, not just a default port.

`UltraControlSystem` depends on the WebSocket module. To avoid a cycle, `WebSocketControlFunctionLibrary.cpp` resolves `/Script/UltraControlSystem.UCS_Camera` by reflected class path and iterates matching Actors; it does not link directly to `AUCS_Camera`. Preserve this direction when adding camera-specific behavior.

## Protocol

`WebSocketJsonProtocol.cpp` validates UTF-8 and requires a top-level JSON object. On connection each server sends:

```json
{
  "type": "instance_info",
  "projectName": "UCS_Core",
  "projectPath": "F:/UnrealProject/UCS_Core/UCS_Core.uproject",
  "computerName": "...",
  "processId": 12345,
  "mode": "editor",
  "port": 21378,
  "worldName": "GameModeOverView",
  "instanceId": "..."
}
```

`mode` is `editor` or `runtime`. The process ID and instance ID distinguish simultaneous instances. Invalid input receives `type: "error"`; ordinary dispatched JSON receives `type: "ack"` with `sequence`, `ok`, and `receiverCount`.

Built-in `{ "command": "get_all_ucs_cameras" }` returns `type: "ucs_camera_list"`, `cameraCount`, and `cameras`. Each camera carries `name`, object `path`, `class`, `variables` (all reflected UPROPERTY fields, including inherited ones), `MotionControl`, and `Transform` (Location, Rotation, Scale). See `WebSocketControlFunctionLibrary.cpp` for serialization. Non-reflected plain C++ fields are not included.

The Runtime web page's camera button sends `{ "command": "camera_info", "camera": {...}, "Info": {...} }`. `UUCS_GameInstanceSubsystem::OnWebSocketJsonReceived_Implementation` validates/converts `Info` and invokes `CallMessanger` if `Info.LogicMap.Key` is nonempty. The Editor server currently has no equivalent GameInstance message hub; its camera list is for viewing/editing tool UI.

`WebSocketJsonReceiver.h` is the BlueprintNativeEvent receiver interface. When extending server commands, update C++ dispatch, Vue handling, and README/protocol docs together. Do not treat `127.0.0.1:30010` (Unreal Remote Control HTTP API) as this plugin's WebSocket endpoint.

## Vue pages

`main.ts` selects `/` → `HomePage.vue`, `/Runtime` → `App.vue`, `/Editor` → `EditorPage.vue`. Vite listens on `0.0.0.0:4173`. The pages default to the browser hostname plus the mode's base port, and both allow editing the WebSocket URL when disconnected. `InstanceIdentity.vue` and `instanceIdentity.ts` parse/show the server's real project path, mode, PID, port, world, and instance ID; identity is cleared on disconnect/reconnect.

`App.vue` is the Runtime controller: JSON editor, locally saved named messages, communication log, camera list, dynamically created camera buttons, and `camera_info` send. `EditorPage.vue` is the Editor controller: camera query, compact camera selection, Info/MotionControl/Transform details, UE-style vector/rotator copy text, a JSON command modal, and logs. New reusable web behaviors should avoid inconsistent copies across these pages.
