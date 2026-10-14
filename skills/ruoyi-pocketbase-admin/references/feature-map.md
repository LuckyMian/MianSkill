# 功能地图与方法归纳

一页看清「已经做了什么、每块用了什么方法」，以及新需求该走哪条路。细节在各专题 reference 里，这里只做索引与归纳（2026-10-12 按当前代码整理）。

## 一、页面清单

| 页面 | 路由 | 数据 | 实现方式 | 代码位置 |
| --- | --- | --- | --- | --- |
| 登录 | `/login` | `_superusers` / `users` | 专用页 | `views/login/Index.vue` |
| 工作台 | `/dashboard` | 跨 4 张表聚合 | 只读聚合页（勾选待办复用 todoStore） | `views/dashboard/Index.vue` |
| 待办事项 | `/work/todo` | `work_todo` / `work_todo_list` | **专用视图** + Pinia store | `views/work/todo` + `components/TodoBoard` + `stores/todo.ts` |
| 归档任务 | `/work/task` | `work_task` | schema CRUD（`canEdit: false`，操作列用 `#row-actions` 插槽加「还回待办」） | `config/modules/task.ts` + `views/work/task/Index.vue`（薄壳 + 行操作） |
| 工作记录 | `/work/report` | `work_report` | schema CRUD | `config/modules/report.ts` |
| 随手笔记 | `/work/note` | `work_note` / `work_note_folder`（+ 阿里云 OSS） | **专用视图** + store + 服务端钩子 | `views/work/note` + `components/NoteBoard` + `stores/note.ts` |
| 无限画布 | `/work/canvas` | `work_canvas` / `work_canvas_item`（+ 阿里云 OSS） | **专用视图** + store + DOM 自绘无限画布（含连线流程图、全屏专注） | `views/work/canvas` + `components/CanvasBoard` + `stores/canvas.ts` |
| VPN | 无路由（页面已下线） | 无库表；入口地址由主机名推导（`sys_dict.vpn_panel_token` 可选） | 工作台主页「打开 VPN 面板」按钮 → **新标签**打开 nginx 入口（9080/19080）里的 metacubexd | `views/dashboard/Index.vue` + N1 `/etc/nginx/conf.d/vpn.conf`，见 [vpn-tools.md](vpn-tools.md) |
| 菜单配置 | `/system/menu` | `sys_menu` | schema CRUD（schema 写在页面里，因为下拉选项要按库里数据动态生成） | `views/system/menu/Index.vue` |
| 字典配置 | `/system/dict` | `sys_dict` | schema CRUD | `config/modules/sysDict.ts` |
| 集合总览 | `/system/collections` | 集合元信息（需 superuser） | 只读诊断页 | `views/system/collections/Index.vue` |
| 待办日程（已下线） | `/work/schedule` | `work_schedule` | schema CRUD，代码保留未挂菜单 | `config/modules/schedule.ts` |

外壳（全站共用，`layout/`）：`Sidebar`（菜单树 → 多级 `el-menu`）、`Navbar`（面包屑 + 服务健康标签 + 「菜单来源是 sys_menu 还是内置兜底」提示 + 退出）、`TagsView`（多标签页）。

横切能力：

| 能力 | 位置 | 一句话 |
| --- | --- | --- |
| 菜单驱动路由 | `stores/menu.ts` + `router/guard.ts` | `sys_menu` → `buildTree()` → 扁平注册到 Layout；拉不到就退 `config/fallbackMenu.ts` |
| 字典驱动下拉与颜色 | `stores/dict.ts` | `sys_dict` 按 `dict_type` 分组缓存；`optionsOf` / `labelOf` / `colorOf` |
| 配置化 CRUD | `components/CrudTable` + `config/modules/*.ts` | 一份 schema 驱动查询 / 表格 / 表单，自带分页、排序、批量删除、CSV；按钮开关 `canEdit`/`canDelete`…、行内专属动作走 `#row-actions` 插槽 |
| 请求层 | `api/pb.ts` | axios 封装；基础地址三级回退（localStorage → `VITE_PB_URL` → 同源）；401 统一登出 |
| OSS 图片 | `api/oss.ts` + 服务器 `pb_hooks/oss.pb.js` | 浏览器直传 OSS（目录白名单 `notes/`、`canvas/`），正文只存 `data-oss-key`，私有桶签名读；网页图片可让服务端代抓转存（`/api/oss/fetch`） |
| 亮/暗主题 | `stores/ui.ts` + `style.css` 的 `--app-*` 变量 + Element Plus 官方暗色变量 | `<html>.dark` 一切，全站换肤；专注模式（画布全屏）也在 ui store，见 [theme.md](theme.md) |
| 手机端 | `layout/Index.vue`（≤900px 外壳）+ 各页抽屉 + `CanvasStage` 触摸手势 | 侧栏改抽屉、隐藏标签栏、表格弹窗单列、画布双指缩放/长按菜单，见 [mobile.md](mobile.md) |
| 日期与格式化 | `utils/format.ts` | `pbDateOnly` / `localDay` / `humanDay` / `toCsv` |
| 初始化 | `scripts/setup-collections.mjs` | 幂等建集合、补缺失字段、灌默认菜单与字典 |
| 发布 | `scripts/deploy.mjs` + `deploy-interactive.ps1` | `dist` → `pb_public`，只写不删 + 覆盖前备份 |

## 二、方法归纳（可以重复用的套路）

### 1. 先定形态，再动手

判断标准是交互形状，不是数据量：

- 要的是**录入与台账**（表格 + 查询 + 新增/编辑对话框）→ 写一份 `ModuleSchema`，页面就三行壳。
- 要的是**一眼扫过 + 就地操作**（分栏、分桶、拖拽、自动保存、富文本）→ 专用视图：`views/xxx/Index.vue` 薄壳 + `components/XxxBoard/*` 渲染 + `stores/xxx.ts` 管数据。

`CrudTable` 只覆盖分页/排序/搜索/对话框表单/批量删除/CSV，没有行内勾选、详情面板、分桶分组、就地编辑——硬塞进去会比直接写专用视图更贵。已有三个先例：待办事项、随手笔记、无限画布。

画布这一类还有额外一条判断：**自绘 vs 现成库**。无限画布选了「DOM + CSS transform 自研」（每张图一个绝对定位元素、整体一个 `translate/scale` 层），
理由是零新依赖、命中测试/右键菜单/文字编辑全部白送，几百张图也够快；代价是缩放手柄、裁剪、吸附这些几何逻辑要自己写（见 [canvas-module.md](canvas-module.md)）。

### 2. 一份 schema 驱动三处，但记住它的代价

加字段只改 `config/modules/*.ts`：`inSearch` 决定查询区、`inTable !== false` 决定表格列、`inForm !== false` 决定表单控件。

代价要分清：**schema 在前端代码里，改字段必须重新构建并发布**；而菜单、字典是数据，在页面上改完刷新即生效、不用构建。这也是「加一个新模块」只有第三步（菜单记录）能免构建的原因。

### 3. 专用视图一律三段式

`views/*` 只做布局与响应式（窄屏收抽屉），`components/*Board/*` 只渲染与发出动作，**请求与业务规则全在 `stores/*.ts`**。好处是工作台这类别的页面可以复用同一个 store（工作台勾选待办就走 `todoStore.completeTodo()`，因此同样会触发归档），行为只有一份。

### 4. store 的命名约定

`scopeFilter()` 产出 PocketBase filter、`loadXxx()` 拉数据、`create/patch/remove` 是通用记录操作、领域动作按业务命名（`completeTodo` / `trashNote` / `deleteFolder`）、`refresh()` / `reset()` 收尾。过滤器里的字符串要转义（`\` 与 `'`），所有查询都显式带上「未删除 / 未完成」这类前置条件，别依赖调用方记得加。

### 5. 破坏性动作：先落账，再删除（反向也要对称）

待办的「完成」和「删除」都是先写 `work_task`（`source_id` 存来源待办 id 做幂等键，重复触发只更新同一条），写成功才 `DELETE` 原记录；归档失败就保留待办并把原因放进 `archiveError` 显示出来。**不要为了「删干净」把失败吞掉**——宁可留下一条待办，也不要丢数据。同类规则：删除清单先把清单下的待办移到未分类（relation 是 `cascadeDelete=false`，前端必须自己兜），整条笔记进「最近删除」不回收图片，只有彻底删除才回收。

反向动作照抄同一个套路，只把顺序倒过来：归档页的「还回待办」先建 `work_todo`，成功后才删 `work_task`；建待办失败就保留归档记录（`todoStore.restoreTaskToTodo()`，见 [todo-module.md](todo-module.md)）。

### 6. 日期一律「本地墙钟、不带时区」

写入 `YYYY-MM-DD HH:mm:ss`，读回来 PocketBase 会补成 `…000Z`，所以**取前 10 位就是本地日期**（`pbDateOnly()`）；不要用 `pbDateToLocal()` 走时区换算，否则日期和时间都 +8 小时。`dayjs` 只用来做「今天/明天/逾期几天」这种相对计算。

### 7. 初始化脚本三原则：幂等、自愈、显式覆盖

`pnpm setup:pb` 可以随时重跑：集合不存在才建，已存在只补缺失字段（按字段名比对、把既有字段原样回传，绝不改删）；菜单按 `path` 缺则补，不覆盖你在界面上改过的记录；字典仅在空表时灌。只有显式加 `--force-seed` 才按默认值覆盖。所以「加集合字段」的流程是改脚本 → 重跑即可，不用手点 Dashboard。

**唯一例外是 select 字段的候选值**：只做「并集扩值」（比如给 `work_canvas_item.kind` 加 `node`/`edge`），已有的值一个不动、顺序也保留。
不这么做的话，新写的枚举值会被服务端直接拒（表现是插入记录 400，提示某个 select 值非法）。

新集合务必带 `created` / `updated`（`collection()` 帮助函数已自动追加），否则任何按它们排序的请求直接 400。

### 8. 发布脚本三原则：只写不删、认准路径、先备份

目标路径必须以 `pb_public` 结尾（否则要显式 `--force`）；写入前把已有 `index.html` 备份成 `index.backup-<时间>.html`；三种目标形态（`docker://` 容器、`ssh://` 目录、本地/共享路径）覆盖同一件事。**构建永远在开发机做**，N1 上不装 Node。

### 9. PocketBase 服务端钩子是受限环境

写 `pb_hooks/*.pb.js` 时先接受四条约束（0.40.5 实测）：回调里看不到文件级作用域（用 `$app.store()` 传值）、没有 `require` 模块（签名要自己实现）、`$os.readFile` 读不到就 panic（配置写在钩子文件里）、错误默认只有笼统 400（回调里 `try/catch` 并返回 `String(err)`）。删改钩子走 SFTP，别用超长 SSH 命令。

### 10. 凭据边界

superuser 密码与 OSS 的 AK/SK 只存在于 `frontend/.env.local`（已 gitignore）和 N1 上的钩子文件；技能、仓库、README 里只写「去哪配」。发到公网前必须自己加 TLS 与访问控制，PocketBase 除账号之外不做防护。

### 11. 交互细节的固定套路

- 中文输入法的回车要判 `event.isComposing`（或 keyCode 229），否则拼音选词会被当成提交。
- 富文本工具栏必须 `@mousedown.prevent`，否则编辑器先失焦、命令作用到错误位置。
- 自动保存用 debounce + 显式 `flush()`（切页、失焦、离开组件、`beforeunload`），有未落盘的本地资源（如待上传的图片）时让位给手动保存。
- `:loading` 会连带禁用按钮，别把「已排队保存」当成「正在提交」。

详见 [note-module.md](note-module.md)（富文本与自动保存）与 [todo-module.md](todo-module.md)（输入法保护、分桶）。

### 12. 验证方法

- 界面报错先别信文案：用 `curl` 直接打 API 看状态码与 `data`，400 十有八九是缺 `created`/`updated` 或 filter 引用了不存在的字段。
- 端到端断言用**轮询**等提示出现（`ElMessage` 默认 3 秒就消失），不要固定 `sleep`。
- 私有桶签名这类纯计算可以先离线复算（Node 独立算一遍 `base64(hmac_sha1(...))`），再上真机跑端到端。
- **UI 交互也能自动化**：本机已装 Chrome，用 `puppeteer-core`（临时目录里 `npm i puppeteer-core`，不下载浏览器内核，
  `executablePath` 指向 `C:\Program Files\Google\Chrome\Application\chrome.exe`）就能跑登录 → 画布 → 上传/拖动/裁剪/撤销/回收 的完整断言。
  两个必须记住的坑：① Element Plus 的下拉浮层用完仍留在 DOM 里，`querySelector` 会点到隐藏的旧项——按
  `getBoundingClientRect().width > 0` 判可见（**不能用 `offsetParent`**，浮层是 fixed 定位、恒为 null），并在打开前给已有项打标记、只点新出现的那个；
  ② 画布内的拖动位移是世界坐标，断言时要除以当前 zoom（`scale(...)`），别按屏幕像素算。

## 三、新增一个功能的检查清单

1. 定形态：schema CRUD 还是专用视图（见上面第 1 条）。
2. 建集合：改 `scripts/setup-collections.mjs` → `pnpm setup:pb`（relation 字段要先拿到目标集合 id，照 `work_todo` / `work_note` 的两阶段写法）。
3. 写代码：schema 放 `config/modules/`；专用视图写 `views/` + `components/` + `stores/`。
4. 挂菜单：「系统管理 → 菜单配置」加一条记录，`path` 是地址、`component` 填 `views` 下的相对路径（如 `work/task/Index`）、`parent` 填父级 path；刷新即生效。
5. 校验：`pnpm type-check` → `pnpm build`。
6. 发布：`pwsh -File scripts\deploy-interactive.ps1`。
7. 验证：首页与静态资源 200、`/_/` 管理后台正常、新功能真机走一遍。
8. 结构或方法有变化时，回头更新本技能（并同步到 GitHub）。
