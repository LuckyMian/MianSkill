# API 来源与版本核对

## 先区分两套 API

- **WoW UI API** 在游戏进程内由 AddOn Lua 调用，涵盖全局函数、`C_*` 命名空间、事件、Widget、ScriptObject、FrameXML、XML schema 和 CVars。
- **Battle.net Web API** 通过 HTTPS 和 OAuth 在站外调用，提供游戏静态数据、角色资料等。它不能从普通 WoW AddOn 中直接调用。

## UI API 的证据顺序

1. **目标客户端生成文档**：导出的 `Interface/AddOns/Blizzard_APIDocumentationGenerated/`。这里包含系统、函数、事件、枚举、结构以及新版本的 restricted/secret 标记。
2. **目标客户端 Blizzard UI 源码**：FrameXML、SharedXML、`Blizzard_*` AddOns。它说明官方 UI 实际如何请求数据、监听事件和处理返回值。
3. **Warcraft Wiki**：便于按名字检索签名、限制、游戏类型和 patch history，也覆盖生成文档没有记录的 systemless API。
4. **社区镜像与资料**：仅作为检索辅助，必须确认分支和 build。

可在登录或角色选择界面的真实控制台运行 `ExportInterfaceFiles code`，导出后查看 WoW 安装目录下的 `BlizzardInterfaceCode`。社区维护的 [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) 提供 `live`、PTR/Beta 及其他分支镜像；分支名不能代替 build 核对。

## Warcraft Wiki 路由

- 总入口：[World of Warcraft API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- 全局函数字母表：[Global functions](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API/Alphabetic)
- 命名空间：[API namespaces](https://warcraft.wiki.gg/wiki/Category:API_namespaces)
- API 系统：[API systems](https://warcraft.wiki.gg/wiki/Category:API_systems)
- API 类型：[API types](https://warcraft.wiki.gg/wiki/API_types)
- Widget 方法：[Widget methods](https://warcraft.wiki.gg/wiki/Category:Widget_methods)
- 补丁变更：[API change summaries](https://warcraft.wiki.gg/wiki/API_change_summaries)
- TOC：[TOC format](https://warcraft.wiki.gg/wiki/TOC_format)
- 加载时序：[AddOn loading process](https://warcraft.wiki.gg/wiki/AddOn_loading_process)
- SavedVariables：[Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions)
- 安全执行与 taint：[Secure Execution and Tainting](https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting)
- 受限函数：[API functions/restricted](https://warcraft.wiki.gg/wiki/Category:API_functions/restricted)
- Secret values：[Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values)
- 导出官方 UI 源码：[Viewing Blizzard's interface code](https://warcraft.wiki.gg/wiki/Viewing_Blizzard%27s_interface_code)

Wiki API 页面通常列出 Game Types、签名、参数、返回值、Details、Restrictions 与 Patch changes。不要只读取页面开头的签名。

## 每次使用 API 的最小核对清单

- 精确拼写与命名空间是否存在于目标分支？
- 参数和返回值是多个返回值还是结构体？哪些字段可空？
- 数据是否需要先请求、等待事件或依赖缓存？
- 页面是否标记 deprecated、protected、hwevent、nocombat、restricted 或 secret？
- Retail 与目标 Classic 分支是否行为不同？
- 对应补丁是否重命名、移除或替换了该 API？
- Blizzard 自己的 UI 如何调用它？

## Interface 值

不要长期硬编码“最新” Interface 数字到技能说明。首选目标客户端：

```lua
/dump (select(4, GetBuildInfo()))
```

若用户无法运行客户端，再从当期 TOC 文档或与目标 build 一致的 Blizzard UI 源码获取，并在交付说明中记录来源。

