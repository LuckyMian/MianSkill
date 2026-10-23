---
name: dingtalk-kanboard-bot
description: "Operate and maintain this machine's DingTalk-to-Kanboard bridge for RuoYi finance: StreamBridge routing, reimbursement and finance PHP services, invoice OCR, SQL Server Finance data, notification queues, web ledger, and desktop printing. Use for this deployment's bot changes or troubleshooting; do not apply it to unrelated Kanboard robots or RuoYi business modules."
metadata:
  short-description: Operate the DingTalk finance and reimbursement bridge
---

# DingTalk x Kanboard robot

This server runs a two-way DingTalk robot in front of Kanboard. Apache serves
Kanboard from `D:\Apache24` on port 801, PHP is `D:\php\php.exe`, and all DingTalk
code lives in `D:\Apache24\htdocs\kanboard\plugins\DingTalkNotifier`.

The canonical current-state overview is
`D:\Apache24\htdocs\kanboard\plugins\DingTalkNotifier\README.md`. Read it before
changing this deployment. The branch `codex/ruoyi-erp-cutover` retired Kanboard
project-management bot features; finance, reimbursement, invoice OCR, the shared
queue and RuoYi-facing CLI integrations remain active.

## Runtime layers

| Layer | Lives in | Runs as |
| --- | --- | --- |
| Inbound bot | `StreamBridge.py` | long-running Python process (`D:\Apache24\python\python.exe`), DingTalk Stream WSS |
| Intent + business state | `Console\*.php`, `Service\*Service.php` | `D:\php\php.exe cli dingtalk:*` |
| Finance state | SQL Server `Finance` via `FinanceDb.php` | Kanboard CLI, Apache PHP and RuoYi |
| Queue + bindings | `data\db.sqlite`, `QueueService.php`, `DingTalkClient.php` | Kanboard CLI and Apache PHP |
| OCR | `D:\Apache24\invoice-ocr\ocr_worker.py` + `C:\Users\Administrator\Documents\ChatGPT\发票助手` | Python 3.12 worker |
| Excel/printing | `print-worker.py`, `PrintService.py`, `ReimbursementPrint.py` | administrator interactive session |

The Python bridge only classifies an incoming message and shells out to Kanboard
CLI commands that print JSON arrays of finished message strings; it sends one
DingTalk message per array element. Outbound notifications bypass Python: PHP
queues them into SQLite and `dingtalk:run` delivers them.

Current active capabilities are reimbursement, invoice OCR/ledger, finance review,
finance notifications, web ledger, RuoYi "my reimbursement", and attendance/staff
mapping. Project queries, onboarding, task events, daily summaries, scheduler and
password commands are retained only as migration reference and are filtered or
unregistered in the live runtime.

## Invariants that are easy to break

- **Do not follow the old project-bot flow as if it were live.** The runtime filters
  project intents with `KANBOARD_PROJECT_FEATURES_ENABLED = False`, and `Plugin.php`
  has the related commands/listeners commented out. Finance, reimbursement, invoice,
  `dingtalk:run`, `registration-status`, `staff-map`, and `attendance-status` stay on.
- **Finance data is in SQL Server, not `data\finance.sqlite`.** `FinanceDb.php` is the
  connection entry; DDL lives in `D:\Apache24\db\sqlserver\01...06-*.sql`. Times are
  Beijing `datetime2(0)`, PHP uses Unix seconds, amounts are cents, and writes use
  `SET XACT_ABORT ON` with deadlock/lock-timeout retries.
- **Reimbursement state is also in SQL Server.** Both
  `dingtalk_reimbursement_sessions` and `dingtalk_reimbursement_forms` use `FinanceDb`.
  `data\db.sqlite` remains for inbound dedupe, bindings, the outbound queue, and the
  personal invoice ledger.
- Current `REQUIRE_MENTION` is `False`, so matching commands are accepted without a
  mention. Do not use the group/private mention flag as a substitute for command
  authorization. Reimbursement and finance review still require a private chat.
- **In a private (1:1) chat DingTalk never sets `is_in_at_list`** — 147 of 147 private
  messages in the live log arrived with `mentioned=False`, while every group message
  that mentioned the robot had `mentioned=True`. "私聊 @机器人" therefore shows up as the
  literal `@机器人` prefix inside the message text, which `MENTION_PREFIX` in
  `StreamBridge.py` detects (`at_prefix`). Never gate private-chat behaviour on the
  mention flag, and never gate it on "is private" alone either: that made every private
  message answer with the daily summary until 2026-09-16.
- **"Finished" is not `is_active=0` on this instance.** Kanboard only closes a task when
  someone uses the close action, and nobody here does: on 2026-09-16 all 11 tasks were
  still `is_active=1` and finished work simply sits in the last column, which every
  project names 完成 (待办 / 预备 / 进行中 / 完成). Reports that trusted `is_active`
  alone called that finished work 逾期. Every counting query in the plugin must go
  through `Service\TaskScope` (`openCondition` / `doneCondition` / `finishedAt` /
  `isDone`), which treats a done-titled column as finished as well.
- Routing is a priority chain, not a switch: `绑定账号` > `查询项目` > `查询任务` >
  keyword `项目情况` > generic `查询`. The generic `查询\s*(...)` pattern would also
  match `查询项目`, so only the order keeps them apart.
- **The live route order is reimbursement wizard -> finance wizard -> attachment OCR
  -> intent catalog.** A reimbursement wizard releases any active catalog command
  except the review-step actions `打印` and `暂不打印`; the finance wizard owns only
  its check words and must not swallow unrelated commands.
- Claim each `message_id` in `dingtalk_inbound_messages` before the first reply, or
  DingTalk retries produce duplicate replies.
- Keep each reply under roughly 12000 bytes of JSON-encoded content;
  `DingTalkClient::send` fails hard above 15000 with `MESSAGE_TOO_LONG`. Multi-part
  replies are normal, not an error.
- Source files are UTF-8 without BOM. Write them back with
  `[IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`.
- Never print or log `app_secret`, access tokens, or message content.
- `StreamBridge.py` is single-instance through an `msvcrt` lock on
  `data\dingtalk-stream.lock`. Stop the old process before starting a new one.
- **Restart the daemon after every change to the robot's logic** — reply text, config
  values, CLI commands, print scripts, Python: all of it. This is a standing user
  requirement, so a change is not finished until the bridge has been restarted and the
  new startup line is in the log. See "Restart the daemon".
- Anything that needs Excel (printing a 报销单, the 预览 PDF) can only run in the
  logged-on desktop session, so it goes through `data\reimbursement\print-queue` and the
  `DingTalkKanboardPrint` scheduled task. A new queued command must also be added to
  `ALLOWED_COMMANDS` in `print-worker.py` or the worker silently refuses it.
- **Invoice OCR has two codebases.** PHP invokes the ASCII-path worker, but parser rules
  live in the Chinese-path invoice project. Read
  `references/invoice-ocr.md` before changing extraction logic. A worker result is not
  enough: re-run the archived form and verify `dingtalk:finance-detail` or
  `finance_invoices`.
- **RuoYi delegates writes back to this deployment.** Its finance/project modules call
  the Kanboard CLI; do not reimplement verification, printing, OCR, archive or restore
  in Java. `kanboard.assign-notify` is still `true` in current RuoYi configs although
  `dingtalk:pm-task-assign` is unregistered; treat assignment notification as a known
  cutover risk until fixed and verified.

## RuoYi panel spacing (standing UI rule)

All panels on the RuoYi personnel / attendance screens use the **same 12px gap**.
This is a standing user requirement, not a one-off style choice:

- Page container: **no extra outer padding**. `AppMain` already supplies the
  shared 12px content inset; do not add `p-2` / `p-3` on the route view.
  Define `--panel-gap: 12px` on the page for the gaps inside it.
- The fixed-header offsets in `AppMain.vue` also carry the 12px gap:
  `117px` with the tags view and `82px` without it.
- Tree / content row: `el-row :gutter="12"`.
- Vertical panel stack (person board → people Gantt → any future panel):
  `content-main { gap: var(--panel-gap, 12px); }`.
- Panels and filter bars must not add their own `margin-bottom`; the shared gap is
  the only spacing between them.
- Do not mix 8px / 16px / 20px panel gaps on these screens. New panels must reuse
  `--panel-gap` and the existing page-shell layout.
- Reference implementation: `plus-ui/src/views/project/people/index.vue`,
  `plus-ui/src/views/project/people/PersonStatusBoard.vue`, and
  `plus-ui/src/assets/styles/components/_page-shell.scss` (`content-stack`).

## RuoYi project menu permissions (standing rule)

The 项目管理 menu tree must follow this role split:

- `sysadmin` / 管理员 and `project_manager` / 项目经理 see **all** menus under
  项目管理.
- `employee` / 员工 see only **项目列表**, **任务列表**, and **归档任务**.
- 项目详情 (`detail/:id`) is a hidden route (`visible = 1`), not a sidebar item.
  Employees keep this route plus the query / own-task permissions needed to open
  a project and update or archive their own tasks.

Identifiers:

| Item | Value |
| --- | --- |
| 项目管理 root menu | `2107000000000000001` |
| 员工 role | `1900000000000000001` (`employee`) |
| 项目经理 role | `1900000000000000002` (`project_manager`) |
| 管理员 role | `2104527031220105218` (`sysadmin`) |

- The project subtree currently has 27 nodes: 9 pages including the root, and
  18 functional permissions.
- 项目经理 gets the role automatically when the user is in the 项目经理 department
  or owns a project (`pm_project.owner_user_id`).
- Do not remove `project:task:edit`, `project:task:remove`, `project:task:query`,
  `project:column:list`, `project:node:query`, or `project:project:query` from the
  employee role; the backend still scopes task changes to the employee's own
  tasks.
- `PeopleController` / `PmPeopleServiceImpl.canViewStatusBoard()` accepts either
  the people-menu permission or `project_manager`, so managers can open 人员总览
  without being the project owner.
- Idempotent setup and rollback-safe reapplication live in
  `RuoYi-Vue-Plus/script/sql/sqlserver/ry_pm_v8.sql`.
- Verify through a real login rather than only reading `sys_role_menu`:
  `/system/menu/getRouters` should return the three employee items and the full
  manager tree. `D:\Apache24\setup-packages\ruoyi-menu-login-probe.php` creates
  temporary probe users and removes them afterwards.

## People AI analysis (RuoYi)

- Endpoint: `GET /project/people/ai-analysis`; `?refresh=true` bypasses the cache.
- `PeopleAiAnalysisService` calls DeepSeek's OpenAI-compatible endpoint with
  `deepseek-flash`. The server cache is 1 hour, and the browser panel also caches
  the result for 1 hour. This is a **low-frequency** request by user requirement.
- The analysis covers the whole board (not the department filter): personnel
  load, task clashes, overdue and idle people, plus short recommendations.
- The response is structured JSON (`sections[].items[]`); the UI renders short
  bullets. Do not return large paragraphs; keep each item under ~120 chars.
- Items must start with an emoji and use `**bold**`, `{red:...}`, and
  `{big:number}` for emphasis. The panel renders these as bold / red / 16px
  spans. Bump `PROMPT_VERSION` here and the localStorage cache key when changing
  this markup, otherwise the old plain-text analysis stays cached.
- `DEEPSEEK_API_KEY` lives only in `D:\RuoYi\run-ruoyi.cmd` (gitignored). Never
  commit it, log it, or paste it into this skill or a repository. `application.yml`
  only contains the `${DEEPSEEK_API_KEY:}` placeholder.
- Frontend: `plus-ui/src/views/project/people/AiAnalysisPanel.vue`.
- Layout: the AI panel sits in the department-tree footer (bottom-left); the
  people Gantt fills the remaining right-column height and both bottom edges align.

## Workflow

1. Read the plugin's canonical `README.md` for current runtime scope, commands and data
   ownership.
2. Read `references/interaction-logic.md` for detailed routing and queue mechanics;
   treat its project/onboarding/SQLite-era sections as legacy unless the current
   cutover notes say otherwise.
3. Read `references/change-recipes.md` for the files to touch, and
   `references/invoice-ocr.md` for any invoice extraction change.
4. Make the change and verify it through the CLI and the relevant regression tests.
5. **Restart the daemon** — always, whatever changed — and confirm the new startup
   line in `data\dingtalk-stream.log`. Do not report the work as done before this.

## Verify

```powershell
Set-Location D:\Apache24\htdocs\kanboard
D:\php\php.exe cli list
D:\php\php.exe cli dingtalk:project-status test
D:\php\php.exe cli dingtalk:run --limit 5
```

## Restart the daemon

The bridge runs as SYSTEM under the `run-bridge.cmd` supervisor (scheduled task
`DingTalkKanboardBridge`). Do not start `StreamBridge.py` by hand from an ordinary
shell: a second instance only hits the single-instance lock. Kill the running one and
the supervisor starts a fresh process within about a minute.

```powershell
Set-Location D:\Apache24\htdocs\kanboard

# 0) The supervisor refuses to start while ANY python.exe is running, so clear out
#    leftovers from one-off scripts first. Stop-Process works for your own processes;
#    the SYSTEM bridge needs taskkill.
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match 'python\.exe"?\s+-\s*$' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# 1) kill the bridge
$bridge = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like '*StreamBridge.py*' }
taskkill /F /PID $bridge.ProcessId

# If the sandbox refuses to launch taskkill ("Access is denied") or Stop-Process
# ("Access is denied" — the bridge is owned by SYSTEM), kill it through WMI instead:
Invoke-CimMethod -InputObject $bridge -MethodName Terminate   # ReturnValue 0 = killed

# 2) wait for the supervisor, then prove the new process came up
Start-Sleep -Seconds 80
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like '*StreamBridge.py*' } | Select-Object ProcessId
Get-Content data\dingtalk-stream.log -Tail 4 -Encoding UTF8
```

The log must show `DingTalk Stream bridge starting` at a time **later** than the last
edit, followed by `open connection` and `endpoint is`. The cheapest proof that the
running code is current is comparing the process start time with the file mtime:

```powershell
(Get-Process -Id <pid>).StartTime
(Get-Item plugins\DingTalkNotifier\StreamBridge.py).LastWriteTime
```

The process must have started **after** that mtime. (PHP, config and the
`*.py` helper scripts are read per call, so only the bridge needs the restart — but the
restart is required regardless, per the user's instruction.)

Logs: `D:\Apache24\htdocs\kanboard\data\dingtalk-stream.log` and
`D:\Apache24\logs\error_log`. PHP edits take effect on the next CLI call or HTTP
request. Edits to `Schema\Sqlite.php` are migrated automatically the next time the
plugin loads, so any `cli` call or web request applies them; `cli plugin:upgrade` only
installs plugin releases and is not configured on this host.

If writes or process execution are blocked by the sandbox, request approval to run
the command outside the sandbox instead of working around it.

## Current finance and OCR runbook

Re-run OCR for one archived invoice:

```powershell
Set-Location D:\Apache24\htdocs\kanboard
D:\php\php.exe cli dingtalk:finance-ocr BX20261021-10076 --seq=1
D:\php\php.exe cli dingtalk:finance-sync --limit 5
$env:DINGTALK_STAFF_ID='<staff id with finance permission>'
D:\php\php.exe cli dingtalk:finance-detail BX20261021-10076
```

Run parser and worker checks:

```powershell
Set-Location C:\Users\Administrator\Documents\ChatGPT\发票助手
.\.venv\Scripts\python.exe -m pytest -q
$env:INVOICE_NAMES='["invoice.pdf"]'
D:\Apache24\invoice-ocr\.venv\Scripts\python.exe `
  D:\Apache24\invoice-ocr\ocr_worker.py D:\path\to\invoice.pdf
```

Known text-layer cases that have caused real misreads:

- A 20-digit digital invoice number concatenated with the four-digit invoice-date year.
- Buyer/seller labels split into vertical single-character tokens.
- The name block reduced to `称:` and the tax-id line prefixed with `信息`.
- Left/right buyer-seller assignment lost when tiny y-coordinate differences reorder rows.

Do not "fix" these by guessing arbitrary digit lengths. Keep the 20-digit number rule
anchored to a following date and keep buyer/seller side inference limited to a plausible
single-page horizontal band.

## Legacy project-management knowledge

If explicitly asked to revive Kanboard project features, first read the cutover document
and verify that RuoYi no longer owns the data path. Re-enable only with matching work in:

- `KANBOARD_PROJECT_FEATURES_ENABLED` and `KANBOARD_PROJECT_INTENT_KEYS`.
- `Plugin.php` command registration and task event listeners.
- The RuoYi project notifier or replacement event source.

When project reports are revived, use `TaskScope` for finished/overdue semantics. On this
instance tasks are normally left active and moved to a column named `完成`, so
`is_active=0` alone is wrong.
