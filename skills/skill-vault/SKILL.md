---
name: skill-vault
description: Maintain this machine's skill library and push it to the GitHub backup repo MianSkill — creating, updating, or deleting any skill under ~/.codex/skills, registering official skill sources, regenerating the manifest, and restoring the library on another machine. Use whenever a skill is created, edited, or removed, or when the user asks to back up, sync, push, or move skills; do not use it for git operations on unrelated projects.
metadata:
  short-description: Skill library backup and push hub
---

# Skill Vault（技能库总入口）

本技能是 `%USERPROFILE%\.codex\skills` 下所有技能「新建 / 更新 / 删除 / 备份 / 迁移」的唯一总入口。用的就是这一条命令：

```powershell
powershell -NoProfile -File F:\Codex\Skill\MianSkill\sync.ps1
```

它把本机技能镜像到 GitHub 仓库 `MianSkill`（https://github.com/LuckyMian/MianSkill），重新生成 `README.md` 与 `skills.json`（含来源标注），然后提交并推送 `origin/main`。

## 什么时候用它

- 本机任何技能被创建、修改、删除之后 —— 收尾必须执行上面那条命令，不能只留在本地。
- 用户要求备份 / 同步 / 推送技能，或在新电脑上还原技能库。
- 要把官方技能登记进备份，或确认某个技能是「官方未修改」还是「克隆后独立修改」。

只管 `~/.codex/skills` 这一层。其他项目的 git 操作、其他仓库的推送不要用本技能。

## 每次改动的标准收尾

1. 想先看会发生什么：`powershell -NoProfile -File F:\Codex\Skill\MianSkill\sync.ps1 -DryRun`（只报告，不写文件、不提交）。
2. 执行同步（复制 → 生成清单 → 提交 → 推送）。要自定义提交信息就加 `-Message "<前缀>：<改动摘要>"`，例如 `-Message "ruoyi：待办模块补充归档语义"`。
3. 读输出：技能状态表（名称 / 类型 / 文件数 / 变化）、`README.md` 与 `skills.json` 是否重新生成、有没有 orphan 提示、最后的 commit 与 push 结果。
4. 把结果如实汇报；推送失败要给出失败原因和重试命令，不要说“已备份”。

## 必须守住的不变量

1. `README.md` 与 `skills.json` 由 `sync.ps1` 生成，**绝不手工编辑**；要改文案就改脚本里的模板。
2. 新技能不需要往仓库里手工拷贝、也不改脚本：放进 `%USERPROFILE%\.codex\skills\<名字>\` 后会自动被收录为「自建」。
3. `.system` 与插件自带技能默认不入库（会被客户端更新覆盖，改了也留不住）；确实要备份才加 `-IncludeSystem`。
4. 官方技能来源只在 `sync.ps1` 的官方来源表里登记。不要为了让它保持「官方（未修改）」而改写文件或伪造哈希 —— 改过就是 `official-modified`，清单会写明「克隆自 X 后独立修改」。
5. 本机全局 git 配置挂着已失效的代理 `127.0.0.1:10809`：手工 git 命令要带 `-c http.proxy= -c https.proxy=`（`sync.ps1` 内部已自带）。GitHub 直连**平时**通，但会间歇被掐：症状是 `fatal: unable to access … OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to github.com:443`（TCP 端口能连上、TLS 握手被打断），`Test-NetConnection github.com -Port 443` 仍是 True，容易误判成「网络正常」。这时别反复重试，改走能访问 GitHub 的机器的 socks 隧道（N1 侧路由装了 OpenClash，实测可用）：
   ```powershell
   ssh -D 11080 -N root@192.168.1.168        # 另开一个窗口常驻（要输密码）
   git -C F:\Codex\Skill\MianSkill -c http.proxy=socks5h://127.0.0.1:11080 `
       -c https.proxy=socks5h://127.0.0.1:11080 push origin main
   ```
   推完记得 `git fetch origin` 核对 `origin/main` 真的到了那个 commit。
6. 技能改动必须推送，且推送失败必须报告 —— 本地提交不等于备份完成。

## 按需选读

- 跑同步 / 看懂输出 / 排查失败 / 改官方来源表 / 提交信息写法 → [references/sync-ps1.md](references/sync-ps1.md)
- 新建或更新技能、写法规范、登记官方技能、在新电脑上还原技能库 → [references/new-skill.md](references/new-skill.md)
