---
name: gismap-helper
description: 处理并切片已下载的谷歌卫星地图：自动识别大图+坐标文件、GeoTIFF、z/x/y 瓦片目录、MBTiles，按经纬度精确对齐输出 XYZ、TMS、MBTiles 瓦片与离线预览页，并可导出整幅大图或 2x2、3x3、4x4 分幅。当用户要拼接、切片、切瓦片、分幅、裁剪、转格式或校准已下载的谷歌卫星影像/航拍底图，或要生成可离线浏览的瓦片底图时使用；不用于联网抓取或下载瓦片（本技能只处理已下载的数据），也不用于与瓦片产出无关的 GIS 数据加工。
---

# 谷歌卫星地图切片

全部操作由 `scripts/gismap.py` 完成，只依赖 Pillow。**先调用 `load_workspace_dependencies` 取内置 Python 路径，用该 `python.exe` 运行脚本，不要安装任何包。**

技能目录：`<工作区>/.dsh/skills/gismap-helper`。下文的 `gismap.py` 指 `<技能目录>/scripts/gismap.py`。

## 必须遵守的顺序

1. **先 `inspect`，再动手。** 它决定坐标系、范围来源和真实精度层级；跳过这步就给 `--bounds` 猜测值是所有错位的根源。
2. **切片用 `tile`，拼图/分幅用 `export`**，两者不要混用。
3. **结束时用 `verify` 校验**，再用 `present` 交付预览页与清单。

```bash
<py> gismap.py inspect <源> --json
<py> gismap.py tile    <源> -o <输出目录> [--scheme xyz,tms,mbtiles] [--dry-run]
<py> gismap.py export  <源> -o big.jpg [--split 2|3|4|2x3] [--scale 0.5]
<py> gismap.py verify  <输出目录或.mbtiles> --source <源> --json
```

## 第一步：识别输入

`inspect` 自动判定四类输入，并给出 `kind`、`crs`、`bounds`、`bounds_source`、`native_zoom`、`suggested`。

| `kind` | 来源 | 处理方式 |
|---|---|---|
| `image` | 单张大图，范围来自 `.tfw/.jgw/.pgw/.wld`、`.aux.xml`、GeoTIFF 内部标签或 `.map/.xml/.json` 侧车文件 | 直接 `tile` |
| `tiledir` | 现成的 `z/x/y` 目录 | 直接 `tile` 转格式/换方案，或 `export` 拼图 |
| `mbtiles` | MBTiles 单文件 | 同上 |
| 失败 | 找不到坐标信息 | 向用户索取范围，用 `--bounds 西,南,东,北` |

- `bounds_source` 为空却 `crs` 有值，说明只认出了坐标系没认出范围 —— 必须补 `--bounds`。
- 米制范围（绝对值 >180）自动判为 `EPSG:3857`，否则按 `EPSG:4326`。
- GeoTIFF 若是 UTM 等其他投影，脚本会明确报错；此时告知用户需要 `gdalwarp -t_srs EPSG:3857`，不要自行伪造范围。
- 输入瓦片目录若是 TMS 命名（y 轴翻转），加 `--input-tms`。

## 第二步：切片

默认行为已经够用，**不要随意加大 `--maxzoom`**：`inspect` 的 `native_zoom` 是源数据的真实精度，超过它只是插值放大，瓦片数量却按 4 倍增长。

```bash
# 大图 + 坐标文件 → XYZ 目录 + 预览页（自动 z(原生-2) ~ z(原生)）
<py> gismap.py tile "北京.jpg" -o out

# 卫星影像要体积小：JPEG；要边缘透明：PNG（默认）
<py> gismap.py tile "北京.jpg" -o out --format jpg --quality 88

# 同时出 XYZ、TMS、MBTiles 三种
<py> gismap.py tile "北京.jpg" -o out --scheme xyz,tms,mbtiles --name 北京影像

# 指定层级；先干跑看数量
<py> gismap.py tile "北京.jpg" -o out --zooms 14-17 --dry-run
```

产物布局：`out/tiles/{z}/{x}/{y}.png`、`out/tiles_tms/…`、`out/<name>.mbtiles`、`out/preview.html`、`out/manifest.json`。

关键参数：

- `--overview N`：往下生成几级缩略（默认 2）。给地图当底图时通常要，给单点核查时可设 0。
- `--edge transparent|white|black`：范围不是整瓦片时的补边方式，JPEG 恒为白底。
- `--workers`：默认 4；超大任务可提到 8。
- 超过 30 万瓦片会拒绝执行，确认无误再加 `--force`。
- 大图（>2 亿像素）先 `export --scale 0.5` 降采样再切，避免内存爆掉。

## 第三步：拼图与分幅

```bash
# 整幅导出（附带 .jgw/.prj，可直接进 GIS）
<py> gismap.py export "北京.jpg" -o 北京_整幅.jpg

# 2x2 / 3x3 / 4x4 分幅；也支持 2x3 这种行列形式
<py> gismap.py export "北京.jpg" -o 北京.jpg --split 3

# 限长边，控制文件体积
<py> gismap.py export "北京.jpg" -o 北京_预览.jpg --max-size 8000
```

分幅产物为 `北京_r1c1.jpg … 北京_r3c3.jpg`，每块都配同名 `.jgw` 与 `.prj`，并额外生成 `北京_index.csv` 记录每块的经纬度范围，便于后续拼版或建索引。整幅导出时只有 `-o` 指定的单个文件。

## 第四步：校验与交付

```bash
<py> gismap.py verify out --source "北京.jpg" --json
```

`verify` 检查瓦片数量与 manifest 是否一致、抽查瓦片能否解码、并把中心瓦片与源图重渲染结果比对（`center_tile_mae`）。**有 `problems` 必须修好再交付**；`center_tile_mae` 明显偏大（>12）说明存在错位，先查基准面而不是重切。

交付时用 `present` 给出 `preview.html`、`manifest.json`，以及 `.mbtiles`（若有）。预览页必须经 HTTP 打开：

```bash
cd <输出目录> && <py> -m http.server 8000
```

## 三个最容易踩的坑

1. **GCJ-02 偏移。** 高德/腾讯等国内底图用 GCJ-02，谷歌卫星影像本身接近 WGS-84；两者套合必然差 100~600 米。**这是基准面差异，不是切片错。** 要与国内底图对齐时用 `--bounds-datum gcj02`（输入按 GCJ-02 解释并反算成 WGS-84）。用户只说"偏了"时，先确认他拿什么底图比对，再决定要不要换算。
2. **层级过高。** 用户常要 z18，但源图可能只到 z15。给出 `native_zoom` 并说明超出部分只是放大模糊，除非用户明确要 overzoom。
3. **预览打不开。** 直接双击 `preview.html` 会因 `file://` 被浏览器拦截而白屏，必须用上面的 `http.server`。这是环境限制，不是产物损坏。

## 不要做

- 不要联网抓取谷歌瓦片；下载是用户既有工具的职责，本技能只处理已下载的数据。
- 不要为"修偏移"去改 `--bounds` 数值硬凑 —— 先用 `--bounds-datum`，再用预览页叠加在线底图确认。
- 不要在输出目录已存在时无脑加 `--force`，先确认目录内容是否用户要保留的。

## 本工作区：GisMapsHelper 桌面端

切片能力最终要接进同目录的 PySide6 应用，**两套解释器不要混用**：

| 用途 | 解释器 | 说明 |
|---|---|---|
| 跑 `gismap.py` | `load_workspace_dependencies` 返回的内置 Python | 只依赖 Pillow，不要把 PySide6 或 GIS 库装进去 |
| 跑桌面应用 / 测试 | `.venv\Scripts\python.exe` | Python 3.13.5、PySide6 6.12，`src/` 布局，已 `pip install -e .` |

桌面端现状（v0.1.0）：

- 启动：`python -m gismapshelper`；`--env` / `--version` 只在终端输出；VS Code 按 F5。不要直接 `python src\gismapshelper\app.py`，脚本方式执行没有父包，会报 `attempted relative import`。
- 界面：`src/gismapshelper/gui/`。`main_window.py` 是左侧导航 + `QStackedWidget`，新页面继承 `pages/base.py` 的 `BasePage`（声明 `title` / `subtitle`），再登记到 `pages/__init__.py` 的 `NAV_PAGES` 即可。
- 首个页面「首页」只显示运行环境，业务页尚未接。

准备接入时：

- 切片算法从 `scripts/gismap.py` 抽到 `src/gismapshelper/core/`，界面只负责收集参数、显示进度；本技能脚本作为独立命令行工具保留，两边共用同一套语义：`inspect → tile/export → verify`。不要在界面层重算范围或层级。
- 打包 exe 用 `--windowed`；PySide6 体积大，`.spec` 里排除 `PySide6.QtWebEngine*`、`Qt3D*` 等未用模块；Pillow 的 JPEG/WEBP 若运行时才加载，要确认对应 DLL 被打进包（打包后双击测一遍解码，别只看构建成功）。

本机两个环境坑（与本技能无关，但会让上面的命令跑不起来）：

- `E:\DeepSeek\GisMapsHelper` 下的 `.ps1` 被 PowerShell 判为不受信任位置，`Activate.ps1` 会报「未进行数字签名」。用 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` 临时放开，或改用 `.venv\Scripts\activate.bat`，或直接调 `python.exe`。
- `%LOCALAPPDATA%\pip\Cache` 曾损坏（435 MB）导致 `pip install` 静默挂死：清缓存或加 `--no-cache-dir`；同样不要执行 `pip install --upgrade pip`。

细节见 `references/input-formats.md`（各坐标文件格式与补充范围的办法）、`references/alignment.md`（对齐与偏移排查）、`references/troubleshooting.md`（报错对照表）。改动脚本后跑 `scripts/selftest.py` 做端到端回归。
