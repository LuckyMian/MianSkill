# 模块：钉钉机器人（DingTalk bot）

> 读我：改 `StreamBridge.py` 的路由 / 意图 / 回复文案、增删 CLI 命令、动队列、改
> `Config.local.php`、或要重启桥接进程时。归属技能：`figgo-erp-dev`。
> 前提：机器人只做**分类 + 转发**，业务逻辑一律在 PHP；不要把业务判断写进 Python。

## 运行时与文件

| 文件 | 角色 |
| --- | --- |
| `StreamBridge.py` | 入站长连接、路由、回复、`queue_worker` / `finance_worker` 线程、单实例锁 |
| `Config.local.php` | 凭据、robot code、项目白名单、群/人映射、`public_url`、`reminder_time`、财务名单 |
| `Service/Config.php` | 读取并校验 `Config.local.php` |
| `Service/QueueService.php` | 入队、认领、完成、重试、恢复、每日汇总去重 |
| `Service/DingTalkClient.php` | access token 缓存与刷新、机器人发送 API、错误分类 |
| `Plugin.php` | 注册 CLI 命令（与封存的项目监听器） |
| `Console/*.php` | 薄包装：读环境变量 → 调 Service → 打印 JSON 数组 |

进程事实：桥接跑在 **SYSTEM**，由 `run-bridge.cmd` 守护（计划任务
`DingTalkKanboardBridge`），stdout 追加到 `data\bridge-console.log`；单实例靠
`data\dingtalk-stream.lock`（msvcrt）。Python 是 `D:\Apache24\python\python.exe`
（3.11.9 + `dingtalk-stream==0.24.3`、`requests`、`pywin32`）。

## 入站路由（现役）

顺序即优先级，**先匹配先返回**：

1. 报销向导（`报销助手` 开着的会话，除非消息命中「放行命令」）
2. 财务核对向导（只认它自己的几个词）
3. **附件**（picture / file / richText）→ 发票助手 OCR
4. 意图目录 `match_intent()`（帮助、报销入口、打印、台账、核对入口、已打款等）

为什么是这个顺序：向导需要自由文本，但它不能吞掉正常命令；附件路径要放在意图目录之后，
否则带附件的普通消息会被 OCR 抢走。

### 两个「不吞命令」的例外（都踩过线上事故）

- **报销向导**：`reimbursement_releases()` 决定哪些消息交还命令目录——`核对报销`、
  `查看细则`、`帮助`、`查询项目`、发票台账、`报销历史`、`打印 BX…`／裸单号都能在填单中途用，
  且**不动 session**。只有 `打印` 和 `暂不打印` 必须留在向导里（确认页的「保存并打印」/
  「只保存」与命令目录同名但含义不同，见 `_REIMBURSEMENT_HELD_KEYS`）。
  附件永远留给向导——发票就在这条路上收。
- **财务向导**：`finance_wizard_owns()` **只**认 `核对报销 …` / `查看细则 …` / `核对完成` /
  `返回` / `取消`，其余照常走 `match_intent()`。改词必须同时改
  `StreamBridge.finance_wizard_owns()` 和 `FinanceService::checkStep()`。

### 私聊 mention 的坑（最容易复发）

钉钉在 1:1 会话里**从不设置** `is_in_at_list`：线上 147 条私聊消息 `mentioned` 全是 False，
群聊里 @机器人 的则是 True。「私聊 @机器人」实际是正文开头的 `@机器人` 字面量，由
`MENTION_PREFIX` 识别为 `at_prefix`。历史事故：只用 `mentioned` → 永远不触发；只用
`is_private` → 管理员私聊发什么都回当日汇总，被投诉。**结论：私聊行为看正文前缀，不看标志位。**

另：`REQUIRE_MENTION` 现在是 `False`，命令无需 @ 即可触发；它不能替代授权，权限仍在 PHP
（`FinanceService::permission()` fail closed），报销与核对还要求单聊。

## 意图与命令契约

桥接用 `subprocess` 调 `php cli <cmd>`，cwd 为 Kanboard 目录、`CREATE_NO_WINDOW`；
命令**必须**输出 `json_encode($messages, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)`，
即「非空字符串数组」，桥接对数组每个元素发一条钉钉消息。

参数里的中文一律走**环境变量**（argv 会乱码）；附件路径也走环境变量。

| 命令 | 参数 / 环境变量 | 用途 |
| --- | --- | --- |
| `dingtalk:run [--limit N] [--test-message]` | — | 排空出站队列 |
| `dingtalk:registration-status` | `DINGTALK_STAFF_ID` | 注册 / 管理员 / 财务标记（桥接用它做门禁） |
| `dingtalk:reimbursement-start` | `DINGTALK_STAFF_ID`、`DINGTALK_CONVERSATION_ID/TYPE` | 开报销向导 |
| `dingtalk:reimbursement-step` | `DINGTALK_STAFF_ID`、`DINGTALK_REIMBURSEMENT_TEXT` | 向导下一步 |
| `dingtalk:reimbursement-attach` | `…FILE`、`…NAME` | 收发票附件 |
| `dingtalk:reimbursement-status` | `DINGTALK_STAFF_ID` | 有没有开着的会话（路由前先问） |
| `dingtalk:reimbursement-preview <staff>` | `DINGTALK_PRINT_WORKER` | 生成预览 PDF（桌面会话） |
| `dingtalk:reimbursement-print <code>` | `DINGTALK_PRINT_WORKER` / `DINGTALK_PRINT_DRY_RUN` | 打印单据 |
| `dingtalk:reimbursement-list` / `-history [--page N]` | `DINGTALK_STAFF_ID` | 可打印列表 / 报销历史 |
| `dingtalk:reimbursement-options` | — | 网页表单下拉（类型 / 团队 / 科目） |
| `dingtalk:reimbursement-web-save <json>` | — | RuoYi 新建报销单 |
| `dingtalk:finance-check-start` | `…TARGET`（直接点名） | 开财务核对向导 |
| `dingtalk:finance-check-step` | `DINGTALK_FINANCE_TEXT` | 核对的点选 / 输入 |
| `dingtalk:finance-check-status` | `DINGTALK_STAFF_ID` | 会话状态 |
| `dingtalk:finance-detail <code>` | `DINGTALK_STAFF_ID`（权限） | 单据细则 |
| `dingtalk:finance-submit <code>` | — | 进队列（幂等兜底） |
| `dingtalk:finance-sync [--limit N]` | `DINGTALK_FINANCE_RECIPIENTS` | OCR + 提醒（`finance_worker` 调） |
| `dingtalk:finance-backfill [--dry-run] [--limit N]` | — | 历史单归档回填，默认 dry-run |
| `dingtalk:finance-verify <code…>` | `DINGTALK_FINANCE_STAFF_ID` / `_NAME` | 批量核对（钉钉与网页共用） |
| `dingtalk:finance-pay <code…>` | 同上 | 标记已打款，**不发消息** |
| `dingtalk:finance-recipients` | — | 打印当前提醒接收人及来源 |
| `dingtalk:finance-staff <用户名>` | — | RuoYi 用户名 → 钉钉 staff id（没绑定退出码 3） |
| `dingtalk:invoice-scan` / `-list` / `-export` / `-clear` | `DINGTALK_STAFF_ID`、`DINGTALK_INVOICE_FILES` | 个人发票台账 |
| `dingtalk:pm-task-assign <json>` | — | 项目任务指派通知（**已注销**，见封存风险） |
| `dingtalk:staff-map`、`dingtalk:attendance-status` | — | 人员/考勤映射（仍在） |

`DINGTALK_INVOICE_FILES` 是 `[{"path":"临时文件","name":"聊天文件名"}]` 的 JSON，**必须
ASCII 转义**：名字要穿 bridge → PHP → Python 三道代码页转换，中文原样会坏。

## 回复机制

- 带 `dtmd://` 的可点链接 → 切 markdown（`sampleMarkdown`）；纯文本 → `sampleText`。
  出站队列同理，`DingTalkClient::payload()` 按内容自动选——财务提醒曾因此点不动。
- 标题约定 `[Kanboard] …`；进 markdown 链接的标题过 `markdown()` 转义 `[ ] ( )`。
- 数组每个元素 ≤ 约 12000 字节（JSON 编码后）；> 15000 直接 `MESSAGE_TOO_LONG`。
- 回复失败返回 `None` 会抛 `RuntimeError("DingTalk reply failed")`，要有兜底文案。

## 出站队列

- 表 `dingtalk_notifications`：`dedupe_key`、`recipient_kind`(`group`/`user`)、`recipient`、
  `content`、`status`(`pending/sending/sent/failed/unknown`)、`attempts`、`available_at`、
  `process_query_key`、`error_code`。
- 投递：`dingtalk:run` 先 `recoverInterrupted()`（`sending` 超过 120 秒 → `unknown` /
  `WORKER_INTERRUPTED`），再逐条认领。群发 `/v1.0/robot/groupMessages/send`，私聊
  `/v1.0/robot/oToMessages/batchSend`，成功存 `processQueryKey` 回执。
- 重试：`retry` 且 attempts < 6 → 回 `pending`，延迟 `min(480, 30 * 2^(attempts-1))` 秒。
- 错误码：`DINGTALK_TOKEN_CONFIG/…_TEMPORARY/…_REJECTED`、`DINGTALK_RATE_LIMIT`、
  `DINGTALK_PERMISSION_DENIED`、`DINGTALK_SERVER_RESULT_UNKNOWN`、
  `DINGTALK_NETWORK_RESULT_UNKNOWN`、`DINGTALK_USER_REJECTED`、
  `DINGTALK_MISSING_RECEIPT`、`DINGTALK_CONFIG_OR_PAYLOAD_REJECTED`、`MESSAGE_TOO_LONG`。
  结果不明一律留 `unknown`，**不要盲目重发**，会重复投递。
- 没人跑 `dingtalk:run` 就没有任何东西会被投递；桥接在跑时由 `queue_worker`
  每 5 秒 `--limit 20` 触发，所以不需要额外调度器。

## 线程与阻塞

- `queue_worker`：每 5 秒排空队列。
- `finance_worker`：每 10 秒 `dingtalk:finance-sync --limit 1`。**OCR 必须留在这里**，
  一次识别十几秒，塞进 `queue_worker` 会拖慢消息投递。
- 除后台线程外，桥接调 PHP 是**同步阻塞**的：OCR 最长 240 秒、当日汇总 240 秒、
  其他命令也有超时。入站 `message_id` 在工作开始前就认领，所以钉钉重试不会产生第二次回复。

## 配置（`Config.local.php`）

`enabled`、`app_key`、`app_secret`、`robot_code`、`project_ids`、`test_group_id`、
`project_groups`、`user_ids`、`public_url`、`reminder_time`、`finance_group`（默认「财务」）、
`finance_staff_ids`、`finance_recipients`（真机演练只指向欧阳冕，清空恢复全组）、
`assign_notify_enabled`、`ruoyi_public_url`，以及打印相关 `daily_print_printer`、
`daily_print_device_mac`、`daily_print_addresses`。

`Service/Config.php` 校验：`enabled=true` 时必须有 `project_ids`、`app_key`、`app_secret`、
`robot_code`，且 `test_group_id` / `project_groups` 至少一个；id 为正整数；
`reminder_time` 为 `HH:MM`。

**凭据**：`app_secret` 只存在于 `Config.local.php`，不打印、不入库、不写进技能或聊天。

## 重启守护进程

改任何机器人逻辑（含 PHP 文案、配置、打印脚本）后必须重启。桥接以 SYSTEM 运行，
`Stop-Process` 会 Access denied；用 `taskkill` 或 WMI。

```powershell
Set-Location D:\Apache24\htdocs\kanboard

# 0) 守护进程只要看到任何 python.exe 就不启动，先清掉一次性脚本的残留
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match 'python\.exe"?\s+-\s*$' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# 1) 杀掉桥接
$bridge = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like '*StreamBridge.py*' }
taskkill /F /PID $bridge.ProcessId
# 若 taskkill/Stop-Process 被拒（SYSTEM 进程），改走 WMI：
# Invoke-CimMethod -InputObject $bridge -MethodName Terminate   # ReturnValue 0 = 已杀

# 2) 等守护进程拉起，并证明新进程真的起来了
Start-Sleep -Seconds 80
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like '*StreamBridge.py*' } | Select-Object ProcessId
Get-Content data\dingtalk-stream.log -Tail 4 -Encoding UTF8
```

验收标准：日志出现**晚于最后一次编辑**的 `DingTalk Stream bridge starting`，随后
`open connection`、`endpoint is`。最硬的证据是进程启动时间 > 文件 mtime：

```powershell
(Get-Process -Id <pid>).StartTime
(Get-Item plugins\DingTalkNotifier\StreamBridge.py).LastWriteTime
```

PHP、配置和 `*.py` 辅助脚本是每次调用重新读的，只有桥接需要重启——但重启的要求是**无条件的**。

## 验证

```powershell
Set-Location D:\Apache24\htdocs\kanboard
D:\php\php.exe cli list
D:\php\php.exe cli dingtalk:run --limit 5
Get-Content data\dingtalk-stream.log -Tail 10 -Encoding UTF8
```

真实回归（用真实 `StreamBridge.process()`，自己造数据自己清）：

- `D:\Apache24\setup-packages\reimbursement-bridge-test.py`
- `D:\Apache24\setup-packages\finance-bridge-test.py`
- `D:\Apache24\setup-packages\invoice-bridge-test.py`
- `D:\Apache24\setup-packages\daily-summary-bridge-test.py`

收尾还要发一条真实钉钉消息，确认**只回一条**（证明入站去重仍然有效）。

## 加命令 / 改路由的固定动作

1. `Service\<X>Service.php`：产出「可直接发送的字符串数组」，输入清洗用现有 `clean()`/`chunk()`。
2. `Console\<X>Command.php`：`setName('dingtalk:x')`，最后一行 `writeln(json_encode(...))`。
3. `Plugin.php`：`use` + `$this->container['cli']->add(new XCommand(...))`。
4. `StreamBridge.py`：`build_x()` 调 `php_output([...])` 并校验是「非空字符串数组」，
   加正则和分支——**放在泛匹配之前**；需要向导时先查 `-status`。
5. `php cli list` + 直接调一次 + 重启桥接 + 发真实消息。

## 不要做

- 不要用 `mentioned` 或「是否私聊」单独做门禁（见上文私聊坑）。
- 不要在 Python 里拼业务文案或用 SQL 查业务数据。
- 不要把消息内容、token、密钥写进日志。
- 不要把 OCR / 长任务挪进 `queue_worker`。
