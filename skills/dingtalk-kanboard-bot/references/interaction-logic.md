# Current interaction logic

Scanned 2026-09-11 on this machine: Kanboard 1.2.54 at `D:\Apache24\htdocs\kanboard`,
Apache on port 801, PHP 8.5.10 at `D:\php`. Everything DingTalk lives in
`plugins\DingTalkNotifier`.

## File map

| File | Role |
| --- | --- |
| `StreamBridge.py` | Inbound loop, routing, replies, queue-worker thread, single-instance lock |
| `Config.local.php` | App credentials, robot code, project allow-list, group/user maps, public_url, reminder_time |
| `Plugin.php` | Registers TaskModel listeners and the eight CLI commands |
| `Service/Config.php` | Loads and validates `Config.local.php` |
| `Service/EventListener.php` | Kanboard event to MessageBuilder to QueueService |
| `Service/MessageBuilder.php` | Event and daily-digest text, dedupe keys |
| `Service/QueueService.php` | Enqueue, claim, finish, retry, recover, daily-digest guard |
| `Service/DingTalkClient.php` | Access token plus robot send API, error classification |
| `Service/PortfolioService.php` | Whole-portfolio report across all active projects |
| `Service/UserStatusService.php` | One person's projects and assigned tasks |
| `Service/ProjectStatusService.php` | One project's active tasks with clickable links |
| `Service/TaskDetailService.php` | One task: fields, subtasks, image and file attachment links |
| `Service/UserBindingService.php` | `绑定账号` self-binding with name-match check |
| `Service/OnboardingService.php` | `#新人入职` session and Kanboard account creation |
| `Service/ReimbursementService.php` | 报销助手 wizard: steps, parsing, invoice storage, form saving |
| `Service/InvoiceService.php` | 发票助手: OCR worker call, ledger rows, CSV export |
| `Controller/ReimbursementLedgerController.php` + `Service/ReimbursementLedgerService.php` + `Template/reimbursement_ledger/*` | 网页版报销台账：员工自查、财务筛选与核对、CSV、发票原件 |
| `Schema/Sqlite.php` | Tables and schema version 8 |
| `Console/*.php` | Thin CLI wrappers that print JSON |

## Inbound routing (ProjectStatusHandler.process)

First match wins, top to bottom.

| # | Condition | Action | Reply style |
| --- | --- | --- | --- |
| 1 | private chat, text exactly `#新人入职` | `dingtalk:onboarding-start` | text |
| 2 | private chat, text exactly `美术` / `模型` / `项目经理` / `程序` | `dingtalk:onboarding-complete` | text |
| 3 | registered user with an open 报销助手 session, and the text is not a catalog command (`reimbursement_releases()`) | `dingtalk:reimbursement-step` / `-attach` | markdown |
| 4 | registered user with an open 财务核对 session | `dingtalk:finance-check-step` | markdown |
| 5 | robot not mentioned and `REQUIRE_MENTION` were true | ignored, no reply | - |
| 6 | `绑定\s*账号\s*([A-Za-z0-9_.@\-\u3400-\u9fff]+)` | `dingtalk:bind-user` | text (currently commented out) |
| 7 | `查询\s*项目` (no argument) | `dingtalk:project-list` | markdown |
| 8 | `查询\s*人员` | `dingtalk:user-list` | markdown |
| 9 | `查询\s*项目\s*(arg)` | `dingtalk:project-status` | markdown |
| 10 | `查询\s*任务\s*#?(\d+)` | `dingtalk:task-status` | markdown |
| 11 | `报销\s*助手` | `dingtalk:reimbursement-start` | markdown |
| 12 | `定时任务` (robot owner only) | scheduler module | markdown |
| 13 | `核对\s*报销` (no argument) | `dingtalk:finance-check-start` | markdown (finance only, private chat) |
| 14 | `核对\s*报销\s*(name)` | `dingtalk:finance-check-start` + `DINGTALK_FINANCE_TARGET` | markdown |
| 15 | `查看\s*细则\s*(BX…)` | `dingtalk:finance-detail` | markdown |
| 16 | `控制台`, `查询\s*(name)`, text containing `项目情况` | console / `dingtalk:user-status` / `dingtalk:portfolio` | mixed |
| 17 | anything else | ignored | - |

The final `else` branch splits once more: a message that carries an attachment
(picture / file / richText) goes to 发票助手 instead of `match_intent`, so 发票助手
needs no wizard and cannot swallow ordinary commands. Attachments are only routed
here when no other wizard is open: the 报销助手, 财务核对 and 定时任务 branches sit
above it.

The 财务核对 wizard (step 4, added 2026-09-28) is the mirror image of 报销助手: it
owns every text from a finance member while it is open, so the tapped list items
(`核对报销 <姓名>`, `查看细则 <单号>`, `核对完成`, `返回`, `取消`) are handled inside
`dingtalk:finance-check-step`, not by `match_intent`. Rows 13–15 only cover the case
where no session is open yet (a stale tap link still works). Permission is checked in
PHP, not in the bridge: a non-finance sender gets 「核对报销只对财务开放」, and the
whole flow refuses to run outside a 1:1 chat.

**例外：核对向导不吞普通命令。** 2026-09-28 上线当天就踩了一次：财务发过「核对报销」
之后（会话还开着），再发「报销助手」被向导接管，只回了向导兜底的「请点下面的按钮」。
向导没有自由输入步骤，所以桥接层用 `finance_wizard_owns()` 只看
`核对报销 …` / `查看细则 …` / `核对完成` / `返回` / `取消` 这些词，别的消息照常走
`match_intent()`。改动这套词时，`StreamBridge.finance_wizard_owns()` 和
`FinanceService::checkStep()` 必须一起改。另外 `checkStart()` 在队列为空时不再建会话，
从根上避免留下一个空向导占着用户 30 分钟。

The chain itself lives in `ProjectStatusHandler.process`: onboarding trigger ->
private job words -> registration gate -> schedule wizard -> 报销助手 wizard ->
`match_intent()`. `INTENTS` in `StreamBridge.py` is the catalog that drives both
routing and the help reply, and the schedule/reimbursement branches run before it.

Notes that matter when editing:

- `conversation_type == "1"` means private chat; `is_in_at_list` is the mention flag.
  Because step 3 runs before the query branches, private chat cannot use the query
  commands, only onboarding.
- Step 8's pattern also matches `查询项目 ...`, so steps 5 and 6 must stay ahead of it.
- `#新人入职` calls `oapi.dingtalk.com/topapi/v2/user/get` to read the enterprise real
  name; without the contact read permission it raises
  `DINGTALK_CONTACT_PERMISSION_OR_USER_ERROR` and the bridge replies with a
  permission hint.
- The job list exists twice: `ONBOARDING_JOBS` in `StreamBridge.py` and `JOBS` in
  `OnboardingService.php`. Change both together.
- `message_id` is claimed in `dingtalk_inbound_messages` (rows older than 7 days are
  purged on each inbound message) before the first reply; a duplicate claim returns
  `duplicate` and sends nothing.

## Reply mechanics

- Markdown replies (`reply_markdown(title, content, incoming)`) are used for steps 5
  and 6 so Kanboard links render as clickable markdown. Titles used: `Kanboard 项目情况`,
  `Kanboard 任务情况`, otherwise `Kanboard 查询结果` or `新人入职`.
- Everything else uses `reply_text(content, incoming)`.
- A `None` return raises `RuntimeError("DingTalk reply failed")`; the handler logs
  `Unable to build or reply with portfolio` and sends a fallback text reply.
- Each element of the CLI JSON array becomes one DingTalk message, sent in order.

## CLI contract

Display commands print `json_encode($messages, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)`
as a JSON array of strings, always at least one element. The bridge calls PHP with
the Kanboard directory as `cwd` and `CREATE_NO_WINDOW`.

| Command | Argument | Extra environment |
| --- | --- | --- |
| `dingtalk:portfolio [--json]` | none | - |
| `dingtalk:user-status <search>` | username or display name, exact match before partial | - |
| `dingtalk:project-status <search>` | project id, name, or identifier | - |
| `dingtalk:task-status <task_id>` | numeric task id | - |
| `dingtalk:bind-user <search>` | Kanboard name | `DINGTALK_BIND_USER_ID`, `DINGTALK_BIND_USER_NAME` |
| `dingtalk:onboarding-start` | none | `DINGTALK_ONBOARDING_USER_ID`, `DINGTALK_ONBOARDING_REAL_NAME` |
| `dingtalk:onboarding-complete <job>` | one of the four job words | `DINGTALK_ONBOARDING_USER_ID` |
| `dingtalk:run [--limit N] [--test-message]` | none | - |
| `dingtalk:reimbursement-start` | none | `DINGTALK_STAFF_ID`, `DINGTALK_CONVERSATION_ID`, `DINGTALK_CONVERSATION_TYPE` |
| `dingtalk:reimbursement-step` | none | `DINGTALK_STAFF_ID`, `DINGTALK_REIMBURSEMENT_TEXT` |
| `dingtalk:reimbursement-attach` | none | `DINGTALK_STAFF_ID`, `DINGTALK_REIMBURSEMENT_FILE`, `DINGTALK_REIMBURSEMENT_NAME` |
| `dingtalk:reimbursement-status` | none | `DINGTALK_STAFF_ID` |
| `dingtalk:reimbursement-print <code>` | form code | `DINGTALK_PRINT_DRY_RUN` skips the printer |
| `dingtalk:reimbursement-list` | none | `DINGTALK_STAFF_ID` (the `打印` hint list) |
| `dingtalk:reimbursement-history [--page N]` | none | `DINGTALK_STAFF_ID` (the 报销历史 list, 10 forms per page) |
| `dingtalk:finance-check-start` | none | `DINGTALK_STAFF_ID`, `DINGTALK_CONVERSATION_ID/TYPE`, `DINGTALK_FINANCE_TARGET` (name to open directly) |
| `dingtalk:finance-check-step` | none | `DINGTALK_STAFF_ID`, `DINGTALK_FINANCE_TEXT` |
| `dingtalk:finance-check-status` | none | `DINGTALK_STAFF_ID` |
| `dingtalk:finance-detail <code>` | form code | `DINGTALK_STAFF_ID` (permission check) |
| `dingtalk:finance-submit <code>` | form code | - |
| `dingtalk:finance-sync [--limit N]` | none | `DINGTALK_FINANCE_RECIPIENTS` overrides the recipients |
| `dingtalk:finance-backfill [--dry-run] [--limit N]` | none | - |
| `dingtalk:finance-recipients` | none | 打印当前财务提醒接收人 + 名单来源（env/meta/config/group） |
| `dingtalk:finance-verify <code…>` | 单号列表 | 按单号批量核对，Kanboard 网页台账与 RuoYi 面板共用（`FinanceService::verifyCodes()`）；核对人来自 `DINGTALK_FINANCE_STAFF_ID` / `DINGTALK_FINANCE_NAME` |
| `dingtalk:finance-pay <code…>` | 单号列表 | 核对之后的下一步：标记「已打款」（`FinanceService::markPaid()`）。只允许 `verify_status='verified' AND paid_status='none'` → `paid`，记一条 `finance_events(event='paid')`，**不发钉钉消息**；操作人同样来自 `DINGTALK_FINANCE_STAFF_ID` / `DINGTALK_FINANCE_NAME` |
| `dingtalk:finance-staff <用户名>` | RuoYi/Kanboard 用户名或姓名 | 查 `dingtalk_user_bindings` 换成钉钉 staff id，供 RuoYi「我的报销」把范围钉死到登录人；没绑定就退出码 3，最后一行是给人看的一句话 |
| `dingtalk:reimbursement-options` | none | 网页表单选项：单据类型 + `teams`（5 个团队）+ 科目（`subjects` 扁平值、`categories` 两级结构），都直接读 `READY_TYPES` / `TEAMS` / `CATEGORIES` |
| `dingtalk:reimbursement-web-save <json>` | 草稿 JSON 文件路径 | RuoYi 面板「新建报销单」；JSON 里 `user` 是 RuoYi/Kanboard 用户名，服务侧查 `dingtalk_user_bindings` 拿 staff id，发票路径由调用方落盘后传入 |
| `dingtalk:invoice-scan` | none | `DINGTALK_STAFF_ID`, `DINGTALK_INVOICE_FILES` |
| `dingtalk:invoice-list` | none | `DINGTALK_STAFF_ID` |
| `dingtalk:invoice-export` | none | `DINGTALK_STAFF_ID` |
| `dingtalk:invoice-clear` | none | `DINGTALK_STAFF_ID` |

`DINGTALK_INVOICE_FILES` is a JSON array of `{"path": 临时文件, "name": 聊天文件名}`.
It must stay ASCII-escaped: the names travel bridge -> PHP -> Python, and raw Chinese
is mangled by the codepage conversions in between. One message's attachments are
recognised in a single call so the OCR models load once.

## Printing (`ReimbursementPrint.py`)

The 打印 button, and the `打印 <单号>` intent, call `ReimbursementPrint.py`, which
fills the finance template and prints it plus the invoices:

- Template `C:\Users\Administrator\Desktop\费用报销单.xlsx`: 项目名称 goes to AL5,
  摘要/金额/科目/附单据数 to AG/AJ/AK/AL rows 7-10 (extra item rows are inserted), and
  the filled copy is saved to `data/reimbursement/forms/<code>/`. Writes must use
  `Range(...).MergeArea` - plain `ClearContents` on a merged cell fails here - and an
  empty project needs an `=""` formula or `=AL5` prints `0`.
- `data/reimbursement/forms/` also keeps the invoice files; they are moved out of the
  per-user draft folder when a form is saved, because printing happens later and the
  files are the audit trail.
- Ink saving is monochrome + single sided via `PrintService.ink_saving_devmode`, which
  temporarily swaps the queue's default DEVMODE (Excel ignores its own BlackAndWhite /
  Draft flags on this driver, verified through the spooler). Draft quality and N-up are
  driver-private and are rejected, so page count and content are what save toner.
- Invoices become pure black-and-white images (Otsu threshold) laid out two per A4
  sheet; **when there is only one invoice it still uses just one slot, so it stays on
  the top half of the sheet** (user request, 2026-09-16). Printing does that through
  `PrintService.print_image_pages(..., slots_per_page=2)`, the preview through the same
  `slots = max(INVOICES_PER_SHEET, len(sheet))` in `compose_preview()` — change both or
  the preview stops matching the paper.
  The Canon PrintTicket does offer `psk:DocumentBinding=Booklet` (小册子), but
  it forces duplex and folding, which would double the invoices per sheet.
- `_stretch_image` draws through a ctypes DIB section: no `PyCBitmap.CreateBitmap` in
  this pywin32 build, and DDBs fail `StretchBlt` to a printer DC at full page size.
- The bridge runs as SYSTEM, where Excel automation is unusable: `Workbooks.Open` hangs
  or refuses the file (even a copy under `data\`), and Excel's only visible printer
  there is "Microsoft Print to PDF" whose `ActivePrinter` cannot be set. Printing is
  therefore delegated to the logged-on administrator session through the
  `DingTalkKanboardPrint` scheduled task: PHP writes
  `data/reimbursement/print-queue/<号>.request`, runs the task, the worker
  (`print-worker.cmd` -> `print-worker.py`) executes
  `php cli dingtalk:reimbursement-print <号>` with `DINGTALK_PRINT_WORKER=1` and writes
  `<号>.result`, and the SYSTEM side relays that reply into the chat. Printing needs the
  administrator desktop session to be logged on; when it is not, the reply says so and
  the form stays saved.
- `ReimbursementPrint.main` pins stdout to UTF-8: without a console Python falls back to
  the ANSI code page and the JSON reply is unreadable to PHP.
- The worker must not append to `data\bridge-console.log`: the StreamBridge supervisor
  holds that file open and cmd fails with "being used by another process".

## 报销助手 wizard

Steps: `type` -> `team` -> `project` -> `items` -> `invoices` -> `review` -> form saved.
团队（`TEAMS`：智慧数字 / 智慧城市 / 智慧感知 / 乐享 / 总经办）是 2026-09-29 加的一步，
存在**草稿 JSON** 里（`draft['team']`，不占会话表的一列）——注意 `saveSession()` 是整列覆盖，
任何一处保存会话都要把整份 draft 带上，传 `[]` 会把团队洗掉（`stepProject` 就踩过）。
One row
per DingTalk user in `dingtalk_reimbursement_sessions` (draft JSON, 30-minute TTL);
finished forms go to `dingtalk_reimbursement_forms` with a `BX<YYYYMMDD>-<id>` code
and status `saved` or `pending_print`.

- `READY_TYPES` decides which menu entries start a form and which answer with the menu
  again: 费用报销单 (`expense`) and 员工报销单 (`employee`) are implemented, the other four
  types still just re-send the menu.
- Items are parsed from `摘要 金额 4200 科目 办公费/设备维修`. 科目是**两级**的：白名单是
  `ReimbursementService::CATEGORIES`（8 个一级 / 47 个可选值），落库值写成「一级/二级」，
  只有一级的（招聘费）写一级本身——「餐费」「交通费」「其他」「素材」在多个一级下重复，
  只存二级分不清。`科目 12` 按扁平序号选；文本匹配把分隔符（`/ - 空格`）和空白一起抹掉
  再比，所以 `一级/二级`、`一级 二级` 都认。只写一级而它下面有二级、或者写了个重复的
  二级名，都会回一句带正确写法的提示。金额按分存。
  明细行里的「金额」「科目」两个标记取**最后一次**出现，摘要里带这两个词也不会误判。
- Invoices arrive as picture/file/richText messages. The bridge turns the download
  code into bytes, checks the magic number (PDF/PNG/JPEG), writes a temp file and
  hands the path to PHP through the environment; PHP copies it to
  `data/reimbursement/<staff id>/` and deletes the temp file. Closing or cancelling a
  session deletes the invoice files.
- **放行规则（`StreamBridge.reimbursement_releases()`，2026-09-28 加）**：向导靠自由文本
  填单（项目名、明细），没法像财务核对那样只认几个词，所以改成「命中命令目录的消息一律
  交还给正常命令目录」：`核对报销`、`查看细则`、`帮助`、`查询项目`、发票台账、`报销历史`、
  `打印 BX…`／裸单号都能在填单中途直接用，而且**不动 session**。当天两起实测都是这条：
  会话停在选类型那步发「核对报销」/「打印 BX…」，被 `stepType()` 当成单据类型，只回了
  「没有认出这个类型」。两个例外（`_REIMBURSEMENT_HELD_KEYS`）必须留在向导里：
  `打印`（= 确认页「保存并打印这张」，命令目录里同名的是「翻列表」）和
  `暂不打印`（= 确认页「只保存」，命令目录里同名的是当日汇总的「不用打印」）。
  附件永远留给向导 —— 发票就是在这条路上收的。
  剩下的自由文本仍然全归向导，没有 `取消` 就走不掉（30 分钟 TTL）。
- Choosing 预览 returns a print-preview PDF link without saving anything (see the 预览
  section below); 打印 prints for real; 暂不打印 stores the form as `saved`, and a later
  `打印 <单号>`, a bare `单号`, or `打印` (lists the caller's ten most recent forms with
  tappable codes) brings it back.
- 类型菜单最后一项是「报销历史」（`报销历史`/`历史`/`报销记录`/`我的报销`，可带页码），
  列这个人开过的所有单据、每页 10 张、点单号重新打印。它由
  `ReimbursementService::formHistory()` 渲染，`listForms()`（回「打印」时）和
  `history()`（菜单/命令）共用，所以两条路的格式不会走偏。菜单链接在填写中的任何一步
  都认，且**不动 session**（看一眼旧单子不该丢草稿）；不在向导里时由
  `StreamBridge` 的 `reimbursement-history` intent 走 `dingtalk:reimbursement-history`。
- **补打要能穿过打开着的向导**：`step()` 在 switch 之前先认 `报销历史`、`打印 <单号>`／
  裸单号、以及不在 `review` 步时的光一个「打印」。2026-09-28 用户实测踩到过：会话停在
  `type` 步，点历史列表里的单号（=发回「打印 BX…」）被 `stepType()` 当成单据类型，只回了
  「没有认出这个类型」。`review` 步的「打印」是「保存并打印这张」，**不能**被列表抢走，
  所以那里单独放行；`matchReprintCode()` 的写法要和 `StreamBridge` 的
  `reimbursement-print` 正则一起改。

Test harnesses (they use `TEST-` staff ids and print their own cleanup SQL):
`D:\Apache24\setup-packages\reimbursement-flow-test.py` drives the PHP state machine,
`reimbursement-bridge-test.py` simulates DingTalk callbacks against the real
`StreamBridge.process()`.

## 发票助手 (invoice OCR)

Recognises invoices sent into the chat and keeps a per-user ledger. It exists so the
finance PC, which is Windows 7 and cannot run the OCR stack itself, only has to send
files through DingTalk.

- Routing: no wizard. Any registered user's message carrying a picture / file /
  richText attachment is recognised; the three ledger commands are plain intents
  (`发票台账`, `导出台账`, `清空台账`). `发票助手` returns instructions with tap links.
- The OCR runs in `D:\Apache24\invoice-ocr\.venv` (Python 3.12), driven by
  `Service\InvoiceService.php` through `ocr_worker.py`. That path is deliberately
  ASCII-only: PHP -> cmd -> Python crosses several codepage conversions and a Chinese
  script or interpreter path gets corrupted. The worker adds the Chinese project
  directory (`C:\Users\Administrator\Documents\ChatGPT\发票助手`) to `sys.path`
  itself, and prints ASCII-escaped JSON.
- The worker uses `pythonw.exe` so no console window flashes; pipes still capture its
  stdout. It redirects library stdout to stderr so rapidocr's logging cannot corrupt
  the JSON.
- One chat message's attachments go through a single worker run so the ONNX models
  load once. A run costs roughly 15s cold, then ~3s per extra page.
- The bridge calls the scan command with a 240s timeout (`INVOICE_SCAN_TIMEOUT`); the
  service's own read loop gives up at 180s. This blocks the bridge for the duration,
  exactly like the other PHP calls; the inbound `message_id` claim happens before the
  work, so a DingTalk retry cannot produce a second reply.
- Duplicate protection is by `(staff_id, invoice_number)`: re-sending the same invoice
  answers "已经识别过" and writes nothing.
- CSV is written to `D:\Apache24\htdocs\kanboard\invoice-export\` with a random token
  in the name and answered as a markdown link. `.htaccess` only rewrites *missing*
  paths to `index.php`, so a real file there is served directly; `data\` is denied and
  must not be used for this. Files older than 7 days are pruned on each export.
- Note the export directory is reachable from the public URL
  (`public_url` is `http://www.figgo.pro:801/kanboard`); the random token and the
  prune window are the only protection.

Bridge test: `D:\Apache24\setup-packages\invoice-bridge-test.py` drives the real
`StreamBridge.process()` with stubbed replies and file downloads.

## Outbound notifications

Registered Kanboard events (`Plugin.php`): `task.create`, `task.assignee_change`,
`task.move.column`, `task.close`, `task.open`.

- `EventListener::handle` returns immediately when `enabled` is false, then merges
  DB bindings under `user_ids` (the config map wins) and enqueues
  `MessageBuilder::eventNotices`.
- A notice is produced only for projects in the `project_ids` allow-list. Group
  notices go to `project_groups[project_id] ?? test_group_id`; personal notices exist
  only for `task.create` and `task.assignee_change` and only for bound users.
- Dedupe key: sha256 over event name, task id, version timestamp
  (`date_moved` / `date_modification` / `date_creation`), owner, column, active flag,
  and source column. The table constrains `(dedupe_key, recipient_kind, recipient)`.
- Daily digest (`enqueueDailyDigest`): after `reminder_time` Beijing time it selects
  active tasks due within 24 hours, chunks 10 lines per message, keys
  `digest:<YYYY-MM-DD>:<n>`, and writes the day into `dingtalk_reminder_runs` so it
  fires at most once per day.
- Delivery (`dingtalk:run`): `recoverInterrupted()` marks `sending` rows older than
  120 seconds as `unknown` / `WORKER_INTERRUPTED`, then claims pending rows one at a
  time. Group sends use `/v1.0/robot/groupMessages/send`, personal sends use
  `/v1.0/robot/oToMessages/batchSend`, both with `msgKey=sampleText`; success stores
  the `processQueryKey` receipt.
- **带 tap link 的通知必须用 `msgKey=sampleMarkdown`**：`DingTalkClient::payload()` 现在
  按内容里有没有 `dtmd://` 自动选 `sampleMarkdown`（带 `title`，取首行）或 `sampleText`。
  2026-09-28 财务提醒就踩过：链接本身是对的，但纯文本发出去钉钉只当普通文字，点不动。
  桥接层直接回复时一直是「含 tap link 就切 markdown」，出站队列现在对齐。
- Retries: a `retry` state with attempts below 6 returns the row to `pending` with
  delay `min(480, 30 * 2^(attempts-1))` seconds. Other states finish as `failed` or
  `unknown`.
- Error codes seen in the code: `DINGTALK_TOKEN_CONFIG`, `DINGTALK_TOKEN_TEMPORARY`,
  `DINGTALK_TOKEN_REJECTED`, `DINGTALK_RATE_LIMIT`, `DINGTALK_PERMISSION_DENIED`,
  `DINGTALK_SERVER_RESULT_UNKNOWN`, `DINGTALK_NETWORK_RESULT_UNKNOWN`,
  `DINGTALK_USER_REJECTED`, `DINGTALK_MISSING_RECEIPT`,
  `DINGTALK_CONFIG_OR_PAYLOAD_REJECTED`, `MESSAGE_TOO_LONG`.
- The bridge's own `queue_worker` thread runs `dingtalk:run --limit 20` every 5
  seconds, so no scheduler is required while the bridge is running. Without the
  bridge, nothing drains the queue.

## Data model (`data\db.sqlite`)

| Table | Purpose |
| --- | --- |
| `dingtalk_notifications` | Outbound queue: dedupe_key, recipient_kind (`group`/`user`), recipient, content, status (`pending`/`sending`/`sent`/`failed`/`unknown`), attempts, available_at, process_query_key, error_code |
| `dingtalk_reminder_runs` | One row per day the digest was queued |
| `dingtalk_inbound_messages` | Inbound dedupe by message_id |
| `dingtalk_user_bindings` | Kanboard user id to DingTalk staff user id, FK to users with ON DELETE CASCADE |
| `dingtalk_onboarding_sessions` | Pending onboarding sessions, 30-minute expiry |
| `dingtalk_reimbursement_sessions` | One open 报销助手 wizard per DingTalk staff id |
| `dingtalk_reimbursement_forms` | Finished reimbursement forms (code, payload, total, status) |
| `dingtalk_invoice_records` | 发票助手 ledger: one row per recognised invoice, columns match the exported CSV |

### Finance database (`data\finance.sqlite`, added 2026-09-28)

Separate file on purpose: 凭证、发票原件和核对流水是财务资产，而且发票原件（BLOB，单张最大
20 MB）放进 `db.sqlite` 会把看板库撑大。`data/.htaccess` 全拒绝，Web 访问不到。这个库
没有 Kanboard 的插件迁移机制可用，DDL 由 `Service/FinanceDb.php` 在连接时幂等执行，后加的
列用 `ensureColumn()`（PRAGMA table_info + ALTER TABLE）补上。

| Table | Purpose |
| --- | --- |
| `finance_submissions` | 一张单一行，主键 `code`（BX 单号）：period（YYYY-MM）、提交人、类型、项目、金额、`source`（print/hold/backfill）、`ocr_status`/`notify_status`/`verify_status`、archive_dir、workbook_path、各时间戳、核对人 |
| `finance_items` | 明细，`UNIQUE(code, seq)` |
| `finance_invoices` | 发票/附件，`UNIQUE(code, seq)`：文件名/扩展名/大小/sha256/归档路径/原件 BLOB `content`、全部 OCR 字段，以及 `ocr_records_json`（一个 PDF 识别出多张时留全量） |
| `finance_events` | 审计流水：archived / submitted / ocr_done / notified / verified / employee_notified … |
| `finance_check_sessions` | 财务核对向导，一人一行，30 分钟 TTL |
| `finance_meta` | schema_version |

Schema version 8 is recorded in `plugin_schema_versions`. Kanboard migrates a plugin
schema automatically when the plugin is loaded (`SchemaHandler::loadSchema`), so any
CLI call or web request applies a new `version_N`; `cli plugin:upgrade` is for
installing plugin releases from the directory and is not configured on this host.

`SchemaHandler::migrateSchema` calls each `version_N` only if `function_exists()` says
it is there, and then records the new version **either way**. On this live server a
request can load the plugin in the window between "VERSION bumped" and "version_N
written", which silently skips the migration for good. Always change `VERSION` and add
the function in the same edit, and make the DDL idempotent (`IF NOT EXISTS`) plus
self-healing from the service, as `InvoiceService::ensureTable` does.

## Config keys (`Config.local.php`)

`enabled`, `app_key`, `app_secret`, `robot_code`, `project_ids`, `test_group_id`,
`project_groups` (project id to openConversationId), `user_ids` (Kanboard user id to
DingTalk staff id), `public_url`, `reminder_time`, `finance_group` (Kanboard 用户组名，
默认 `财务`), `finance_staff_ids` (额外的钉钉 id 名单，默认只有机器人持有者
`202124090427574057`), `finance_recipients` (非空时财务提醒只发这些钉钉 id；现在为了让
真机演练不打扰李雪、刘李，指向 `202124090427574057` = 欧阳冕)。

Validation in `Service/Config.php`: when `enabled` is true it requires `project_ids`,
`app_key`, `app_secret`, `robot_code`, and at least one of `test_group_id` or
`project_groups`; ids must be positive integers; `reminder_time` must be `HH:MM`.

## Current state (verified 2026-09-15)

- Python lives in `D:\Apache24\python` (official embeddable 3.11.9 plus pip) with
  `dingtalk-stream==0.24.3`, `requests` and `pywin32` installed. `StreamBridge.py`
  hardcodes `PHP = Path(r"D:\php\php.exe")`, which is correct. The `.venv` folder in
  the plugin directory is a leftover from the old `C:\Apache24` machine and is
  unusable; delete it if it gets in the way.
- `public_url` is `http://www.figgo.pro:801/kanboard`.
- The bridge is supervised by `run-bridge.cmd` (started at boot by the
  `DingTalkKanboardBridge` scheduled task), which restarts it and appends stdout to
  `data\bridge-console.log`. It runs as **SYSTEM**, so `Stop-Process` from an elevated
  Administrator shell fails with Access denied; use `taskkill /F /PID <pid>` and the
  supervisor brings it back within about a minute. The supervisor refuses to start a
  second instance while any `python.exe` is running (it polls every 60s).
- `D:\Apache24\invoice-ocr` holds the 发票助手 OCR virtualenv and worker, also run as
  SYSTEM. Both it and the invoice-assistant project directory grant SYSTEM full
  control, verified by running the worker through a SYSTEM scheduled task.
- Nine active projects are visible (ProjectBase, 深铁华著, 昭通湖滨one, 秋桂锦堂,
  金沙镜, 金地上宸, 周口港, 佛山顺控珑悦湾, …), three of them with active tasks.
- Printing works from Python through the driver GDI path (`PrintService.py`,
  pywin32); the default printer is `Canon MF650C Series UFR II`.

## 当日项目情况汇总 (added 2026-09-15)

管理员私聊 @ 机器人时，除了本来该回的内容，再附一份当天汇总 + DeepSeek 分析，最后问是否
打印。取数与渲染全在 PHP（`Service/DailyOverviewService.php`），桥接层只判断权限、转发
字符串。

| 触发 | 结果 |
| --- | --- |
| 私聊 + `@机器人` 前缀 + 管理员 + 空消息 / 无匹配命令 / 帮助 | 原回复 + 汇总（多条） |
| `当日汇总`（`今日`/`每日`/`项目` + 汇总 都行，需管理员） | 只有汇总 |
| `打印总览` / `打印汇总` | 当天那份汇总排成 1 页 A4 送打印机 |
| `不用打印` / `暂不打印` | 不再追问 |

- 管理员 = 绑定的 Kanboard 账号 `role=app-admin`，或 `Config.local.php` 的
  `summary_staff_ids` 名单（名单是为了让机器人持有者在还没绑定管理员账号时也能用）。
  当前名单里是 `202124090427574057`；系统里唯一的 `app-admin` 是 Kanboard 的 `admin`
  账号，还没有绑定钉钉。
- **单聊的 `mentioned` 永远是 False**（线上 147 条私聊消息全是 False，群消息 @ 机器人
  则全是 True）；「私聊 @机器人」表现为**正文里的 `@机器人` 前缀**，由
  `StreamBridge.MENTION_PREFIX` 识别成 `at_prefix`。自动附汇总的条件是
  `is_private and at_prefix and (无匹配命令 or 帮助) and 管理员`：
  - 只用 `mentioned`（最初版本）→ 永远不触发；
  - 只用 `is_private`（2026-09-16 上午的版本）→ 管理员私聊发什么都回汇总，被用户投诉；
  - 现在这版两者都不靠，靠正文前缀。
- `dingtalk:registration-status` 的返回多了一个 `admin` 字段，桥接层用它做门禁，省掉一次
  PHP 进程。`registered()` 仍然 fail-open，`is_admin_staff()` 则 fail-closed。
- 管理员专属条目在 `INTENTS` 里标 `module="admin"`；`build_help(include_admin=...)` 决定
  帮助里是否列出来。非管理员发 `当日汇总` 得到「只对管理员开放」。
- AI 分析只在数据（总体/项目/人员/同日撞车/逾期明细的哈希）变化或有 `--refresh` 时重算，
  否则沿用当天已存的那份，所以重复点开几乎不花钱。这份端点上的模型是推理模型：思维链会吃掉
  `max_tokens`，太小就只返回空的 `content`（`finish_reason=length`），
  `deepseek_max_tokens` 因此默认 8000。
- `Config.local.php` 新增 `deepseek_api_key` / `deepseek_base_url` / `deepseek_model` /
  `deepseek_max_tokens` / `deepseek_timeout` / `summary_staff_ids`。Key 留空时汇总照常发，
  只有 AI 那一段写明原因。Key 是本机密钥，不要外传。
- 新增 CLI：`dingtalk:daily-summary [--refresh]`（`DINGTALK_STAFF_ID` 走环境变量）、
  `dingtalk:daily-print [day]`。桥接侧超时 240 秒。
- 表 `dingtalk_daily_overviews`（schema 9）：一天一行，存事实 JSON + AI 原文，打印用的就是
  这份，所以纸面和聊天内容一致。
- 打印走和报销单同一条队列：PHP 写 `data/daily-summary/print-queue/daily-<day>.request`
  （内容是 `{"command":"dingtalk:daily-print","argument":"<day>"}`），`schtasks /run
  DingTalkKanboardPrint` 唤醒桌面会话里的 `print-worker.py`，它按 JSON 里的命令再调一次
  CLI（`ALLOWED_COMMANDS` 白名单），最后 `DailyOverviewPrint.py` 用 `PrintService` 排版
  并打印 1 页 A4。worker 现在同时排空报销单和汇总两个队列目录。
- `DailyOverviewPrint.py --no-print` 只排版不打印；`DINGTALK_PRINT_DRY_RUN=1` 会让 PHP 自动
  带上它，回复里也会注明是干跑。
- 回归测试：`D:\Apache24\setup-packages\daily-summary-bridge-test.py` 驱动真实的
  `StreamBridge.process()`（打印那一步打桩），跑完打印清理 SQL。

### 打印设置与「纸没出来」的排查（2026-09-15）

- 总览和报销单一样走黑白 + 单面：`PrintService.ink_saving_devmode()` 会临时改队列默认
  DEVMODE，读回来是 `Color=1`（单色）、`Duplex=1`（单面）、`PrintQuality=600`。
  **草稿质量在这个 Canon 驱动上设不进去**（请求 draft 后被驱动重置回 600 dpi），N-up 同理，
  所以省墨只能靠单色、单面和内容本身（纯文字 + 细表格线，不用大块底纹）。
- `DailyOverviewPrint.py` 提交完任务后会在 spooler 里盯几秒：任务离队且打印机没有错误位才算
  成功；还压在队列里就把「打印机没有取走这一页（设备报错/缺纸/脱机）」原文回给用户，
  不再谎报已打印。`--check-seconds` 控制等待时长（默认 4 秒）。
- 打印机可以用 `Config.local.php` 的 `daily_print_printer` 指定，**建议一直写死名字**：
  默认打印机一旦换成别的队列（例如临时诊断队列被删掉），`GetDefaultPrinter()` 会返回失效
  名字，打印直接报 `(1801, 'OpenPrinter', '打印机名无效')`。
- 2026-09-15 的「打印没出来」根因不在代码：主队列挂在 Canon MFNP 端口
  `CNMFNP_B48C9DFFF2E8` 上，这个端口缓存着设备的旧地址 172.16.1.38（该地址已无人应答），
  而设备（MAC `B4-8C-9D-FF-F2-E8`）当时只有链路本地地址 169.254.138.7（80/9100/8610 都通）。
  表现是每个任务在队列里 `8210`（错误+正在打印+保留）、`PagesPrinted=0`，并且 spooler
  重启都清不掉。改用标准 TCP/IP RAW 端口直连设备当前地址后立刻正常出纸。
  现在的队列指向 `IP_Canon_MF650C` → 169.254.138.7:9100（SNMP 关闭）。回退一行命令：
  `Set-Printer -Name 'Canon MF650C Series UFR II' -PortName 'CNMFNP_B48C9DFFF2E8'`。
  链路本地地址会漂，长期解法是给打印机在局域网里固定一个 IP（或 DHCP 保留）。
- 排查用到的只读手段：`PrintService.list_printers()` / `printer_queue()`、
  `Get-WinEvent -LogName Microsoft-Windows-PrintService/Operational`、
  `Get-CimInstance Win32_Printer`、往 `设备IP:9100` 直接发一张纯文本测试页。
  注意：会卡住的旧任务只有重启 Print Spooler 才清得掉。

### 打印前自动确认打印机地址（`PrinterLocator.py`）

- 打印机地址是怎么查出来的：**`arp -a` 里按 MAC 找**。设备的 MAC 来自原 Canon 端口名
  `CNMFNP_B48C9DFFF2E8` → `B4-8C-9D-FF-F2-E8`；ARP 表里这条记录当时解析到
  169.254.138.7，并且挂在**有线**接口 172.16.1.84 下（打印机在有线局域网上，只是 DHCP
  没成功才自保留了 169.254 地址，不是走 Wi-Fi）。
- 每次打印（`DailyOverviewPrint.py` 真正出纸前）都会重新定位一次，顺序是：
  ① ARP 里按 MAC 命中 → ② `printer-address.json` 里上次成功的地址 → ③
  `daily_print_addresses` 候选，逐个探 9100，第一个应答的胜出；成功后写回状态文件。
  ④（2026-09-28 新增）上面全不通就扫本机各 /24 的 9100，再用邻居表把 MAC 对上——
  打印机 DHCP 换到一个谁都没记过的地址时 ARP 里是空的，只有扫网段才能发现它。
  `ReimbursementPrint.py` 现在也走同一套（`--device-mac/--candidate/--state-file`，状态
  文件共用 `data/daily-summary/printer-address.json`），不再只有「当日总览」会纠地址。
- 换了地址就要换端口：`Win32_TCPIPPrinterPort.HostAddress` 在**这个 Windows 版本上是只读
  属性**（`Set-CimInstance` 会报 ReadOnly），所以按地址新建端口 `CanonIP_<地址>` 再用
  `Set-Printer -PortName` 切过去，最后把不再被任何队列使用的 `CanonIP_*` 旧端口删掉。
- 新增配置：`daily_print_device_mac`（现在是 `B4-8C-9D-FF-F2-E8`）、
  `daily_print_addresses`（`['172.16.1.38','169.254.138.7']`）。
- 回复里会带上实际用的地址和来源，例如「打印机地址 169.254.138.7（ARP），已自动把打印端口
  切过去」。验证方式：故意把队列指到失效的 172.16.1.38，再跑一次
  `php cli dingtalk:daily-print`，它应当自己纠正后正常出纸（2026-09-15 实测通过）。
- 设备侧能自动发现的口子都关着：SSDP（1900）无应答、WS-Discovery（3702）只回本机，所以
  ARP + 候选地址就是当前最可靠的路子。路由器给打印机做的 172.16.1.38 保留地址当天还没
  生效（该 IP 上 ping/ARP/80/9100/8610 全无响应），打印机仍在 APIPA 地址上。
- **提交成功 ≠ 出纸**：`PrintService.spooler_warning()`（2026-09-28 从
  `DailyOverviewPrint` 提到公共位置）会盯 `check_seconds` 秒，任务还留在队列里就返回
  「打印机没有取走这一页（设备报错/缺纸/脱机/任务报错），已打出 N 页」。报销单打印
  也用它：`printRow()` 收到 warning 就**不标已打印、不通知财务**，只回一条「没有真正
  打印出来 + 怎么重打」。2026-09-28 之前报销单这条路径没有这个检查，打印机离线时
  机器人照样回「已打印」，财务还收到了一条提醒。
- 卡住的任务：`Remove-PrintJob` 经常只是把它推进「Deleting, Printing, Retained」，
  重启 Spooler 也清不掉（Retained 任务会被重新加载）。实测有效的是
  `Invoke-CimMethod -InputObject (Get-CimInstance Win32_Printer -Filter "Name='…'") -MethodName CancelAllJobs`；
  注意 `C:\Windows\System32\spool\PRINTERS` 下的文件受沙箱保护，不要靠删文件。
- Excel 的 `ActivePrinter` 在这台中文系统上是「`<队列名> 在 Ne01: 上`」，**不能赋值**
  （连赋当前值都报「不能设置类 Application 的 ActivePrinter 属性」）。所以
  `print_workbook()` 只在队列名不在这个字符串里时才试着切，且失败只记 stderr——Excel
  按名字找队列、按队列当前端口出纸，端口被 PrinterLocator 换掉也不影响。

## 「已完成 / 逾期」的口径（2026-09-16 修）

用户反馈陈灿的任务「珑悦湾新模型处理」在网页里已完成，汇总却把它算成逾期。查下来不是
查询写错，而是**这台机器上「完成」和 Kanboard 的 is_active 不是一回事**：

- 每个项目的列都是 `待办 / 预备 / 进行中 / 完成`；2026-09-16 全库 11 个任务**全部**
  `is_active=1`，`is_active=0` 的一个都没有——没人用「关闭任务」这个动作，做完就是拖到
  「完成」列。
- Kanboard 自己只在 `TaskModel::close()` 里把 `is_active` 置 0 并写 `date_completed`，
  所以只认 `is_active` 的报表会把「完成」列里的任务一直当进行中、还判定为逾期。

统一口径放在 `Service/TaskScope.php`，所有计数查询都必须用它：

| 方法 | 含义 |
| --- | --- |
| `openCondition($pdo,'t')` | `t.is_active=1 AND t.column_id NOT IN (完成列)`，替代裸 `is_active=1` |
| `doneCondition($pdo,'t')` | `(t.is_active=0 OR t.column_id IN (完成列))`，替代裸 `is_active=0` |
| `finishedAt($pdo,'t')` | 完成时间：`is_active=0` 用 `date_completed`，否则用进列的 `date_moved` |
| `isDone($task,$ids)` | 单行判断，给任务详情这类非 SQL 场合用 |

完成列按列名匹配（大小写不敏感）：`完成 / 已完成 / 已结束 / 结束 / 关闭 / 已关闭 / 归档 /
交付 / done / finished / closed / complete / completed / archive`，改这个名单就改
`TaskScope::DONE_TITLES`。已接入的服务：`DailyOverviewService`、`ProjectListService`、
`ProjectStatusService`、`UserStatusService`、`TaskDetailService`、`PortfolioService`、
`QueueService`（每天 09:00 的到期提醒）。任务的「今日新增」按 `date_creation` 算，不再
要求还处于进行中；「今日完成」用 `finishedAt` 落在今天判断。

逾期边界保持和 Kanboard 一致：`getOverdueTasksQuery()` 用的是 `is_active=1 AND date_due
<= time()`，所以**当天到期当天就算逾期**是 Kanboard 自己的口径，插件没有跟着改。

验证：`dingtalk:project-list` 总体从「进行中 11｜已完成 0｜逾期 5」变成
「进行中 10｜已完成 1｜逾期 4」；`dingtalk:project-status 佛山顺控珑悦湾` 显示
「进行中 1｜已完成 1｜逾期 0」；`dingtalk:task-status 3` 显示「状态：已完成｜看板列：完成」。

## 报销助手「预览」（2026-09-16 新增）

确认页（详情确认）的按钮变成 `预览 ｜ 打印 ｜ 暂不打印 ｜ 取消`。点「预览」返回一条带链接的
消息，点开就是打印预览 PDF：**第 1 页是 Excel 自己导出的单据**（和打印出来的那份完全一致），
后面按实际打印的排布拼上发票（每张 A4 两张，边距 8mm、间距 6mm；**只有一张时也只占上半页**）。
预览**不保存单据、不打印**，
会话保持打开，看完还能接着选打印或暂不打印。

- 入口：`dingtalk:reimbursement-preview <staff_id>`，服务侧 `ReimbursementService::preview()`。
  Excel 只能在桌面会话里跑，所以 SYSTEM 侧先写 `data/reimbursement/print-queue/preview-<staff>.request`
  （JSON `{"command":"dingtalk:reimbursement-preview","argument":"<staff>"}`），`schtasks /run
  DingTalkKanboardPrint` 唤醒 worker，worker 带 `DINGTALK_PRINT_WORKER=1` 回来执行同一命令。
  `print-worker.py` 的 `ALLOWED_COMMANDS` 里已加这个命令。
- PDF 由 `ReimbursementPrint.py --session <staff> --pdf <out>` 生成：`load_session()` 读
  **还没保存的草稿**（不是 dingtalk_reimbursement_forms），`fill_workbook(..., pdf_path=...)`
  在 SaveAs 之后调用 `book.ExportAsFixedFormat(0, pdf)`，`compose_preview()` 用 pymupdf 把
  发票页拼上去。没有发票时就只有单据页。
- 文件落在站点根目录 `D:\Apache24\htdocs\kanboard\preview-export\`，文件名
  `reimbursement-preview-<32 位随机 token>.pdf`，链接是 `{public_url}/preview-export/<file>`；
  `.htaccess` 只重写不存在的路径，所以真实文件直接由 Apache 发出。和发票台账导出一样靠 token
  保护，7 天后 `prunePreviews()` 清理。
- 临时产物（填好的 xlsx 和 Excel 导出的 pdf）放在 `data/reimbursement/preview/`，测试完记得清。
- 回归脚本：`D:\Apache24\setup-packages\reimbursement-preview-test.py`，跑真实向导 → 传一张
  生成的发票 → 分别走 worker 直连和「预览」按钮队列两条路，下载链接校验 `%PDF` 头和页数
  （1 张发票时应当 2 页），跑完打印清理 SQL。

## 员工报销单（2026-09-16 新增）

`READY_TYPES` 从 `['expense']` 变成 `['expense', 'employee']`，第二种单据类型上线。它和
费用报销单共用同一套状态机、同一份 Excel 模板、同一套保存/打印/预览代码，只有两处不同：

**1. 表头换字。** 模板里的标题是共享字符串 `费\xa0用\xa0报\xa0销\xa0单`——**每个字之间
夹的是不换行空格 U+00A0**，所以按普通文本搜「费用报销单」在单元格里是搜不到的（我第一遍就
栽在这：openpyxl 遍历、xlsx 解包搜 `报销单` 都查不到，最后是把 `sharedStrings.xml` 全打印
出来才看见）。`ReimbursementPrint.retitle_workbook()` 的做法是：把模板整张表的值去掉所有
空白再和 `费用报销单` 比对，命中后按原样用同一个分隔符拼出 `员\xa0工\xa0报\xa0销\xa0单`。
**必须在 `SaveAs` 之前改**，否则存下来的审计用 xlsx 还是旧表头（PDF 会新、xlsx 会旧）。

**2. 附件排版。** 费用报销单收的是税务发票，按两栏排（`layout="slots"`，单张只占上半页）；
员工报销单收的是各式单据/截图，改成 `layout="full-width"`：

- 每张单据**独占一页**（`invoice_pages()` 一张一页，而不是两张一页）；
- **最长边对齐 A4 可打印宽度**（595.276 - 2×8mm = 550pt），顶部对齐、水平居中；
- 只有"按宽度缩放后高度超过可打印高度"时才回退成整页适配。
- 实测：1600×900 的付款截图 → 550×309pt（占满宽度）；1240×1754 的竖版收据 → 389×550pt
  （它的最长边是高度，所以是高度对齐 550pt）。**竖版单据会比"整页适配"小**，这是按需求
  原文实现的；如果希望竖版改成铺满页高，改 `PrintService.print_image_pages` 里
  `layout == "full-width"` 那几行即可。

- 预览侧 `compose_preview(layout=...)` 必须和打印侧同步，两边都在
  `FORM_LAYOUTS = {"expense": "slots", "employee": "full-width"}` 里取值。
- 措辞：员工报销单的第三步叫「单据」，正文写着"发票、收据、付款截图、订单截图都行"，按钮
  显示「单据完成／无单据」，但**点下去发的命令仍是 `发票完成`／`无发票`**（状态机词汇不变）。
- 回归脚本：`D:\Apache24\setup-packages\employee-reimbursement-test.py`（20 项断言：菜单、
  措辞、表头换字、3 页结构、两张附件的尺寸与对齐）。脚本每次用带时间戳的 staff id，否则上
  一次留下的会话会让向导走"继续填写"分支，测试就会假失败。

## 财务侧：留档 + 核对闭环（2026-09-28 新增）

报销单的财务闭环，数据全在独立的 `data\finance.sqlite`（主键就是 `BX` 单号）：

| 时机 | 谁触发 | 结果 |
| --- | --- | --- |
| 保存单据（打印或暂不打印） | `ReimbursementService::saveForm()` | `archiveForm($id,'hold')`：按月归档 + 发票原件 BLOB + 明细入库；**不进队列** |
| 打印成功 | `ReimbursementService::printRow()` | `archiveForm($id,'print')` + `submit($code)`：`ocr/notify/verify` 置 pending，写 archived/submitted 事件 |
| 补打同一张 | 同上 | 队列状态原样返回，只更新 printed_at：**同一单号只提醒一次** |
| 后台 OCR | 桥接的 `finance_worker` 线程每 10 秒调 `dingtalk:finance-sync --limit 1` | `InvoiceService::extract()` 识别（不写员工台账）→ 写发票行 + `ocr_records_json` → 给每个财务接收人私聊提醒 |
| 财务核对 | 单聊 `核对报销` → 点姓名 → 查看细则 → `核对完成` | 该人所有 pending 单批量 `verified`，并私聊员工「单号+项目+金额+科目摘要」 |

- 归档目录 `data\reimbursement\archive\<YYYY-MM>\<code>\`，period 取**保存月份**（北京时区）；
  文件用 `link()` 硬链接（失败回退 `copy()`），另写 `manifest.json`。原件同时进
  `finance_invoices.content`，并记 sha256/大小 —— 库和磁盘互为备份。
- OCR 失败重试 3 次（`ocr_attempts`），超过就 `ocr_status='error'` 并**照常提醒**，提醒里
  写明失败原因；一个 PDF 识别出多张发票时行里存第一条、全量进 `ocr_records_json`。
- 提醒的去重键 `finance:<code>:<接收人>:<段号>`，走现有 `dingtalk_notifications` 队列
  （`kind=user`），`DingTalkClient` 用 oToMessages/batchSend 私聊发出。
- 接收人 = Kanboard「财务」用户组里已绑定钉钉的成员 + `finance_staff_ids` 名单；
  `DINGTALK_FINANCE_RECIPIENTS` 环境变量可临时覆盖（冒烟测试用，别在正式环境设置）。
- 接收人优先级：`DINGTALK_FINANCE_RECIPIENTS`（env）> `finance_meta.override_recipients`
  （库里，后台 `finance_worker` 另起进程也看得到，冒烟测试必须用它，否则后台线程可能抢先
  处理测试单据、用真实接收人把测试提醒发出去）> `Config.local.php` 的 `finance_recipients`
  （**2026-09-28 起真机演练只发欧阳冕**，清成 `[]` 即恢复全组）> 财务组 + 名单。
  体检命令：`php cli dingtalk:finance-recipients`。
- 菜单可见性（只是显示，权限仍由 `FinanceService::permission()` fail closed 判）：
  「报销助手」的回复菜单在 `ReimbursementService::financeMenuLines()` 里给有权限的人加一段
  「财务专用」（核对报销 / 查看细则）；「帮助」在 `StreamBridge.build_help(include_finance=…)`
  里给同一个人群加一条 `核对报销`。判定字段是 `dingtalk:registration-status` 新增的
  `finance`（`RegistrationService::isFinance()`，Fail closed，查不出来就不列）。
- 权限在 PHP 里判（`FinanceService::permission()`，fail closed），桥接层不做门禁；核对流程
  只在单聊可用（群聊回「请在与我的单聊里使用」，避免金额外泄）。
- 队列只列 `verify_status='pending'` 的人，跨月保留并标出月份，本月在前；同名不同人会加
  `（ID 后四位）`，但点下去的 tap 文本仍是原始姓名。
- 水印：凭证在 `fill_workbook()` 里写 Excel 页眉右对齐 `&8<单号>`（草稿跳过）；发票汇总页
  在 `print_image_pages(corner_text=…)` 和 `compose_preview(corner_text=…)` 里预留
  `CORNER_BAND_MM=5` 的顶部空白带、右上角 7pt 单号，两边共用同一组常量。
- 回填：`dingtalk:finance-backfill`（默认 dry-run）把 `dingtalk_reimbursement_forms` 里的
  历史单归档为 `source=backfill`，**不提醒、不进队列、不跑 OCR**。
- 回归脚本：`reimbursement-finance-test.py`（全链路 + 水印 + 自清理）和
  `finance-bridge-test.py`（真实 `StreamBridge.process()` 的路由、权限、向导归属）。

## 报销台账网页（员工自查 + 财务核对，2026-09-28 新增）

Kanboard 里多了一个网页版台账，入口在右上角用户菜单：员工看到「我的报销」，
财务看到「报销台账」（同一路由 `/kanboard/reimbursements`）。**没有引入任何第三方系统**：
本机没有 Node/Docker/Git/Composer，而且外面的成品会带来第二套账号和第二份核对状态
（钉钉队列不知道网页那边核过了）。所以直接做成 Kanboard 插件页，复用现有 26 个账号、
`财务` 用户组和现有的 `finance.sqlite`。

| 层 | 位置 |
| --- | --- |
| 路由 / 菜单 / 助手注册 | `plugins\DingTalkNotifier\Plugin.php`（`reimbursements*` 五条路由 + `template:header:dropdown` 钩子 + `ledgerHelper`） |
| 控制器 | `Controller\ReimbursementLedgerController.php`（index / detail / invoice / verify / export） |
| 数据层 | `Service\ReimbursementLedgerService.php`（筛选、分页、CSV、权限、状态文案） |
| 模板 | `Template\reimbursement_ledger\{index,detail}.php`、`Template\header\ledger_dropdown.php`、`Asset\ledger.js` |

- 登录走 Kanboard 自己的中间件（未登录 302 到登录页）；权限判定 fail closed：
  `app-admin` 或属于 `Config.local.php` 的 `finance_group`（默认「财务」）或绑定的钉钉 id 在
  `finance_staff_ids` 里 → 财务视图，其余 → 只能看自己（按 `dingtalk_user_bindings` 把
  Kanboard 账号映射到 staff id）。员工视图**在 SQL 层就钉死 staff_id**，改 URL 也看不到别人的单。
- 数据源只有 `finance_submissions`（`hold`/`print`/`backfill` 都在里面），明细 `finance_items`，
  发票 `finance_invoices`。状态口径和 `FinanceService::verifyLabel()` 一致：
  `verified`=已核对（带核对人+时间）/`pending`=待核对/其它=未进队列。
- 筛选：月份（`period` 下拉，来自当前人范围）、状态、人员（只有财务，按月份范围列出提交人）；
  默认全部月份 + 全部状态，按 `created_at DESC` 排，每页 50。
- **核对共用一套逻辑**：`FinanceService::verifyCodes()` 是钉钉「核对完成」和网页勾选核对的
  唯一实现（`UPDATE … WHERE code=? AND verify_status='pending'` + `finance_events` 记
  `财务核对完成`／`财务核对完成（网页）` + 复用 `notifyEmployee()` 私聊员工），所以两边
  幂等、不重复记账、不重复通知。钉钉侧的 `verify()` 现在只是调它 + 自己那几句话。
- 导出两个 CSV（都按当前筛选、带 BOM）：`shape=forms` 一单一行，`shape=items` 一行一条明细；
  金额不带千分位，方便 Excel 求和。
- 发票原件由 `reimbursements/invoice/:invoice_id` 从 `finance_invoices.content` 内联下发，
  权限和列表一致；他人单据详情/原件返回 403，单号不存在返回 404 页。
- 已知边界：网页只读 + 核对，不新建/打印/重打/删除（那些仍只在钉钉里）；`finance_submissions`
  是唯一数据源，归档失败的单在网页上同样看不到。
- 验证方式（当时全绿）：临时账号走 HTTP 端到端——员工只看到自己的 3 张、他人详情/原件 403、
  非财务 POST 核对 403、未登录 302；财务看到全部 4 张、按人/月/状态筛选正确、勾选核对后
  `verify_status=verified` + 事件 + 员工私聊入队、重复核对提示已不在队列；分页 55 条分两页；
  钉钉侧回归 `finance-bridge-test.py` 22 项全过。测试数据全部清理（用户 26 / 绑定 25 /
  单据 12 恢复原值）。

## 「已打款」与 RuoYi「我的报销」（2026-09-29 新增）

RuoYi 的「财务管理」下现在有两页：**报销台账**（财务）和**我的报销**（员工自助，
`/finance/my`）。两条路都读同一个 Finance 库，写操作仍然全回 Kanboard。

- **已打款**是核对的下一步：`finance_submissions` 加 `paid_status` / `paid_at` /
  `paid_by_name` / `paid_by_staff_id`（DDL 在 `db\sqlserver\04-finance-paid-status.sql`）。
  状态只单向前进：`verify_status='verified' AND paid_status='none'` → `paid`，
  实现在 `FinanceService::markPaid()`，CLI 是 `dingtalk:finance-pay`。
  **打款不发钉钉消息**（财务内部动作），员工在「我的报销」里自己看到状态变「已打款」。
  别再给这一步加提醒——测试脚本里专门有一条断言盯着队列没有新增。
- **「我的报销」的范围钉在登录账号上**：RuoYi 用户名 → `dingtalk:finance-staff` →
  钉钉 staff id（RuoYi 侧缓存 10 分钟），`FinanceMyController` 每次请求强制
  `bo.setStaffId(...)`，详情 / 原件 / 补打还各过一次 `assertOwner()`。员工端**没有**
  核对、识别、人员筛选，只有查看明细、重新打印、导出。菜单和权限在
  `setup-packages\ruoyi-finance-menu.php`（员工角色拿 `finance:my:*`，财务拿 `finance:ledger:*`）。
- **导出只有一种形态**：一行一条明细，列固定成财务给的 16 列（日期 / 团队 / 项目 / 摘要 /
  报销金额 / 领款人 / 购买方 / 发票号 / 发票金额 / 开票日期 / 类目 / 发票种类 / 月份 /
  支付日期 / 科目 / 二级科目），台账和「我的报销」共用 `FinanceLedgerExportVo`。
  发票字段按整单贴到每条明细上、多张发票用「；」连接，发票金额取整单「价税合计」之和；
  类目 = 发票的项目名称（`item_names`）。改列顺序/标题就改那个 VO，两个页面自动跟着变。
- 回归：`setup-packages\ruoyi-finance-verify.php`（HTTP 闭环：范围、403、打款幂等、
  导出状态列）和 `setup-packages\ruoyi-ui-test.py`（真浏览器：员工登录进「我的报销」，
  断言没有识别/核对按钮、有查看/复制/重新打印）。两个脚本都会自己造临时账号和测试单，
  跑完删掉；**测试单一律用 `TEST-`/`WEB-PROBE-1` 这类假 staff id**，不要拿真人的钉钉 id
  建单，否则本人会收到真实提醒（2026-09-29 就踩过一次）。
