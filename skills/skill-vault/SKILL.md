---
name: skill-vault
description: Maintain this machine's skill library and keep it in sync with the GitHub backup repo MianSkill — clone the repo into the current workspace, copy workspace skills into the active agent tool's skills directory (Codex/WorkBuddy/Claude Code/DSH), and run pull/push in the fixed order (pull = git pull then copy out; push = copy in then commit and push). Use whenever a skill is created, edited, removed, backed up, synced, or restored; do not use it for git operations on unrelated projects.
metadata:
  short-description: Skill library sync hub (workspace clone ↔ agent skills dir)
---

# Skill Vault（技能库总入口）

一句话：**GitHub 仓库 `MianSkill` 是唯一事实源，当前工作区的克隆是本地副本，agent 工具的技能目录是运行时副本。** 三处必须保持一致，顺序不能乱。

## 三条规则（2026-10-22 定，最高优先级）

### 规则 1：仓库克隆到「当前工作区」

仓库地址 https://github.com/LuckyMian/MianSkill ，克隆位置固定为**当前工作区根目录下的 `MianSkill/`**，不再放到工作区之外的其他路径。

```powershell
cd <当前工作区>
git -c http.proxy= -c https.proxy= clone https://github.com/LuckyMian/MianSkill.git MianSkill
```

- 路径一律相对工作区：克隆路径就是 `<当前工作区>\MianSkill`，下文命令都从**工作区根目录**出发写 `.\MianSkill\...`，不写死任何盘符。
- 已经存在克隆就不要重复克隆，直接 `git pull`。
- 历史遗留的工作区外克隆（旧机器上的 `F:\Codex\Skill\MianSkill`）已作废，不再作为工作副本使用（可保留只读，或确认无本地未推送改动后删除）。
- 工作区本身可能是另一个 git 仓库，`MianSkill/` 是嵌套仓库，应写进工作区的 `.gitignore`，不要被外层仓库当普通文件收进去。

### 规则 2：工作区技能复制到「当前 agent 工具的技能目录」

仓库里的 `MianSkill\skills\<技能名>\` 才是源；agent 工具只认自己的技能目录，所以每次同步都要复制过去。

| 你在用什么 | 技能目录 |
| --- | --- |
| WorkBuddy | `%USERPROFILE%\.workbuddy\skills` |
| Codex（桌面 / CLI） | `%USERPROFILE%\.codex\skills` |
| Claude Code | `%USERPROFILE%\.claude\skills` |
| DSH（DeepSeek Harness） | `%USERPROFILE%\.dsh\skills` |

```powershell
cd <当前工作区>
robocopy .\MianSkill\skills "$env:USERPROFILE\.dsh\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
```

- 换工具只改目标目录：`.dsh` 换成 `.workbuddy` / `.codex` / `.claude` 即可。
- 用 `/E` 只增改、不删除；确认仓库里某个技能已彻底废弃、要求严格镜像时才用 `/MIR`。
- 复制完 agent 若没识别到，执行一次**刷新**：WorkBuddy 在技能设置里把该技能关掉再打开（或开新会话，技能清单在会话启动时加载）；Codex 重开会话；DSH 会自动刷新技能目录，不用重启。

### 规则 3：拉取与推送的顺序相反

**拉取（GitHub → 仓库 → agent）**：先 `git pull`，再复制到 agent 技能目录，必要时刷新。

```powershell
cd .\MianSkill
git -c http.proxy= -c https.proxy= pull --ff-only
robocopy .\skills "$env:USERPROFILE\.dsh\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
```

**推送（agent → 仓库 → GitHub）**：反过来的顺序，先把 agent 目录的改动复制回仓库 `skills\`，再生成清单、提交、推送。这一步用仓库里的 `sync.ps1` 一次做完（它内部就是复制 → 重生成 `README.md` / `skills.json` → commit → push）：

```powershell
# 在工作区根目录执行（脚本必须从仓库里跑）
powershell -NoProfile -File .\MianSkill\sync.ps1 -Message "<前缀>：<改动摘要>"
```

- `-SkillsRoot` **可以不传**：脚本按**当前 agent 工具**自动定位——DSH → `%USERPROFILE%\.dsh\skills`、Codex → `.codex\skills`、WorkBuddy → `.workbuddy\skills`、Claude Code → `.claude\skills`。顺序是先看工具自己注入的环境变量（`DSH_HOME` / `DSH_*`、`CODEX_*`、`CLAUDECODE`、`WORKBUDDY_HOME`），再看进程祖先链（`DeepSeek Harness.exe` / `codex` / `workbuddy` / `claude`）；两样都判断不出就**报错退出**，不会默认成某个目录。
- 只有在「在 A 工具里推 B 工具的技能库」这种跨工具操作时才显式传 `-SkillsRoot`，显式值永远优先。
- 只想先看差异：加 `-DryRun`（不写文件、不提交）。只提交不推送：加 `-NoPush`。
- 收尾必须核对 `origin/main` 真的到了那个 commit（`git fetch origin` + `git log --oneline -1 origin/main`）；推送失败要如实报告，不要说“已备份”。

## 固定心智模型

```text
GitHub  LuckyMian/MianSkill
   ↑ push (commit)                    ↓ pull
工作区克隆  <工作区>\MianSkill\skills
   ↑ 复制回（推送前）                  ↓ 复制到（拉取后）
agent 技能目录  %USERPROFILE%\.<工具>\skills\<技能名>\
```

1. 改技能：直接在 **agent 技能目录**里改（那才是运行时生效的位置），改完立刻按规则 3 推送。
2. 换机器 / 新环境：先规则 1 克隆，再规则 2 复制，最后刷新。
3. 同步前先确认三处版本一致（`git status`、`git log -1`），不一致时先想清楚哪边是最新的，别用旧覆盖新。

## 每次改动的标准收尾

1. `sync.ps1 -DryRun` 看会有什么变化。
2. `sync.ps1 -SkillsRoot ... -Message "..."` 执行（复制 → 生成清单 → 提交 → 推送）。
3. 读输出：技能状态表（名称 / 类型 / 文件数 / 变化）、`README.md` 与 `skills.json` 是否重生成、有没有 orphan 提示、最后的 commit 与 push 结果。
4. 把结果如实汇报；推送失败要给出失败原因和重试命令。

## 必须守住的不变量

1. `README.md` 与 `skills.json` 由 `sync.ps1` 生成，**绝不手工编辑**；要改文案就改脚本里的模板。
2. 新技能不需要往仓库里手工拷贝、也不改脚本：放进当前 agent 的技能目录后跑一次 `sync.ps1 -SkillsRoot ...` 就会自动收录为「自建」。
3. `.system` 与插件自带技能默认不入库（会被客户端更新覆盖，改了也留不住）；确实要备份才加 `-IncludeSystem`。
4. 官方技能来源只在 `sync.ps1` 的官方来源表里登记。不要为了让它保持「官方（未修改）」而改写文件或伪造哈希 —— 改过就是 `official-modified`，清单会写明「克隆自 X 后独立修改」。
5. 本机全局 git 配置挂着已失效的代理 `127.0.0.1:10809`：手工 git 命令要带 `-c http.proxy= -c https.proxy=`（`sync.ps1` 内部已自带）。GitHub 直连**平时**通，但会间歇被掐：症状是 `fatal: unable to access … OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to github.com:443`（TCP 端口能连上、TLS 握手被打断），`Test-NetConnection github.com -Port 443` 仍是 True，容易误判成「网络正常」。这时别反复重试，改走能访问 GitHub 的机器的 socks 隧道（N1 侧路由装了 OpenClash，实测可用）：
   ```powershell
   ssh -D 11080 -N root@192.168.1.168        # 另开一个窗口常驻（要输密码）
   git -C .\MianSkill -c http.proxy=socks5h://127.0.0.1:11080 `
       -c https.proxy=socks5h://127.0.0.1:11080 push origin main
   ```
   推完记得 `git fetch origin` 核对 `origin/main` 真的到了那个 commit。
6. 技能改动必须推送，且推送失败必须报告 —— 本地提交不等于备份完成。

## 按需选读

- 跑同步 / 看懂输出 / 排查失败 / 改官方来源表 / 提交信息写法 → [references/sync-ps1.md](references/sync-ps1.md)
- 新建或更新技能、写法规范、登记官方技能、在新电脑上还原技能库 → [references/new-skill.md](references/new-skill.md)
