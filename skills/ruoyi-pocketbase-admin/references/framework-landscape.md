# 选型调研（2026-10-12 实测数据）

当初的问题是「有没有像若依那样可配置的现成前端框架」，结论是：**有，但"可配置"分三条完全不同的路子**，代价差别很大。这份记录用于回答选型质疑，或在需求变化时重新决策。星标均为 2026-10-12 查询结果。

## 若依家族（Java 后端 + Vue 管理端）

| 项目 | 规模 | 说明 |
| --- | --- | --- |
| RuoYi（单体） | Gitee 48.9k | 前端是 Thymeleaf + H+ 模板，**没有独立 SPA 前端**，可配置程度最低 |
| RuoYi-Vue | Gitee 43.2k | Vue2 + Element UI 前后端分离版 |
| RuoYi-Vue3 | GitHub 6.8k | Vue3 + Vite + Element Plus，配套 RuoYi-Vue 后端；动态菜单、按钮权限、字典、代码生成器、表单构建器 |
| RuoYi-Vue-Plus | Gitee 17.1k | 重写版，Spring Boot 4.1 / JDK 21+，前端在独立仓库 `plus-ui`（另有 React 版与社区 vben5/soybean 版） |
| 芋道 ruoyi-vue-pro | Gitee 111.7k / GitHub 39.7k | 功能最全：RBAC、数据权限、Flowable 工作流、OA/HRM/报表/CRM/ERP，前端 `yudao-ui-admin-vue3`（Gitee 25.3k，Vue3 + Element Plus + form-create 表单设计器 + bpmn-js 流程设计器），MIT |

共同代价：必须跑 Java + MySQL + Redis（约 1–2GB 依赖），且要裁剪掉商城/ERP/MES 等用不到的模块。

## 纯前端管理框架（需自接后端）

vue-element-admin 90.1k（2024-10 起停更，Vue2，别选）、vue-vben-admin 33.6k、vue-pure-admin 20.7k、lin-xin/vue-manage-system 19.6k、Soybean Admin 15.1k（Naive UI，颜值高）、Geeker-Admin 8.1k、form-create 7.1k（低代码动态表单 + 可视化设计器）、art-design-pro 5.9k、vue3-antdv-admin 4.1k、vue-naive-admin 4.0k、vue-element-plus-admin 3.7k、vue3-element-admin 2.6k。它们只提供骨架与动态路由机制，"配置化"要自己实现——本项目正是照这条路走，但把机制做出来了。

## 配置型低代码 / 无代码平台

NocoDB 65.3k（把数据库变智能表格）、JeecgBoot 48.2k（online 表单 + 代码生成）、Appsmith 41.1k、ToolJet 41.1k、Directus 38.4k、NocoBase 24.5k（中文团队，AI + 无代码）、Teable 21.9k（开源 Airtable）、APITable 15.6k；成品应用另有 Focalboard 26.5k（看板，维护模式）、Vikunja 5.7k（待办）。几乎零代码，但定制空间小、不太像"若依式后台"。

## 为什么最终选了「PocketBase + 自建若依式前端」

1. **环境不允许**：开发机与 N1 上都没有 Java / MySQL / Redis / Docker 之外的运行时；N1 只有 1.9GB 内存和 1.2GB eMMC，跑不动若依全家桶。
2. **PocketBase 已经跑着**：单文件 + SQLite + REST + 权限规则 + 管理后台，1 个容器 20MB 内存，天然适合这个盒子。
3. **"可配置"能自己拿回来**：若依的四大可配置项都有等价实现——菜单表驱动路由（`sys_menu`）、角色/按钮权限（`permission` 字段预留）、字典（`sys_dict`）、代码生成器（用 `CrudTable` 的 schema 化 CRUD 替代，加模块从"生成代码"变成"写一份配置"）。
4. **部署形态更简单**：前端就是静态文件，塞进 PocketBase 的 `pb_public`，同容器同卷，迁移时整体搬走。

## 什么情况下应该重新考虑

- 需要多用户、细粒度数据权限、审批流引擎 → 芋道 `ruoyi-vue-pro` + `yudao-ui-admin-vue3` 是现成的，接受装 JDK 21 + MySQL + Redis 即可。
- 需要"界面里拖拽建表就有页面"、连 schema 都不想写 → NocoDB / JeecgBoot online 表单更省事。
- 需要复杂的前端交互与组件生态（图表、大屏、富文本编排）→ vue-vben-admin / vue-pure-admin 作骨架，本项目的前端可平滑迁到它们之上。
