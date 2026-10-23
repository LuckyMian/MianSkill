# 模块：打印流水线（Excel / printing）

> 读我：改单据排版、出纸尺寸、打印机地址、预览 PDF，或排查「回复说打印了但纸没出来」时。
> 归属技能：`figgo-erp-dev`。业务侧见 `modules/reimbursement.md`。

## 为什么这条链路是异步的

桥接进程跑在 **SYSTEM**，那里 Excel 自动化不可用：`Workbooks.Open` 会挂住或拒绝文件（即使
是 `data\` 下的副本），而且唯一可见的打印机是「Microsoft Print to PDF」，`ActivePrinter`
又设不进去。所以凡是需要 Excel 的动作（打印报销单、生成预览 PDF、当日汇总）都必须交给
**已登录的管理员桌面会话**执行。

## 队列协议

```text
SYSTEM 侧（PHP）
  写 data\reimbursement\print-queue\<单号>.request   （或 preview-<staff>.request）
  JSON: {"command":"dingtalk:reimbursement-print","argument":"<单号>"}
  schtasks /run DingTalkKanboardPrint
        ↓
桌面会话（print-worker.cmd → print-worker.py）
  读 request → 校验 command 在白名单 → 执行 php cli <command>（带 DINGTALK_PRINT_WORKER=1）
  写 <单号>.result
        ↓
SYSTEM 侧把 result 里的回复转进聊天
```

- **新命令必须加进 `print-worker.py` 的 `ALLOWED_COMMANDS`**，否则 worker 静默拒绝，表现是
  「一直没反应」。
- worker 覆盖两个队列目录：报销单（`data\reimbursement\print-queue`）和当日汇总
  （`data\daily-summary\print-queue`，已随项目功能封存）。
- worker **不要**往 `data\bridge-console.log` 追加：那个文件被 StreamBridge 守护进程占着，
  cmd 会报「being used by another process」。
- 需要管理员桌面会话处于登录状态；没登录时回复要明说，单据保持已保存状态，不能谎报成功。

## Excel 模板（费用报销单）

模板：`C:\Users\Administrator\Desktop\费用报销单.xlsx`。

- 项目名称写 **AL5**；摘要 / 金额 / 科目 / 附单据数写 AG / AJ / AK / AL 的 7–10 行（多出的
  明细行要插入）。填好的副本存 `data/reimbursement/forms/<code>/`。
- 合并单元格只能用 `Range(...).MergeArea`——在这里对合并单元格直接 `ClearContents` 会失败。
- 项目为空要写 `=""` 公式，否则 `=AL5` 会打印出 `0`。
- 单据保存时发票文件从个人草稿目录**移到** `data/reimbursement/forms/<code>/`：打印在之后才发生，
  这些文件就是审计轨迹。
- 员工报销单的标题替换见 `modules/reimbursement.md`（U+00A0 不换行空格，必须在 `SaveAs` 前改）。

## 发票 / 单据图片排版

- 发票转**纯黑白**（Otsu 阈值）后每张 A4 放两张；**只有一张时仍只占一个槽位**，也就是留在
  A4 上半页（用户 2026-09-16 的要求）。打印侧是
  `PrintService.print_image_pages(..., slots_per_page=2)`，预览侧是
  `compose_preview()` 里的 `slots = max(INVOICES_PER_SHEET, len(sheet))`——**两边必须一起改**，
  否则预览和纸面不一致。
- 员工报销单改用 `layout="full-width"`：每张独占一页、最长边对齐 550pt 可打印宽度、顶部对齐、
  水平居中（竖版单据会比「整页适配」小，这是需求原文；要改成铺满页高就动
  `print_image_pages` 里 `layout == "full-width"` 那几行）。
- `_stretch_image` 通过 ctypes 的 DIB 区绘制：这个 pywin32 版本没有 `PyCBitmap.CreateBitmap`，
  而 DDB 在全页尺寸下 `StretchBlt` 到打印机 DC 会失败。
- 水印：发票汇总页顶部预留 `CORNER_BAND_MM=5` 空白带，右上角 7pt 单号；与凭证页眉
  （`fill_workbook()` 里的 `&8<单号>`）共用常量，打印与预览同时改。

## 省墨

- 通过 `PrintService.ink_saving_devmode()` 临时替换队列默认 DEVMODE：单色 + 单面，
  读回来应是 `Color=1`、`Duplex=1`、`PrintQuality=600`。
- **草稿质量设不进去**：在这个 Canon 驱动上请求 draft 会被重置回 600 dpi；N-up 同理（驱动私有）。
  省墨只能靠单色、单面和内容本身（纯文字 + 细表格线，不要大块底纹）。
- Canon PrintTicket 确实提供 `psk:DocumentBinding=Booklet`，但它强制双面 + 折页，等于把每页
  发票数量翻倍，不要用。

## 出纸确认（提交成功 ≠ 出纸）

`PrintService.spooler_warning()` 会盯 `check_seconds`（默认 4 秒）：任务仍留在队列就返回
「打印机没有取走这一页（设备报错/缺纸/脱机/任务报错），已打出 N 页」。

- 报销单：`printRow()` 收到 warning **不标已打印、不通知财务**，只回一条「没有真正打印出来 +
  怎么重打」。（2026-09-28 之前没有这个检查，打印机离线时机器人照样回「已打印」，财务还收到提醒。）
- `DailyOverviewPrint.py` 同一套（已封存）。

## 打印机地址自动定位（`PrinterLocator.py`）

每次真正出纸前重新定位，顺序：

1. `arp -a` 里按 **MAC** 命中（设备 MAC 来自原 Canon 端口名 `CNMFNP_B48C9DFFF2E8` →
   `B4-8C-9D-FF-F2-E8`）。
2. `printer-address.json` 里上次成功的地址。
3. `daily_print_addresses` 候选逐个探 9100，第一个应答的胜出。
4. 都不通就扫本机各 /24 的 9100，再用邻居表把 MAC 对上（DHCP 换到没人记过的地址时 ARP 里是空的）。

成功后写回状态文件；回复里带上实际地址与来源，例如「打印机地址 169.254.138.7（ARP），已自动把
打印端口切过去」。报销单打印也走这套（`--device-mac/--candidate/--state-file`，状态文件共用
`data/daily-summary/printer-address.json`）。

**换地址必须换端口**：这个 Windows 版本上 `Win32_TCPIPPrinterPort.HostAddress` 是只读属性
（`Set-CimInstance` 报 ReadOnly）。做法是按地址新建端口 `CanonIP_<地址>`，`Set-Printer
-PortName` 切过去，最后删掉不再被任何队列使用的旧 `CanonIP_*`。

设备侧可自动发现的通道都关着：SSDP(1900) 无应答、WS-Discovery(3702) 只回本机，所以
ARP + 候选地址是目前最可靠的路子。链路本地地址会漂，长期解法是给打印机固定 IP 或 DHCP 保留。

## Excel 的 ActivePrinter 怪癖

这台中文系统上 `Application.ActivePrinter` 的值是「`<队列名> 在 Ne01: 上`」，**不能赋值**
（连赋当前值都会报「不能设置类 Application 的 ActivePrinter 属性」）。所以
`print_workbook()` 只在队列名不在这个字符串里时才尝试切换，失败只记 stderr——Excel 按名字找
队列、按队列当前端口出纸，端口被 PrinterLocator 换掉也不影响。

## 卡住的打印任务

`Remove-PrintJob` 经常只把任务推进「Deleting, Printing, Retained」，重启 Spooler 也清不掉
（Retained 任务会被重新加载）。实测有效：

```powershell
Invoke-CimMethod -InputObject (Get-CimInstance Win32_Printer -Filter "Name='Canon MF650C Series UFR II'") -MethodName CancelAllJobs
```

`C:\Windows\System32\spool\PRINTERS` 下的文件受保护，**不要靠删文件解决**。

## 排查清单

| 现象 | 先查 |
| --- | --- |
| 回复「已打印」但没纸 | `spooler_warning` 是否真的执行；队列里任务状态码（8210 = 错误+正在打印+保留） |
| 打印报 `(1801, 'OpenPrinter', '打印机名无效')` | 默认打印机被换成了失效队列；`daily_print_printer` 应写死名字 |
| 端口指到旧 IP（如 172.16.1.38） | 打印机 DHCP 变了；跑一次 PrinterLocator，或 `Set-Printer -PortName` 切到新端口 |
| worker 完全不响应 | `ALLOWED_COMMANDS` 是否包含该命令；计划任务是否在跑；桌面会话是否登录 |
| 预览和纸面不一致 | `slots_per_page` / `compose_preview` 的 `slots` 是否同步 |
| Excel 打不开文件 | 当前进程是不是 SYSTEM；必须走桌面会话队列 |

只读诊断手段：`PrintService.list_printers()` / `printer_queue()`、
`Get-WinEvent -LogName Microsoft-Windows-PrintService/Operational`、`Get-CimInstance Win32_Printer`、
往 `设备IP:9100` 直接发一张纯文本测试页。
