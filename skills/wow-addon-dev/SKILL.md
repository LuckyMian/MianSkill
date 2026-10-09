---
name: wow-addon-dev
description: Develop, migrate, review, and debug World of Warcraft in-game AddOns using Lua, XML, TOC metadata, Blizzard UI code, and the version-matched WoW UI API. Use for Retail or Classic AddOn projects; do not use the Battle.net web API as a substitute for the in-game API.
---

# WoW AddOn Development

为目标客户端交付可加载、可验证、符合 WoW 安全模型的插件代码。所有技术结论都要绑定到客户端分支与版本；不要凭记忆编造 API、事件、参数、返回值或 TOC Interface 值。

## 开始前

1. 从用户要求、现有 `.toc`、项目说明或客户端信息确定游戏分支：Retail/Mainline、PTR/Beta、Classic Era、或具体 Classic 资料片。
2. 确定目标 build 与 Interface。优先使用用户客户端执行 `/dump (select(4, GetBuildInfo()))` 的结果；否则查询该分支当前资料并明确记录依据。目标分支会影响实现时，不能默认 Retail。
3. 阅读现有项目的 `AGENTS.md`、`.toc`、入口文件、依赖与许可证，保留用户已有结构和未相关改动。
4. 先判断需求使用哪类接口：
   - 游戏内 AddOn：Lua/UI API、事件、Widget、FrameXML、SavedVariables。
   - 站外工具或网站：Battle.net OAuth 与 WoW Web API。游戏内插件不能发起任意 HTTP 请求，也不能把 Web API 当成游戏内 API。

需要查证 API、版本或来源时，阅读 [references/api-sources.md](references/api-sources.md)。涉及 Battle.net Web API 时，另读 [references/battlenet-web-api.md](references/battlenet-web-api.md)。

## 查证规则

- 对每个新使用或修改的 WoW API，核对精确名称、命名空间、参数、返回值、事件时序、游戏分支及限制标记。
- 证据优先级：与目标客户端匹配的 Blizzard 生成文档/导出的 UI 源码；对应分支的 UI 源码；Warcraft Wiki 的具体 API 页面和补丁变更；其他社区资料。
- Wiki 适合检索与解释，客户端随附的 `Blizzard_APIDocumentationGenerated` 和实际 FrameXML 行为更接近目标 build。二者冲突时说明 build 差异，不要悄悄选一个。
- 修改旧插件前查看从其支持版本到目标版本的 API change summaries，重点搜索 removed、renamed、deprecated、protected、restricted、secret 与返回结构变化。
- 如果无法验证某个接口，明确标成“未验证”，给出可在目标客户端执行的最小探针或需要用户提供的 build；不要生成看似合理的虚构调用。

## 实现约束

- 插件目录名与主 `.toc` 文件名匹配；`.toc` 文件顺序就是加载顺序。只声明实际需要的 SavedVariables、依赖和客户端条件。
- 默认使用 `local addonName, ns = ...` 共享模块状态，控制全局变量数量；SavedVariables 是必须存在于全局环境的例外。
- 采用事件驱动。避免无条件高频 `OnUpdate`；确有逐帧需求时节流、减少分配并在不需要时注销。
- 在本插件对应的 `ADDON_LOADED` 后初始化和迁移 SavedVariables。迁移必须幂等、保留用户数据，并处理缺失字段与旧 schema。
- 许多数据 API 依赖缓存或异步事件。首次返回 `nil` 或不完整数据时，不要忙等；触发允许的加载请求并监听对应事件后刷新。
- 修改 Blizzard UI 优先使用公开 API、Mixin、事件与 `hooksecurefunc`/`HookScript`。不要直接覆盖安全函数，也不要复制整段 FrameXML 来做小改动。
- 把 combat lockdown、hardware event、protected/restricted API、taint 和 secret values 当作设计约束，绝不尝试绕过。需要脱战执行的 UI 改动应排队到 `PLAYER_REGEN_ENABLED` 后重新校验。
- secret value 可能无法比较、拼接、索引、遍历、序列化或记录。先查 API 的 secret 标记和允许的 predicate/包装方式；失败时降级 UI，而不是泄露或推断受限信息。
- 除非项目已有明确依赖，不擅自引入 Ace3 等大型库。小插件优先原生 API；大型项目按维护成本选择库。
- 面向多客户端时，把差异收敛在能力检测或薄兼容层中。不要用版本号散落地控制业务逻辑，也不要把已删除 API 的 fallback 暴露给不支持它的客户端。

需要搭建结构、处理事件、SavedVariables、兼容层或性能问题时，阅读 [references/engineering-playbook.md](references/engineering-playbook.md)。

## 验证与交付

1. 检查 `.toc` 路径、大小写、加载顺序、依赖、Interface 与 SavedVariables 声明。
2. 做 Lua 静态检查，但不要把桌面 Lua 解释器通过当作 WoW 运行时兼容证明。
3. 在目标客户端开启 Lua 错误并测试全新登录、`/reload`、登出保存、缺失缓存、战斗进入/退出、区域或实例切换，以及用户指定的边界条件。
4. 使用 `/fstack`、事件追踪、`/dump` 和精确的临时日志定位问题；移除高噪声调试输出和任何可能触碰 secret value 的日志。
5. 交付时列出改动文件、目标客户端/build、实测内容、未能在客户端验证的事项，以及已知的分支限制。若只是生成骨架，要明确它仍需游戏内验证。

