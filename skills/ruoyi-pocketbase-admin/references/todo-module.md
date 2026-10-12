# 待办事项模块（微软 To Do 风格 v1）

区别于 `CrudTable` 那类表格模块，这一页是**专用视图**：`src/views/work/todo/Index.vue` + `src/components/TodoBoard/`（`TodoSidebar` / `TodoListPane` / `TodoRow` / `TodoDetailPane`），状态在 `src/stores/todo.ts`。数据在 `work_todo`（待办）与 `work_todo_list`（清单），字段定义见 [pocketbase-collections.md](pocketbase-collections.md)。

## 界面结构

- 左：智能视图（**我的一天 / 重要 / 今天 / 已计划 / 全部任务**）+ 我的清单（含每清单未完成角标、重命名、配色、删除），无清单归属的显示为「未分类」。
- 中：搜索框、回车即建的快速添加、未完成项按「逾期 / 今天 / 明天 / 接下来 / 无到期日」分桶。
- 右：详情面板（勾选完成、标题、星标、加入/移出我的一天、到期日 + 今天/明天/下周快捷键、所属清单、备注自动保存、子步骤增删勾选、创建时间、删除）。
- 窄屏（<1100px）：侧栏与详情改为抽屉。

**刻意没有「已完成」视图，中栏也没有已完成分组**：完成的待办会移出本模块、进「归档任务」（见下）。待办页只承载「还没做完的事」。

## 不能改错的语义

- **快速添加会带上下文语义**：在「今天」里建 → `due_date` = 今天；在「我的一天」建 → `my_day` = 今天；在「重要」建 → `important = true`；在「已计划」建 → `due_date` = 今天；在某个清单下建 → 归属该清单。
- **中文输入法保护**：快速添加与子步骤输入框都用 `@keydown.enter` 并检查 `event.isComposing`（或 keyCode 229），否则拼音按回车选词会被当成提交，表现为「加不上 / 乱建」。
- **我的一天是手动加入、次日清空**：`my_day` 存当天日期，判断用 `my_day~'今天'`；不跟 `due_date` 挂钩。
- **勾选完成 = 归档 + 移出待办**：先写 `work_task`，写成功才 `DELETE` 这条 `work_todo`。**归档失败就保留待办**（`archiveError` 会提示原因），绝不因为归档出问题丢数据；因此没有「取消完成」这条路径。
- **删除待办 = 归档（status archived）+ 删除**，保证删掉的东西有据可查。
- **删除清单不删待办**：先把该清单下所有待办的 `list` 清空（移到未分类），再删清单；`work_todo.list` 是 relation 但 `cascadeDelete = false`，前端必须自己兜这一层。
- **子步骤存在 `steps` json 字段**：数组 `[{ title, done }]`，读取一律走 `normalizeSteps()`（兼容历史上被存成字符串的情况），增删勾选都是整字段 PATCH。
- 单视图最多加载 200 条未完成，本地分桶排序；超出时给提示，没有无限滚动。

## 归档任务契约（与「归档任务」页面）

待办不自己留历史，终结状态写进 `work_task`（页面「归档任务」，菜单 `/work/task`）：

| 待办动作 | 归档动作 |
| --- | --- |
| 勾选完成 | 写一条 `work_task`：`status='done'`、`progress=100`、`archived_at=今天`；随后删除该待办 |
| 删除待办 | 写一条 `work_task`：`status='archived'`、`progress=0`；随后删除该待办 |

映射规则：`title` 同名；`tags` 存原清单名；`priority` 由「重要」映射为 high/mid；`due_date` 原样带过；`content` 拼成「来源 + 清单 + 备注 + 子步骤勾选摘要」；`source_id` 存原待办 id 便于追溯（重复触发只更新同一条，不会堆重复）。

注意点：

- 归档失败不能吞掉：store 把原因放在 `archiveError`，界面提示「待办本身保留，归档失败」，不要假装成功。
- 归档是单向的：在「归档任务」页面删记录不会影响待办；待办完成后也不再回到待办列表。
- `work_todo` 的 `done` / `completed_at` 字段保留但已不再写入（历史兼容 + 过滤防御），所有查询仍带 `done=false`。
- 「待办日程」已下线（用户不再需要）：不要因为看到 `work_schedule` 集合还在就把它挂回菜单；要恢复的话，前端代码在 `views/work/schedule` + `config/modules/schedule.ts`，加一条菜单记录即可。

## 扩展时的注意点

- 加新的智能视图：在 `stores/todo.ts` 的 `scopeFilter()` 里加分支，再在 `TodoSidebar.vue` 的 `smartViews` 里加一项（label + 图标）。
- 加字段（例如提醒时间、附件）：先给 `work_todo` 补字段（PocketBase 后台 `/_/`，或改 `scripts/setup-collections.mjs` 后跑 `pnpm setup:pb` 自动补齐），再在 `TodoDetailPane.vue` 补 UI。
- 计数角标来自 `loadCounts()`：一次拉全部未完成的 `(id, list)` 在前端聚合，单清单超过 200 条未完成时角标会偏小；真到那个量级再改成服务端分组统计。
- 待办页与工作台「今日待办」卡片是两处独立查询：卡片 = `done=false && (my_day~'今天' || due_date~'今天')`，单次查询天然去重；卡片上的勾选走同一个 `todoStore.completeTodo()`，所以同样会归档。
