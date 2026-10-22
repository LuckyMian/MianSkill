# sync.ps1 使用与排查

脚本位置：`<当前工作区>\MianSkill\sync.ps1`（仓库 `LuckyMian/MianSkill` 克隆在当前工作区，分支 `main`）。它必须从仓库里运行：在工作区根目录用 `-File .\MianSkill\sync.ps1` 调用，或先 `cd` 到仓库根目录。

## 参数

| 参数 | 作用 |
| --- | --- |
| `-SkillsRoot <路径>` | 本机技能目录，默认 `%USERPROFILE%\.codex\skills`（脚本原有默认值）；**必须显式传当前工具的技能目录**：DSH `$env:USERPROFILE\.dsh\skills`、WorkBuddy `$env:USERPROFILE\.workbuddy\skills`、Claude Code `$env:USERPROFILE\.claude\skills` |
| `-DryRun` | 只报告会发生什么：robocopy 用 `/L` 预演，不写 `README.md` / `skills.json`，不做任何 git 操作 |
| `-NoPush` | 只提交到本地，不推送 |
| `-Message "<文本>"` | 自定义提交信息；缺省为 `sync skills: <日期> [<n> 个技能变更]` |
| `-IncludeSystem` | 连 `.system` 下的 Codex 内置技能一起备份（默认跳过，开启时逐条列出） |

## 执行分解

1. **校验**：仓库根必须有 `.git`，`-SkillsRoot` 必须存在，否则直接报错退出。
2. **扫描与判定**：遍历技能目录（目录名 = 技能名），读 `SKILL.md` 的 frontmatter（`name` / `description`），算目录聚合哈希与 `SKILL.md` 的 SHA256。两种哈希都按**行尾归一（CRLF→LF）后**的字节计算，因此同一份内容在不同机器、不同 checkout 行尾下结果一致；无法按 UTF-8 解码的二进制文件保持原字节。
3. **镜像**：`robocopy /MIR` 到 `skills\<名字>\`，排除 `.git`、`__pycache__`、`*.pyc`、`.DS_Store`；退出码 ≥ 8 视为失败。
4. **生成清单**：按扫描结果整体重写 `README.md` 与 `skills.json`；内容（含语义）没变时不重写，所以重复运行是幂等的。
5. **提交推送**：`git add -A` → 无差异则报「已是最新」并结束 → 有差异则 commit → `git push origin main`。

脚本内所有 git 调用都带 `-c http.proxy= -c https.proxy=`，绕开本机失效的全局代理。

## 类型判定（清单里的「类型」列）

| 类型 | 条件 | 清单表现 |
| --- | --- | --- |
| `own` 自建 | 目录名不在官方来源表里 | 来源「无（本地自建）」，显示目录聚合哈希 |
| `official` 官方（未修改） | 在官方来源表里，且 `SKILL.md` 哈希与表中记录一致 | 来源为官方仓库 + 仓库内路径，显示固定版本号与 `SKILL.md` SHA256 |
| `official-modified` 克隆后独立修改 | 在官方来源表里，但 `SKILL.md` 哈希不一致 | 来源写「克隆自 X 后独立修改」，基线版本 + 本机哈希 |

官方来源表在脚本顶部（`$OfficialSkills`），每条字段：`Name` / `Repo` / `Path`（仓库内的技能目录）/ `Rev`（固定 commit）/ `File`（默认 `SKILL.md`）/ `Sha256`（该文件**行尾归一后**的 SHA256，大写）。登记时先把官方文件归一化再取哈希，别直接拿原始下载文件的字节哈希。

新增一条的做法：

1. 找到官方仓库里该技能的目录与当前 commit；
2. `Get-FileHash <本机 SKILL.md> -Algorithm SHA256` 取本机哈希（本机若是官方原版，这个值就等于官方文件哈希）；
3. 在 `$OfficialSkills` 追加一条，跑 `-DryRun` 确认类型变成 `official`；
4. 同步推送，提交信息建议写成 `sync.ps1: 登记官方技能 <名字>`。

## 输出解读

- **技能状态表**：`名称 / 类型 / 文件 / 变化`；「变化」是 `新增` / `已更新` / `无变化`（`-DryRun` 下 `新增` 表示仓库里还没有它）。
- **README.md / skills.json**：`已重新生成` 或 `无变化`。
- **orphan 提示**：仓库里有、本机已不存在的技能；脚本只提示不删除。确认要移除时手工删掉仓库对应目录再同步（`git rm -r skills/<名字>`）。
- **已是最新**：没有任何改动需要提交，正常结果。

## 失败排查

| 现象 | 原因与处理 |
| --- | --- |
| `Failed to connect to 127.0.0.1 port 10809` | 全局 git 代理失效。`sync.ps1` 已自带绕过；手工命令用 `git -c http.proxy= -c https.proxy= ...` |
| 推送要求登录 / 认证失败 | 检查 Windows 凭据管理器里 `git:https://github.com` 的凭据（当前用户 `LuckyMian`）；失效就重新登录一次 |
| `! [rejected] main -> main (fetch first)` | 远端有新提交：先 `git -c http.proxy= -c https.proxy= pull --rebase`，再重跑同步 |
| `robocopy 失败（退出码 ≥ 8）` | 目标被占用或没权限；关掉占用 `skills\` 的程序（编辑器、同步盘）后重试 |
| 中文乱码 / 脚本报语法错 | `sync.ps1` 必须保留 UTF-8 with BOM（Windows PowerShell 5.1 才能正确解析中文）；改脚本时别丢 BOM |
| README/skills.json 反复「重新生成」 | 正常不会发生（JSON 用语义比较）；若出现，先确认脚本是最新版本，再检查是不是手工改过 `skills.json` |

## 提交信息约定

仓库日志里的风格是 `<前缀>：<改动摘要>`，前缀用技能名或项目名：

- 技能内容变化：`ruoyi：待办模块补充归档语义`
- 新增技能：`add skill: <名字>`
- 脚本 / 基础设施：`sync.ps1: <改了什么>`

不指定 `-Message` 时脚本用 `sync skills: <日期> [<n> 个技能变更]`。
