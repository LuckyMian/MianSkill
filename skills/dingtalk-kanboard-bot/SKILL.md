---
name: dingtalk-kanboard-bot
description: "Change the two-way DingTalk (钉钉) robot that fronts this machine's Kanboard instance: StreamBridge.py reply routing and keywords, the DingTalkNotifier PHP plugin commands and services, the SQLite notification queue, user binding, and onboarding. Use when adding or editing bot commands, reply text or formatting, task notifications, or DingTalk API behavior for this deployment."
metadata:
  short-description: Change the DingTalk bot on this Kanboard server
---

# DingTalk x Kanboard robot

This server runs a two-way DingTalk robot in front of Kanboard. Apache serves
Kanboard from `D:\Apache24` on port 801, PHP is `D:\php\php.exe`, and all DingTalk
code lives in `D:\Apache24\htdocs\kanboard\plugins\DingTalkNotifier`.

## Three layers

| Layer | Lives in | Runs as |
| --- | --- | --- |
| Inbound bot | `StreamBridge.py` | long-running Python process (`D:\Apache24\python\python.exe`), DingTalk Stream WSS |
| Intent + rendering | `Console\*.php`, `Service\*Service.php` | `D:\php\php.exe cli dingtalk:*` |
| State + delivery | `data\db.sqlite`, `QueueService.php`, `DingTalkClient.php` | Kanboard CLI and Apache PHP |

The Python bridge only classifies an incoming message and shells out to Kanboard
CLI commands that print JSON arrays of finished message strings; it sends one
DingTalk message per array element. Outbound task notifications bypass Python
entirely: Kanboard events are queued into SQLite by the plugin and sent by
`dingtalk:run`.

## Invariants that are easy to break

- Group messages are ignored unless the robot is mentioned. Private chat handles
  only `#新人入职` and the four job words, not the query commands.
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

## People AI analysis (RuoYi)

- Endpoint: `GET /project/people/ai-analysis`; `?refresh=true` bypasses the cache.
- `PeopleAiAnalysisService` calls DeepSeek's OpenAI-compatible endpoint with
  `deepseek-flash`. The server cache is 1 hour, and the browser panel also caches
  the result for 1 hour. This is a **low-frequency** request by user requirement.
- The analysis covers the whole board (not the department filter): personnel
  load, task clashes, overdue and idle people, plus short recommendations.
- The response is structured JSON (`sections[].items[]`); the UI renders short
  bullets. Do not return large paragraphs; keep each item under ~120 chars.
- `DEEPSEEK_API_KEY` lives only in `D:\RuoYi\run-ruoyi.cmd` (gitignored). Never
  commit it, log it, or paste it into this skill or a repository. `application.yml`
  only contains the `${DEEPSEEK_API_KEY:}` placeholder.
- Frontend: `plus-ui/src/views/project/people/AiAnalysisPanel.vue`.
- Layout: the AI panel sits in the department-tree footer (bottom-left); the
  people Gantt fills the remaining right-column height and both bottom edges align.

## Workflow

1. Read `references/interaction-logic.md` for current routing, commands, message
   formats, queue semantics, and database tables.
2. Read `references/change-recipes.md` for which files to touch, in what order, for
   the change being made.
3. Make the change and verify it through the CLI.
4. **Restart the daemon** — always, whatever changed — and confirm the new startup
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
