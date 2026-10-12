# 待办事项模块（微软 To Do 风格 v1）

区别于 `CrudTable` 那类表格模块，这一页是**专用视图**：`src/views/work/todo/Index.vue` + `src/components/TodoBoard/`（`TodoSidebar` / `TodoListPane` / `TodoRow` / `TodoDetailPane`），状态在 `src/stores/todo.ts`。数据在 `work_todo`（待办）与 `work_todo_list`（清单），字段定义见 [pocketbase-collections.md](pocketbase-collections.md)。

## 界面结构

- 左：智能视图（我的一天 / 重要 / 今天 / 已计划 / 全部任务 / 已完成）+ 我的清单（含每清单未完成角标、重命名、配色、删除），无清单归属的显示为「未分类」。
- 中：搜索框、回车即建的快速添加、未完成项按「逾期 / 今天 / 明天 / 接下来 / 无到期日」分桶、底部「已完成 N 项」可折叠。
- 右：详情面板（勾选完成、标题、星标、加入/移出我的一天、到期日 + 今天/明天/下周快捷键、所属清单、备注自动保存、子步骤增删勾选、创建与完成时间、删除）。
- 窄屏（<1100px）：侧栏与详情改为抽屉。

## 不能改错的语义

- **快速添加会带上下文语义**：在「今天」里建 → `due_date` = 今天；在「我的一天」建 → `my_day` = 今天；在「重要」建 → `important = true`；在「已计划」建 → `due_date` = 今天；在某个清单下建 → 归属该清单。
- **我的一天是手动加入、次日清空**：`my_day` 存当天日期，判断用 `my_day~'今天'`；不跟 `due_date` 挂钩，所以「今天到期」不等于「在我的一天里」。
- **勾选语义**：`done = true` 时把 `completed_at` 写成当天；取消勾选清空 `completed_at`。「已完成」视图按 `-completed_at` 排序。
- **删除清单不删待办**：先把该清单下所有待办的 `list` 清空（移到未分类），再删清单；`work_todo.list` 是 relation 但 `cascadeDelete = false`，前端必须自己兜这一层。
- **子步骤存在 `steps` json 字段**：数组 `[{ title, done }]`，读取一律走 `normalizeSteps()`（兼容历史上被存成字符串的情况），增删勾选都是整字段 PATCH。
- 单视图最多加载 200 条未完成 + 200 条已完成，本地分桶排序；超出时页面顶部给提示，没有无限滚动。

## 扩展时的注意点

- 加新的智能视图：在 `stores/todo.ts` 的 `scopeFilter()` 里加分支，再在 `TodoSidebar.vue` 的 `smartViews` 里加一项（label + 图标）。
- 加字段（例如附件、提醒时间）：先给 `work_todo` 补字段（PocketBase 后台 `/_/` 或改 `scripts/setup-collections.mjs` 后跑 `pnpm setup:pb`），再在 `TodoDetailPane.vue` 补 UI；`TodoListPane` 的行内摘要只展示到期日、子步骤进度和备注。
- 计数角标来自 `loadCounts()`：一次拉全部未完成的 `(id, list)` 在前端聚合，所以每清单超过 200 条未完成时角标会偏小；真到那个量级再改成服务端分组统计。
- 待办页与工作台「今日待办」卡片是两处独立查询：卡片 = `done=false && (my_day~'今天' || due_date~'今天')`，单次查询天然去重。
