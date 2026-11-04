# 光轴桌面模块化增高架（案例）

这是一个真实项目的设计记录，用来避免后续把“手机支架”做成错误的安装方式。通用 API 约定仍以 [addon-development.md](addon-development.md) 和 [testing-and-release.md](testing-and-release.md) 为准。

## 0. 项目位置

- 独立工作区/仓库：`F:\DSH\FreeCAD`
- 插件包：`plugins/optical-axis-modular`
- 原始模型：[模块化光轴增高架 · MakerWorld](https://makerworld.com.cn/zh/models/2188599-mo-kuai-hua-guang-zhou-zeng-gao-jia)
- 参考文件：`C:\Users\Administrator\Desktop\未命名.FCStd`

> 这是用户明确指定的独立项目，不在 `F:\Codex\Freecad` 集合内；不要把它搬回集合或改写集合的 README。

## 1. 尺寸体系

### 1.1 S / M / L

S/M/L 指**两块封板内侧面之间的净宽**：

| 规格 | 净宽 | 外形（含 2×30 封板） | 光轴长度（净宽 + 2×20） |
| --- | ---: | ---: | ---: |
| S | 100 mm | 160 mm | 140 mm |
| M | 200 mm | 260 mm | 240 mm |
| L | 300 mm | 360 mm | 340 mm |

必须满足 `2S = M`、`3S = L`。现有文件的框架净宽是 970 mm，对应光轴 1010 mm、外形 1030 mm；`VarSet.AxisLength` 写作 1000 mm，但实际 `Pad004` 是 1010 mm。

### 1.2 封板基准

- 深 190 mm × 高 82 mm × 厚 30 mm；
- 前侧 60° 斜边，顶部短边 142.657 mm；
- 内部减重窗边框 22 mm；
- 4 个孔（孔径 = 光轴 + 0.1 mm）：

| 孔 | X | Z |
| --- | ---: | ---: |
| 后上 | 11.000 | 71.000 |
| 后下 | 11.000 | 11.000 |
| 前下 | 170.947 | 11.000 |
| 前上 | 136.306 | 71.000 |

前侧孔公式：

```text
x_front(z) = panel_depth - z / tan(slope) - edge_margin / sin(slope)
```

## 2. 侧封板实现

### 2.1 外轮廓与减重窗

- 外轮廓：`(0,0) → (190,0) → (142.657,82) → (0,82)`；
- 两个前侧外角 R10；
- 减重窗：`(22,22) → (151.895,22) → (129.956,60) → (22,60)`；
- 默认不是通孔，而是**盲槽**：外侧面封闭，内侧留槽，底板 3 mm；
- 可选：`通孔` / `盲槽（外侧封口）` / `盲槽（内侧封口）`。

### 2.2 左右封板的关键坑

两块封板朝相反方向。**不能把同一块带盲槽的封板直接复制/平移**：这样一块的外侧会变成另一块的内侧，两侧封口方向相反。

正确做法：给单块封板增加 `outer_at_zero`（或左右镜像参数），按“外侧在哪一边”分别生成左右封板。验证时检查：

- 左封板 y=-30 面应为 5 条线（外环 + 4 孔），y=0 面 6 条线（多一条窗）；
- 右封板 y=+T 面 5 条线，y=W 面 6 条线。

### 2.3 光轴孔封口、倒角、内圆角

- 4 个光轴孔在外侧面做**齐平盲孔封口**：盲孔从内侧面切入，外侧留 `CapHeight`（默认 1.2 mm）壁厚，端面与封板外侧平面齐平；**不要**再加凸出的锥形端盖（旧方案已被用户否掉）。
- 壁厚中心钻 **Φ2 排气孔**（`VentHoleDiameter`），贯通盲孔与外界；光轴与孔只有 0.1 mm 直径间隙时，这个孔用来排掉气压，否则插拔会“打气筒”。
- 孔径 = 光轴直径 + 0.1 mm **直径**间隙：12 mm 轴 → **12.1 mm 孔**，不是 12 整。
- 盲孔深度必须大于光轴嵌入深度：默认盲孔 28.8 mm > `RodEmbed` 20 mm，光轴端距盲孔底约 8.8 mm。
- 外轮廓 1.0 mm 倒角；内侧面 12.1 mm 孔口 0.5 mm 倒角；外侧面 Φ2 排气孔口约 0.3 mm 倒角；
- 减重窗四角 R5；
- 布尔顺序很重要：

```text
外轮廓拉伸 → 前侧 R10
→ 切 4 个光轴盲孔 + 4 个 Φ2 排气孔
→ 内孔口 0.5 / 排气孔口 0.3 倒角
→ 切减重窗/盲槽 → 窗四角 R5 → 外轮廓 1.0 倒角
```

不再有“外侧面端盖”这一步。外轮廓倒角只选 **y≈0 和 y≈T 两个大面的 OuterWire**，不要按面积选，否则会把盲槽底板当成外轮廓。光轴孔倒角按圆心 Y 区分内侧面大孔口和外侧面排气孔口，避免把盲孔底部的内部边也倒掉。

## 3. 手机支架：滑入共享光轴（前 2 穿孔 + 后 2 穿孔）

### 3.1 最终结论（2026-11-04 更新）

手机支架是独立模块，但**不生成自己的光轴**，也**不是 C 形卡扣**。默认把底座 **4 根光轴**都穿过模块，并从左侧滑入：

```text
打开/拆下底座左侧封板
→ 前上、前下两根光轴穿过两个贯通套筒
→ 后上、后下两根光轴穿过后立柱的两个通孔
→ 顶盖从靠板背面盖到后侧，模块宽度内看不到后光轴
→ 装回左侧封板
```

- 两个前套筒内孔中心 = 底座前下、前上光轴中心；
- 后立柱两个通孔中心 = 底座后下、后上光轴中心（X=11，Z=11 / 71）；
- 内孔 = 光轴直径 + 0.1 mm；
- 套筒/后立柱都贯通整个模块宽度，光轴从中穿过；
- 手机支架宽度 = 模块宽度 − 2×0.3 mm，可以从左侧滑入；
- `HideRearRods` 默认 **true**；关掉时只穿前两根，后光轴外露。**任何打印模型都必须倒角**，见 3.8。
- 靠板沿底座 60° 斜边，底部托唇托住手机。

### 3.2 四根光轴坐标

对默认 190×82×60° 封板：

| 光轴 | X | Z |
| --- | ---: | ---: |
| 前下 | 170.947 mm | 11.000 mm |
| 前上 | 136.306 mm | 71.000 mm |
| 后下 | 11.000 mm | 11.000 mm |
| 后上 | 11.000 mm | 71.000 mm |

```text
前中心距 = sqrt(34.641² + 60²) = 69.282 mm
后中心距 = 60 mm（竖直排列）
```

**不要写成 160 mm**。参考图里模块的安装位置容易被误读成 160 mm 间距；本项目最终确认的是底座前面两根光轴，实际中心距 69.282 mm，且沿 60° 斜边。任何新的底座尺寸都要用 `x_front(z)` 公式重新计算，不能硬编码。

### 3.3 结构

一个可打印滑套体（默认含后光轴封盖）：

```text
手机支架滑套体
├─ 靠板：沿 60° 斜边，长 160 mm，正面浅蜂窝
├─ 两个前套筒：外半径 10 mm，内孔 d+0.1
├─ 底部托唇：前伸 35 mm，前挡边 10 mm，与下套筒重叠 1.5 mm
├─ 顶部封盖：z=77.55…82 mm，从靠板背面盖到 x=0
└─ 后立柱：x=0…21.05，z=0.95…82，两个 Φ12.1 后光轴通孔
```

关键默认值：

| 参数 | 默认 |
| --- | ---: |
| `ModuleWidth` | 100 mm（本模块占用宽度，靠板 = 99.4） |
| `PanelLength` | 160 mm |
| `PanelOffset` | 8 mm（靠板背面到光轴中心法向距离） |
| `PanelThickness` | 4 mm |
| `SleeveOuterRadius` | 10 mm |
| `PanelClearance` | 0.3 mm/侧 |
| `LipDepth` | 35 mm |
| `LipShelfHeight` | 8 mm |
| `FrontLipHeight` | 10 mm |
| `HideRearRods` | true |
| `CoverThickness` | 4 mm |
| `CoverClearance` | 0.5 mm（顶盖底到后上光轴外缘） |
| `PillarWall` | 4 mm |
| `Chamfer` | 0.5 mm（套筒/后立柱孔口） |
| `OuterChamfer` | 1.0 mm（靠板/托唇/顶盖/后立柱外轮廓） |
| 蜂窝 | R9 / 间距 22 / 深 1.5 / 留边 10 |

### 3.4 设计检查清单

- [ ] 套筒/后立柱孔中心是否由底座公式计算，而不是硬编码 160 或 69.28？
- [ ] 前套筒和后立柱是否**贯通**整个宽度？用 `shape.isInside(rod_center)` 检查，孔中心必须为 `False`。
- [ ] 顶盖底边是否高于后上光轴外缘 + `CoverClearance`？默认 `77.55 > 77.05`。
- [ ] 顶盖是否在 `(11, 任意 y, 顶盖内)` 处为实体？后光轴从上方必须被盖住。
- [ ] 后立柱后表面是否与底座后面齐平（默认 x=0）？大光轴时允许向后延伸。
- [ ] 底部托唇是否从套筒外缘之外开始并与套筒有 ≥1 mm 重叠？不能把套筒内孔填死。
- [ ] 支架宽度是否小于底座净宽（留 0.2–0.3 mm/侧）？
- [ ] 是否明确安装方向：从左侧滑入，需要打开/拆下左封板？
- [ ] 是否所有外轮廓和孔口都有倒角参数，并且 `makeChamfer` 失败只警告不中断？
- [ ] 新增第二个模块时，是否走 `StackWidth` 定位，而不是回到原位置？

### 3.5 多模块堆叠：光轴加长、左封板偏移（最重要）

底座参数里新增 `StackWidth`：**已经滑入的模块占用宽度总和**。模块从右往左排，右侧贴住右封板，左侧依次排开：

```text
右封板内侧面            y = W0
第一个模块（原基础段）  y = W0 - U1 … W0
第二个模块（左侧新段）  y = W0 - U1 - U2 … W0 - U1
...
左封板内侧面            y = -max(0, StackWidth - W0)
总净宽                  W0 + max(0, StackWidth - W0)
```

新模块创建时：

```text
new_stack   = base.StackWidth + ModuleWidth
segment_left = W0 - new_stack
base.StackWidth = new_stack
LeftExtension = max(0, new_stack - W0)
左封板向左平移 LeftExtension，光轴长度 += LeftExtension
模块 group.Placement.y = segment_left（其余沿用底座 placement）
```

- `base.ModuleWidth` **保持基础单元宽 W0**，不把模块宽度混进基础尺寸；
- 只有 `StackWidth > W0` 时左封板才移动、光轴才加长；
- 多个模块可以填满基础净宽，再继续向左扩展；
- 新模块的 `ModuleWidth` 默认取剩余空位（≥40 mm），否则取 W0；
- 代码入口：`feature.module_stack_width(doc, base)`、`phone_feature.create_phone_stand()`；
- 通过 `BaseModuleName` 找同一底座上的模块；`StackWidth` 是快路径，扫描绑定模块可修复旧文档。

S 底座 + 两个 100 mm 手机支架的结果：

```text
模块 #1 y = 0 … 100（实际 0.3…99.7）
模块 #2 y = -100 … 0（实际 -99.7…-0.3）
StackWidth = 200；LeftExtension = 100
左封板 y = -130 … -100；右封板 y = 100 … 130
光轴长度 240；外形 260
```

不要在第二次添加时把新支架再放到 `y=0`，也不要为了“放下第二个”把两个支架都改宽。新增模块必须拿新槽位。

### 3.6 走过的弯路（不要重复）

1. **第一版错误**：给手机支架做了自己的 160 mm 上下光轴、高侧颊和落在封板顶部的定位脚。用户指出：应该和底座共用同一根光轴。
2. **第二版错误**：把手机支架做成 C 形卡扣，从前方压到前两根光轴上。用户指出：应该是穿孔套筒，打开封板后从左侧滑入。
3. **第三版错误**：第二个手机支架仍在 `y=0` 创建，和第一个重叠。正确逻辑：从左侧继续滑入，光轴加长，左封板偏移一个模块宽度（见 3.5）。
4. **后光轴外露**：只穿前两根时，从顶部能看见后两根光轴。正确做法：顶盖 + 后立柱双穿孔（见 3.1/3.3）。
5. **无倒角**：第一版手机支架所有外棱都是直角。后续规则：所有模型都必须倒角（见 3.8）。

### 3.7 多模块示例（FreeCAD 里验证）

```powershell
& 'C:\Program Files\FreeCAD 1.1\bin\FreeCADCmd.exe' F:\DSH\FreeCAD\tools\smoke_phone.py
```

检查：第二个支架 `ModuleOffset=-100`、`StackWidth=200`、`InfoLeftExtension=100`、`InfoRodLength=240`、`InfoOuterWidth=260`、左封板 `Y=-131.2…`；保存重开后继续添加得到 `ModuleOffset=-400`、`StackWidth=500`。

### 3.8 倒角规则（项目级）

所有打印模型都必须有倒角，包括以后新增的笔筒/层板/无线充模块：

- 外轮廓倒角：默认 1.0 mm，参数 `OuterChamfer`；
- 孔口/套筒口倒角：默认 0.5 mm，参数 `Chamfer`；
- 简单实体（盒子、棱柱、单个套筒）在**融合前**倒角；融合后的 L 形/U 形/薄壁复杂边只做兜底；
- 每个 `makeChamfer` 包 `try/except`，失败时 `App.Console.PrintWarning` 并继续，不能整个模型失败；
- 参数模型中暴露倒角字段，对话框可调，默认值不是 0。


## 4. FreeCAD 1.1 实现要点

### 4.1 参数对象与显示

`Part::FeaturePython` 的默认视图提供器在 FreeCAD 1.1 下不一定把 `Shape` 显示出来。项目中最终使用：

```text
App::Part 容器
├─ App::FeaturePython 参数控制器（无 Shape）
├─ Part::Feature 封板（可打印）
├─ Part::Feature 光轴
└─ Part::Feature 手机支架滑套体
```

参数控制器 `execute()` 负责重建子对象的 `Shape`；子对象用标准 `Part::Feature`，显示、选择、导出都正常。

不要给 `Part::Feature` 的 `ViewObject.Proxy` 随便赋一个普通 Python 对象，会破坏默认 Part 显示。

### 4.2 跨 App::Part 引用

`App::PropertyLink` 跨 `App::Part` 链接会报警：

```text
Link(s) to object(s) ... go out of the allowed scope ...
```

项目里手机支架用 `App::PropertyString BaseModuleName` 保存底座控制器对象名，`execute()` 里 `Document.getObject(name)` 取回。这样没有 scope 警告，也能跟随底座尺寸重建。

### 4.3 持久化

`FeaturePython` 代理的 `__init__` 在文档恢复时不一定被调用。必须在 `__setstate__` 里初始化瞬态字段：

```python
def __getstate__(self):
    return None

def __setstate__(self, state):
    self._building = False
```

项目第一次保存/重开时就是因为缺少 `_building` 导致 `onChanged`/`execute` 报 `AttributeError`。

### 4.4 InitGui.py 不能用 __file__

FreeCAD 1.1 通过 `RunInitGuiPy` 执行 `InitGui.py` 时，`__file__` 可能未定义。不要写：

```python
os.path.dirname(__file__)
```

要用包自身定位：

```python
from pathlib import Path
import FreeCADGui as Gui
import my_package

ICON_DIR = str(Path(my_package.__file__).resolve().parents[1] / "resources" / "icons")
Gui.addIconPath(ICON_DIR)
```

模板已按这个方式修正。

### 4.5 数据库/属性单位

- `App::PropertyLength` 的 `float()` 返回 mm，但**不接受负值**：给 `PropertyLength` 赋负数会被静默改成 0。有符号的 Y 偏移必须用 `App::PropertyDistance`（实测可存 -100 mm），或用 `PropertyFloat`。
- `App::PropertyAngle` 的 `float()` 返回度；
- 只读信息属性在 `execute()` 里赋值通常可行，但不同构建可能拒绝，最好 try/except。

## 5. 验证

```powershell
# 纯 Python
& 'C:\Program Files\FreeCAD 1.1\bin\python.exe' -m unittest discover -s tests -v

# 封板 / 手机支架几何
& 'C:\Program Files\FreeCAD 1.1\bin\FreeCADCmd.exe' tools\smoke_module.py
& 'C:\Program Files\FreeCAD 1.1\bin\FreeCADCmd.exe' tools\smoke_phone.py

# 插件包
& 'C:\Program Files\FreeCAD 1.1\bin\python.exe' `
  "$env:USERPROFILE\.dsh\skills\freecad-plugin-dev\scripts\validate_addon.py" `
  "F:\DSH\FreeCAD\plugins\optical-axis-modular"
```

当前结果（2026-11-04）：

- 52 个纯 Python 测试通过；
- `SMOKE_OK`、`RELOAD_OK`、`PHONE_SMOKE_OK`；
- 封板外侧面齐平封口（无凸出端盖）：孔中心 `(11, y, 71)` 在 Φ2 排气孔内为 `False`，孔旁盲孔壁 `(14, y, 71)` 为 `True`；内侧面大孔开孔；孔径 Φ12.1、排气孔半径 1.0；
- 手机支架冒烟检查前套筒 + 后立柱 4 个光轴孔中心 `isInside=False`；
- 顶部封盖在 `(11, y, 80)` 为实体，后上光轴顶面 `z=77.05` 与顶盖底 `z=77.55` 之间留 0.5 mm；
- 第二个手机支架 `ModuleOffset=-100`，`StackWidth=200`，`InfoRodLength=240`，`InfoOuterWidth=260`；第三个 `-200`，保存重开后第四个 `-400`、`StackWidth=500`；
- S→M 时手机支架不再被拉宽（模块宽度独立）；两个 100 mm 模块可以填满 M 底座；
- GUI 命令可打开新对话框（模块宽度、封盖、倒角），连续创建两个模块后左封板左移 100 mm；
- 顶部视图截图确认模块宽度内看不到后光轴。

## 6. 代码地图

```text
optical_axis/
├─ core.py           # 封板 S/M/L、孔径、齐平封口/排气孔、减重窗、StackWidth/left_extension
├─ geometry.py       # 封板 Part 几何（盲孔+排气孔、左封板偏移、布尔顺序）
├─ feature.py        # 封板控制器 + 左右封板/光轴子对象 + 模块堆叠扫描
├─ phone_core.py     # 手机支架参数、前/后光轴坐标、顶盖/后立柱
├─ phone_geometry.py # 靠板 + 前套筒 + 托唇 + 顶盖 + 后立柱 + 倒角
├─ phone_feature.py  # 手机支架控制器 + BaseModuleName + ModuleOffset
├─ dialog.py         # 封板对话框（封口厚度/排气孔直径）
├─ phone_dialog.py   # 手机支架对话框（模块宽度/封盖/倒角）
└─ commands.py       # 创建/导出命令
```

对应文档：`docs/design-notes.md`（封板尺寸）、`docs/phone-stand.md`（四光轴滑入 + 多模块堆叠）。

## 7. 下次接到类似需求

先问清装配路径，再建模：

1. 模块是**共用底座光轴**，还是自带光轴？
2. 若是共用：是**穿孔滑入**，还是 C 形/卡扣压入？
3. 从哪一侧滑入？对应封板是否需要打开/拆下？
4. 模块宽度与底座净宽的关系、每侧间隙多少？
5. 套筒内孔直径、外径、是否需要防滑/紧配？
6. 是否需要遮住**后两根**光轴？需要的话做顶盖 + 后立柱双穿孔，而不是只穿前两根。
7. 同一底座上已有模块时，新模块放在哪里？必须走 `StackWidth` 新槽位，并确认光轴加长、左封板偏移的量。
8. 每个新模型的外轮廓/孔口倒角参数是多少？默认不能用 0。
9. 光轴孔外侧面要凸出的端盖还是齐平？齐平时是否加排气孔（默认 Φ2）？孔径间隙是直径 0.1 mm 还是径向 0.1 mm（前者 12.1，后者 12.2）？

这九个问题的答案会直接决定结构。不要只看参考图猜 160 mm 间距、C 形卡扣，或在原位置重复添加模块。
