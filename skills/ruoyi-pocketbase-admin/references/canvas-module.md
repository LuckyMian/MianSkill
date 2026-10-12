# 无限画布模块（PureRef 风格参考板）

第三个**专用视图**（前两个是待办、笔记）：`src/views/work/canvas/Index.vue`（薄壳两栏）+
`src/components/CanvasBoard/`（`CanvasSidebar` / `CanvasStage` / `CanvasItemView` / `CanvasToolbar` / `CanvasContextMenu`）+
`src/stores/canvas.ts`（数据、几何、撤销、自动保存）。路由 `/work/canvas`，菜单名「无限画布」。

一块画布 = 一份布局：能放**图片 / 文字便签 / 分组框**，自由平移缩放、框选、拖动、等比缩放、旋转、裁剪、翻转、对齐吸附、层级调整，带撤销重做与自动保存。

## 数据模型

- `work_canvas`：`title`、`theme`(dark/light)、`viewport`(json `{x,y,zoom}`)、`sort`、`trashed`、`trashed_at`。
- `work_canvas_item`：`canvas`(relation) + `kind`(image/text/frame) + `oss_key`/`source_url` +
  几何（`x`/`y`/`w`/`h`/`rotation`/`z`）+ `crop`(json 归一化) + `flip_h`/`flip_v` + `color`/`text`/`font_size` +
  `frame_id`（所属分组框 id，空=顶层）+ `deleted`/`deleted_at`。

两个要点：

1. **坐标是世界坐标**，跟视图缩放无关；视口单独存在 `work_canvas.viewport`（`screen = world * zoom + x/y`）。
2. **分组框是容器**：子元素靠 `frame_id` 归属（不是靠几何包含），拖动框的标题栏会带上 `frame_id` 指向它的元素一起位移；
   缩放框时子元素同比例位移 + 缩放（文字项同步改 `font_size`）。拖动结束按「中心点落在哪个框里」重新归属，
   所以拖进/拖出框是自然发生的，不需要额外的挂载操作。不支持框套框。

## 图片链路（复用笔记那套 OSS 直传，多了目录白名单）

- 走 `canvas/` 前缀直传 OSS，**不占 N1 eMMC**；`crop`/`flip`/`rotation` 都只是渲染参数，不产生新对象。
- 只有「任一边 > 2560px 或文件 > 6MB」才压到长边 2560（PNG/WebP 输出 PNG 保透明，GIF/SVG 原样传），
  与笔记的 1600px 策略分开（`shrinkForCanvas` vs `shrinkIfNeeded`）。
- 图片在画布里的初始长边上限 800 世界像素（`IMAGE_MAX_EDGE`），避免一张大图糊满屏幕。
- **同一张图允许多个元素共用一个 OSS key**（Ctrl+D 复制、复制画布都会复用对象），
  所以回收前必须 `recycleUnreferenced()` 查一遍引用：还有元素在用的 key 一个都不删；查询失败时**保守全留**。
- 粘贴 / 拖文件 / 拖网页图片链接（服务端转存，见 [oss-images.md](oss-images.md)）三个入口都在 `CanvasStage.vue`。

## 撤销重做：拖拽中不写栈

拖拽的每一帧都调用 `store.setItemFields()`（只改内存 + 标脏），拖拽开始时用 `snapshotItems()` 存一份「拖前快照」，
指针抬起再 `commitGeometry(快照, '移动')` 生成**一条**撤销记录。否则一次拖动会塞进上百条历史。

撤销条目 = `{ label, created: [id...], changes: [{id, before, after}] }`：

- `created` 里的元素，撤销 = 软删除（对象保留，可重做恢复）；
- `changes` 存字段级 before/after，撤销反向应用、重做正向应用；
- 栈深 50，**只覆盖布局与内容**（移动/缩放/旋转/裁剪/翻转/层级/对齐/新增/删除/文字/分组），
  视口平移缩放与画布重命名不进栈。

## 交互约定（写死在代码里，改前先想清楚）

| 操作 | 键位 |
| --- | --- |
| 平移 | 中键拖动 或 空格+左键拖动 |
| 缩放 | 滚轮（以光标为锚点，0.05–8×）；Ctrl+0 适应窗口、Ctrl+1 100% |
| 选择 | 左键点选、Shift 加选、空白拖动框选、Ctrl+A、Esc 取消 |
| 移动 | 拖动选中项；方向键 1px、Shift+方向键 10px |
| 缩放元素 | 拖角手柄等比（Shift 自由变形）、拖边手柄单轴拉伸、Alt 以中心缩放 |
| 旋转 | **Ctrl + 拖角手柄**（吸附 15°，Shift 自由）；`R` 键 90° |
| 翻转 | `H` 水平、`J` 垂直（**别用 Ctrl+H/Ctrl+V**：前者是浏览器历史、后者是粘贴） |
| 层级 | Ctrl+] 上移、Ctrl+[ 下移、右键置顶/置底 |
| 复制 / 删除 | Ctrl+D 复制（偏移 20px）、Delete/Backspace 软删除 |
| 裁剪 | 右键「裁剪…」进入，拖 8 个手柄，Enter 或点空白确认、Esc 取消 |
| 文字 | 双击空白新建、双击文字项编辑；编辑时若缩放≠1 会先临时切到 100% 便于输入，结束恢复 |

细节坑：

- **元素 rotated 时的手柄**：缩放/裁剪的世界位移要按 `-rotation` 旋转到元素自身坐标系（`localDelta()`），否则旋转过的图拖手柄会「斜着跑」。
- **翻转要作用在整个元素上**（外框 transform 里 `scaleX/scaleY`），不能只翻 `<img>`：裁剪后 img 比外框大且带偏移，翻 img 会翻错轴。
- **裁剪语义**：`crop` 是相对原图的归一化区域，裁剪浮层显示的是**整张原图**（`sourceRectOf()` 给出原图在元素坐标系里的位置），
  所以可以往外拖把裁掉的区域补回来。点「确认」时 `cropFromLocalRect()` 会**同时给出新外框**——
  外框必须跟着裁剪框平移（`x/y` 一起改），否则「从左边裁掉一块」会把剩下的画面整体左移。
- **对齐吸附**阈值是 `6 / zoom`（屏幕像素恒定），拖动时按选区外框与其它元素的边缘/中线比对，`Alt` 临时关掉吸附。
- **原生拖拽会掐断指针手势（踩过）**：鼠标从元素移到图片上时，Chrome 会启动 HTML5 图片拖拽，紧接着对进行中的指针手势发出
  **`pointercancel`**（表现：拖到一半就断了，只有第一小步生效）。所以画布根节点上必须有 `@dragstart.prevent`，
  元素与裁剪浮层里的 `<img>` 一律 `draggable="false"`；`.canvas-stage` 上还要 `touch-action: none`。
- **别让新画布排在最后就找不到**：新建画布 `sort` 取 max+1，会排在列表末尾，而 `init()` 原来只打开 `canvases[0]`，
  于是刷新后会跳到另一块板。现在用 `localStorage.pb_canvas_last` 记住上次打开的板（不存在才退回首块）。

## 保存策略

- 元素：改动标脏（`dirtyIds`，模块级 `Set` 不参与响应式），300ms debounce 后逐条 PATCH 变化过的元素；
  失败重新标脏并保留本地数据，工具栏显示错误 + 「重试」，**不吞错也不清空界面**。
- 画布级（viewport/标题/主题）：500ms debounce。
- 强制落盘：切画布、组件卸载、`beforeunload`（有未保存项时拦截提醒）。
- 工具栏的 `:loading` 之类不能用「保存中」当条件——按钮会被连带禁用（笔记模块踩过同一个坑），这里只用文字状态。

## 删除语义（与随手笔记一致）

删除元素 = `deleted=true`（图片还在 OSS），画布侧栏「最近删除」可恢复或彻底删除；
**只有彻底删除**（单个元素、清空本画布回收站、彻底删除整块画布）才调 `POST /api/oss/delete` 回收对象，回收前查引用。
删除整块画布也是软删除（`trashed`），彻底删除时才连带删掉它的元素记录。

## 已知边界

- 元素上限 2000（`ITEM_LIMIT`，一次 `listAll` 拉完当前画布）；超了界面会提示拆板。
- 单人使用、服务端存储即多设备同步，最后写入者胜，不做并发合并。
- 不做导出 PNG、演示模式、网格吸附。
- 画布内不做跨板共享素材库（从笔记复用图片也没做），但复制元素/复制画布会复用同一批 OSS 对象。

## 实测性能（2026-10-13，本机 Chrome 无头 + 真机）

200 个元素（复用同一个 OSS 对象、20×10 网格）：

| 指标 | 结果 |
| --- | --- |
| 世界层 DOM 节点 | 400（每张图 = 外层 div + img） |
| 元素挂载（骨架出现） | 274ms |
| 图片全部加载完 | 586ms |
| 拖动 30 步指针移动 | 501ms（约 17ms/步，跟手） |
| Ctrl+A 全选 200 项 | 11ms |
| 进板自动「适应全部」 | zoom 0.23（把整块板收进视口） |

结论：几百张图这个量级，DOM + CSS transform 的路子完全够用，不必上 Canvas 2D。
