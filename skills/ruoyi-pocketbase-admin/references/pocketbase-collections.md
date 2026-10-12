# PocketBase 集合与数据

服务端：PocketBase **0.40.5**（`http://192.168.1.168:8090`）。superuser 登录用 `POST /api/collections/_superusers/auth-with-password`，之后所有请求带 `Authorization: <token>`。

## 六个业务集合

由 `frontend/scripts/setup-collections.mjs` 创建，权限统一为「登录用户可读写」（`@request.auth.id != ""`，superuser 天然全权限）：

| 集合 | 字段（名称 / 类型） | 用途 |
| --- | --- | --- |
| `sys_menu` | `name` text*、`parent` text、`path` text*、`component` text、`icon` text、`sort` number、`visible` bool、`permission` text | 菜单与路由配置 |
| `sys_dict` | `dict_type` text*、`label` text*、`value` text*、`sort` number、`color` text、`remark` text | 下拉选项与标签颜色 |
| `work_task` | `title` text*、`status` select(todo/doing/done/archived)、`priority` select(high/mid/low)、`due_date` date、`progress` number、`owner` text、`tags` text、`content` text、`source_id` text、`archived_at` date | **归档任务**（待办里完成/删除的任务自动归档到这里，`source_id` 存来源待办 id 做幂等键） |
| `work_schedule` | `title` text*、`start_at` date、`type` select(meeting/todo/remind/other)、`done` bool、`location` text、`notes` text | 待办日程 |
| `work_report` | `title` text*、`period_start` date、`period_end` date、`hours` number、`tags` text、`content` text、`issues` text、`next_plan` text | 工作记录 / 周报 |
| `work_note` | `title` text*、`tags` text、`content` text | 随手笔记 |
| `work_todo_list` | `title` text*、`color` select(primary/success/warning/danger/info)、`sort` number | 待办清单 |
| `work_todo` | `title` text*、`list` relation→work_todo_list（maxSelect 1、cascadeDelete false，可空=未分类）、`due_date` date、`important` bool、`done` bool、`completed_at` date、`my_day` date、`notes` text、`steps` json | 待办事项（微软 To Do 风格，见 [todo-module.md](todo-module.md)） |

（`text*` = 必填。`id` 由 PocketBase 自动生成，但 **`created` / `updated` 不会自动加**，见下面的坑。）

## 必须显式声明 `created` / `updated`（踩过）

v0.23+ 把 `created` / `updated` 从隐式系统字段改成了**可选的 autodate 字段**：Dashboard 里建集合默认勾选，纯 API 建（就是 `setup-collections.mjs` 这条路）则必须自己写：

```js
{ name: 'created', type: 'autodate', onCreate: true, onUpdate: false }
{ name: 'updated', type: 'autodate', onCreate: true, onUpdate: true }
```

缺失时的表现极具误导性：读取正常，但任何 `sort=-created` / `sort=-updated` 都返回 `HTTP 400 {"message":"Something went wrong while processing your request."}`，界面则显示「读取失败」。`sys_menu`、`sys_dict`、`work_*` 这 8 个集合都已经补上；新写集合定义时别忘了这两个字段（`collection()` 帮助函数已自动追加）。

## 初始化命令

```powershell
# 方式一：写 frontend/.env.local（PB_URL / PB_EMAIL / PB_PASSWORD），然后
pnpm setup:pb

# 方式二：直接把凭据作为参数传（会出现在命令行历史里，注意场合）
node scripts/setup-collections.mjs --url=http://192.168.1.168:8090 --email=admin@istoreos.lan --password=...
```

脚本是幂等且自愈的：

- 集合不存在就建；已存在则**只补缺失字段**（按字段名比对，`PATCH` 时把已有字段原样回传，绝不改动或删除既有字段），所以给集合加字段后重跑一次即可。
- 菜单**按 `path` 缺则补**，不会覆盖你在「系统管理 → 菜单配置」里改过的记录；要按默认值整条覆盖才加 `--force-seed`。
- `sys_dict` 仍只在空表或 `--force-seed` 时灌默认字典。
- `work_todo` 是两阶段创建：先确保 `work_todo_list` 存在，再用它的集合 id 建 relation 字段。

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
