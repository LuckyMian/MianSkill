# 模块：报销与财务（Reimbursement & finance）

> 读我：改报销向导、单据类型、明细/科目、预览、财务核对、已打款、归档闭环、网页台账时。
> 归属技能：`figgo-erp-dev`。代码主体在 `Service/ReimbursementService.php`、
> `Service/FinanceService.php`、`Service/ReimbursementLedgerService.php`；
> 数据在 SQL Server（见 `modules/database.md`），打印在 `modules/printing.md`。

## 一条业务流水线

```text
报销助手向导（单选/多选/自由文本/附件）
  → 保存单据（打印 or 暂不打印）→ 归档（按月 + 原件 BLOB + 明细）
  → 打印成功才进财务队列（submit）
  → finance_worker 后台 OCR + 私聊提醒财务
  → 财务核对（钉钉向导 / 网页）→ 已打款 → 员工在「我的报销」看到状态
```

三条不能破的规则：**打印成功才进队列**、**同一单号只提醒一次**、**暂不打印只留档**。

## 报销助手向导

状态机：`type → team → project → items → invoices → review → 已保存`。
一人一行（`dingtalk_reimbursement_sessions`），草稿是 JSON，TTL 30 分钟；完成的单进
`dingtalk_reimbursement_forms`，单号 `BX<YYYYMMDD>-<id>`，状态 `saved` / `pending_print`。

| 要点 | 说明 |
| --- | --- |
| 单据类型 | `READY_TYPES`：`expense`（费用报销单）、`employee`（员工报销单）已实现；另外 4 类只重发菜单 |
| 团队 | `TEAMS`：智慧数字 / 智慧城市 / 智慧感知 / 乐享 / 总经办。存在**草稿 JSON** 的 `draft['team']`，不占会话表的列 |
| 会话保存 | `saveSession()` 是**整列覆盖**：任何一处保存都要带上整份 draft，传 `[]` 会把团队洗掉（`stepProject` 踩过） |
| 明细解析 | `摘要 金额 4200 科目 办公费/设备维修`；金额按分存 |
| 科目 | 两级：`ReimbursementService::CATEGORIES`（8 个一级 / 47 个可选值），落库写「一级/二级」；只有一级的（招聘费）写一级本身 |
| 科目匹配 | `科目 12` 按扁平序号选；文本匹配先抹掉分隔符（`/ - 空格`）和空白，所以 `一级/二级`、`一级 二级` 都认 |
| 标记取值 | 明细行里「金额」「科目」取**最后一次**出现，摘要里带这两个词也不会误判 |
| 附件 | 图片/文件/richText 消息 → 桥接取 download code → 校验魔数（PDF/PNG/JPEG）→ 临时文件 → 环境变量给 PHP → 复制到 `data/reimbursement/<staff id>/`；关闭或取消会话时删除 |
| 保存后 | `预览` 只出 PDF 不保存；`打印` 真打；`暂不打印` 存为 `saved` |

补打入口：`打印 <单号>`、裸单号、`打印`（列最近 10 张，可点）。菜单最后一项是
**报销历史**（`报销历史`/`历史`/`报销记录`/`我的报销`，可带页码），由
`ReimbursementService::formHistory()` 渲染，`listForms()` 与 `history()` 共用，格式不会走偏。

### 补打必须能穿过打开着的向导

`step()` 在 switch 之前先认 `报销历史`、`打印 <单号>`/裸单号，以及**不在 `review` 步**时的
单个「打印」。线上踩过：会话停在 `type` 步，用户点历史单号（=发回 `打印 BX…`）被
`stepType()` 当成单据类型，只回「没有认出这个类型」。`review` 步的「打印」是「保存并打印这张」，
不能被列表抢走，所以那里单独放行。`matchReprintCode()` 的写法要和 `StreamBridge` 的
`reimbursement-print` 正则一起改。

### 员工报销单（`employee`）与费用报销单的差异

同一套状态机、模板、保存/打印/预览代码，只有两点不同：

1. **表头换字**：模板标题是共享字符串 `费\xa0用\xa0报\xa0销\xa0单`——**每个字之间夹的是
   不换行空格 U+00A0**，按普通文本搜「费用报销单」搜不到（openpyxl 遍历、解包 xlsx 搜
   `报销单` 都不行，要打印 `sharedStrings.xml` 才看见）。`ReimbursementPrint.retitle_workbook()`
   的做法是「去掉所有空白后比对」，命中后按原分隔符拼 `员\xa0工\xa0报\xa0销\xa0单`；
   **必须在 `SaveAs` 之前改**，否则审计 xlsx 还是旧表头（PDF 新、xlsx 旧）。
2. **附件排版**：费用单收税务发票，两栏（`layout="slots"`，单张只占上半页）；员工单收各种
   单据/截图，`layout="full-width"`：每张独占一页、最长边对齐 A4 可打印宽度
   （595.276 - 2×8mm = 550pt）、顶部对齐、水平居中；只有按宽度缩放后超高才回退整页适配。
   实测 1600×900 截图 → 550×309pt，1240×1754 竖版收据 → 389×550pt（竖版会比整页适配小，
   这是按需求原文实现的）。要改成竖版铺满页高，动 `PrintService.print_image_pages` 里
   `layout == "full-width"` 那几行。

措辞：员工单第三步叫「单据」，按钮显示「单据完成／无单据」，但**发出去的命令仍是**
`发票完成`/`无发票`（状态机词汇不变）。打印与预览的 `FORM_LAYOUTS = {"expense": "slots",
"employee": "full-width"}` 必须同步。

## 预览（不保存、不打印）

详情确认页按钮：`预览 ｜ 打印 ｜ 暂不打印 ｜ 取消`。入口
`dingtalk:reimbursement-preview <staff>` → `ReimbursementService::preview()`。

- Excel 只能在桌面会话跑：SYSTEM 侧写
  `data/reimbursement/print-queue/preview-<staff>.request`（JSON
  `{"command":"dingtalk:reimbursement-preview","argument":"<staff>"}`）→ `schtasks /run
  DingTalkKanboardPrint` → worker 带 `DINGTALK_PRINT_WORKER=1` 回来执行同一命令。
- PDF 由 `ReimbursementPrint.py --session <staff> --pdf <out>` 生成：`load_session()` 读
  **未保存的草稿**，`fill_workbook(..., pdf_path=...)` 在 SaveAs 后
  `book.ExportAsFixedFormat(0, pdf)`，`compose_preview()` 用 pymupdf 拼发票页。
- 产物落 `D:\Apache24\htdocs\kanboard\preview-export\`，文件名带 32 位随机 token，7 天后
  `prunePreviews()` 清理。临时 xlsx/pdf 在 `data/reimbursement/preview/`，测试完记得清。

## 财务闭环

| 时机 | 触发 | 结果 |
| --- | --- | --- |
| 保存单据（打印或暂不打印） | `ReimbursementService::saveForm()` | `archiveForm($id,'hold')`：按月归档 + 原件 BLOB + 明细入库，**不进队列** |
| 打印成功 | `ReimbursementService::printRow()` | `archiveForm($id,'print')` + `submit($code)`：ocr/notify/verify 置 pending，写 archived/submitted 事件 |
| 补打同一张 | 同上 | 队列状态原样返回，只更新 `printed_at`：同一单号只提醒一次 |
| 后台 OCR | `finance_worker` 每 10 秒 `dingtalk:finance-sync --limit 1` | `InvoiceService::extract()`（**不写员工台账**）→ 写发票行 + `ocr_records_json` → 私聊提醒每个接收人 |
| 财务核对 | 单聊 `核对报销` → 点姓名 → 查看细则 → `核对完成` | 该人所有 pending 单批量 `verified`，并私聊员工「单号+项目+金额+科目摘要」 |
| 已打款 | `dingtalk:finance-pay <code…>` / 网页按钮 | 仅 `verified` 且 `paid_status='none'` → `paid`，记 `finance_events(event='paid')`，**不发钉钉消息** |

- 归档目录 `data\reimbursement\archive\<YYYY-MM>\<code>\`，period 取**保存月份**（北京时区）；
  文件用 `link()` 硬链接（失败回退 `copy()`），另写 `manifest.json`；原件同时进
  `finance_invoices.content` 并记 sha256/大小——库和磁盘互为备份。
- OCR 失败重试 3 次（`ocr_attempts`），超过置 `ocr_status='error'` 并**照常提醒**，提醒里写明
  失败原因；一个 PDF 多张发票时行里存第一条、全量进 `ocr_records_json`。
- 提醒去重键 `finance:<code>:<接收人>:<段号>`，走 `dingtalk_notifications`（`kind=user`），
  私聊 batchSend 投递。
- 接收人优先级：`DINGTALK_FINANCE_RECIPIENTS`（env）> `finance_meta.override_recipients`
  （库里——后台 `finance_worker` 是另一个进程，看不到测试环境变量，冒烟测试**必须**用这一层）
  > `Config.local.php` 的 `finance_recipients`（2026-09-28 起只指向欧阳冕，清成 `[]` 恢复全组）
  > 财务组 + `finance_staff_ids`。体检：`php cli dingtalk:finance-recipients`。
- **权限 fail closed**，判定只在 `FinanceService::permission()`；菜单可见性
  （`ReimbursementService::financeMenuLines()`、`StreamBridge.build_help(include_finance=…)`）
  只是显示，两处都要给同一个人群加，但都不能当权限。核对流程**只允许单聊**（群里回
  「请在与我的单聊里使用」，避免金额外泄）。
- 队列只列 `verify_status='pending'`，跨月保留并标月份，本月在前；同名不同人加「（ID 后四位）」，
  但 tap 文本仍是原始姓名。
- 水印：凭证在 `fill_workbook()` 写 Excel 页眉右对齐 `&8<单号>`（草稿跳过）；发票汇总页在
  `print_image_pages(corner_text=…)` 和 `compose_preview(corner_text=…)` 预留
  `CORNER_BAND_MM=5` 顶部空白带、右上角 7pt 单号，两边共用常量，**打印和预览必须同时改**。
- 回填：`dingtalk:finance-backfill`（默认 dry-run）把历史单归档为 `source=backfill`，
  不提醒、不进队列、不跑 OCR。

## 财务核对向导

镜像结构：开着时会话拥有该财务成员的所有**核对词**（`核对报销 <姓名>`、`查看细则 <单号>`、
`核对完成`、`返回`、`取消`），其余消息交还命令目录（见 `modules/dingtalk-bot.md`）。
`checkStart()` 在队列为空时不建会话，避免空向导占用户 30 分钟。

## 网页台账（Kanboard 页面）

入口在右上角用户菜单：员工看「我的报销」，财务看「报销台账」，同一路由
`/kanboard/reimbursements`。**没有引入第三方系统**——本机没有 Node/Docker/Composer，
外部成品会带来第二套账号和第二份核对状态。

| 层 | 位置 |
| --- | --- |
| 路由 / 菜单 / 助手 | `Plugin.php`（`reimbursements*` 五条路由 + `template:header:dropdown` + `ledgerHelper`） |
| 控制器 | `Controller\ReimbursementLedgerController.php`（index / detail / invoice / verify / export） |
| 数据 | `Service\ReimbursementLedgerService.php`（筛选、分页、CSV、权限、状态文案） |
| 模板 | `Template\reimbursement_ledger\{index,detail}.php`、`Template\header\ledger_dropdown.php`、`Asset\ledger.js` |

- 权限 fail closed：`app-admin` 或 `finance_group`（默认「财务」）或绑定的钉钉 id 在
  `finance_staff_ids` → 财务视图；其余只能看自己（按 `dingtalk_user_bindings` 映射）。
  员工视图**在 SQL 层就钉死 staff_id**，改 URL 看不到别人的单。
- 数据源只有 `finance_submissions`（`hold`/`print`/`backfill` 都在）；明细 `finance_items`，
  发票 `finance_invoices`。状态口径与 `FinanceService::verifyLabel()` 一致。
- 筛选：月份 / 状态 / 人员（仅财务），默认全部，`created_at DESC`，每页 50。
- **核对只实现一次**：`FinanceService::verifyCodes()` 是钉钉「核对完成」和网页勾选核对的唯一实现
  （`UPDATE … WHERE code=? AND verify_status='pending'` + 事件 + `notifyEmployee()`），
  两边幂等、不重复记账、不重复通知。钉钉侧 `verify()` 只是调它。
- 导出两个 CSV（带 BOM、按当前筛选）：`shape=forms` 一单一行，`shape=items` 一行一条明细；
  金额不带千分位。
- 发票原件 `reimbursements/invoice/:invoice_id` 从 BLOB 内联下发，权限同列表；他人单据
  403，不存在 404。
- 已知边界：网页**只读 + 核对**，不新建/打印/重打/删除；归档失败的单网页同样看不到。

## 回归

| 脚本 | 覆盖 |
| --- | --- |
| `setup-packages\reimbursement-flow-test.py` | PHP 状态机（用 `TEST-` staff id，自带清理 SQL） |
| `setup-packages\reimbursement-bridge-test.py` | 真实 `StreamBridge.process()` 的路由 |
| `setup-packages\reimbursement-preview-test.py` | 真向导 → 传生成发票 → 两条预览路径 → 校验 `%PDF` 与页数 |
| `setup-packages\employee-reimbursement-test.py` | 员工单 20 项断言（菜单、措辞、U+00A0 表头、3 页结构、附件尺寸） |
| `setup-packages\reimbursement-finance-test.py` | 全链路 + 水印 + 自清理 |
| `setup-packages\finance-bridge-test.py` | 核对的真实路由、权限、向导归属 |
| `setup-packages\ruoyi-finance-verify.php` | RuoYi 面板第 2~4 步（HTTP） |

测试纪律：Staff id 一律 `TEST-*` / `WEB-PROBE-*`；预览类脚本要**带时间戳**的 staff id，
否则上次留下的会话会让向导走「继续填写」分支，测试假失败。

## 常见坑

- 团队放 draft 里却在保存会话时被 `[]` 覆盖 → 选完团队又回到上一步。
- 明细里「金额」「科目」取第一次而不是最后一次 → 摘要带关键词时解析错。
- 只写一级科目但下面有二级，或写重复二级名 → 必须回提示带正确写法，不能静默存。
- 打印前没做 `spooler_warning()` → 打印机离线也回「已打印」，财务还收到提醒（2026-09-28 才补上）。
- 给「已打款」加提醒 → 违反「打款不发消息」，测试里有断言盯着队列。
