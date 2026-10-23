# 模块：RuoYi 后台（RuoYi backend & console）

> 读我：改 RuoYi 页面 / 接口 / 菜单权限 / 样式，或排查「RuoYi 与 Kanboard 数据不一致」时。
> 归属技能：`figgo-erp-dev`。RuoYi 是独立 git 仓库，不要和 Kanboard 插件混在一个提交里。

## 部署

| 部分 | 位置 |
| --- | --- |
| 后端 | `D:\RuoYi\RuoYi-Vue-Plus`（`ruoyi-modules/ruoyi-finance`、`ruoyi-modules/ruoyi-project`） |
| 启动 | `D:\RuoYi\run-ruoyi.cmd`（含 `DEEPSEEK_API_KEY`，**gitignored**） |
| 前端 | `D:\RuoYi\plus-ui`（`src/views/finance/{ledger,wizard}`、`src/views/project/people`） |
| 构建产物 | 镜像到 `D:\Apache24\htdocs\ruoyi` |
| 对外地址 | `http://www.figgo.pro:801/ruoyi`（= `Config.local.php` 的 `ruoyi_public_url`） |
| 数据库 | 同一台 SQL Server，财务模块用 `@DS("finance")` 直连 `Finance` 库 |

## 铁律：RuoYi 只读 + 委派

财务与项目的**写操作全部回调 Kanboard CLI**，不在 Java 里重写：

- 核对 / 打印 / 补打 / OCR / 归档 / 恢复：`dingtalk:finance-verify`、
  `dingtalk:reimbursement-print`、`dingtalk:reimbursement-web-save`（下拉走
  `dingtalk:reimbursement-options`）。
- 任务指派通知：`dingtalk:pm-task-assign <json>`（参数先落盘成 UTF-8 JSON 文件，
  约定「最后一行是一行 JSON」，超时 15 秒）。
- 用户名 → 钉钉身份：`dingtalk:finance-staff <用户名>`，没绑定退出码 3。

理由：同一套核对状态、同一份归档、同一套打印，不能出现第二份真相。要做「一样的功能」时，
先找对应的 CLI，而不是再写一遍。

## 财务模块

- 两页：**报销台账**（财务，`/finance/ledger`）和 **我的报销**（员工自助，`/finance/my`）。
- 「我的报销」的范围**钉在登录账号上**：RuoYi 用户名 → `dingtalk:finance-staff` → 钉钉
  staff id（RuoYi 侧缓存 10 分钟），`FinanceMyController` 每次请求强制
  `bo.setStaffId(...)`，详情 / 原件 / 补打还各过一次 `assertOwner()`。员工端没有核对、
  识别、人员筛选，只有查看明细、重新打印、导出。
- **导出只有一种形态**：一行一条明细，固定 16 列（日期 / 团队 / 项目 / 摘要 / 报销金额 /
  领款人 / 购买方 / 发票号 / 发票金额 / 开票日期 / 类目 / 发票种类 / 月份 / 支付日期 /
  科目 / 二级科目），台账和「我的报销」共用 `FinanceLedgerExportVo`。发票字段按整单贴到每条
  明细上、多张用「；」连接，发票金额取整单「价税合计」之和；类目 = 发票的 `item_names`。
  改列顺序或标题只改这个 VO，两个页面自动跟随。
- 菜单与权限：`D:\Apache24\setup-packages\ruoyi-finance-menu.php`（员工角色拿
  `finance:my:*`，财务拿 `finance:ledger:*`）。
- 状态口径必须和 `FinanceService::verifyLabel()` 一致：`verified`=已核对（带核对人+时间）、
  `pending`=待核对、其它=未进队列；`paid_status` 是下一步，**打款不发钉钉消息**。

## 项目模块

- 任务可以挂到项目节点（`pm_task.node_id`），**挂在节点上的任务必须有负责人**；负责人变化
  时 `PmNotifyServiceImpl` 调 `dingtalk:pm-task-assign`。
- 入参：`assignee`（RuoYi 昵称 = Kanboard 姓名）、`task_id`、`task_title`、`project_id`、
  `project_name`、`node_code`、`node_name`、`due_date`、`actor`、`event_at`（秒，去重键）。
- 去重键 `pmtask:<task_id>:<staff_id>:<event_at>`：同一次指派只发一条，换人算新的。
- **「发不出去」不是错误**：没绑定、开关关闭、写队列失败都返回
  `{"queued":false,"reason":"…"}` 且退出码 0，RuoYi 只显示 reason，任务保存照常成功。
- ⚠️ **已知切换风险**：`application.yml` 的 `kanboard.assign-notify` 仍为 `true`，但
  `dingtalk:pm-task-assign` 在封存时被注销。修好或关掉之前，不要声称指派通知可用。

## 面板间距（强制的 12px 规则）

人员 / 考勤等页面所有面板用**同一个 12px 间距**，这是长期要求，不是一次性样式：

- 页面容器**不加外层 padding**：`AppMain` 已提供 12px 内容内边距，路由视图不要加 `p-2`/`p-3`。
  在页面上定义 `--panel-gap: 12px`。
- `AppMain.vue` 的固定头部偏移也带这 12px：有 tags view 时 `117px`，没有时 `82px`。
- 树 / 内容行：`el-row :gutter="12"`。
- 竖向面板栈：`content-main { gap: var(--panel-gap, 12px); }`。
- 面板与筛选条**不得**自带 `margin-bottom`，间距只由共享 gap 提供。
- 不要在这些页面混用 8 / 16 / 20px；新面板复用 `--panel-gap` 和现有 page-shell。
- 参考实现：`plus-ui/src/views/project/people/index.vue`、
  `.../PersonStatusBoard.vue`、`src/assets/styles/components/_page-shell.scss`（`content-stack`）。

## 项目管理菜单权限

| 角色 | 可见范围 |
| --- | --- |
| `sysadmin` / 管理员、`project_manager` / 项目经理 | 项目管理下**全部**菜单 |
| `employee` / 员工 | 只有 **项目列表**、**任务列表**、**归档任务** |

项目详情（`detail/:id`）是隐藏路由（`visible = 1`），不是侧栏项；员工保留这条路由和
打开项目、更新/归档自己任务所需的查询与本人任务权限。

| 标识 | 值 |
| --- | --- |
| 项目管理根菜单 | `2107000000000000001` |
| 员工角色 | `1900000000000000001`（`employee`） |
| 项目经理角色 | `1900000000000000002`（`project_manager`） |
| 管理员角色 | `2104527031220105218`（`sysadmin`） |

- 项目子树当前 27 个节点：含根共 9 个页面 + 18 个功能权限。
- 项目经理角色自动获得：用户在「项目经理」部门，或拥有项目（`pm_project.owner_user_id`）。
- **不要**从员工角色移除 `project:task:edit`、`project:task:remove`、`project:task:query`、
  `project:column:list`、`project:node:query`、`project:project:query`——后端仍把任务变更
  限制在本人任务。
- `PeopleController` / `PmPeopleServiceImpl.canViewStatusBoard()` 接受人员菜单权限**或**
  `project_manager`，所以经理不必是项目 owner 也能开人员总览。
- 幂等建菜单与可回滚重放在 `RuoYi-Vue-Plus/script/sql/sqlserver/ry_pm_v8.sql`。
- **用真实登录验证，不要只看 `sys_role_menu`**：`/system/menu/getRouters` 应返回员工的三个
  条目和经理的完整树。`D:\Apache24\setup-packages\ruoyi-menu-login-probe.php` 会建临时探针
  用户并在结束后删除。

## 人员 AI 分析

- 接口 `GET /project/people/ai-analysis`，`?refresh=true` 绕过缓存。
- `PeopleAiAnalysisService` 调 DeepSeek 的 OpenAI 兼容端点，模型 `deepseek-flash`；
  服务端缓存 1 小时，浏览器面板也缓存 1 小时——按用户要求**低频**。
- 覆盖整个看板（不受部门筛选影响）：人员负载、任务撞车、逾期与空闲的人、简短建议。
- 返回结构化 JSON（`sections[].items[]`），UI 渲染短条目；**每条 ≤ 约 120 字**，不要大段文字。
- 条目必须以 emoji 开头，并用 `**加粗**`、`{red:...}`、`{big:number}` 强调（面板渲染为粗体 /
  红色 / 16px）。改这套标记时要同时 bump `PROMPT_VERSION` 和前端 localStorage 缓存键，否则
  旧纯文本分析会一直命中缓存。
- `DEEPSEEK_API_KEY` 只在 `D:\RuoYi\run-ruoyi.cmd`（gitignored）；`application.yml` 只有
  `${DEEPSEEK_API_KEY:}` 占位符。**不提交、不打印、不写进技能。**
- 前端 `plus-ui/src/views/project/people/AiAnalysisPanel.vue`；AI 面板在部门树页脚（左下），
  人员甘特占满右侧剩余高度，两者底边对齐。

## 验证

| 脚本 | 用途 |
| --- | --- |
| `setup-packages\ruoyi-finance-verify.php` | 财务 HTTP 闭环：范围、403、打款幂等、导出状态列 |
| `setup-packages\ruoyi-finance-menu.php` | 财务菜单与角色授权 |
| `setup-packages\ruoyi-menu-login-probe.php` | 用真实登录探针验证 `/system/menu/getRouters` |
| `setup-packages\ruoyi-ui-test.py` | 真浏览器：员工进「我的报销」，断言无识别/核对按钮 |
| `setup-packages\ruoyi-project-assign-verify.py` | 项目指派通知 30 项（接口 + 浏览器 + 合图甘特） |
| `setup-packages\ruoyi-project-assign-cleanup.py` | 清理残留（先 `--dry-run`） |

测试账号一律临时创建、用完删除；钉钉 id 用 `TEST-pm-assign-…` 这类假值，别拿真人 id 建单
（2026-09-29 踩过：真人收到真实提醒）。

## 不要做

- 不要在 Java 里重写核对 / 打印 / OCR / 归档 / 补打。
- 不要用前端隐藏按钮代替后端权限；权限判定必须在 Controller/Service。
- 不要在项目页面上另立一套间距体系。
- 不要把 `DEEPSEEK_API_KEY` 写进 `application.yml`、日志、提交或技能。
