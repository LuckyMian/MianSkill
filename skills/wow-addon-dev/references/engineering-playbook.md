# AddOn 工程手册

## 最小结构

```text
MyAddon/
├── MyAddon.toc
├── Core.lua
└── Modules/...
```

目录与 `.toc` 主文件名必须一致。小型插件通常不需要 XML；需要声明式模板、继承或复杂布局时再使用 XML。

入口常用形态：

```lua
local addonName, ns = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, loadedName)
    if event == "ADDON_LOADED" and loadedName == addonName then
        -- 此时读取并迁移本插件 SavedVariables。
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
```

这只是时序示例；实际生成前仍需核对目标 build 的 API。

## 模块与状态

- 每个文件用局部变量保存热路径函数与模块状态，通过 `ns` 暴露真正跨文件的接口。
- SavedVariables 使用单一根表和 `schemaVersion`，升级时逐级迁移。默认值合并不能覆盖用户已有选择。
- 将数据层、事件协调、视图和兼容代码分开到足以降低耦合的程度；不要为了形式拆出大量空模块。

## 事件与异步数据

- 只注册当前状态所需的事件，销毁或停用功能时注销。
- 同一刷新由多个事件触发时做合并/去抖；不要在事件风暴中重建完整 UI。
- 物品、法术、玩家资料等数据可能尚未缓存。对 `nil` 做正常分支，等待相应结果事件，并确认回调仍属于当前请求。
- `OnUpdate` 只用于动画、计时或 API 没有事件的情形；累计 `elapsed` 节流，并在 UI 隐藏时停止。

## UI 与安全执行

- 显式设置父级、锚点、尺寸/布局与 frame strata；避免未命名全局 Frame。
- 使用 `HookScript` 或 `hooksecurefunc` 做观察型扩展。覆盖全局函数、替换受保护脚本或写入 Blizzard 私有状态会放大 taint 风险。
- 战斗中不要创建或重配受保护按钮、属性或状态。把意图记录下来，在 `PLAYER_REGEN_ENABLED` 后重新检查对象与条件再应用。
- 不对 secret value 做比较、数学运算、格式化、表键、序列化或日志记录，除非目标 build 文档明确允许对应操作。

## 多客户端兼容

- 优先能力检测，例如检查命名空间/函数是否存在；但对语义不同的同名 API，使用清晰的分支适配器。
- 把兼容逻辑放在少量文件中，为业务层提供稳定的内部接口。
- `.toc` 可使用多个 Interface 值、条件指令或客户端专用后缀；选择前核对当前 TOC 规范，不复制旧项目配置。

## 调试与验收

- 开启 `scriptErrors`，首次登录与 `/reload` 都测试。
- 用 `/fstack` 检查鼠标下 Frame；用事件追踪验证事件名、顺序和参数；用 `/dump` 做只读探针。
- 测试 SavedVariables 的首次创建、旧版本迁移、重载和登出再登录。
- 测试进入/离开战斗、UI scale、不同分辨率、无目标/数据未缓存、区域切换及加载依赖缺失。
- 性能问题先测量：事件频率、`OnUpdate`、表分配、字符串格式化、全量扫描和 UI 重建是常见热点。

