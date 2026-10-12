# PocketBase 集合与数据

服务端：PocketBase **0.40.5**（`http://192.168.1.168:8090`）。superuser 登录用 `POST /api/collections/_superusers/auth-with-password`，之后所有请求带 `Authorization: <token>`。

## 六个业务集合

由 `frontend/scripts/setup-collections.mjs` 创建，权限统一为「登录用户可读写」（`@request.auth.id != ""`，superuser 天然全权限）：

| 集合 | 字段（名称 / 类型） | 用途 |
| --- | --- | --- |
| `sys_menu` | `name` text*、`parent` text、`path` text*、`component` text、`icon` text、`sort` number、`visible` bool、`permission` text | 菜单与路由配置 |
| `sys_dict` | `dict_type` text*、`label` text*、`value` text*、`sort` number、`color` text、`remark` text | 下拉选项与标签颜色 |
| `work_task` | `title` text*、`status` select(todo/doing/done/archived)、`priority` select(high/mid/low)、`due_date` date、`progress` number、`owner` text、`tags` text、`content` text | 任务台账 |
| `work_schedule` | `title` text*、`start_at` date、`type` select(meeting/todo/remind/other)、`done` bool、`location` text、`notes` text | 待办日程 |
| `work_report` | `title` text*、`period_start` date、`period_end` date、`hours` number、`tags` text、`content` text、`issues` text、`next_plan` text | 工作记录 / 周报 |
| `work_note` | `title` text*、`tags` text、`content` text | 随手笔记 |

（`text*` = 必填。PocketBase 会自动补 `id`/`created`/`updated`。）

## 初始化命令

```powershell
# 方式一：写 frontend/.env.local（PB_URL / PB_EMAIL / PB_PASSWORD），然后
pnpm setup:pb

# 方式二：直接把凭据作为参数传（会出现在命令行历史里，注意场合）
node scripts/setup-collections.mjs --url=http://192.168.1.168:8090 --email=admin@istoreos.lan --password=...
```

脚本幂等：集合已存在就跳过；`sys_menu` / `sys_dict` 已有数据就跳过，加 `--force-seed` 才会追加默认菜单与字典。新增字段时不要重跑脚本（它不会改已存在的集合定义），直接在 PocketBase 管理后台 `/_/` 里加字段，或走 `PATCH /api/collections/<name>`。

默认灌入：`sys_menu` 10 条（工作台 / 日常工作 4 个子项 / 系统管理 3 个子项）、`sys_dict` 11 条（`task_status` 4、`task_priority` 3、`schedule_type` 4）。字典的 `color` 取 Element Plus 的标签色名（`primary`/`success`/`warning`/`danger`/`info`），直接决定列表里标签长什么样。

## 前端用到的查询语法

引擎在 `CrudTable/index.vue` 的 `buildFilter()` 里拼 PocketBase filter：

- 关键词：`(title~'x'||content~'x')` —— 由字段的 `searchAll` 决定参与哪些列
- 文本/日期：`field~'值'`（包含匹配）；select/bool：`field='值'` / `field=true`
- 组合用 `&&`，字符串里的 `\` 与 `'` 会被转义
- 排序：`sort=-updated`（前缀 `-` 为降序）；分页 `page` / `perPage`（前端可选 10/20/50/100）
- 空值过滤注意 `due_date!=''`（date 字段清空后是空字符串，直接比较会报错）

## 常见错误与处置

- **列表提示「集合不存在，请先执行 pnpm setup:pb」**：请求 404，集合没建或名字写错。到「系统管理 → 集合总览」看缺哪个（该页读集合元信息，需要 superuser 登录）。
- **401**：token 失效（PocketBase 默认 120 小时），前端会自动清登录态；重新登录即可。
- **写记录 400 且提示字段类型**：date 字段要传 `YYYY-MM-DD HH:mm:ss`（前端 `localToPbDate` 已处理），number 字段不要传空字符串。
- **superuser 密码忘了**：在 N1 上执行
  `docker exec pocketbase /pb/pocketbase superuser upsert admin@istoreos.lan '<新密码>'`
  （`upsert` 会创建或更新，不需要先登录）。

## 现网数据现状（2026-10-12）

13 个集合：6 个 PocketBase 内置（`_superusers` / `users` / `_mfas` / `_otps` / `_externalAuths` / `_authOrigins`）、`demo_posts`（早期测试页残留的空集合，可删）、以及上面 6 个业务集合。`sys_menu` 10 条、`sys_dict` 11 条，四个 `work_*` 表为空。
