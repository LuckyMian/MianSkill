---
name: ruoyi-pocketbase-admin
description: Develop, extend, configure, or deploy the 日常工作台 frontend at G:\文档\ChatGPT\ruoyi — a RuoYi-style configurable console (menu- and dictionary-driven routing, schema-driven CRUD) built with Vue 3 + Element Plus and hosted by PocketBase inside the Docker container on the Phicomm N1 side-router. Use for this project's frontend, PocketBase collections, runtime configuration, or N1 deployment work; do not use it for RuoYi/yudao Java backends or unrelated admin templates.
metadata:
  short-description: RuoYi-style admin on PocketBase
---

# 日常工作台（RuoYi 风格 · PocketBase 后端）

> **技能改动必须推送（强制）**：修改本技能或 `%USERPROFILE%\.codex\skills` 下任何技能后，立即执行
> `powershell -NoProfile -File F:\Codex\Skill\MianSkill\sync.ps1`
> （复制技能 → 更新 `README.md` / `skills.json` → 提交推送；先看差异用 `-DryRun`，只提交不推送用 `-NoPush`）。
> 推送失败要如实报告，不要静默跳过。

`G:\文档\ChatGPT\ruoyi\frontend` 把若依那套「可配置」重新实现了一遍：菜单表驱动路由、字典驱动下拉与颜色、一份字段配置同时驱动查询/表格/表单；后端是 N1 侧路由上的 PocketBase 单容器，**前端构建产物直接放进该容器的 `pb_public`**，两者同容器同卷，迁移时整体搬走。

## 按需求选读

- 架构、目录地图、配置化 CRUD 引擎、怎么加一个模块 → [architecture.md](references/architecture.md)
- 动集合/字段/权限，或列表报「集合不存在」 → [pocketbase-collections.md](references/pocketbase-collections.md)
- 发布、验证、回滚、线上排查、迁移到外置盘 → [deploy-n1.md](references/deploy-n1.md)
- 被问「为什么不用若依/yudao/低代码」，或要重新选型 → [framework-landscape.md](references/framework-landscape.md)

## 必须守住的不变量

1. **路由只能是 hash 模式**。PocketBase 的静态托管没有 SPA 回退重写，`history` 模式一刷新就 404；地址形如 `http://192.168.1.168:8090/#/work/task`。
2. **不在 N1 上构建**。N1 只有约 1.9GB 内存、1.2GB eMMC、无 swap；`pnpm install` 与 `vite build` 一律在开发机做，只把 `dist` 送过去。
3. **菜单与字典是真数据**。侧边栏、路由、下拉选项、标签颜色都来自 `sys_menu` / `sys_dict`；拉取失败时前端退回 `src/config/fallbackMenu.ts` 的内置菜单。改动前先确认当前生效的是哪一种（导航栏右侧用户菜单里有提示）。
4. **一份 schema 驱动三处**。加字段只改 `src/config/modules/*.ts`，不要在页面里手写表格列或表单控件。
5. **凭据不落仓库、不落技能**。PocketBase superuser 密码放 `frontend/.env.local`（已被 gitignore）；SSH 是另一套密码。两者都不要写进技能文件或提交到 git。

## 常用动作

在 `frontend/` 目录下执行：

| 目的 | 命令 |
| --- | --- |
| 本地开发 | `pnpm dev` → http://localhost:5173 ，直连 N1 的 PocketBase，热更新 |
| 建/补集合 | `pnpm setup:pb`（幂等；加 `--force-seed` 覆盖默认菜单与字典） |
| 构建 | `pnpm build`（`vue-tsc` + vite，产物约 1.6MB / gzip 约 450KB） |
| 交互式发布 | `pwsh -File scripts\deploy-interactive.ps1`（自动探测容器与挂载路径，提示输 SSH 密码两次） |
| 非交互发布 | `pnpm deploy:pb --target=docker://root@192.168.1.168:22/pocketbase:/pb/pb_public` |
| 类型检查 | `pnpm type-check` |

## 环境速查

| 项 | 值 |
| --- | --- |
| 前端 | `G:\文档\ChatGPT\ruoyi\frontend`（Vue 3.5 + Vite 8 + TS + Element Plus 2.14 + Pinia 4 + Vue Router 5） |
| 后端 | PocketBase **0.40.5**，`http://192.168.1.168:8090`，容器 `pocketbase`（镜像 `alpine:3.24`，`--restart unless-stopped`，命令 `serve --http=0.0.0.0:8090`） |
| 挂载 | 宿主 `/opt/pocketbase` → 容器 `/pb`；前端产物落在 `/opt/pocketbase/pb_public` |
| 管理后台 | `http://192.168.1.168:8090/_/`（自带多语言，含简体中文） |
| SSH | `root@192.168.1.168:22`，**密码登录**；路由器是 iStoreOS（dropbear），`scp` 必须加 `-O` |
| 资源上限 | 容器内存限制 96MiB（实测占用约 21MiB）；rootfs 1.2GB，可用约 1.1GB |

## 当前状态与待办（截至 2026-10-12）

- 线上：`http://192.168.1.168:8090` 就是本系统；原测试页备份为 `/opt/pocketbase/pb_public/index.backup-*.html`。
- 数据：`sys_menu` 10 条、`sys_dict` 11 条已灌入；`work_task` / `work_schedule` / `work_report` / `work_note` 均为空表。
- 遗留：`demo_posts` 是早期测试页留下的空集合，可删；SSH 仍为密码登录（未装公钥，发布会要求输密码）。
- 候选下一步：附件上传、日历/看板视图、模块级权限、把 `/opt/pocketbase` 迁到外置盘（eMMC 只有 1.2GB）。
