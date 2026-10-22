# 新建、更新与迁移技能

## 新建一个技能

1. **建目录**：当前 agent 的技能目录（WorkBuddy：`%USERPROFILE%\.workbuddy\skills\<技能名>\`；Codex：`%USERPROFILE%\.codex\skills\<技能名>\`），目录名必须与技能名一致（小写字母、数字、连字符，少于 64 字符）。
2. **写 `SKILL.md`**：frontmatter 必填 `name`（= 目录名）与 `description`；正文只写「模型自己想不到、但会改变决策」的东西，不写通用建议。
3. **按需加资源**：`references/` 放按需读取的细节文档（在 SKILL.md 里用相对链接写明何时读）、`assets/` 放要复制进产出的模板或图片、`scripts/` 放值得固化的确定性脚本。**不要**加 `README.md`、changelog 或重复的速查表。
4. **可选 UI 元数据**：`agents/openai.yaml`（`display_name` / `short_description` / `default_prompt`，其中 `default_prompt` 必须显式写 `$技能名`）。
5. **校验**：`py -3 -X utf8 <skill-creator>\scripts\quick_validate.py <技能目录>`（`-X utf8` 不能省，见下）。
6. **收尾必须推送**：`powershell -NoProfile -File F:\WorkBuddy\MianResourcePlanning\MianSkill\sync.ps1 -SkillsRoot "$env:USERPROFILE\.workbuddy\skills" -Message "add skill: <名字>"`。

本机的 `python` 是 Microsoft Store 占位符，用不了；统一用 `py -3`（Python 3.11.2）。

官方 skill-creator 的脚本（`<skill-creator>` = `C:\Users\Administrator\.codex\skills\.system\skill-creator`）：

```powershell
py -3 C:\Users\Administrator\.codex\skills\.system\skill-creator\scripts\init_skill.py <技能名> --path $env:USERPROFILE\.codex\skills --resources references
py -3 -X utf8 C:\Users\Administrator\.codex\skills\.system\skill-creator\scripts\quick_validate.py $env:USERPROFILE\.codex\skills\<技能名>
```

`init_skill.py` 生成的是待填模板，写完内容后务必跑一次校验；`generate_openai_yaml.py` 会整份重写 `agents/openai.yaml`，已有 `policy` / `dependencies` 字段时不要用它。

两个环境坑：校验脚本用系统默认编码读文件，中文 Windows 上是 GBK，直接跑会报 `UnicodeDecodeError`，所以必须加 `-X utf8`；它依赖 `pyyaml`，缺了会报 `ModuleNotFoundError: No module named 'yaml'`，补一次即可 `py -3 -m pip install --user pyyaml`。

## description 怎么写

一句话覆盖三件事：**做什么** + **什么时候该用** + **什么时候不要用**（边界）。它决定技能会不会被正确选中，是全文最值钱的一句。例如 `ruoyi-pocketbase-admin` 写成 `… Use for this project's frontend, PocketBase collections, runtime configuration, or N1 deployment work; do not use it for RuoYi/yudao Java backends or unrelated admin templates.`

## 更新已有技能

- 改完正文或引用文件后跑一次同步命令即可：脚本自动比对差异、更新清单哈希并推送。
- 被登记过官方来源、但已被改动的技能，清单会自动变成 `official-modified` 并写明「克隆自 X 后独立修改」——这是预期行为，不要绕过。
- 删除技能：先删本机目录，再跑同步；仓库里的旧目录会以 orphan 提示列出，确认后手工 `git rm -r skills/<名字>`。

## 迁移 / 在新电脑上还原

新机器：先把仓库克隆到当前工作区（规则 1），再复制到该机器上 agent 工具的技能目录（规则 2）。

```powershell
cd <当前工作区>
git -c http.proxy= -c https.proxy= clone https://github.com/LuckyMian/MianSkill
robocopy .\MianSkill\skills "$env:USERPROFILE\.workbuddy\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
```

Codex（技能目录 `%USERPROFILE%\.codex\skills`）：

```powershell
robocopy .\MianSkill\skills "$env:USERPROFILE\.codex\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
```

其他 AI 工具 / Claude Code（技能目录 `~/.claude/skills`）：

```powershell
robocopy .\MianSkill\skills "$env:USERPROFILE\.claude\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
```

还原后要在新机器上继续维护备份，就把仓库留在工作区，直接跑仓库里的 `sync.ps1 -SkillsRoot <该 agent 的技能目录>`；不传 `-SkillsRoot` 时脚本默认对 `.codex\skills` 生效。

## 清单字段（skills.json）

顶层：`schemaVersion`(1) / `repo` / `generatedAt` / `skillsRoot`。每个技能：

| 字段 | 含义 |
| --- | --- |
| `name` / `path` | 技能名与仓库内相对路径 |
| `type` | `own` / `official` / `official-modified` |
| `description` | 取自 `SKILL.md` frontmatter 原文 |
| `source` | `own` 为 `null`，否则 `{repo, path, ref}` |
| `sha256` | 目录聚合哈希（相对路径 + 文件内容，按路径排序） |
| `files` | 收录文件数（已排除 `.git` / `__pycache__` / `*.pyc` / `.DS_Store`） |
| `installTargets` | Codex 与通用工具的目标安装路径 |
| `provenance` | 一句话来源说明：自建 / 官方固定版本 / 克隆后独立修改 |
