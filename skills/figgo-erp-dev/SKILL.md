---
name: figgo-erp-dev
description: "Develop and maintain the Figgo (飞戈) ERP stack on this machine: the DingTalk robot bridge, the reimbursement and finance workflow across Kanboard PHP, SQL Server Finance and RuoYi, invoice OCR, the RuoYi backend and console UI, the Excel/printing pipeline, and the data stores behind them. Load the matching module under modules/ before changing anything. Kanboard project-management bot features are sealed, not live."
metadata:
  short-description: 飞戈 ERP 全栈：钉钉机器人 / 报销财务 / RuoYi / 数据库 / 打印
---

# Figgo ERP dev（飞戈 ERP 全栈）

这台机器上跑着一套 Figgo（飞戈数字）ERP：Kanboard 插件里的钉钉机器人、SQL Server 上的
财务与报销数据、RuoYi 管理后台、发票 OCR 和桌面打印。本技能是这套部署的**唯一入口**，
内容按领域拆成 `modules/` 下的子技能模块——**先读模块，再动代码**。

权威来源（永远优先于本技能）：

- `D:\Apache24\htdocs\kanboard\plugins\DingTalkNotifier\README.md` — 当前运行时范围、命令、数据归属。
- `D:\php\php.exe cli list` — 线上真实注册的命令。
- 两者与本技能冲突时，以线上行为和 README 为准；模块文档是地图，不是合同。

## 部署地图

| 角色 | 位置 | 运行方式 |
| --- | --- | --- |
| Web 服务 | `D:\Apache24`，Kanboard 在 `D:\Apache24\htdocs\kanboard`，端口 801 | Apache |
| PHP | `D:\php\php.exe`（8.5.x） | CLI 与 Apache 模块 |
| 钉钉插件 | `plugins\DingTalkNotifier`（`StreamBridge.py` + `Console\*.php` + `Service\*.php`） | 见下两行 |
| 入站机器人 | `StreamBridge.py` | `D:\Apache24\python\python.exe`，SYSTEM，DingTalk Stream WSS |
| 业务命令 | `D:\php\php.exe cli dingtalk:*` | 每次调用起一个 PHP 进程 |
| 财务/报销数据 | 本机 SQL Server 库 `Finance` | `Service\FinanceDb.php` 统一连接 |
| 队列与绑定 | `D:\Apache24\htdocs\kanboard\data\db.sqlite` | Kanboard 数据目录下的 SQLite |
| OCR | `D:\Apache24\invoice-ocr\ocr_worker.py` + `C:\Users\Administrator\Documents\ChatGPT\发票助手` | Python 3.12 worker |
| 打印 | `print-worker.py` / `PrintService.py` / `ReimbursementPrint.py` | 管理员桌面会话（计划任务） |
| RuoYi 后端 | `D:\RuoYi\RuoYi-Vue-Plus` | Java，独立 git 仓库 |
| RuoYi 前端 | `D:\RuoYi\plus-ui`，构建产物镜像到 `D:\Apache24\htdocs\ruoyi` | Vite 构建 |
| 对外地址 | `http://www.figgo.pro:801/kanboard`、`.../ruoyi` | 与 `public_url` / `ruoyi_public_url` 一致 |

数据流一句话：**入站**由 `StreamBridge.py` 分类 → 调 Kanboard CLI 拿 JSON 字符串数组 → 逐条回钉钉；
**出站**不经过 Python，PHP 把消息写进 SQLite 队列，`dingtalk:run`（由桥接进程的 `queue_worker`
每 5 秒触发）负责投递。

## 模块索引

| 模块 | 文件 | 覆盖 | 什么时候读 |
| --- | --- | --- | --- |
| Kanboard（已封存） | `modules/kanboard.md` | 老项目机器人：项目/任务查询、新人入职、当日汇总、任务事件、`TaskScope` 完成口径 | 仅在明确要求复活项目功能，或要读懂遗留代码时 |
| 钉钉机器人 | `modules/dingtalk-bot.md` | StreamBridge 路由链、意图目录、CLI 契约、回复格式、出站队列、线程模型、配置、重启 | 任何路由 / 文案 / 命令 / 配置 / 队列改动 |
| 报销与财务 | `modules/reimbursement.md` | 报销助手向导、单据类型、明细与科目、预览、财务核对、已打款、归档闭环、网页台账 | 改报销流程、财务状态机、台账页面 |
| RuoYi 后台 | `modules/ruoyi.md` | RuoYi 前后端、财务与项目模块、菜单权限、面板间距、人员 AI 分析 | 改 RuoYi 页面、接口、权限、样式 |
| 数据库 | `modules/database.md` | SQL Server `Finance`、SQLite 残余、表清单、迁移规则、时间/金额约定 | 建表加列、查数、迁移、排查数据不一致 |
| 发票 OCR | `modules/invoice-ocr.md` | `ocr_worker.py`、解析规则、文本层真实坑、重跑与回归 | 改识别 / 解析 / 重跑 OCR |
| 打印流水线 | `modules/printing.md` | Excel 模板、GDI 打印、打印队列协议、打印机自动定位、spooler 检查 | 改单据排版、出纸、打印机地址 |

模块之间只有一处强耦合：**报销/财务的写操作全在 Kanboard 侧**，RuoYi 和网页只调用这里的
CLI。跨模块改动先确认这条边界没有被越过。

## 跨模块铁律

1. **改完机器人逻辑必须重启桥接进程**，回复文案、配置值、CLI 命令、打印脚本、Python 都算。
   这是长期要求：没在 `data\dingtalk-stream.log` 看到新的启动行，就不算改完。程序见
   `modules/dingtalk-bot.md` →「重启守护进程」。
2. **财务与报销数据在 SQL Server `Finance`**，不是 `data\finance.sqlite`。`data\db.sqlite`
   只保留：入站去重、用户绑定、出站队列、个人发票台账。
3. **Kanboard 项目功能已封存**：运行时 `KANBOARD_PROJECT_FEATURES_ENABLED = False`，
   `Plugin.php` 里相关命令与监听器已注释。不要按老项目机器人的流程改线上代码。
4. **单聊永远没有 mention 标志**：线上 147 条私聊消息 `mentioned` 全为 False，群聊 @ 则全为
   True。「私聊 @机器人」表现为正文里的 `@机器人` 前缀，由 `MENTION_PREFIX` / `at_prefix` 识别。
   既不要用 mention 标志，也不要用「是否私聊」单独做门禁。
5. **「完成」不等于 `is_active=0`**：任务做完只是拖到「完成」列。所有计数查询走
   `Service\TaskScope`（见 `modules/kanboard.md`）。
6. **回复体量**：单条 JSON 编码后约 12000 字节以内；`DingTalkClient::send` 超过 15000 直接
   失败（`MESSAGE_TOO_LONG`）。拆成多条数组元素是正常做法。
7. **源文件 UTF-8 无 BOM**：
   `[IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`。
8. **不打印、不记录** `app_secret`、access token、`DEEPSEEK_API_KEY`、消息内容。
9. **RuoYi 只读 + 委派**：核对、打印、OCR、归档、补打一律回调 Kanboard CLI，不在 Java 里重写。
10. **入站 `message_id` 先在 `dingtalk_inbound_messages` 认领再回复**，否则钉钉重试会重复回话。
11. **桥接单实例**：`StreamBridge.py` 用 `data\dingtalk-stream.lock`（msvcrt）。不要手工起第二个。
12. **要 Excel 的动作只能在已登录的桌面会话跑**（打印报销单、预览 PDF），走
    `data\reimbursement\print-queue` + `DingTalkKanboardPrint` 计划任务；新命令还要加进
    `print-worker.py` 的 `ALLOWED_COMMANDS`。

## 工作流

1. 判断改动落在哪个模块，读对应 `modules/*.md`；跨模块的再读相邻模块。
2. 读插件 `README.md` 和 `cli list`，确认当前生效范围（封存功能别当活的用）。
3. 改代码 / DDL / 文案，按模块里的「改哪里」表格挑文件。
4. 用 CLI 和对应回归脚本验证；数据类改动要查真实表，不能只看返回值。
5. **重启桥接进程**并核对启动时间晚于最后一次编辑。
6. 用 `skill-vault` 技能把改动同步回 `MianSkill` 仓库（本地提交 ≠ 备份完成）。

## 快速校验

```powershell
Set-Location D:\Apache24\htdocs\kanboard
D:\php\php.exe cli list                      # 命令是否注册
D:\php\php.exe cli dingtalk:run --limit 5    # 队列能否正常排空
Get-Content data\dingtalk-stream.log -Tail 5 -Encoding UTF8
```

## 不要做

- 不要在 RuoYi 或网页里重写核对、打印、OCR、归档、补打。
- 不要为图省事放宽 `FinanceService::permission()`（fail closed），也不要靠菜单可见性当权限。
- 不要把真实发票、真实钉钉 id、密钥写进技能、日志、仓库或测试夹具；测试单一律用
  `TEST-` / `WEB-PROBE-` 假 id。
- 不要在没有匹配 RuoYi 侧改动的情况下单独复活 Kanboard 项目功能。

## 沿革

原技能 `dingtalk-kanboard-bot`（2026-09-11 建立）于 2026-10-23 更名为 `figgo-erp-dev`，
内容按上表拆成 7 个模块；Kanboard 项目机器人部分原样封存进 `modules/kanboard.md`。
