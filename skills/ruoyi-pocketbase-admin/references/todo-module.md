# 待办事项模块（微软 To Do 风格 v1）

区别于 `CrudTable` 那类表格模块，这一页是**专用视图**：`src/views/work/todo/Index.vue` + `src/components/TodoBoard/`（`TodoSidebar` / `TodoListPane` / `TodoRow` / `TodoDetailPane`），状态在 `src/stores/todo.ts`。数据在 `work_todo`（待办）与 `work_todo_list`（清单），字段定义见 [pocketbase-collections.md](pocketbase-collections.md)。

## 界面结构

- 左：智能视图（**我的一天 / 重要 / 全部任务**，默认选「全部任务」）+ 我的清单（含每清单未完成角标、重命名、配色、删除），无清单归属的显示为「未分类」。
  （2026-10-14 定稿：去掉「今天」与「已计划」两个视图，**「我的一天」直接等于「到期日 = 今天」**——`scopeFilter()` 里就是 `done=false && due_date~'今天'`。
   没有到期日的待办**只出现在「全部任务」**，不进「我的一天」。原先靠 `my_day` 字段做手动标记的机制已废弃，见下。）
- 中：搜索框、回车即建的快速添加、未完成项按「逾期 / 今天 / 明天 / 接下来 / 无到期日」分桶。
- 右：详情面板（勾选完成、标题、星标、加入/移出我的一天（= 今天到期开关）、到期日 + 今天/明天/下周快捷键、所属清单、备注自动保存、子步骤增删勾选、创建时间、删除）。
- 窄屏（<1100px）：侧栏与详情改为抽屉。

**刻意没有「已完成」视图，中栏也没有已完成分组**：完成的待办会移出本模块、进「归档任务」（见下）。待办页只承载「还没做完的事」。

## 不能改错的语义

- **快速添加会带上下文语义**：在「我的一天」建 → `due_date` = 今天（建完就出现在当前视图里）；在「重要」建 → `important = true`；在某个清单下建 → 归属该清单；在「全部任务」建 → 只建一条没有归属、没有到期日的待办。
- **中文输入法保护**：快速添加与子步骤输入框都用 `@keydown.enter` 并检查 `event.isComposing`（或 keyCode 229），否则拼音按回车选词会被当成提交，表现为「加不上 / 乱建」。
- **我的一天 = 到期日是今天**（派生视图，不是标记）：判断只看 `due_date`，没有任何「手动加入」的独立状态，所以不会出现「在列表里却看不出为什么在」的情况。
- **`my_day` 字段已废弃**：早期用 `my_day~'今天'` 做手动标记，现在**没有任何地方读写它**（`TodoItem.my_day` 留着只当历史字段，`types/index.ts` 有注释）。数据库里可能还留着几行当日值，是死数据，别拿它做筛选，也别据此判断「这条在我的一天里」。
- **太阳图标 = 今天到期开关**：`toggleMyDay()` 加入时写 `due_date` = 今天，移出时**清空 `due_date`**（任务落回「全部任务」的「无到期日」分桶）。这是「我的一天」由到期日派生后的必然结果——想留在「我的一天」又不想有到期日，在这个模型里不存在。
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

归档页的列（`config/modules/task.ts`）：任务 / 状态 / 优先级 / 截止日期 / 负责人 / 标签 / 更新时间 / 操作。**`progress` 既不进表格也不进表单**（归档记录只可能是 0 或 100，列里没有信息量），字段与历史数据都留着。

### 逆向：归档页的「还回待办」

`work_task` 不是死账本。归档页操作列上的「还回待办」（`views/work/task/Index.vue` 薄壳 + 自定义行操作插槽 → `todoStore.restoreTaskToTodo()`）把一条归档记录还原成待办：

| 归档字段 | 还原成 |
| --- | --- |
| `title` | `work_todo.title` |
| `tags`（归档时存的是原清单名） | 按名字找回清单 → `list`；找不到就落「未分类」 |
| `priority='high'` | `important=true`（其余都是 false） |
| `due_date` | 原样带过（`pbDateOnly()` 取前 10 位再补 ` 00:00:00`）；正好是今天的话，还回待办后自然就出现在「我的一天」（没有额外字段要写） |
| `content` | 去掉「来自…」「清单：…」两行、剥掉「备注：」前缀，其余（含子步骤摘要）写进 `notes` |

**顺序与归档相反，但同样是「先落账再删除」**：先建待办，成功后才 `DELETE` 归档记录；建待办失败就保留归档记录并报错，绝不弄成两边都没有。还原出来的是**新 id 的待办**，之后再次完成会写一条 `source_id` 为新 id 的归档记录。

注意点：

- 归档失败不能吞掉：store 把原因放在 `archiveError`，界面提示「待办本身保留，归档失败」，不要假装成功。
- 归档页**不做编辑**（`taskSchema.canEdit = false`）：要改内容就还回待办、改完再归档，避免同一条记录两处都能改。
- 归档页直接删记录不影响待办；「还回待办」则会连这条归档记录一起删掉（等价的“移动”，不是“复制”）。
- `work_todo` 的 `done` / `completed_at` 字段保留但已不再写入（历史兼容 + 过滤防御），所有查询仍带 `done=false`。
- 「待办日程」已下线（用户不再需要）：不要因为看到 `work_schedule` 集合还在就把它挂回菜单；要恢复的话，前端代码在 `views/work/schedule` + `config/modules/schedule.ts`，加一条菜单记录即可。

## 扩展时的注意点

- 加新的智能视图：先扩 `stores/todo.ts` 的 `SmartViewKey` 联合类型与 `SMART_LABELS`，再在 `scopeFilter()` 里加分支，最后在 `TodoSidebar.vue` 的 `smartViews` 里加一项（label + 图标）；删视图就是反过来（漏掉 `SmartViewKey`/`SMART_LABELS` 会被 `vue-tsc` 挡下来）。要做「在某个视图里建的待办默认带什么字段」，改 `createTodo()`。
- 加字段（例如提醒时间、附件）：先给 `work_todo` 补字段（PocketBase 后台 `/_/`，或改 `scripts/setup-collections.mjs` 后跑 `pnpm setup:pb` 自动补齐），再在 `TodoDetailPane.vue` 补 UI。
- 计数角标来自 `loadCounts()`：一次拉全部未完成的 `(id, list)` 在前端聚合，单清单超过 200 条未完成时角标会偏小；真到那个量级再改成服务端分组统计。
- 待办页与工作台「今日待办」卡片是两处独立查询，但口径一致：卡片 = `done=false && due_date~'今天'`（等价于「我的一天」）；卡片上的勾选走同一个 `todoStore.completeTodo()`，所以同样会归档。计数卡里的「我的一天 N 项」用的是同一条 filter。
