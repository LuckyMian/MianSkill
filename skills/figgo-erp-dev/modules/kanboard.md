# 模块：Kanboard 项目机器人（已封存）

> **状态：封存（sealed）。** 2026-09 起由 `codex/ruoyi-erp-cutover` 分支切到 RuoYi ERP，
> 项目/任务机器人功能全部下线，代码保留作迁移参考。**默认不读、不改、不复活。**
> 只在两种情况下打开本模块：① 用户明确要求恢复某个项目机器人功能；② 需要读懂遗留代码
> 或被封存的表结构。归属技能：`figgo-erp-dev`。

## 封存的具体形态

| 位置 | 现状 |
| --- | --- |
| `StreamBridge.py` | `KANBOARD_PROJECT_FEATURES_ENABLED = False`，项目意图被过滤；`KANBOARD_PROJECT_INTENT_KEYS` 列出被封存的意图 |
| `Plugin.php` | 项目查询、任务事件监听、入职、定时任务等命令与监听器**已注释** |
| 线上仍开着的 | 报销、财务、发票/OCR、`dingtalk:run`、`registration-status`、`staff-map`、`attendance-status` |
| 数据库 | `data\db.sqlite` 里 `dingtalk_onboarding_sessions` 等表还在，但不再有新数据 |

判据：`php cli list` 里没有 `dingtalk:project-*` 之外的查询命令、`dingtalk:pm-task-assign`
已注销（RuoYi 配置里 `kanboard.assign-notify` 仍为 `true`，属于**已知切换风险**，见
`modules/ruoyi.md`）。

## 遗留能力清单（仅作参考）

| 能力 | 入口命令 | 说明 |
| --- | --- | --- |
| 全量项目总览 | `dingtalk:portfolio` | 跨所有活跃项目的报表 |
| 单人任务 | `dingtalk:user-status <name>` | 一个人的项目与指派任务；也响应 `查询 <名字>`、正文含「项目情况」 |
| 项目情况 | `dingtalk:project-status <name>` | 单项目活跃任务 + 可点链接 |
| 任务详情 | `dingtalk:task-status <id>` | 字段、子任务、附件链接 |
| 账号绑定 | `dingtalk:bind-user <name>` | `绑定账号`，要求姓名匹配 |
| 新人入职 | `dingtalk:onboarding-start` / `-complete <job>` | `#新人入职` → 选 美术/模型/项目经理/程序 → 建 Kanboard 账号并回一次性密码 |
| 任务事件通知 | `task.create` / `task.assignee_change` / `task.move.column` / `task.close` / `task.open` | `EventListener` → `MessageBuilder` → 队列 |
| 每日到期汇总 | `enqueueDailyDigest`（`reminder_time` 之后） | 24 小时内到期任务，每 10 行一条，每天最多一次 |
| 当日汇总 + AI 分析 | `dingtalk:daily-summary [--refresh]`、`dingtalk:daily-print [day]` | 管理员私聊 @机器人 时附带；打印 1 页 A4 |
| 定时任务 | `定时任务`（仅机器人持有者） | 调度模块 |

## 路由优先级（历史形态）

老链路是「首个匹配即返回」的优先级链，不是 switch：
`#新人入职` > 私聊工种词 > 注册门禁 > 定时任务 > 报销向导 > 财务向导 > 附件 OCR > 意图目录。
其中 `查询\s*(...)` 这种泛匹配会吃掉 `查询项目`，只有顺序能把它们分开——这段经验在
`modules/dingtalk-bot.md` 的现役路由里仍然适用。

## 完成 / 逾期口径（`Service\TaskScope`）

**这台机器上「完成」不是 `is_active=0`。** Kanboard 只在「关闭任务」动作里置
`is_active=0`，而这里没人用关闭，做完只是把任务拖到「完成」列。2026-09-16 时全库 11 个任务
全是 `is_active=1`，按 `is_active` 统计的报表把完成的任务算成逾期，用户投诉后才统一口径。

所有计数查询必须走 `Service\TaskScope`：

| 方法 | 含义 |
| --- | --- |
| `openCondition($pdo,'t')` | `t.is_active=1 AND t.column_id NOT IN (完成列)` |
| `doneCondition($pdo,'t')` | `(t.is_active=0 OR t.column_id IN (完成列))` |
| `finishedAt($pdo,'t')` | 完成时间：`is_active=0` 用 `date_completed`，否则用进列的 `date_moved` |
| `isDone($task,$ids)` | 非 SQL 场合的单行判断 |

完成列按列名匹配（大小写不敏感），名单在 `TaskScope::DONE_TITLES`：完成 / 已完成 / 已结束 /
结束 / 关闭 / 已关闭 / 归档 / 交付 / done / finished / closed / complete / completed / archive。
「今日新增」按 `date_creation`，「今日完成」按 `finishedAt` 落在今天。逾期边界保持 Kanboard
原口径：`date_due <= time()`，**当天到期当天就算逾期**。

## 复活前必须同时改的四处

只在用户明确要求恢复项目功能时执行，顺序不要反：

1. RuoYi 侧确认：项目数据路径已不在 Kanboard，或已由 RuoYi 接管（否则两套真相）。
2. `KANBOARD_PROJECT_FEATURES_ENABLED` 与 `KANBOARD_PROJECT_INTENT_KEYS` 放开。
3. `Plugin.php` 命令注册与任务事件监听器取消注释。
4. `StreamBridge.py` 路由分支、帮助菜单（`build_help`）、RuoYi 项目通知器或替代事件源。

复活后：

- 报表一律用 `TaskScope`，不要退回裸 `is_active`。
- 任务指派通知要么修好 `dingtalk:pm-task-assign`，要么把 RuoYi 的
  `kanboard.assign-notify` 关掉——现在它是开着的但 CLI 已注销。
- 回归：`D:\Apache24\setup-packages\` 下的项目类脚本（`ruoyi-project-assign-verify.py`、
  `daily-summary-bridge-test.py`）能跑再算完成。

## 不要做

- 不要因为 `data\db.sqlite` 里还有 `dingtalk_onboarding_sessions` 之类的表就以为功能还活着。
- 不要为了「让报表好看」把完成列改名或改 `DONE_TITLES`，那会同时改变历史统计。
- 不要在没验证 RuoYi 数据路径前就放开 `KANBOARD_PROJECT_FEATURES_ENABLED`。
