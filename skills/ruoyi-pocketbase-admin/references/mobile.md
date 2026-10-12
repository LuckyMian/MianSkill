# 手机端适配

两级断点，别混用：

| 断点 | 位置 | 做什么 |
| --- | --- | --- |
| **≤900px** | `layout/Index.vue` 的 `matchMedia('(max-width: 900px)')` | 应用外壳切手机模式：侧栏收进抽屉、隐藏标签栏、顶栏只留汉堡+页面标题+头像 |
| **≤1100/1200px** | 待办 / 笔记 / 画布三个页面各自的 `isNarrow` | 平板级：把左栏、右栏收成 `el-drawer`（原有实现，手机自然也命中） |

触摸能力判定用 **`matchMedia('(pointer: coarse)')`**（`CanvasStage.vue` 的 `isTouch`），不要拿宽度当触摸依据——触屏笔记本是宽屏但也是触摸。

## 应用外壳（手机）

- 侧栏 `v-if="!isMobile"`，改用 `<el-drawer direction="ltr" size="76%">` 装 logo + `Sidebar`；汉堡按钮（`Navbar` 的 `mobile` prop）打开抽屉，**路由一变就自动关**（watch `route.path`）。
- 顶栏：面包屑换成当前页标题，用户名隐藏只留头像。
- 标签栏 `v-if="!isMobile"` 隐藏，同时 `.is-mobile { --app-tags-height: 0px }`——页面里那些
  `calc(100vh - var(--app-header-height) - var(--app-tags-height))` 的高度就自动对了，不用改各页面。
- 抽屉内容背景要显式设成 `var(--app-sidebar-bg)`（`el-drawer__body` 默认是白底）。

## 表格页（CrudTable）

一个组件承载所有台账页，所以手机适配都放在它里面：

- 弹窗宽度 `width="min(620px, 94vw)"`（`min()` 直接写进 inline style，不需要响应式代码）。
- 表单一列铺满：`colSpanOf(field)` 在手机上强制 24；分页 `layout` 切成 `prev, pager, next`（`sizes/jumper` 在手机上放不下）。
- 查询区字段原本写死 `style="width:220px"`，改成 class + `@media (max-width: 900px) { width: 100% }`。
- 表格本身不用动：列有 `min-width`，超宽时 el-table 自己出横向滚动条；操作列 `fixed="right"` 保证够得着。

## 画布触摸手势（`CanvasStage.vue`）

指针事件天然统一，但要按 `pointerType` 分叉：

- **单指空白处**：触摸 = 平移画布（鼠标仍是框选）——`startEmptyGesture()`。
- **单指元素上**：拖动元素、拖角缩放、拖连接点连线，和桌面一致（`touch-action: none` 已保证浏览器不抢手势）。
- **双指**：用 `Map<pointerId, Pt>` 记活跃指针，第二根手指落下时立刻 `finishDrag()` 收口当前拖拽并进入 `pinch` 状态，
  之后按「两指距离比」缩放、按「中点位移」平移（`screenToWorld` 保证中点下的世界坐标不动）。松手后到全部抬起前用
  `ignorePointer` 吞掉残留的单指移动，避免指尖一滑就拖动元素。
- **长按 480ms**：手机上没右键，长按直接弹同一个上下文菜单（`showMenuAt()` 与 `contextmenu` 共用）。
  移动超过 8px 就取消长按；长按触发后要**取消当前拖拽并吞掉随后的 pointerup**，否则会顺手挪一下元素。
- 触摸热区放大：`touchScale = isTouch ? 1.7 : 1`，用于缩放手柄、连接点圆点、裁剪手柄、连线命中宽度（都是「屏幕尺寸 / zoom」，再乘这个系数）。
- 底部工具条：手机上改成**一行横向滚动**（`flex-wrap: nowrap; overflow-x: auto`）+ `bottom: calc(8px + env(safe-area-inset-bottom))`；
  注意画布整体是 `touch-action: none`，工具条必须单独写 `touch-action: pan-x` 才能滑动。状态文字（已保存/元素数）在手机上隐藏。

## 踩过的坑

1. **抽屉的焦点捕获会掐掉画布里的文字编辑**：手机上从画布抽屉里「新建画布」后如果抽屉还开着，紧接着新建流程节点/文字时，
   `startTextEdit()` 聚焦的 textarea 会被抽屉的 focus trap 抢走焦点 → 立刻触发 `blur` → `finishTextEdit()` 提交并关掉编辑器。
   修法是**新建画布后自动收起抽屉**（`CanvasSidebar.createCanvas()` 里 `emit('select')`），别去改编辑器的失焦逻辑。
2. **`touch-action: none` 是全局的**：工具条里的横向滑动会被它一起挡掉，必须给可滚动容器单独放开。
3. **模板里不要写 `xxx.value`**：`<script setup>` 中的 ref 在模板里自动解包，写 `touchScale.value` 会被 vue-tsc 报
   `Property 'value' does not exist on type '1 | 1.7'`（本次真实踩到）。
4. **触摸模拟下 `page.click(selector, { clickCount: 3 })` 不会清空输入框**：用
   `document.querySelector(...).select()` 再 `type()`，否则 ElMessageBox 的默认值会和新输入拼在一起（画布名会变成「画布 1M-1791…」）。

## 怎么验（真机级自动化）

`puppeteer-core` + 本机 Chrome，`defaultViewport: { width: 390, height: 844, isMobile: true, hasTouch: true }`：

- 点按用 `page.touchscreen.tap(x, y)`；拖动/双指/长按用 CDP 的 `Input.dispatchTouchEvent`
  （`touchStart` → 多次 `touchMove` → `touchEnd`；双指就是两个 touchPoint；长按 = touchStart 后 hold 900ms 再 end）。
- 断言要读「世界变换」而不是像素：`document.querySelector('.canvas-stage__world').style.transform` 里的 `scale(...)`。
- 长按/捏合这类会改变视野的用例，**顺序上先做长按再做捏合**，或者先点工具条的 `1:1` 复位，否则元素被放大到屏幕外、坐标点不到。

## 还没做（想做再补）

- 画布的双指旋转、双指拖拽框选；手机上连接点靠「选中后常显」（桌面是 hover 才显示）。
- 表格页的行内快捷操作（手机上点行进详情）——目前仍是桌面式表格 + 横向滚动。
