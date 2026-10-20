---
name: ruoyi-pocketbase-admin
description: Develop, extend, configure, or deploy the 日常工作台 frontend at G:\文档\ChatGPT\ruoyi — a RuoYi-style configurable console (menu- and dictionary-driven routing, schema-driven CRUD) built with Vue 3 + Element Plus and hosted by PocketBase inside the Docker container on the Phicomm N1 side-router. Use for this project's frontend, PocketBase collections, runtime configuration, or N1 deployment work; do not use it for RuoYi/yudao Java backends or unrelated admin templates.
metadata:
  short-description: RuoYi-style admin on PocketBase
---

# 日常工作台（RuoYi 风格 · PocketBase 后端）

> **技能改动必须推送（强制）**：规则与完整流程见 `$skill-vault`；本技能或 `%USERPROFILE%\.codex\skills` 下任何技能改完后立即执行
> `powershell -NoProfile -File F:\Codex\Skill\MianSkill\sync.ps1`
> （复制技能 → 更新 `README.md` / `skills.json` → 提交推送；先看差异用 `-DryRun`，只提交不推送用 `-NoPush`）。推送失败要如实报告，不要静默跳过。

`G:\文档\ChatGPT\ruoyi\frontend` 把若依那套「可配置」重新实现了一遍：菜单表驱动路由、字典驱动下拉与颜色、一份字段配置同时驱动查询/表格/表单；后端是 N1 侧路由上的 PocketBase 单容器，**前端构建产物直接放进该容器的 `pb_public`**，两者同容器同卷，迁移时整体搬走。

## 按需求选读

- 想知道「现在有哪些功能、分别用了什么方法」，或要照着加一个新模块 → [feature-map.md](references/feature-map.md)
- 架构、目录地图、配置化 CRUD 引擎、怎么加一个模块 → [architecture.md](references/architecture.md)
- 动集合/字段/权限，或列表报「集合不存在」 → [pocketbase-collections.md](references/pocketbase-collections.md)
- 改「待办事项」（微软 To Do 风格那一页）的交互语义 → [todo-module.md](references/todo-module.md)
- 改「随手笔记」（Apple 备忘录风格那一页）→ [note-module.md](references/note-module.md)
- 改「无限画布」（PureRef 风格参考板：图片/文字/分组框、平移缩放、裁剪旋转、撤销重做）→ [canvas-module.md](references/canvas-module.md)
- 改「项目管理」（需求看板/拖拽、进度总览、需求转待办、GitHub 仓库卡片）→ [pm-module.md](references/pm-module.md)
- 改亮/暗主题、画布全屏（专注模式）、给新页面加配色 → [theme.md](references/theme.md)
- 改手机端适配、加触摸手势、改断点 → [mobile.md](references/mobile.md)
- VPN 面板入口（工作台主页按钮 → 新标签打开）、外网访问怎么配 → [vpn-tools.md](references/vpn-tools.md)
- 配/改笔记图片上传（阿里云 OSS 直传、PocketBase 钩子） → [oss-images.md](references/oss-images.md)
- 发布、验证、回滚、线上排查、迁移到外置盘 → [deploy-n1.md](references/deploy-n1.md)
- 定时把整个容器备份到 GitHub、改备份时间、在别的 docker 上还原 → [backup-github.md](references/backup-github.md)
- 被问「为什么不用若依/yudao/低代码」，或要重新选型 → [framework-landscape.md](references/framework-landscape.md)

## 必须守住的不变量

1. **路由只能是 hash 模式**。PocketBase 的静态托管没有 SPA 回退重写，`history` 模式一刷新就 404；地址形如 `http://192.168.1.168:8090/#/work/task`。
2. **不在 N1 上构建**。N1 只有约 1.9GB 内存、1.2GB eMMC、无 swap；`pnpm install` 与 `vite build` 一律在开发机做，只把 `dist` 送过去。
3. **菜单与字典是真数据**。侧边栏、路由、下拉选项、标签颜色都来自 `sys_menu` / `sys_dict`；拉取失败时前端退回 `src/config/fallbackMenu.ts` 的内置菜单。改动前先确认当前生效的是哪一种（导航栏右侧用户菜单里有提示）。
4. **一份 schema 驱动三处**。加字段只改 `src/config/modules/*.ts`，不要在页面里手写表格列或表单控件。
5. **凭据不落仓库、不落技能**。PocketBase superuser 密码放 `frontend/.env.local`（已被 gitignore）；SSH 是另一套密码。两者都不要写进技能文件或提交到 git。
6. **日期按「本地墙钟、不带时区」存取**（写 `YYYY-MM-DD 00:00:00`），显示日期用 `pbDateOnly()` 取前 10 位，不要用 `pbDateToLocal()`（会把 `…000Z` 当 UTC 换算，日期时间都 +8 小时）。
7. **破坏性动作先落账再删除**。待办「完成/删除」都先写 `work_task`（`source_id` 做幂等键），成功才删原记录；失败就保留原数据并把原因显示出来。同类：删清单先把待办移到未分类，进「最近删除」的笔记不回收图片。归纳见 [feature-map.md](references/feature-map.md)。

## 踩过的坑（再犯代价很高）

- **API 建的集合默认没有 `created` / `updated`**。v0.23+ 里它们是可选的 autodate 字段，Dashboard 建集合会默认勾上，纯 API 建要自己声明；缺了它，任何按 `created`/`updated` 排序或读这两个字段的请求都会直接 **HTTP 400**（报错文案是笼统的 `Something went wrong while processing your request.`）。`pnpm setup:pb` 现在会幂等补齐缺失字段，改集合后跑一次即可。
- **报错别只看前端文案**：400 常见成因就是上面这条、或 filter 里引用了不存在的字段。用 `curl` 直接打 API 定位比看界面快得多。
- **iStoreOS 的 crond 只在启动时读 crontab**：手工往 `/etc/crontabs/root` 加行不重启 cron，任务永远不会执行（实测加探针 6 分钟无反应，`/etc/init.d/cron restart` 后当分钟就跑）。改完必须 restart。
- **备份仓库必须私有，且一把公钥只能挂一个仓库**：快照里有 OSS 密钥、超管密码哈希、VPN token；`MianHelperDocker` 建的时候是公开的（已改私有）。同一把 deploy key 挂第二个仓库会 HTTP 422，换仓库要新生成一把（配置项 `SSH_KEY`）。

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

N1 上（备份相关，详见 [backup-github.md](references/backup-github.md)）：

| 目的 | 命令 |
| --- | --- |
| 立刻整容器备份一次 | `ssh root@192.168.1.168 sh /opt/pb-backup/backup.sh` |
| 看上次备份结果 | `ssh root@192.168.1.168 cat /opt/pb-backup/logs/last-status` |
| 改备份时间 | 改 `/opt/pb-backup/backup.conf` 的 `CRON_SCHEDULE` 后跑 `sh /opt/pb-backup/apply-schedule.sh`（必须重启 cron，见下文） |

## 环境速查

| 项 | 值 |
| --- | --- |
| 前端 | `G:\文档\ChatGPT\ruoyi\frontend`（Vue 3.5 + Vite 8 + TS + Element Plus 2.14 + Pinia 4 + Vue Router 5） |
| 后端 | PocketBase **0.40.5**，`http://192.168.1.168:8090`，容器 `pocketbase`（镜像 `alpine:3.24`，`--restart unless-stopped`，命令 `serve --http=0.0.0.0:8090`） |
| 挂载 | 宿主 `/opt/pocketbase` → 容器 `/pb`；前端产物落在 `/opt/pocketbase/pb_public` |
| 管理后台 | `http://192.168.1.168:8090/_/`（自带多语言，含简体中文） |
| nginx（VPN 面板入口） | N1 上 `apk add nginx` 装的 **nginx-ssl**，监听 **9080**：人用的直连走 Basic Auth（用户名固定 `admin`，密码只存在于 `/etc/nginx/conf.d/vpn.htpasswd`，**与 mihomo secret 不是同一个值**）。**应用内嵌的 iframe 不走 Basic**（Chromium 不给子帧带 Basic 凭证，会反复弹框），改走 `/__panel?token=<TOKEN>` 换 Cookie（token 在 nginx 配置与 `sys_dict.vpn_panel_token` 两处，换要一起换）。反代 `127.0.0.1:9090` 并注入 mihomo secret；配置 `/etc/nginx/conf.d/vpn.conf` + 播种页 `/etc/nginx/seed/index.html`。**内网用 9080、外网用 19080**（电信网关上 19080 → 内网 9080，前端按访问主机名自动选），见 [vpn-tools.md](references/vpn-tools.md) |
| 包管理器 | N1 是 iStoreOS 25.12.5，用 **`apk`**（`opkg` 不存在） |
| SSH | `root@192.168.1.168:22`，**密码登录**；路由器是 iStoreOS（dropbear），`scp` 必须加 `-O` |
| 资源上限 | 容器内存限制 96MiB（实测占用约 21MiB）；rootfs 1.2GB，可用约 1.1GB |
| 定时备份 | 每周一 00:00（`/etc/crontabs/root` 里 `# pb-backup` 那行，`0 0 * * 1`）→ `/opt/pb-backup/backup.sh` → 私有仓库 `LuckyMian/MianHelperDocker` 的 `pb-backup` 分支；工具在 `/opt/pb-backup/`，源码在 `G:\文档\ChatGPT\ruoyi\backup\` |

## 当前状态与待办（截至 2026-10-15）

- 线上：`http://192.168.1.168:8090` 就是本系统；原测试页备份为 `/opt/pocketbase/pb_public/index.backup-*.html`。
- 集合：21 个 —— 6 个 PocketBase 内置、`demo_posts`（早期测试残留，可删）、`sys_menu` / `sys_dict` / `work_task` / `work_schedule`（已下线，仅留数据）/ `work_report` / `work_todo_list` / `work_todo` / `work_note` / `work_note_folder` / `work_canvas` / `work_canvas_item` / `pm_project` / `pm_module` / `pm_item`（项目管理，见 [pm-module.md](references/pm-module.md)）。
- 数据：`sys_menu` 15 条（含「无限画布」与「项目管理」1+3 条；「工具 → VPN」两条已于 2026-10-14 删除，种子脚本里的这两条也已清掉，别再跑回来）、`sys_dict` 38 条（含 `vpn_dashboard` 老地址预设、`vpn_panel_token` 入口口令、`dashboard_link` 工作台快捷按钮、`pm_*` 5 类 23 条）；`pm_project` 预置 4 个项目（UltraControlSystem / UnrealPackTimeVerification / HotPackTest / MianSkill，均带 repo），其余业务表基本为空。
- 已上线功能：工作台（顶部一排**可配置的快捷按钮**，`sys_dict` 里 `dict_type='dashboard_link'` 的记录驱动，新标签打开，见 [vpn-tools.md](references/vpn-tools.md)）、待办事项（微软 To Do 风格 v1；智能视图只有「我的一天 / 重要 / 全部任务」，进来默认「全部任务」，**「我的一天」= 到期日今天**，没有到期日的只在「全部任务」，见 [todo-module.md](references/todo-module.md)）、归档任务、工作记录、随手笔记（Apple 备忘录风格）、**无限画布（PureRef 风格参考板：图片/文字/Markdown 表格/链接卡片/流程节点/分组框 + 连线流程图 + 全屏专注 + 手机触摸手势 + Ctrl+C 复制图片到系统剪贴板，见 [canvas-module.md](canvas-module.md)）**、**全站亮/暗主题**（顶栏切换，见 [theme.md](theme.md)）、**手机端适配**（≤900px 外壳抽屉化 + 画布双指缩放/长按菜单，见 [mobile.md](mobile.md)）、菜单/字典/集合管理。
- **无限画布 2026-10-14 更新**：粘贴/拖入网页地址时先由服务端（`/api/oss/fetch` 的 HEAD）判类型——是图片照旧转存 OSS，不是图片就贴成可点开的**链接卡片**（新 `kind='link'`，地址存 `source_url`；`pnpm setup:pb` 会幂等扩值，老库要跑一次）；**文本框拖左右边手柄只改宽度**、高度按重排后的文字自动贴合（角手柄仍是含字号的整体缩放）；**双击语义统一**（文字＝编辑、空白＝新建、分组框标题栏＝改名、框内空白＝新建且自动归到这个框、流程节点＝改节点文字、**链接卡片＝编辑标题+地址**）；**选中单个元素时上方浮一条操作栏**（文字/节点＝复制文本，链接卡片＝打开/复制地址/编辑）；编辑文字时把元素本身藏起来（去重影）。顺手修了三个老问题：四边中点手柄被连接点圆点挡住只能拖角手柄、**双击文字变成新建文字**（`setPointerCapture` 会把 click/dblclick 的 `event.target` 改派到 stage，必须用 `elementFromPoint` 取元素）、以及弹窗快捷键让路的判断（别用 `.el-overlay`，布局里有隐藏 overlay 会吞掉 Ctrl+0）。细节见 [canvas-module.md](canvas-module.md)。
- **无限画布 2026-10-15 修「元素发虚」**：`CanvasItemView` 的 `.canvas-item` 去掉 `will-change: transform`，
  并在没有旋转/翻转时不写 transform——否则缩放到 177% 时元素被当成独立合成层按 1:1 栅格化、再被放大 1.77 倍，
  文字和边框发虚（同一张图里画在世界层的连线、网格是清楚的）。机制、定位手法与代价见
  [canvas-module.md](references/canvas-module.md) 的「元素不要有合成层提示」。
- **无限画布 2026-10-17 加「复制出去」**：`Ctrl+C` / 右键「复制图片（Ctrl+C）」把选中图片写进系统剪贴板，
  `Ctrl+D` / 右键「在画布内复制（Ctrl+D）」才是在画布内再放一张。复制会应用裁剪/翻转/旋转；多选按相对位置合成一张 PNG。
  **HTTPS/localhost 下是真正的 image/png 位图；当前 `http://…:8090` 不是安全上下文，只能退回 HTML 图片**（文档/聊天可粘，
  画图/PS 不行），要位图必须 HTTPS 访问。实现与坑见 [canvas-module.md](references/canvas-module.md) 的「复制图片到系统剪贴板」。
- **无限画布 2026-10-19 文字段落**：选中文字/流程节点按 `Ctrl+C` 复制段落文字，`Ctrl+V` 粘贴普通文字直接落成新段落；
  文本框默认先贴合文字宽度（上限 280）再换行，高度始终自适应，拖左右边手柄后 `wrap_fixed` 固定折行宽度。
  同日把编辑框从固定 textarea 改成 `contenteditable` 自适应宽高（输入法候选串由浏览器原生排版，
  彻底消除候选词被挤到第二行），并去掉双击编辑临时跳 100%/居中（原地编辑，视口不动）。
  详见 [canvas-module.md](references/canvas-module.md) 的「文本框自动宽高 + Ctrl+C / Ctrl+V 段落」。
- **无限画布 2026-10-19 加 WYSIWYG 表格**：新 `kind='table'`，`table_data`(json) 存单元格；双击单个单元格编辑，
  默认单元格是浅色提示文本（旧默认表自动迁移），用户已输入内容双击不覆盖、光标在末尾；
  `Ctrl+V` 可直接把图片贴进单元格；`+行/+列/插图/删行/删列` 在操作栏；
  单元格可放 OSS 图片；`ResizeObserver` 让行高列宽随内容自适应；
  仍支持粘贴 Markdown 表格/在文字框输入表格自动转换，`text` 保留 Markdown 镜像。
  详见 [canvas-module.md](references/canvas-module.md) 的「WYSIWYG 表格」。
- **无限画布 2026-10-20 修编辑框拖选**：编辑框内拖动选文字时，`pointerdown` 不再冒泡成画布的框选/指针捕获；
  画布世界层禁止选中、编辑框允许选中，拖出编辑框也不会把其它画布文字一起选进来。
  详见 [canvas-module.md](references/canvas-module.md) 的「编辑框内拖选文字会误选画布元素」。
- **无限画布 2026-10-20 加栅格吸附**：工具栏磁铁「吸附」开关（默认开，`localStorage.canvas_grid_snap` 持久化），
  拖动/单轴缩放吸附到 24px 网格；元素对齐「对齐」也有独立开关；栅格只吸左上角，`pointermove` 合并到动画帧，
  拖动中用屏幕坐标独立画框、结束 60ms 后再恢复蓝点/手柄；等高角缩放和旋转元素不吸栅格，`Alt` 临时关闭。
  详见 [canvas-module.md](references/canvas-module.md) 的「栅格吸附」。
- **无限画布 2026-10-20 移除框四周圆点**：删掉 4 个连接点圆点（连线改用右键「给选中的两个元素连线」）；
  桌面端缩放手柄改为**框外**不可见热区（鼠标移到边/角仍可缩放，文字内部拖动不会误触上下拉伸），
  触屏保留小点，消除放大缩小时的蓝点抖动和拖动文字时的上下抖动。
- **项目管理（2026-10-14 上线）**：项目总览 `/pm/overview`（项目进度卡 + 模块进度表 + 近 7 天完成 + GitHub 仓库卡）、需求看板 `/pm/board`（6 列看板、桌面原生拖拽改状态、触屏降级为下拉、详情抽屉自动保存、需求转待办、回收站软删除）、项目与模块 `/pm/setup`（schema CRUD）；顶栏全站「+ 想法」（`Alt+I`）+ 工作台「项目进度」卡。**GitHub 数据改走服务端代理钩子 `/api/gh/repo`**（令牌只在 N1 的 `pb_hooks/github.pb.js` 里，浏览器拿不到，所以能显示私有仓库；服务端缓存 5 分钟 + 前端 30 分钟，页脚显示令牌剩余配额）。细节见 [pm-module.md](references/pm-module.md)。
- 钩子目录 `/opt/pocketbase/pb_hooks/`（开发机源码副本 `G:\文档\ChatGPT\ruoyi\pocketbase-hooks\`；改完 scp 上去即可，PocketBase 检测到文件变化会自己重启，不用手动 restart）：
  - `oss.pb.js`（2026-10-13 更新，旧版备份在同级 `oss.pb.js.bak-20261013`）：上传目录白名单 `notes/` + `canvas/`，新增 `/api/oss/fetch` 网页图片抓取代理；改动细节与 JSVM 限制见 [oss-images.md](oss-images.md)。**换访问地址（域名/端口/公网 IP）必须同步 bucket 的 CORS 白名单**，否则图片直传会报 `图片添加失败：Failed to fetch`（当前白名单：`http://192.168.1.168:8090`、`http://localhost:5173`、`http://luckymian.xyz:18090`）。
  - `github.pb.js`（2026-10-14 新增，**令牌 2026-10-15 已配好**）：`GET /api/gh/repo?slug=owner/repo`（项目总览的仓库卡取数，服务端持有 GitHub 只读令牌，所以私有仓库也能显示）+ `GET /api/gh/status`（诊断）。令牌没配时接口返回明确提示、卡片照原样显示这句话。配令牌的写法与验证见 [pm-module.md](references/pm-module.md)。
  - ⚠️ 两个钩子里有阿里云 OSS 的 AK/SK 与 GitHub 令牌，**别提交到公开仓库**；每周的整容器备份会把它们一起带走，所以备份仓库必须私有。
- 待办与归档是双向的：待办里「完成」或「删除」都会**先写入 `work_task`（「归档任务」）再从待办移除**，所以待办页只留未完成的事，没有「已完成」视图；归档失败时待办会被保留，不会丢数据。反过来，归档页操作列上的**「还回待办」**会把一条归档记录还原成待办（先建待办、成功后再删归档记录），归档页因此不再提供「编辑」（要改就还回待办改完再归档）。
- **「待办日程」已下线**（用户不再需要）：菜单记录已删除，`work_schedule` 集合与数据保留未动，前端代码也留在 `views/work/schedule` + `config/modules/schedule.ts`——想开回来只需在「系统管理 → 菜单配置」加一条 `path=/work/schedule`、`component=work/schedule/Index` 的记录。
- 遗留：SSH 仍为密码登录（未装公钥，发布会要求输密码）。
- 候选下一步：待办的提醒与重复任务、拖拽排序、附件上传、日历/看板视图、模块级权限、把 `/opt/pocketbase` 迁到外置盘（eMMC 只有 1.2GB）。
- **定时整容器备份（2026-10-14 上线）**：每周一 00:00（= 周日晚上 12 点）停容器约 23–28 秒打
  整包快照（31.3MB），force push 到**私有**仓库 `LuckyMian/MianHelperDocker` 的 `pb-backup`
  分支（`main` 留给用户自己用），还原用
  `git clone -b pb-backup --single-branch … && ./restore.sh`（已在 N1 上实测还原到 8099 端口，
  数据 md5 与线上一致）。认证用路由器上的 Ed25519 部署密钥（`SSH_KEY` 配置项），不落账号令牌；
  `KEEP_SNAPSHOTS=4` + orphan 覆盖式提交把 eMMC 占用稳定在约 170MB。
  **仓库必须私有**——快照含 OSS 密钥与超管密码哈希。细节、坑与运维命令见
  [backup-github.md](references/backup-github.md)。
