# 模块：数据库（Database）

> 读我：建表 / 加列、写查询、改迁移、排查数据不一致或对不上账时。
> 归属技能：`figgo-erp-dev`。**先确认数据该落在哪个存储**，这是本模块最容易出错的地方。

## 三个存储

| 存储 | 位置 / 入口 | 存什么 | 谁在写 |
| --- | --- | --- | --- |
| SQL Server `Finance` | 本机实例，`Service/FinanceDb.php` | 财务单据、明细、发票原件（BLOB）、审计事件、核对会话、报销会话与表单 | Kanboard CLI、Apache PHP、RuoYi（`@DS("finance")`） |
| SQLite `data\db.sqlite` | 插件目录 | 入站去重、用户绑定、出站队列、每日汇总去重、个人发票台账、历史入职会话 | Kanboard 插件 |
| 磁盘归档 | `data\reimbursement\archive\<YYYY-MM>\<code>\` | 原件、`manifest.json`、填好的 xlsx | `ReimbursementService` |

口径：

- **财务与报销是 SQL Server**。`dingtalk_reimbursement_sessions` / `dingtalk_reimbursement_forms`
  也在 SQL Server；`data\db.sqlite` 里的同名表是 2026-09-29 之前的遗留，不再有新写入。
- `data\finance.sqlite` 自 2026-09-29 起**停写**，只留作回滚点，不要从它读业务数据。
- BLOB 与磁盘归档互为备份：`finance_invoices.content` 存原件，同时归档目录存文件并记 sha256。

## SQL Server `Finance`

连接与约定：

- 连接集中在 `Service/FinanceDb.php`（`sqlsrv:` DSN，密码来自 `RUOYI_DB_PASSWORD` 或
  `Config.local.php`）；时间转换只走 `ts()` / `unix()`。
- **DDL 在 `D:\Apache24\db\sqlserver\0N-*.sql`**（幂等、按序号执行），表结构**不在 PHP 里维护**；
  和 SQLite 的方言差异记在 `db\sqlserver\README.md`。
- 时间：北京时区 `datetime2(0)`；PHP 侧用 Unix 秒。
- 金额：**按分存**（`*_cents`），展示时才转元。
- 写：`SET XACT_ABORT ON`，带死锁 / 锁超时重试。
- 发票原件：流式单条写入，**别把整单的图一次读进内存**。

SQLite → SQL Server 的方言替换（改 SQL 时逐条对）：

| SQLite | SQL Server |
| --- | --- |
| `ON CONFLICT … DO UPDATE` | 拆成「先判后写」（`IF EXISTS … UPDATE ELSE INSERT`） |
| `LIMIT n` | `TOP n`；分页用 `OFFSET … FETCH NEXT` |
| `finance_meta.key` | 必须写 `[key]`（保留字） |
| 写 BLOB | `CONVERT(varbinary(max), ?, 2)` |
| 拿自增 id | `OUTPUT INSERTED.id` |

`dingtalk_reimbursement_forms.code` 是 `NOT NULL + UNIQUE`，所以**先插唯一占位串，再用
`OUTPUT INSERTED.id` 回填真实单号**。

### 表

| 表 | 用途 |
| --- | --- |
| `finance_submissions` | 一张单一行，主键 `code`（`BX…`）：period（YYYY-MM）、提交人、类型、项目、金额、`source`(print/hold/backfill)、`ocr_status`/`notify_status`/`verify_status`、`paid_status`/`paid_at`/`paid_by_*`、`archive_dir`、`workbook_path`、时间戳、核对人 |
| `finance_items` | 明细，`UNIQUE(code, seq)` |
| `finance_invoices` | 附件，`UNIQUE(code, seq)`：文件名 / 扩展名 / 大小 / sha256 / 归档路径 / 原件 BLOB / 全部 OCR 字段 / `ocr_records_json`（一 PDF 多票时留全量） |
| `finance_events` | 审计流水：archived / submitted / ocr_done / notified / verified / paid / employee_notified … |
| `finance_check_sessions` | 财务核对向导，一人一行，30 分钟 TTL |
| `finance_meta` | `schema_version`；也用于 `override_recipients`（冒烟测试改接收人） |
| `dingtalk_reimbursement_sessions` | 报销向导会话（draft JSON，30 分钟 TTL） |
| `dingtalk_reimbursement_forms` | 完成的报销单（code / payload / total / status） |

SQLite 侧：`dingtalk_notifications`、`dingtalk_reminder_runs`、`dingtalk_inbound_messages`、
`dingtalk_user_bindings`、`dingtalk_onboarding_sessions`、`dingtalk_invoice_records`
（个人发票台账，列与导出 CSV 一致）。

## 迁移

**Kanboard 插件 schema**（`Schema/Sqlite.php`，当前 version 8）：

- 加表/加列 = 写一个新的 `version_N` **并且**同一次编辑里 bump `VERSION`。
- `SchemaHandler::migrateSchema` 只在 `function_exists()` 为真时执行 `version_N`，但**无论如何
  都会记录新版本**。线上随时可能有人在「已 bump、还没写函数」的窗口里加载插件，于是迁移被
  永久跳过。所以：**同一次编辑写完两者**，DDL 必须幂等（`IF NOT EXISTS`），服务侧还要自愈
  （`InvoiceService::ensureTable` 那种）。
- 迁移自动发生：任意 `cli` 调用或网页请求都会加载插件；`cli plugin:upgrade` 是装插件发行包用的，
  这台机器没配，不要拿它当迁移命令。

**Finance 库没有插件迁移机制**：DDL 由 `0N-*.sql` + `FinanceDb` 幂等执行；后加的列用
`ensureColumn()`（PRAGMA 等价物 + `ALTER TABLE`）补。

## 体检与排查

```powershell
Set-Location D:\Apache24\htdocs\kanboard

# 单据与状态
# SELECT code, period, source, ocr_status, notify_status, verify_status, paid_status
#   FROM finance_submissions ORDER BY created_at DESC;
# 队列积压
# SELECT status, COUNT(*) FROM dingtalk_notifications GROUP BY status;
# 某单的审计轨迹
# SELECT event, actor_name, created_at FROM finance_events WHERE code='BX...' ORDER BY id;

D:\php\php.exe cli dingtalk:finance-recipients     # 提醒会发给谁、来源
D:\php\php.exe cli dingtalk:finance-backfill --dry-run
```

排查顺序：先看 `finance_submissions` 的状态列 → 再看 `finance_invoices` 的 OCR 字段 →
最后看归档目录和 BLOB 是否一致（sha256）。

## 备份与回滚

- 财务资产 = SQL Server `Finance` + 归档目录 + 原件 BLOB，三者要一起备份；只备份库会丢磁盘
  归档，只备份目录会丢事件流水。
- `data\finance.sqlite` 是切换前的回滚点，别删；回滚只在确认 SQL Server 侧数据完整后进行。
- 改 schema 前先导一份受影响表；`finance_submissions` 是网页台账、RuoYi、钉钉三处的唯一数据源，
  改坏会同时影响三端。

## 不要做

- 不要从 `data\finance.sqlite` 读业务数据，也不要重新往它写。
- 不要在 PHP 里用 `CREATE TABLE` 维护 Finance 表结构（走 `0N-*.sql`）。
- 不要在迁移里只 bump `VERSION` 而不写 `version_N` 函数。
- 不要把金额存成浮点或元；不要在 SQL 里就地格式化金额（展示层再做）。
- 不要在没有确认归档完整的情况下删 `finance_invoices` 或归档目录。
