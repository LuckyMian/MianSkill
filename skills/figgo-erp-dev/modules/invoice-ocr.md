# 模块：发票 OCR（Invoice OCR）

> 读我：改发票识别/字段提取、排查字段缺失或识别错、或要重跑某张已归档发票的 OCR 时。
> 归属技能：`figgo-erp-dev`。**这个功能有两套代码库**，改错地方等于没改。

## 代码归属

| 层 | 路径 |
| --- | --- |
| PHP 桥接服务 | `plugins\DingTalkNotifier\Service\InvoiceService.php` |
| 财务集成 | `plugins\DingTalkNotifier\Service\FinanceService.php` |
| ASCII 路径 worker | `D:\Apache24\invoice-ocr\ocr_worker.py` |
| worker 环境 | `D:\Apache24\invoice-ocr\.venv`（Python 3.12） |
| 解析器源码 | `C:\Users\Administrator\Documents\ChatGPT\发票助手` |
| 解析规则 | `app\core\parser.py`、`app\core\patterns.py`、`app\core\loader.py` |
| 解析测试 | `tests\test_parser.py`、`tests\test_pipeline.py` |

中文路径**从不**作为 shell 参数穿过 PHP → cmd → Python：worker 自己把该目录加进 `sys.path`；
聊天文件名走 `INVOICE_NAMES`，必须是 ASCII 转义 JSON。

## 处理契约

- 输入：PDF、PNG、JPG/JPEG；单个附件最大 20 MiB。
- `InvoiceService::extract()` **只识别**，不写员工个人台账；`recognize()` = `extract()` + 写台账；
  财务流程直接调 `extract()`。
- worker 的 stdout 只能是**一个 ASCII 转义 JSON 对象**；第三方库的输出全部重定向到 stderr
  （用 `pythonw.exe`，避免弹控制台）。
- 超时：PHP 内部 180 秒，桥接 240 秒。

结果形状：

```json
{
  "ok": true,
  "records": [
    {
      "file_name": "invoice.pdf",
      "invoice_kind": "增值税普通发票",
      "invoice_code": "",
      "invoice_number": "26427000000737843944",
      "invoice_date": "2026-10-21",
      "buyer_name": "湖南飞戈数字科技有限公司",
      "buyer_tax_id": "91430104MA4L4WNJ4E",
      "seller_name": "武汉京东金德贸易有限公司",
      "seller_tax_id": "9142011733356690XY",
      "item_names": "商品名称",
      "amount": "3875.96",
      "tax_amount": "503.87",
      "total_with_tax": "4379.83",
      "total_in_words": "肆仟叁佰柒拾玖圆捌角叁分",
      "status": "成功",
      "remark": ""
    }
  ]
}
```

**不要用真实发票当仓库夹具**：加合成的 `PageTokens` 测试，或生成一张不含个人信息的图片/PDF。

## 识别流水线

1. `loader.load_pages()` 按后缀分流。
2. PDF 先走 `_pdf_text_layer()`（pdfplumber）。
3. 页面文本够多且含「发票」才用文本层，否则整份 PDF 回退到渲染 OCR。
4. 文本层按坐标合并成 token；`WORD_MERGE_GAP` 以 PDF 用户单位为度量。
5. 渲染 OCR 用 RapidOCR；`deskew_if_needed()` 可能触发第二次识别。
6. `InvoiceParser.parse()` 用几何 + 正则提字段。
7. `Pipeline._filter_pages()` 只对多页文件丢弃非发票页。

## 字段规则

- `patterns.compact()` 先归一化全角字符、标点、货币符号和空白，再做匹配；所以 `合 计` 与 `合计`
  等价（标签在压缩后匹配）。
- 发票号码通常 8–20 位；**数电票 20 位**。
- 发票代码 10–12 位，数电票没有代码。
- 纳税人识别号 15 / 18 / 20 位字母数字；只纠正 `I→1`、`O→0`，且**只在纠正后变为合法值**时才改。
- 日期支持中文 `年/月/日`、斜杠、连字符、点号分隔。
- 购买方/销售方可能左右并排，也可能上下堆叠。
- 金额统一为两位小数字符串；财务侧另存分。

## 真实踩过的文本层问题与现有护栏

### 号码与日期粘连

实测 token：

```text
开票日期:发票号码:264270000007378439442026年10月21日
```

20 位号码紧跟 4 位年份，合并成 24 位数字，通用正则匹配不到。现在先找正常边界内的号码，再用
**日期锚定的 20 位规则**：

```text
^(\d{20})(?=\d{4}\s*(?:年|[-/.]))
```

不要在没有日期锚点的情况下随便截短数字串——税号和其他数字会变成误报。

### 竖排标签与名字被吞

实测 token：

```text
购
买
名
称: 湖南飞戈数字科技有限公司
方

销
售 名
称: 武汉京东金德贸易有限公司
方
```

没有任何 token 含完整的 `购买方` / `销售方`，名字行还可能以 `称:` 开头，所以解析器接受
「塌陷的名字标签」。

### 税号前缀「信息」

实测形式：`信息统一社会信用代码/纳税人识别号: 91430104MA4L4WNJ4E`。税号标签可能被短前缀
包住，`strip_embedded_label()` 在 token 内部定位标签、取标签后的值。

### 买卖双方左右归属

缺完整方锚点时：

- 选一个**合理的同一横向带**，不要在全页范围推左右。
- 候选同时出现在页面中线两侧 → 左买右卖。
- 上下堆叠布局 → 回退阅读顺序。

y 坐标可能只差零点几个点：左右并排时**不要**只按 `(cy, x0)` 排序，微小抖动会把右侧销售方排到
前面。

## 回归

```powershell
Set-Location C:\Users\Administrator\Documents\ChatGPT\发票助手
.\.venv\Scripts\python.exe -m pytest -q tests\test_parser.py
.\.venv\Scripts\python.exe -m pytest -q
```

用部署版 worker 跑归档文件：

```powershell
$env:INVOICE_NAMES='["invoice.pdf"]'
D:\Apache24\invoice-ocr\.venv\Scripts\python.exe `
  D:\Apache24\invoice-ocr\ocr_worker.py `
  D:\Apache24\htdocs\kanboard\data\reimbursement\archive\YYYY-MM\BX...\invoice.pdf
```

只检查与 bug 相关的字段，**不要把整张发票内容贴进日志或聊天**。

## 重跑某张已归档发票

```powershell
Set-Location D:\Apache24\htdocs\kanboard
D:\php\php.exe cli dingtalk:finance-ocr BX20261021-10076 --seq=1
D:\php\php.exe cli dingtalk:finance-sync --limit 5
$env:DINGTALK_STAFF_ID='<有财务权限的 staff id>'
D:\php\php.exe cli dingtalk:finance-detail BX20261021-10076
```

**worker 结果不等于落库结果**：必须回头看 `dingtalk:finance-detail` 或 `finance_invoices`。
归档的 xlsx 是历史产物，OCR 只更新 Finance 库字段，不会自动重写它；只有用户要求「出更正版」
时才重新生成/重打。

## 排错

| 现象 | 先查 |
| --- | --- |
| worker 返回 null | Python 路径、项目路径、缺模块、PHP 吞掉的 stderr |
| 识别超时 | 模型冷启动、PDF 页数、180s PHP 循环、240s 桥接超时 |
| 只缺号码 | `发票号码` 附近 token，是否与日期粘连 |
| 只缺买卖方 | 竖排标签、`称:` token、`信息` 前缀、页面中线 |
| 买卖方颠倒 | x 坐标与 y 抖动；左右推断必须按页面中线 |
| 金额不一致 | `合计`、`价税合计`、明细行、Otsu/OCR 质量 |
| 跳过重复 | 个人台账唯一键是 `(staff_id, invoice_number)` |
| 已归档单据仍为空 | 队列状态、`finance-sync`、`finance_invoices`、`ocr_records_json` |

任何影响机器人逻辑或 worker 面向接口的改动，都要按 `modules/dingtalk-bot.md` 重启桥接进程。
