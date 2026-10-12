# 架构与改动入口

## 技术栈与目录

Vue 3.5 + Vite 8 + TypeScript + Element Plus 2.14 + Pinia 4 + Vue Router 5（hash 模式）。构建产物由 PocketBase 静态托管，**没有后端服务需要部署**（PocketBase 自己就是后端）。

```
G:\文档\ChatGPT\ruoyi\
├── frontend\                     ← 前端工程（本技能主场）
│   ├── scripts\
│   │   ├── setup-collections.mjs       建集合 + 灌默认菜单/字典（HTTP API，非交互）
│   │   ├── deploy.mjs                  发 dist；支持 docker:// / ssh:// / 本地或共享路径
│   │   └── deploy-interactive.ps1      自动探测容器与挂载后再发（推荐手工发布时用）
│   ├── src\
│   │   ├── api\pb.ts                   PocketBase REST 封装：登录、记录增删改查、集合探测
│   │   ├── components\CrudTable\       配置化 CRUD 引擎 + FieldControl 字段渲染
│   │   ├── config\modules\             各业务模块的字段配置（加模块改这里）
│   │   ├── config\fallbackMenu.ts      sys_menu 不可用时的内置菜单
│   │   ├── layout\                     若依式布局：侧边菜单 / 面包屑 / 标签页
│   │   ├── router\index.ts             静态路由 + Layout 壳
│   │   ├── router\guard.ts             登录守卫 + 动态路由注入 + 标题
│   │   └── stores\{user,menu,dict}.ts  登录态 / 菜单树 / 字典
│   ├── .env.development               VITE_PB_URL 指向 N1（开发态跨网直连）
│   └── .env.production                VITE_PB_URL 留空 = 与页面同源
├── pocketbase-test\index.html    早期连通性测试页（已退役，留在本地做参考）
└── src\RuoYi\                    当初克隆的若依单体版源码，仅作参考，未运行
```

## 配置化 CRUD 引擎（核心）

`src/components/CrudTable/index.vue` 接收 `ModuleSchema`，一份配置同时渲染三处：

- `inSearch: true` 的字段 → 顶部查询条件区（文本用 `~` 包含匹配，select/bool 用 `=`，日期用 `~` 匹配当天）
- `inTable !== false` 的字段 → 表格列（`format: 'progress'` 渲染进度条，select 按字典颜色渲染标签，tags 拆成多个标签）
- `inForm !== false` 的字段 → 新增/编辑对话框表单（`span: 24` 占整行，`required: true` 自动生成校验）

引擎自带分页、排序（`sort-change` 映射为 PocketBase 的 `-field`）、批量删除、CSV 导出（带 BOM，解析当前筛选条件，最多 2000 条）、以及删除确认。

`FieldSchema` 常用键：`key`（PocketBase 字段名）、`label`、`type`（`text`/`textarea`/`number`/`select`/`date`/`datetime`/`bool`/`tags`/`editor`/`password`）、`dict`（字典类型，优先于 `options`）、`options`、`inSearch`/`inTable`/`inForm`、`searchAll`（参与顶部关键字模糊搜索，多个字段用 `||` 拼）、`width`/`minWidth`、`sortable`、`default`、`format`、`span`、`filterable`/`allowCreate`/`multiple`。

## 菜单与字典机制

1. `stores/menu.ts` 拉 `sys_menu`（`perPage: 200`，按 `sort` 排序）→ `buildTree()` 按 `parent`（存父级 `path`，顶级为空）建树 → `flatLeaves()` 取叶子。
2. `guard.ts` 在首次进入受保护路由时，把叶子菜单**扁平注册**到 Layout 路由下（`router.addRoute('Layout', …)`），组件字符串通过 `import.meta.glob('../views/**/*.vue')` 解析；侧边栏则直接用菜单树渲染成多级 `el-menu`，父级菜单只是分组、不参与路由。
3. 兜底：`sys_menu` 不存在或为空 → 用 `FALLBACK_MENU`，所以**不初始化后端也能跑通界面**；`menuStore.source` 会告诉当前用的是哪一种。
4. `stores/dict.ts` 一次拉完 `sys_dict` 并按 `dict_type` 分组缓存；`optionsOf(field)` 字典优先、字段内置 `options` 兜底；`labelOf`/`colorOf` 供表格与看板渲染标签文字和颜色。

## 登录与请求

- `api/pb.ts` 用 axios，`baseURL` 取「localStorage 里保存的地址 → 构建期 `VITE_PB_URL` → 当前 origin」。
- 登录先试 `_superusers`（PocketBase 内置超管），失败再试 `users` 集合；token 存 localStorage。
- 401 且有 token → 清登录态、重置菜单与字典缓存、跳回登录页（`setUnauthorizedHandler`）。
- 登录页提供「自定义服务地址」开关：直接用 `dist/index.html` 打开时会自动带出兜底地址，方便直连 N1。

## 加一个业务模块（三步）

1. `src/config/modules/<模块>.ts` 写 `ModuleSchema`（照抄 `task.ts` 改字段）。
2. `src/views/<目录>/Index.vue` 写薄壳：`<CrudTable :schema="xxxSchema" />`。
3. 在 PocketBase 建对应集合（见 [pocketbase-collections.md](pocketbase-collections.md)），再到「系统管理 → 菜单配置」加一条记录：`component` 填 `views` 下的相对路径（如 `work/task/Index`）、`path` 填路由地址、`parent` 填父级菜单的 `path`。

第 3 步做完刷新页面即生效，**不需要重新构建前端**。反之如果只改了 schema（字段增减），需要重新构建并发布，因为 schema 在前端代码里。

## 什么时候不用 CrudTable

交互不是「表格 + 对话框」时，写专用视图更合适：`CrudTable` 只提供分页、排序、搜索、对话框表单和 CSV 导出，没有行内勾选、详情面板、分桶分组、富文本就地编辑这些能力。已有两个先例：待办事项（`views/work/todo` + `components/TodoBoard` + `stores/todo.ts`，见 [todo-module.md](todo-module.md)）与随手笔记（`views/work/note` + `components/NoteBoard` + `stores/note.ts`，见 [note-module.md](note-module.md)）。它们都绕开 schema，改用 Pinia store 管状态、用 `pb.listRecords` 拼 filter 拉数据。判断标准：如果用户要的是「一眼扫过 + 就地操作」，就做专用视图；如果是「录入与台账」，就用 schema + CrudTable。
交互不是「表格 + 对话框」时，写专用视图更合适：`CrudTable` 只提供分页、排序、搜索、对话框表单和 CSV 导出，没有行内勾选、详情面板、分桶分组、富文本就地编辑这些能力。已有三个先例：待办事项（`views/work/todo` + `components/TodoBoard` + `stores/todo.ts`，见 [todo-module.md](todo-module.md)）、随手笔记（`views/work/note` + `components/NoteBoard` + `stores/note.ts`，见 [note-module.md](note-module.md)）与无限画布（`views/work/canvas` + `components/CanvasBoard` + `stores/canvas.ts`，见 [canvas-module.md](canvas-module.md)）。它们都绕开 schema，改用 Pinia store 管状态、用 `pb.listRecords` 拼 filter 拉数据。判断标准：如果用户要的是「一眼扫过 + 就地操作」，就做专用视图；如果是「录入与台账」，就用 schema + CrudTable。
