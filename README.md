# MianSkill

自用 skill 备份仓库：把平时在用的 AI 技能集中存放，方便换电脑、给其他 AI 工具直接读取，以及长期留档。

> 本文件由 `sync.ps1` 自动生成，请勿手工编辑。最后更新：2026-10-09
> 同一份清单的机器可读版本见 [`skills.json`](skills.json)。

## 快速开始（给 AI 工具 / 新电脑）

每个技能就是 `skills/<名称>/` 下的一个目录，`SKILL.md` 位于该目录根部，拷进 AI 工具的 skills 目录即可生效。

```powershell
git clone https://github.com/LuckyMian/MianSkill
```

Codex（桌面 / CLI，技能目录 `%USERPROFILE%\.codex\skills`）：

```powershell
robocopy .\MianSkill\skills "$env:USERPROFILE\.codex\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
```

通用 AI 工具 / Claude Code（技能目录 `~/.claude/skills`）：

```powershell
robocopy .\MianSkill\skills "$env:USERPROFILE\.claude\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
```

想让 AI 直接读清单：把 `skills.json` 或本文件交给它即可。`skills.json` 字段为 `name` / `type` / `path` / `description` / `source` / `sha256` / `files` / `installTargets` / `provenance`，`schemaVersion` 为 1。

## 技能清单

| 名称 | 类型 | 来源 | 版本 · 哈希 | 用途 |
|------|------|------|-------------|------|
| `drawio` | 官方（未修改） | [jgraph/drawio-mcp](https://github.com/jgraph/drawio-mcp) `plugins/codex/drawio/skills/drawio` | 固定于 `eebe7de` · SKILL.md SHA256 `5e1d5460fc6a2da7da98ad851841ec174670f42c0b7339835cc709957b9328f7` | Always use when user asks to create, generate, draw, or design a diagram, flowchart, architecture diagram, ER diagram, sequence diagram, class diagram, network diagram, mockup, wireframe, or UI sketch, or mentions draw.io, drawio, drawoi, .drawio files, or diagram export to PNG/SVG/PDF. |
| `ucs-development` | 自建 | 无（本地自建） | 聚合 SHA256 `0e20c9561669` | Develop, debug, review, or extend the UCS_Core Unreal Engine project, including UltraControlSystem, its subsystem and loading modules, UEWebSocketController, MeshColorExclusion, and the companion Vue web controller. Use for requests about this UCS codebase; do not apply to unrelated Unreal projects. |
| `wow-addon-dev` | 自建 | 无（本地自建） | 聚合 SHA256 `137a229d6766` | Develop, migrate, review, and debug World of Warcraft in-game AddOns using Lua, XML, TOC metadata, Blizzard UI code, and the version-matched WoW UI API. Use for Retail or Classic AddOn projects; do not use the Battle.net web API as a substitute for the in-game API. |

## 来源与修改标记规则

| 类型 | 含义 | 处理方式 |
|------|------|----------|
| `own` 自建 | 完全自己编写的技能 | 正文入库，来源记为「无（本地自建）」 |
| `official` 官方（未修改） | 直接安装的官方技能 | 正文作为固定版本快照入库，注明来源仓库、仓库内路径与固定版本号；官方发布新版本后不会自动跟随 |
| `official-modified` 克隆后独立修改 | 先克隆官方仓库、之后自己改动过 | 按独立技能维护，正文入库，来源栏写明「克隆自 X 后独立修改」 |

判定由 `sync.ps1` 自动完成：与脚本内官方来源表的哈希一致即为官方（未修改），不一致即为克隆后独立修改，其余目录一律视为自建。新增自建技能无需改脚本即可被自动纳入。

「版本 · 哈希」列中，官方技能显示 `SKILL.md` 的 SHA256，可直接与官方仓库文件核对；自建技能显示目录聚合哈希（同样记录在 `skills.json` 的 `sha256` 字段）。

## 同步更新

本机技能更新后，在仓库根目录执行：

```powershell
.\sync.ps1                  # 复制 + 重新生成清单 + 提交 + 推送
.\sync.ps1 -DryRun          # 只看会有什么变化，不写任何文件
.\sync.ps1 -NoPush          # 只提交到本地，不推送
.\sync.ps1 -Message "说明"  # 自定义提交信息
.\sync.ps1 -IncludeSystem   # 连 Codex 内置 .system 官方技能一起备份
```

`README.md` 与 `skills.json` 均由脚本生成，请勿手工编辑；要改说明文字就改 `sync.ps1` 里的模板。