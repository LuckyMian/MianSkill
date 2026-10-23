# Change recipes

> **Current authority (verified 2026-10-23):** the plugin's `README.md` defines the
> live cutover scope and data ownership. Finance and reimbursement state use SQL Server
> `Finance` through `Service/FinanceDb.php`; `data\db.sqlite` is limited to inbound
> dedupe, bindings, the outbound queue and the personal invoice ledger. Project-bot
> recipes below are legacy unless the cutover section explicitly restores them.

## Which files to touch

| Change | Files |
| --- | --- |
| New or changed query command | `Service\<Name>Service.php`, `Console\<Name>Command.php`, `Plugin.php`, `StreamBridge.py` |
| New multi-step wizard | `Service\<Name>Service.php` (state machine + texts), `Console\*Command.php`, `Plugin.php`, `Schema/Sqlite.php` (session table), `StreamBridge.py` routing |
| Printing a document | `PrintService.py` (GDI, DEVMODE, image pages), `ReimbursementPrint.py` (xlsx fill + Excel print), `Console\ReimbursementPrintCommand.php`, `StreamBridge.py` intent |
| New notification trigger | `Plugin.php` listener list, `Service/MessageBuilder.php` (`EVENTS` plus text) |
| Reply wording only | the owning `Service\*Service.php` |
| Keyword or routing only | `StreamBridge.py` regexes and the if/elif chain |
| New stored state | `Schema/Sqlite.php` (add `version_N`, bump `VERSION`); Kanboard applies it on the next plugin load, so any `cli` call or web request is enough |
| 报销的财务侧（归档 / 提醒 / 核对 / 水印） | `Service/FinanceDb.php`（新库 DDL），`Service/FinanceService.php`（状态机与文案），`Console/Finance*.php`，`Plugin.php`，`Service/ReimbursementService.php`（saveForm/printRow 两个挂钩），`StreamBridge.py`（意图、向导归属、`finance_worker` 线程），`ReimbursementPrint.py` + `PrintService.py`（水印），`Config.local.php` |
| Credentials, allow-list, groups, URL | `Config.local.php` |

`cli plugin:upgrade` takes no plugin name and only installs plugin *releases* from the
directory; this host is not configured for that (`Kanboard is not configured to
install plugins itself`). Plugin schema migrations are automatic.

## 改财务侧（SQL Server 的 Finance 库）

财务数据在**本机 SQL Server 的 `Finance` 库**（2026-09-29 从 `data\finance.sqlite` 切过来，
SQLite 已停写、只留作回滚点），**不走** `Schema/Sqlite.php`：

1. 建表/加字段改 `D:\Apache24\db\sqlserver\0N-*.sql`（幂等，按序号执行），
   `Service/FinanceDb.php` 只负责连接（`sqlsrv:` + `RUOYI_DB_PASSWORD`/Config.local.php）
   和 `ts()`/`unix()` 时间转换；表结构不在 PHP 里维护。
2. 和 SQLite 的方言差异记在 `db\sqlserver\README.md`：`ON CONFLICT` 要拆成
   「先判后写」、`LIMIT` → `TOP` / `OFFSET … FETCH NEXT`、`finance_meta.key` 要写 `[key]`、
   发票原件用 `CONVERT(varbinary(max), ?, 2)`、`dingtalk_reimbursement_forms.code` 是
   `NOT NULL + UNIQUE` 所以先插唯一占位串再用 `OUTPUT INSERTED.id` 回填。
3. RuoYi 面板（`D:\RuoYi\RuoYi-Vue-Plus` 的 `ruoyi-modules/ruoyi-finance`，独立 git 仓库）
   通过 `@DS("finance")` 读同一个库；**核对/打印/落单不在 Java 里重写**，
   一律调这里的 CLI：`dingtalk:finance-verify`、`dingtalk:reimbursement-print`、
   `dingtalk:reimbursement-web-save`（表单下拉走 `dingtalk:reimbursement-options`）。
   前端在 `D:\RuoYi\plus-ui`（`src/views/finance/{ledger,wizard}`），构建产物镜像到
   `D:\Apache24\htdocs\ruoyi`。
5. 状态流转全在 `FinanceService`：`archiveForm()` 负责归档和 `hold/print/backfill`
   三种来源的状态迁移，`submit()` 是「进队列」的幂等兜底，`sync()` 做 OCR + 提醒。
   改队列行为时记住三条不变的规则：**打印成功才进队列、同一单号只提醒一次、暂不打印
   只留档**。
6. 桥接层：新意图加在 `INTENTS`（`finance-check` 那几条后面），向导期间的文本由
   `dingtalk:finance-check-step` 处理（和报销助手一样，`finance_active()` 分支在
   `match_intent()` 之前）；OCR 提醒后台跑在 `finance_worker` 线程里，不要塞进
   `queue_worker`，一次识别十几秒会拖慢消息投递。
7. 水印：几何常量在 `ReimbursementPrint.py`（`CORNER_BAND_MM`/`CORNER_FONT_PT`），
   打印和预览必须同时改，否则屏幕和纸面不一致；凭证的页眉在 `fill_workbook()` 里写。
8. 验证：`php cli dingtalk:finance-backfill --dry-run`、`dingtalk:finance-sync`、
   `D:\Apache24\setup-packages\reimbursement-finance-test.py`、
   `finance-bridge-test.py`。冒烟测试想验证「真的入队」时用
   `DINGTALK_FINANCE_RECIPIENTS=<假 id>`，别把测试提醒推到真正的财务手机上。
9. 改完照样**重启桥接进程**（新意图、新线程、新文案都靠它生效）；
   切到 SQL Server 之后的回归脚本是 `setup-packages\finance-switch-verify.php`（Kanboard 闭环）
   与 `setup-packages\ruoyi-finance-verify.php`（RuoYi 面板第 2~4 步）。

接收人与菜单可见性是两件事，别混：

- **发给谁**由 `FinanceService::recipientPlan()` 决定，优先级
  env > `finance_meta.override_recipients` > `Config.local.php` 的 `finance_recipients`
  （2026-09-28 起真机演练只发欧阳冕）> 财务组 + 名单；冒烟测试必须用前两种（后台
  `finance_worker` 另起进程看不到测试的环境变量），体检用 `dingtalk:finance-recipients`。
- **谁能看到财务命令**由 `RegistrationService` 的 `finance` 字段决定，菜单两处：
  `ReimbursementService::financeMenuLines()`（报销助手菜单）和
  `StreamBridge.build_help(include_finance=…)`（帮助菜单）。两处都只是显示，访问控制仍然
  只在 `FinanceService::permission()` 里，改动菜单时别顺手放松权限。

边界：`FinanceService::permission()` 是 fail closed 的，不要为了图方便放开；核对流程只
允许单聊；发票原件进 BLOB 时是流式单条写入，别一次把整单的图都读进内存。

## Add a multi-step wizard

`Service/ReimbursementService.php` is the worked example: one row per DingTalk user in
a session table, a `step` column, a JSON draft, a 30-minute TTL, and one CLI command
per entry point (`-start`, `-step`, `-attach`, `-status`). Text from the user travels
in an environment variable rather than argv so Chinese survives, and the bridge asks
`-status` before routing to decide whether the wizard owns the message. Keep every
reply under the 12000-byte budget and render options as `dtmd://` tap links; the
bridge switches to markdown automatically when a reply contains one.

## Add a query command

Example: a command that answers `查询逾期 <project>`.

1. `Service/OverdueService.php` - `final class OverdueService extends Base` with
   `public function __construct($container, private array $config)`, exposing
   `buildMessages(string $search, ?int $now = null): array` that returns
   ready-to-send strings. Follow the existing `clean()` and `chunk()` helpers; never
   interpolate raw user input into a reply without cleaning it.
2. `Console/OverdueCommand.php` - extend `BaseCommand`, `setName('dingtalk:overdue')`,
   `addArgument('search', InputArgument::REQUIRED)`, and finish with
   `$output->writeln(json_encode($messages, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));`
3. `Plugin.php` - add the `use` statement and
   `$this->container['cli']->add(new OverdueCommand($this->container, $config));`
4. `StreamBridge.py` - add `def build_overdue(search)` that calls
   `php_output([str(KANBOARD_CLI), "dingtalk:overdue", search])` and validates that the
   JSON is a list of non-empty strings, add a regex beside the other match lines, and
   add a branch in the existing if/elif chain. Put specific intents before the
   generic `查询\s*(...)` branch or they will never be reached.
5. Verify, then restart the bridge.

## Change reply wording or formatting

- Text lives in the owning `Service`; `StreamBridge.py` only chooses markdown versus
  text and the message title.
- Keep the `[Kanboard]` prefix convention for robot-generated messages.
- Run titles through the existing `markdown()` helper when they go into a markdown
  link; it escapes `[`, `]`, `(`, `)`.
- Split long replies into array elements rather than one huge string, keeping each
  element under roughly 12000 bytes of JSON-encoded content.

## Add a task event notification

1. `Plugin.php`: add the event constant to the listener array.
2. `MessageBuilder::EVENTS`: add the display label. Events missing from this map
   produce no notice at all.
3. Extend the personal-notice condition
   (`in_array($eventName, ['task.create', 'task.assignee_change'], true)`) only if the
   new event should also private-message the assignee.
4. If the new event can repeat without a timestamp change, include the distinguishing
   field in the dedupe-key JSON, otherwise legitimate repeats collapse into one row.

## Change DingTalk API behavior

- Payload shape and message key: `DingTalkClient::send` (`msgKey`, `msgParam`,
  recipient fields for group versus personal sends).
- Token acquisition, caching, and the single transparent refresh: `accessToken`.
- Retry versus fail versus unknown classification: `classify`.
- Keep genuinely ambiguous outcomes as `unknown`. Blindly resending can post the same
  message twice to a user.

## Deploy and verify

1. `D:\php\php.exe cli list` shows the command, and `cli dingtalk:<cmd> ...` returns
   valid JSON.
2. `D:\php\php.exe cli dingtalk:run --limit 5` drains the queue without new failures.
3. Check the queue:
   `SELECT status, COUNT(*) FROM dingtalk_notifications GROUP BY status;`
4. **Restart the bridge — always, whatever changed** (standing user requirement, not
   just for Python edits; procedure in `SKILL.md` → "Restart the daemon"). Stop the old
   process with `taskkill /F /PID <pid>` and let the supervisor bring it back; the log
   `data\dingtalk-stream.log` should show the startup line with `keyword=项目情况`
   followed by `open connection` and `endpoint is`, timestamped after your last edit.
5. Send one real DingTalk message and confirm exactly one reply, which proves the
   inbound dedupe claim still works.

## Safety boundaries

- Treat `app_secret` in `Config.local.php` as a secret: do not print it, do not write
  it into the skill, logs, or chat.
- `#新人入职` creates real Kanboard users and returns a one-time password. Only change
  that flow when asked, and never re-send a generated password outside the private
  chat reply.
- Deleting rows from `dingtalk_notifications` or `dingtalk_user_bindings` changes what
  users see; confirm with the user before doing it.
- Do not add logging of message content, tokens, or credentials.
