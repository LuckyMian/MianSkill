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

### 2.3 端盖、倒角、内圆角

- 4 个光轴孔在外侧面加 1.2 mm 高锥形端盖；端盖半径按边框自动收缩，不能侵占外边缘或减重窗；
- 端盖只封外侧面，内侧面保留通孔让光轴插入；
- 外轮廓 1.0 mm 倒角，孔口 0.5 mm 倒角；
- 减重窗四角 R5；
- 布尔顺序很重要：

```text
外轮廓拉伸 → 前侧 R10 → 切 4 孔 → 孔口倒角
→ 切减重窗/盲槽 → 窗四角 R5 → 外轮廓 1.0 倒角 → 外侧面端盖
```

外轮廓倒角只选 **y≈0 和 y≈T 两个大面的 OuterWire**，不要按面积选，否则会把盲槽底板当成外轮廓。

## 3. 手机支架：滑入前两根光轴（最重要）

### 3.1 最终结论

手机支架是独立模块，但**不生成自己的光轴**，也**不是 C 形卡扣**。它有两个**贯通整个支架宽度的穿孔套筒**，与底座共用**前上、前下两根光轴**：

```text
打开/拆下底座左侧封板
→ 把手机支架从左侧套入前下、前上两根光轴
→ 装回左侧封板
```

- 两个套筒内孔中心 = 底座前下、前上光轴中心；
- 内孔 = 光轴直径 + 0.1 mm；
- 套筒贯通整个支架宽度，光轴从套筒中穿过；
- 手机支架宽度略小于底座净宽（每侧留 0.3 mm），可以从左侧滑入；
- 靠板沿底座 60° 斜边，底部托唇托住手机。

### 3.2 前两根光轴坐标

对默认 190×82×60° 封板：

| 光轴 | X | Z |
| --- | ---: | ---: |
| 前下 | 170.947 mm | 11.000 mm |
| 前上 | 136.306 mm | 71.000 mm |

```text
中心距 = sqrt(34.641² + 60²) = 69.282 mm
```

**不要写成 160 mm**。参考图里模块的安装位置容易被误读成 160 mm 间距；本项目最终确认的是底座前面两根光轴，实际中心距 69.282 mm，且沿 60° 斜边。任何新的底座尺寸都要用 `x_front(z)` 公式重新计算，不能硬编码。

### 3.3 结构

一个可打印滑套体：

```text
手机支架滑套体
├─ 靠板：沿 60° 斜边，长 160 mm，正面浅蜂窝
├─ 两个穿孔套筒：外半径 10 mm，内孔 d+0.1
├─ 底部托唇：前伸 35 mm，前挡边 10 mm
└─ U 形理线缺口：中间 30 mm
```

关键默认值：

| 参数 | 默认 |
| --- | ---: |
| `PanelLength` | 160 mm |
| `PanelOffset` | 8 mm（靠板背面到光轴中心法向距离） |
| `PanelThickness` | 4 mm |
| `SleeveOuterRadius` | 10 mm |
| `PanelClearance` | 0.3 mm/侧 |
| `LipDepth` | 35 mm |
| `LipShelfHeight` | 8 mm |
| `FrontLipHeight` | 10 mm |
| 蜂窝 | R9 / 间距 22 / 深 1.5 / 留边 10 |

S 基础的滑套体宽度为 `100 - 2×0.3 = 99.4 mm`。靠板顶部伸出前上光轴约 90.7 mm。

### 3.4 设计检查清单

- [ ] 套筒内孔中心是否由底座 `x_front(z)` 计算，而不是硬编码 160 或 69.28？
- [ ] 套筒是否**贯通**整个宽度？用 `shape.isInside(rod_center)` 检查，孔中心必须为 `False`。
- [ ] 底部托唇是否从套筒外缘之外开始？不能把套筒内孔填死。
- [ ] 支架宽度是否小于底座净宽（留 0.2–0.3 mm/侧）？
- [ ] 是否明确安装方向：从左侧滑入，需要打开/拆下左封板？
- [ ] 是否没有生成额外光轴、没有 C 形卡扣、没有顶部定位脚？

### 3.5 走过的弯路（不要重复）

1. **第一版错误**：给手机支架做了自己的 160 mm 上下光轴、高侧颊和落在封板顶部的定位脚。用户指出：应该和底座共用同一根光轴。
2. **第二版错误**：把手机支架做成 C 形卡扣，从前方压到前两根光轴上。用户指出：应该是两个穿孔套筒，打开两侧封板后从左侧滑入。
3. **最终版**：两个贯通套筒 + 靠板/托唇，共用一个底座的前上/前下光轴，左侧滑入。

只要用户提到“共用光轴”“穿孔”“从左侧滑入”“打开封板”，就应优先考虑本节的滑配套筒方案，不要做卡扣或独立光轴。

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

- `App::PropertyLength` 的 `float()` 返回 mm；
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

当前结果：

- 35 个纯 Python 测试通过；
- `SMOKE_OK`、`RELOAD_OK`、`PHONE_SMOKE_OK`；
- 手机支架冒烟检查套筒孔中心 `isInside=False`；
- 基础净宽 100→200，手机支架宽度 99.4→199.4 跟随；
- GUI 命令可打开对话框并创建模块。

## 6. 代码地图

```text
optical_axis/
├─ core.py           # 封板 S/M/L、孔径、减重窗、端盖参数
├─ geometry.py       # 封板 Part 几何 + 布尔顺序
├─ feature.py        # 封板控制器 + 左右封板/光轴子对象
├─ phone_core.py     # 手机支架滑套参数、前光轴坐标
├─ phone_geometry.py # 靠板 + 贯通套筒 + 托唇 + 蜂窝
├─ phone_feature.py  # 手机支架控制器 + BaseModuleName 引用
├─ dialog.py         # 封板对话框
├─ phone_dialog.py   # 手机支架对话框（从左侧滑入）
└─ commands.py       # 创建/导出命令
```

对应文档：`docs/design-notes.md`（封板尺寸）、`docs/phone-stand.md`（滑入装配）。

## 7. 下次接到类似需求

先问清装配路径，再建模：

1. 模块是**共用底座光轴**，还是自带光轴？
2. 若是共用：是**穿孔滑入**，还是 C 形/卡扣压入？
3. 从哪一侧滑入？对应封板是否需要打开/拆下？
4. 模块宽度与底座净宽的关系、每侧间隙多少？
5. 套筒内孔直径、外径、是否需要防滑/紧配？

这五个问题的答案会直接决定结构。不要只看参考图猜 160 mm 间距或 C 形卡扣。
