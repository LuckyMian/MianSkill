# Invoice OCR maintenance

Read this when changing invoice extraction, debugging missing or wrong invoice fields, or
re-running OCR for an archived reimbursement form.

## Code ownership

| Layer | Path |
| --- | --- |
| PHP bridge service | `D:\Apache24\htdocs\kanboard\plugins\DingTalkNotifier\Service\InvoiceService.php` |
| Finance integration | `D:\Apache24\htdocs\kanboard\plugins\DingTalkNotifier\Service\FinanceService.php` |
| ASCII-path worker | `D:\Apache24\invoice-ocr\ocr_worker.py` |
| Worker environment | `D:\Apache24\invoice-ocr\.venv` |
| Parser/application source | `C:\Users\Administrator\Documents\ChatGPT\发票助手` |
| Parser rules | `app\core\parser.py`, `app\core\patterns.py`, `app\core\loader.py` |
| Parser tests | `tests\test_parser.py`, `tests\test_pipeline.py` |

The Chinese project path never crosses PHP -> cmd -> Python as a shell argument. The worker
adds it to `sys.path` itself. Chat filenames travel through `INVOICE_NAMES` as
ASCII-escaped JSON.

## Processing contract

- Supported inputs: PDF, PNG, JPG/JPEG.
- Maximum attachment size: 20 MiB.
- `InvoiceService::extract()` performs recognition only and does not write the employee's
  personal invoice ledger.
- `InvoiceService::recognize()` calls `extract()` and writes personal ledger rows.
- The finance workflow calls `extract()` directly.
- Worker stdout must contain one ASCII-escaped JSON object; all library output is
  redirected to stderr.
- PHP allows up to 180 seconds internally; the Stream bridge allows 240 seconds.

Expected result shape:

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

Do not use real invoices as repository fixtures. Add either a synthetic `PageTokens` test
or a small generated image/PDF fixture without personal information.

## Extraction pipeline

1. `loader.load_pages()` checks the suffix.
2. PDFs first call `_pdf_text_layer()` via `pdfplumber`.
3. A page must contain enough text and the keyword `发票`; otherwise the whole PDF falls
   back to rendered OCR.
4. Text-layer words are merged into coordinate tokens. `WORD_MERGE_GAP` is measured in PDF
   user-space units.
5. Rendered OCR uses RapidOCR; `deskew_if_needed()` may run a second recognition pass.
6. `InvoiceParser.parse()` extracts fields with geometry and regular expressions.
7. `Pipeline._filter_pages()` drops non-invoice pages only for multi-page files.

## Field rules that matter

- `patterns.compact()` normalizes full-width characters, punctuation, currency symbols and
  whitespace before matching.
- Labels are matched after compaction, so `合 计` and `合计` are equivalent.
- Invoice numbers are normally 8-20 digits. Digital invoices use 20 digits.
- Invoice code is 10-12 digits and is absent on digital invoices.
- Tax IDs are 15, 18 or 20 alphanumeric characters. Only `I -> 1` and `O -> 0` are
  corrected, and only when the corrected value becomes valid.
- Invoice dates accept Chinese `年/月/日`, slash, hyphen and dot separators.
- Buyer and seller may be horizontally side-by-side or vertically stacked.
- Amounts are kept as normalized two-decimal strings; finance writes cents separately.

## Real text-layer failures and current guards

### Number glued to date

Observed token:

```text
开票日期:发票号码:264270000007378439442026年10月21日
```

The 20-digit invoice number is immediately followed by the four-digit year. The generic
number regex cannot match because the combined run is 24 digits. The parser first searches
for a normally bounded number, then uses a date-anchored 20-digit rule:

```text
^(\d{20})(?=\d{4}\s*(?:年|[-/.]))
```

Do not shorten arbitrary numeric runs without the date anchor; tax IDs and unrelated
numbers would become false positives.

### Vertical party labels and collapsed names

Observed tokens:

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

No token contains the complete `购买方` or `销售方`, and the name row may start with `称:`.
The parser therefore accepts the collapsed name label.

### Tax ID prefixed by "信息"

Observed form:

```text
信息统一社会信用代码/纳税人识别号: 91430104MA4L4WNJ4E
```

Tax labels may be embedded after a short prefix. `strip_embedded_label()` locates the tax
label inside the token and parses the value after it.

### Buyer/seller side assignment

When the complete party anchors are missing:

- Select a plausible horizontal band; do not infer left/right across the whole page.
- If candidates exist on both sides of the page midpoint, left is buyer and right is seller.
- If the layout is vertically stacked, fall back to reading order.

Y coordinates can differ by a fraction of a point. Do not sort by `(cy, x0)` alone for a
side-by-side layout, because tiny y jitter can put the right-hand seller first.

## Regression workflow

Run parser tests:

```powershell
Set-Location C:\Users\Administrator\Documents\ChatGPT\发票助手
.\.venv\Scripts\python.exe -m pytest -q tests\test_parser.py
```

Run the full app suite:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
```

Run the deployed worker against the archived file:

```powershell
$env:INVOICE_NAMES='["invoice.pdf"]'
D:\Apache24\invoice-ocr\.venv\Scripts\python.exe `
  D:\Apache24\invoice-ocr\ocr_worker.py `
  D:\Apache24\htdocs\kanboard\data\reimbursement\archive\YYYY-MM\BX...\invoice.pdf
```

Only inspect the fields relevant to the bug; do not paste the full extracted invoice into
logs or chat.

## Re-run an existing form

Queue one invoice and let the finance worker process it:

```powershell
Set-Location D:\Apache24\htdocs\kanboard
D:\php\php.exe cli dingtalk:finance-ocr BX20261021-10076 --seq=1
D:\php\php.exe cli dingtalk:finance-sync --limit 5
```

Verify the persisted row, not just the worker:

```powershell
$env:DINGTALK_STAFF_ID='<staff id with finance permission>'
D:\php\php.exe cli dingtalk:finance-detail BX20261021-10076
```

If a form's spreadsheet still contains old values, the spreadsheet is an archived artifact
and is not automatically rewritten by invoice OCR. OCR updates the Finance database fields;
regenerate or reprint the document only when the user asks for a corrected artifact.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Worker returns null | Python path, project path, missing modules, stderr hidden by PHP |
| Recognition timeout | Cold model load, number of PDF pages, 180s PHP loop, 240s bridge timeout |
| Everything found except number | inspect exact tokens around `发票号码`; check glued date |
| Everything found except parties | inspect vertical labels, `称:` token, `信息` prefix, page midpoint |
| Buyer/seller reversed | inspect x coordinates and y-jitter; side inference must use page midpoint |
| Amounts inconsistent | inspect `合计`, `价税合计`, item rows, and Otsu/OCR quality |
| Duplicate skipped | personal ledger uniqueness is `(staff_id, invoice_number)` |
| Existing form still empty | queue state, `finance-sync`, `finance_invoices`, `ocr_records_json` |

After any robot logic or worker-facing change, restart StreamBridge using the procedure in
`SKILL.md`.
