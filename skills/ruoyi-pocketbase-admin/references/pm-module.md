# 项目管理（需求池 · 进度总览 · GitHub 仓库状态）

2026-10-14 新增。用来随手记想法、把需求从「想法」推到「已完成」，并在一屏里看清各项目/模块的进度与对应 GitHub 仓库的状态。

## 页面与文件

| 页面 | 路由 | 数据 | 实现方式 | 代码位置 |
| --- | --- | --- | --- | --- |
| 项目总览 | `/pm/overview` | `pm_project` / `pm_module` / `pm_item` + GitHub 公开 API | 专用视图（统计卡 + 项目卡 + 模块表 + 趋势条 + 仓库卡） | `views/pm/overview/Index.vue` + `components/PmBoard/RepoCard.vue` |
| 需求看板 | `/pm/board` | `pm_item` | 专用视图（6 列看板 + 原生拖拽 + 详情抽屉 + 回收站） | `views/pm/board/Index.vue` + `components/PmBoard/*` |
| 项目与模块 | `/pm/setup` | `pm_project` / `pm_module` | schema CRUD（两个页签各一个 `CrudTable`） | `views/pm/setup/Index.vue` + `config/modules/pmProject.ts` |
| 顶栏入口 | 全站 | 写 `pm_item` | 「+ 想法」小对话框，`Alt+I` 快捷键 | `layout/components/Navbar.vue` + `components/PmBoard/QuickIdeaDialog.vue` |
| 工作台卡片 | `/dashboard` | 跨 `pm_project` / `pm_item` | 一行一个「进行中」项目的进度 | `views/dashboard/Index.vue` |

状态与业务规则全在 `stores/pm.ts`：`init/loadAll/patchItem/quickAdd/trashItem/restoreItem/purgeItem/createTodoFromItem/progressOf/doneTrend`。

## 数据模型（3 张集合 + 5 类字典）

由 `frontend/scripts/setup-collections.mjs` 幂等创建（无 relation 字段，不需要两阶段）：

| 集合 | 字段 |
| --- | --- |
| `pm_project` | `name`*、`repo`（`owner/repo`）、`status` select(active/paused/done/archived)、`description`、`sort` |
| `pm_module` | `project`*、`name`*、`status` select(planned/doing/done/paused)、`description`、`sort` |
| `pm_item` | `title`*、`content`、`project`、`module`、`kind` select(idea/feature/bug/optimize/doc)、`status` select(idea/planned/doing/testing/done/paused/dropped)、`priority` select(high/mid/low)、`estimate`、`target`、`tags`、`issue_url`、`todo_id`、`done_at`、`trashed`、`trashed_at` |

**`project` / `module` 存的是目标记录的 id，故意做成文本字段而不是 relation**：`CrudTable` 的字段类型里没有 relation，改成文本 + 页面动态生成下拉选项（照抄「菜单配置」页里父级菜单的写法）就能一份 schema 通吃查询/表格/表单，也不用动表格引擎。代价是库里没有外键约束（`views/pm/setup/Index.vue` 里用「删除前统计下面还有多少模块/需求」来兜住）。

字典类型：`pm_project_status`、`pm_module_status`、`pm_item_status`、`pm_item_kind`、`pm_item_priority`（颜色就是 Element Plus 的标签色）。状态的标签与颜色统一从 `config/modules/pmItem.ts` 里导出的 `pmStatusField` / `pmKindField` / `pmPriorityField` 查（`dictStore.labelOf(pmStatusField, value)`），改一处就同时影响看板、抽屉、总览。

## 进度怎么算

`progressOf(predicate)` 一个函数供项目卡与模块表共用：

- **分母**：状态属于 `planned / doing / testing / done` 的条目（`COUNTED_STATUSES`）。
- **分子**：其中 `status='done'` 的数量。
- 「想法」（idea）不进分母，单独显示成「想法池」数量；「搁置/废弃」（paused/dropped）同样不进分母。
- `estimate`（估算工时）只展示、不参与加权——按数量算更不容易被「懒得填工时」拖垮。
- 近 7 天趋势用 `done_at` 的前 10 位（本地墙钟日期，和全站日期约定一致，别改成 `pbDateToLocal`）。

## 看板交互

- 桌面拖拽是**原生 HTML5 DnD**（不加依赖）：`PmItemCard` 的 `dragstart` 把 id 写进 `dataTransfer`，`KanbanColumn` 的 `drop` 派发 `drop(id, column)`，页面调 `patchItem(id, { status: column.status })`；本地先改（乐观更新），失败回滚并在 `lastError` / `ElMessage` 里说原因。
- 最后一列「搁置 / 废弃」合并了 `paused` 与 `dropped`，**拖进去默认置 `paused`**；要标「废弃」在详情抽屉里改（避免误标）。
- 触屏（`matchMedia('(pointer: coarse)')`）或 ≤900px 时卡片上多一个状态下拉，拖拽不参与（`draggable=false`）。
- 详情抽屉：选择类字段（状态下拉、项目、模块、类型、优先级、估算）改动即存；文本类（标题/正文/目标版本/标签/issue）debounce 800ms 自动保存，关闭抽屉、离开组件、`beforeunload` 时 flush。标题栏右上角一直显示「已保存 / 未保存… / 保存失败」。
- 换项目时会检查原模块是否属于新项目，不属于就顺手清空，避免出现跨项目的模块。
- 列表由 `pmStore.init()` 一次拉全（`listAll`，上限 500）在本地过滤：看板要分列、总览要算进度，分页请求反而更麻烦。条目多到这个量级再改成服务端过滤。

## 需求 → 待办（单向联动）

抽屉里「转成待办」调 `pmStore.createTodoFromItem(item)`：

1. 在 `work_todo` 建一条，标题 `[项目·模块] 需求标题`（`labelOf`），`notes` 里写来源、项目/模块、需求 id 与正文摘要。
2. 成功后把 `todo_id` 回写到 `pm_item`，并**把「想法/已规划」自动推进成「开发中」**。
3. 已有 `todo_id` 时按钮变成「已在待办里」不可重复点（幂等）；建待办失败就抛错并保留原状。

反向不联动：待办完成后照旧进「归档任务」，需求侧状态不受影响，只保留「已转待办」标记。

删除是**软删除**：`trashed=true` + `trashed_at`，看板上「回收站」勾选框里还原或彻底删除；彻底删除才 `DELETE` 记录（不写 `work_task`，和待办的归档规则无关）。

## GitHub 取数（`api/github.ts` → N1 钩子 `/api/gh/repo`）

2026-10-14 改造。原来是**浏览器直连** `https://api.github.com`（匿名 = 只认公开仓库），备份仓库转私有后
卡片只剩一句「仓库不存在或已改名」，所以改成**服务端代理**：令牌只放在 N1 上，浏览器拿不到。

```
浏览器 ── GET /api/gh/repo?slug=owner/repo（带 PB 登录令牌，需登录）──> pb_hooks/github.pb.js
                                                                      └─ $http.send 打 api.github.com（Bearer 令牌）
```

- **钩子**：`pb_hooks/github.pb.js`（源码副本在开发机 `pocketbase-hooks/github.pb.js`）。它做 4 个请求
  （`/repos/{slug}`、`/pulls?state=open`、`/commits?per_page=5`、`/commits?since=<本周一 ISO>&per_page=1`），
  把 `Link` 头 `rel="last"` 的页码当本周提交数（没有 `Link` 就按返回条数算 0/1），顺手把
  `open_issues_count` − 开放 PR 数 = 真 issue 数。响应形状：`{slug, ok, error?, repo, openPulls, weekCount, commits, rate, cachedAt}`。
  另有 `GET /api/gh/status`（令牌是否配置 + 剩余配额）用来排查。
- **令牌**：`github.pb.js` 顶部的 `GH_TOKEN`，建议**只读细粒度 PAT**（Repository access 勾上所有要显示的
  仓库；Permissions：Metadata=Read、Contents=Read）。没配时接口返回「N1 上还没配置 GitHub 令牌…」，
  卡片直接把这句显示出来。注意：这个文件在 `/opt/pocketbase/pb_hooks/` 里，**会被每周的整容器备份带走**
  （和 OSS 的 AK/SK 一样），所以备份仓库必须私有。
  **细粒度令牌的 Repository access 是白名单**：漏勾的仓库 GitHub 一律回 404（不是 403），
  最省事的排查办法是 `GET /api/gh/status`（它会用 `/user/repos` 列出 `accessibleRepos`），
  或直接 `curl -H "Authorization: Bearer <令牌>" https://api.github.com/repos/<owner>/<repo>`。
- **盯某个分支**：`pm_project.repo` 支持 `owner/repo#分支`（`parseRepoRef` 解析，缓存键仍用 slug），
  钩子会带 `sha=<分支>` 拉提交与本周提交数，卡片上的「默认分支」显示实际盯的分支。
  备份仓库就是典型例子：内容全在 `pb-backup` 分支上，默认分支只有一句 README。
  **2026-10-15 已配好**（`github_pat_11AX…`，只读细粒度 PAT，Repository access 勾了 5 个仓库：MianHelperDocker /
  HotPackTest / MianSkill / UltraControlSystem / UnrealPackTimeVerification）。**改令牌的标准动作**是：改开发机
  副本 `pocketbase-hooks/github.pb.js` 的 `GH_TOKEN` → `scp -O` 覆盖 N1 的
  `/opt/pocketbase/pb_hooks/github.pb.js` → `docker restart pocketbase`（不要只改一头：本地是占位符时一次 scp
  就会把 N1 上的真令牌覆盖回 `__GITHUB_TOKEN__`）。验证：以 superuser 登录取 token 后
  `GET /api/gh/status` 应回 `configured: true` + `remaining`；`GET /api/gh/repo?slug=…` 对 `LuckyMian/MianHelperDocker`
  应回 `ok: true`、`repo.private: true`。`/api/gh/status` 与 `/api/gh/repo` 都要登录，匿名叫是 401/403。
- **缓存**：服务端 5 分钟（`GH_CACHE_SECONDS`，多个浏览器刷新不会重复打 GitHub，`force=1` 跳过）+
  前端 `localStorage` 键 `pm_gh_cache_v2`，TTL 30 分钟（`GH_CACHE_TTL_MS`）。**全部仓库都失败时不刷新
  前端缓存时间戳**（`anySuccess`）：缓存算过期，下次进页面自动重试，配好令牌后不用等 30 分钟、也不用点「刷新」。
- **配额显示**：页脚「GitHub 剩余配额 N 次（HH:mm 重置）」现在取的是**令牌**的限额（5000 次/小时），
  由 `/api/gh/repo` 响应里的 `rate` 字段带回。
- **必须看状态码，不能只看 body**（2026-10-15 踩过）：404/403 的错误体里也有 JSON（`{"message":"Not Found"}`），
  只判断「body 是不是空」会把「令牌没勾这个仓库」当成取数成功，卡片就显示成「没有读到提交记录」（数字全是 0），
  看起来像前端 bug。钩子里现在先判 `status`、再判 `json`。
- **钩子里别把函数存进 `$app.store()` 再从回调里调**（同一天踩过）：回调分属 JSVM 运行时池的不同运行时，
  跨运行时调用同一个函数对象会让进程 `[PANIC RECOVER]`，前端只看到「Something went wrong while processing your request.」。
  实测 6 个并发请求挂 4 个（顺序请求全对，所以**单条 curl 测试通过 ≠ 并发安全**）。现在 `github.pb.js` 每个回调
  自带完整逻辑，`$app.store()` 里只放纯数据（`gh_config`：令牌/接口地址/超时），服务端也不做缓存。细节见
  [oss-images.md](oss-images.md) 的五条硬约束。
- **失败降级**：钩子把 GitHub 的错误翻成人话（401 令牌无效、403/429 配额或权限、404 仓库不存在或令牌没授权），
  卡片显示这句话并**保留上一次成功的数据**；未登录/登录过期时前端提示「登录已过期，重新登录后即可显示私有仓库」。
  任意一个仓库失败只影响它自己的卡片。改钩子时别踩 JSVM 的坑（见 [oss-images.md](oss-images.md)）：处理器回调里
  看不到文件级 `const`（`$app.store()` 的 key 必须写字面量）、没有 `require`、`$os.readFile` 读不存在的文件会 panic。
- 仓库列表来自 `pm_project.repo`（`parseRepoSlug` 能认 `owner/repo`、仓库 URL、`git@` 形式），所以加项目就等于加仓库，不用另配清单。

## 加东西的步骤

- 加一个字段：改 `scripts/setup-collections.mjs` 的集合定义 → `pnpm setup:pb` → 改 `config/modules/pmItem.ts` 或页面里的表单 → `pnpm build` 发布（**PM 的字段 schema 在前端代码里**，和全站一致）。
- 加一个状态：字典（数据，界面上改即时生效）+ 集合 select 候选值（要跑 `setup:pb` 做并集扩值）+ `stores/pm.ts` 的 `COUNTED_STATUSES`/`PM_COLUMNS`（要构建）。
- 预置项目：`SEED_PROJECTS`（按 `name` 缺则补，不覆盖界面改过的记录，`--force-seed` 才整条覆盖）。

## 踩过的坑

1. **集合不存在时不能把页面搞白**：`loadAll` 用「HTTP 状态码 404 或消息里带 404/not found/集合」双条件判断（某些错误文案里没有「404」字样），命中的集合名进 `missing`，由页面显示「先跑 pnpm setup:pb」提示；`init()` 自己吞掉意外错误并写进 `lastError`，页面显示一行红条而不是崩掉。写这段时的反例：用 `request.respond` 伪造 404 但忘了带 `Access-Control-Allow-Origin`，浏览器会当成 `Network Error`，状态码判断就失效。
2. **Element Plus 的下拉浮层在自动化里很难点**：`ElementHandle.click()` 对 teleport 出来的浮层会报「Node is either not clickable or not an Element」，DOM 的 `el.click()` 又不带 `mousedown/pointerdown`，Element Plus 不认。**用 `page.mouse.click(x, y)` 打真实坐标**，并且浮层有淡入动画，量坐标前先等 ~350ms。选中值不在 `input.value` 里，而在 `.el-select__selected-item`（读 `.el-select__wrapper` 的 innerText 最省事）。
3. **看板被 keep-alive 缓存**：`layout/Index.vue` 的 `<keep-alive>` 让看板的筛选、回收站勾选状态在切页后保留。写自动化时要先整页 `reload()` 再断言，别以为「进页面就是干净状态」。
4. 拖拽回滚：`patchItem` 先本地改再请求，失败用保存的旧对象回滚；不要在失败分支里重新拉全量（会把用户正在编辑的表单数据冲掉）。

## 验证

`pnpm type-check` + `pnpm build` 之后，用本机 Chrome + `puppeteer-core` 跑端到端（登录 → 顶栏/看板快捷捕获 → 拖到「开发中」→ 抽屉改优先级与正文并等「已保存」→ 转成待办 → 去 `/work/todo` 看到带项目前缀的条目 → 刷新后仍在 → 回收站软删/还原 → 总览进度与仓库卡 → 手机端状态下拉与横向滚动 → 断网/404/集合缺失三种失败路径）。要点：

- 断言用**轮询**（`page.waitForFunction`），`ElMessage` 默认 3 秒就消失。
- 按 `PM_E2E_APP` 环境变量切换目标，同一个脚本既能打 `http://localhost:5173` 也能打线上 `http://192.168.1.168:8090`。
- 脚本会造一条测试需求并生成待办，**结束后用 superuser token 直接 `DELETE` 清掉**（不要去点待办页的删除，那会把测试垃圾写进「归档任务」）。
