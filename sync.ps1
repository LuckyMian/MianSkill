#Requires -Version 5.1
<#
.SYNOPSIS
  把本机 skill 同步到 MianSkill 备份仓库，并重新生成 README.md / skills.json。

.DESCRIPTION
  流程：
    1. 扫描本机 skills 目录（默认 %USERPROFILE%\.codex\skills）
    2. 判定每个技能类型：自建 / 官方（未修改）/ 克隆后独立修改
    3. robocopy 镜像到仓库 skills\<名称>\
    4. 重新生成 README.md 与 skills.json（内容无变化时不重写，保证幂等）
    5. git add / commit / push（-NoPush 跳过推送）

.PARAMETER SkillsRoot
  本机 skills 目录，默认 %USERPROFILE%\.codex\skills。

.PARAMETER DryRun
  只报告将要发生的改动，不写任何文件、不执行 git 提交或推送。

.PARAMETER NoPush
  只提交到本地，不推送远程。

.PARAMETER Message
  自定义提交信息，默认 "sync skills: <日期> [<n> 个技能变更]"。

.PARAMETER IncludeSystem
  连 Codex 内置的 .system 官方技能一起备份（默认跳过）。

.EXAMPLE
  .\sync.ps1 -DryRun

.EXAMPLE
  .\sync.ps1

.EXAMPLE
  .\sync.ps1 -NoPush -Message "add new skill"
#>
[CmdletBinding()]
param(
    [string]$SkillsRoot = (Join-Path $env:USERPROFILE '.codex\skills'),
    [switch]$DryRun,
    [switch]$NoPush,
    [string]$Message,
    [switch]$IncludeSystem
)

$ErrorActionPreference = 'Stop'

$RepoRoot       = $PSScriptRoot
$RepoSkillsRoot = Join-Path $RepoRoot 'skills'
$ReadmePath     = Join-Path $RepoRoot 'README.md'
$ManifestPath   = Join-Path $RepoRoot 'skills.json'
$RepoUrl        = 'https://github.com/LuckyMian/MianSkill'
$DefaultBranch  = 'main'
$Now            = Get-Date
$GeneratedAt    = $Now.ToString('yyyy-MM-ddTHH:mm:sszzz')
$GeneratedDate  = $Now.ToString('yyyy-MM-dd')
$Utf8NoBom      = New-Object System.Text.UTF8Encoding($false)

# 复制时永远排除的目录名 / 文件名模式
$ExcludeDirs = @('.git', '__pycache__')
$ExcludeFiles = @('*.pyc', '.DS_Store')

# ---------------------------------------------------------------------------
# 官方 skill 来源表：名称 -> 官方仓库 / 仓库内路径 / 固定版本 / SKILL.md 哈希
# 判定规则：本机 SKILL.md 哈希与表中一致 = official；不一致 = official-modified
# 新增官方技能时在这里追加一条即可。
# ---------------------------------------------------------------------------
$OfficialSkills = @(
    [pscustomobject]@{
        Name   = 'drawio'
        Repo   = 'https://github.com/jgraph/drawio-mcp'
        Path   = 'plugins/codex/drawio/skills/drawio'
        Rev    = 'eebe7def96409a15511a51fda958f4a620c2300a'
        File   = 'SKILL.md'
        Sha256 = '5E1D5460FC6A2DA7DA98AD851841EC174670F42C0B7339835CC709957B9328F7'
    }
)

$OfficialByName = @{}
foreach ($off in $OfficialSkills) { $OfficialByName[$off.Name] = $off }

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------

function Get-RelativePath {
    param([string]$Base, [string]$Full)
    $base = $Base.TrimEnd('\', '/')
    return $Full.Substring($base.Length).TrimStart('\', '/')
}

function Test-ExcludedRelPath {
    param([string]$RelativePath)
    $segments = $RelativePath -split '[\\/]'
    foreach ($seg in $segments) {
        if ($ExcludeDirs -contains $seg) { return $true }
        foreach ($pattern in $ExcludeFiles) {
            if ($seg -like $pattern) { return $true }
        }
    }
    return $false
}

function Get-SkillFiles {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $all = Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue
    return @($all | Where-Object { -not (Test-ExcludedRelPath -RelativePath (Get-RelativePath -Base $Root -Full $_.FullName)) })
}

function Get-FileHashUpper {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

# 目录内容汇总哈希：按相对路径（小写）排序后，把 "相对路径\n + 文件字节" 依次喂给 SHA256
function Get-DirectoryHash {
    param([string]$Root)
    $files = Get-SkillFiles -Root $Root | Sort-Object { (Get-RelativePath -Base $Root -Full $_.FullName).ToLowerInvariant() }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = New-Object System.IO.MemoryStream
    try {
        foreach ($f in $files) {
            $rel = (Get-RelativePath -Base $Root -Full $f.FullName).Replace('\', '/')
            $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($rel + "`n")
            $stream.Write($nameBytes, 0, $nameBytes.Length)
            $fileBytes = [System.IO.File]::ReadAllBytes($f.FullName)
            $stream.Write($fileBytes, 0, $fileBytes.Length)
        }
        $stream.Position = 0
        $hash = $sha.ComputeHash($stream)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

# 读取 SKILL.md 的 YAML frontmatter（只取 name / description，支持 > 和 | 折叠写法）
function Get-SkillFrontmatter {
    param([string]$SkillDir)
    $result = [ordered]@{ Name = ''; Description = '' }
    $skillMd = Join-Path $SkillDir 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillMd)) { return $result }

    $lines = @(Get-Content -LiteralPath $skillMd -Encoding UTF8)
    if ($lines.Count -lt 2) { return $result }
    if ($lines[0].Trim() -ne '---') { return $result }

    $blockKey = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim() -eq '---') { break }

        if ($blockKey) {
            if ($line -match '^\s+\S') {
                $result[$blockKey] = ($result[$blockKey] + ' ' + $line.Trim()).Trim()
                continue
            }
            $blockKey = $null
        }

        if ($line -match '^name:\s*(.+)$') {
            $result['Name'] = $Matches[1].Trim().Trim('"').Trim("'")
            continue
        }
        if ($line -match '^description:\s*(.*)$') {
            $value = $Matches[1].Trim()
            if ($value -eq '>' -or $value -eq '>-' -or $value -eq '|' -or $value -eq '|-') {
                $blockKey = 'Description'
                continue
            }
            $result['Description'] = $value.Trim('"').Trim("'")
            continue
        }
    }
    return $result
}

function Invoke-RepoGit {
    param([string[]]$GitArgs)
    # 全局 git 配置里可能挂着不可用的 http 代理，这里统一直连，避免同步失败
    $output = & git -C $RepoRoot -c http.proxy= -c https.proxy= @GitArgs 2>&1
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Output = @($output); ExitCode = $code }
}

function Copy-SkillDir {
    param([string]$Source, [string]$Destination, [switch]$WhatIfOnly)

    $rcArgs = @($Source, $Destination, '/MIR', '/XD') + $ExcludeDirs + @('/XF') + $ExcludeFiles +
              @('/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1')
    if ($WhatIfOnly) { $rcArgs += '/L' }

    $output = & robocopy @rcArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        throw "robocopy 失败（退出码 $code）：$Source -> $Destination`n$($output -join "`n")"
    }
    return [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}

function Get-NormalizedText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    # 时间戳不参与比较，保证重复运行不会产生空改动
    return ($Text -replace '"generatedAt"\s*:\s*"[^"]*"', '"generatedAt":"__TS__"' `
                  -replace '最后更新：\d{4}-\d{2}-\d{2}', '最后更新：__DATE__')
}

function Write-TextNoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

# ---------------------------------------------------------------------------
# 前置检查
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
    throw "当前目录不是 git 仓库：$RepoRoot（请先 clone https://github.com/LuckyMian/MianSkill）"
}
if (-not (Test-Path -LiteralPath $SkillsRoot)) {
    throw "本机 skills 目录不存在：$SkillsRoot"
}

Write-Host ''
Write-Host "MianSkill 同步" -ForegroundColor Cyan
Write-Host "  仓库      : $RepoRoot"
Write-Host "  本机技能  : $SkillsRoot"
if ($DryRun) { Write-Host "  运行模式  : DryRun（只报告，不写文件）" -ForegroundColor Yellow }
Write-Host ''

# ---------------------------------------------------------------------------
# 扫描本机技能
# ---------------------------------------------------------------------------
$scanDirs = @()
foreach ($dir in (Get-ChildItem -LiteralPath $SkillsRoot -Directory -Force | Sort-Object Name)) {
    if ($dir.Name -eq '.system') {
        if (-not $IncludeSystem) { continue }
        foreach ($child in (Get-ChildItem -LiteralPath $dir.FullName -Directory -Force | Sort-Object Name)) {
            $scanDirs += [pscustomobject]@{ Name = $child.Name; Path = $child.FullName; Bundled = $true }
        }
        continue
    }
    $scanDirs += [pscustomobject]@{ Name = $dir.Name; Path = $dir.FullName; Bundled = $false }
}

if ($scanDirs.Count -eq 0) { throw "没有在 $SkillsRoot 下找到任何技能目录" }

$entries = @()
foreach ($item in $scanDirs) {
    $meta      = Get-SkillFrontmatter -SkillDir $item.Path
    $skillMd   = Join-Path $item.Path 'SKILL.md'
    $skillHash = Get-FileHashUpper -Path $skillMd
    $off       = $OfficialByName[$item.Name]

    if ($off) {
        if ($skillHash -eq $off.Sha256) { $type = 'official' } else { $type = 'official-modified' }
        $source = [ordered]@{ repo = $off.Repo; path = $off.Path; ref = $off.Rev }
        $provenance = if ($type -eq 'official') {
            "官方技能，来源 $($off.Repo) 的 $($off.Path)，固定版本 $($off.Rev.Substring(0,7))，与本机文件哈希一致，未做修改"
        } else {
            "克隆自 $($off.Repo)（$($off.Rev.Substring(0,7))）后独立修改"
        }
    }
    elseif ($item.Bundled) {
        $type = 'official'
        $source = [ordered]@{ repo = 'Codex 内置（随客户端下发）'; path = $item.Name; ref = '' }
        $provenance = 'Codex 内置官方技能，随客户端下发'
    }
    else {
        $type = 'own'
        $source = $null
        $provenance = "本地自建（$($item.Path | Split-Path -Leaf) 目录创建于 $((Get-Item -LiteralPath $item.Path).CreationTime.ToString('yyyy-MM-dd'))）"
    }

    $files      = Get-SkillFiles -Root $item.Path
    $localHash  = Get-DirectoryHash -Root $item.Path
    $repoDir    = Join-Path $RepoSkillsRoot $item.Name
    $repoExists = Test-Path -LiteralPath $repoDir
    $repoHash   = if ($repoExists) { Get-DirectoryHash -Root $repoDir } else { '' }
    $changed    = (-not $repoExists) -or ($repoHash -ne $localHash)

    $entries += [pscustomobject]@{
        Name         = $item.Name
        Type         = $type
        TypeLabel    = switch ($type) {
            'own'               { '自建' }
            'official'          { '官方（未修改）' }
            'official-modified' { '克隆后独立修改' }
        }
        Source       = $source
        Provenance   = $provenance
        Path         = "skills/$($item.Name)"
        LocalPath    = $item.Path
        RepoPath     = $repoDir
        Description  = $meta.Description
        SkillMdHash  = $skillHash
        Sha256       = $localHash
        Files        = $files.Count
        FileCount    = $files.Count
        Changed      = $changed
        RepoExists   = $repoExists
        IsNew        = (-not $repoExists)
    }
}
$entries = @($entries | Sort-Object Name)

# 仓库里存在、本机已删除的技能（只提示，不自动删）
$orphans = @()
if (Test-Path -LiteralPath $RepoSkillsRoot) {
    $localNames = $entries | ForEach-Object { $_.Name }
    $orphans = @(Get-ChildItem -LiteralPath $RepoSkillsRoot -Directory -Force |
        Where-Object { $localNames -notcontains $_.Name } | Select-Object -ExpandProperty Name)
}

# ---------------------------------------------------------------------------
# 执行复制
# ---------------------------------------------------------------------------
$changedEntries = @($entries | Where-Object { $_.Changed })
foreach ($e in $entries) {
    if ($DryRun) {
        $probe = Copy-SkillDir -Source $e.LocalPath -Destination $e.RepoPath -WhatIfOnly
        $delta = @($probe.Output | Where-Object { $_ -match '\S' }).Count
        $state = if (-not $e.RepoExists) { '新增' } elseif ($delta -gt 0) { '有变化' } else { '无变化' }
    }
    else {
        $null = Copy-SkillDir -Source $e.LocalPath -Destination $e.RepoPath
        $state = if ($e.IsNew) { '新增' } elseif ($e.Changed) { '已更新' } else { '无变化' }
    }
    $e | Add-Member -NotePropertyName State -NotePropertyValue $state -Force
}

# ---------------------------------------------------------------------------
# 生成 README.md 与 skills.json
# ---------------------------------------------------------------------------
function Get-SkillsTableMarkdown {
    param($Items)
    $lines = @()
    $lines += '| 名称 | 类型 | 来源 | 版本 · 哈希 | 用途 |'
    $lines += '|------|------|------|-------------|------|'
    foreach ($e in $Items) {
        $shortHash = $e.Sha256.Substring(0, 12).ToLowerInvariant()
        switch ($e.Type) {
            'own' {
                $source    = '无（本地自建）'
                $version   = "聚合 SHA256 ``$shortHash``"
            }
            'official' {
                if ($e.Source.ref) {
                    $source  = "[$(($e.Source.repo -replace '^https://github\.com/', ''))]($($e.Source.repo)) ``$($e.Source.path)``"
                    $version = "固定于 ``$($e.Source.ref.Substring(0,7))`` · SKILL.md SHA256 ``$shortHash``"
                } else {
                    $source  = $e.Source.repo
                    $version = "随客户端下发 · SHA256 ``$shortHash``"
                }
            }
            'official-modified' {
                $source  = "克隆自 [$(($e.Source.repo -replace '^https://github\.com/', ''))]($($e.Source.repo)) 后独立修改"
                $version = "基线 ``$($e.Source.ref.Substring(0,7))`` · 本机聚合 SHA256 ``$shortHash``"
            }
        }
        $desc = ($e.Description -replace '\|', '\|').Trim()
        if (-not $desc) { $desc = '（SKILL.md 未写 description）' }
        $lines += "| ``$($e.Name)`` | $($e.TypeLabel) | $source | $version | $desc |"
    }
    return ($lines -join "`n")
}

$table = Get-SkillsTableMarkdown -Items $entries

$readme = @"
# MianSkill

自用 skill 备份仓库：把平时在用的 AI 技能集中存放，方便换电脑、给其他 AI 工具直接读取，以及长期留档。

> 本文件由 ``sync.ps1`` 自动生成，请勿手工编辑。最后更新：$GeneratedDate
> 同一份清单的机器可读版本见 [``skills.json``](skills.json)。

## 快速开始（给 AI 工具 / 新电脑）

每个技能就是 ``skills/<名称>/`` 下的一个目录，``SKILL.md`` 位于该目录根部，拷进 AI 工具的 skills 目录即可生效。

``````powershell
git clone $RepoUrl
``````

Codex（桌面 / CLI，技能目录 ``%USERPROFILE%\.codex\skills``）：

``````powershell
robocopy .\MianSkill\skills "`$env:USERPROFILE\.codex\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
``````

通用 AI 工具 / Claude Code（技能目录 ``~/.claude/skills``）：

``````powershell
robocopy .\MianSkill\skills "`$env:USERPROFILE\.claude\skills" /E /XD .git __pycache__ /XF *.pyc .DS_Store
``````

想让 AI 直接读清单：把 ``skills.json`` 或本文件交给它即可。``skills.json`` 字段为 ``name`` / ``type`` / ``path`` / ``description`` / ``source`` / ``sha256`` / ``files`` / ``installTargets`` / ``provenance``，``schemaVersion`` 为 1。

## 技能清单

$table

## 来源与修改标记规则

| 类型 | 含义 | 处理方式 |
|------|------|----------|
| ``own`` 自建 | 完全自己编写的技能 | 正文入库，来源记为「无（本地自建）」 |
| ``official`` 官方（未修改） | 直接安装的官方技能 | 正文作为固定版本快照入库，注明来源仓库、仓库内路径与固定版本号；官方发布新版本后不会自动跟随 |
| ``official-modified`` 克隆后独立修改 | 先克隆官方仓库、之后自己改动过 | 按独立技能维护，正文入库，来源栏写明「克隆自 X 后独立修改」 |

判定由 ``sync.ps1`` 自动完成：与脚本内官方来源表的哈希一致即为官方（未修改），不一致即为克隆后独立修改，其余目录一律视为自建。新增自建技能无需改脚本即可被自动纳入。

## 同步更新

本机技能更新后，在仓库根目录执行：

``````powershell
.\sync.ps1                  # 复制 + 重新生成清单 + 提交 + 推送
.\sync.ps1 -DryRun          # 只看会有什么变化，不写任何文件
.\sync.ps1 -NoPush          # 只提交到本地，不推送
.\sync.ps1 -Message "说明"  # 自定义提交信息
.\sync.ps1 -IncludeSystem   # 连 Codex 内置 .system 官方技能一起备份
``````

``README.md`` 与 ``skills.json`` 均由脚本生成，请勿手工编辑；要改说明文字就改 ``sync.ps1`` 里的模板。
"@

$manifestSkills = @()
foreach ($e in $entries) {
    $manifestSkills += [ordered]@{
        name           = $e.Name
        type           = $e.Type
        path           = $e.Path
        description    = $e.Description
        source         = $e.Source
        sha256         = $e.Sha256
        files          = $e.Files
        installTargets = @(
            "%USERPROFILE%\.codex\skills\$($e.Name)",
            "%USERPROFILE%\.claude\skills\$($e.Name)"
        )
        provenance     = $e.Provenance
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    repo          = $RepoUrl
    generatedAt   = $GeneratedAt
    skillsRoot    = 'skills'
    skills        = $manifestSkills
}
$manifestJson = ($manifest | ConvertTo-Json -Depth 8) + "`n"

# 只有内容真的变了才落盘，保证重复运行不产生空改动
$readmeChanged = $true
if (Test-Path -LiteralPath $ReadmePath) {
    $oldReadme = [System.IO.File]::ReadAllText($ReadmePath, [System.Text.Encoding]::UTF8)
    if ((Get-NormalizedText -Text $oldReadme) -eq (Get-NormalizedText -Text $readme)) { $readmeChanged = $false }
}
$manifestChanged = $true
if (Test-Path -LiteralPath $ManifestPath) {
    $oldManifest = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::UTF8)
    if ((Get-NormalizedText -Text $oldManifest) -eq (Get-NormalizedText -Text $manifestJson)) { $manifestChanged = $false }
}

if (-not $DryRun) {
    if ($readmeChanged)   { Write-TextNoBom -Path $ReadmePath   -Text $readme }
    if ($manifestChanged) { Write-TextNoBom -Path $ManifestPath -Text $manifestJson }
}

# ---------------------------------------------------------------------------
# 汇总输出
# ---------------------------------------------------------------------------
Write-Host '技能状态' -ForegroundColor Cyan
$fmt = '  {0,-22} {1,-20} {2,4}  {3}'
Write-Host ($fmt -f '名称', '类型', '文件', '变化')
foreach ($e in $entries) {
    Write-Host ($fmt -f $e.Name, $e.TypeLabel, $e.Files, $e.State)
}
Write-Host ''
Write-Host ("  README.md  : " + $(if ($readmeChanged) { '已重新生成' } else { '无变化' }))
Write-Host ("  skills.json: " + $(if ($manifestChanged) { '已重新生成' } else { '无变化' }))
if ($orphans.Count -gt 0) {
    Write-Host ''
    Write-Host "  提示：仓库里这些技能本机已不存在，本次未删除：$($orphans -join ', ')" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# git 提交与推送
# ---------------------------------------------------------------------------
if ($DryRun) {
    $status = Invoke-RepoGit -GitArgs @('status', '--short')
    Write-Host ''
    Write-Host 'DryRun：未写入任何文件，未执行 git 操作。' -ForegroundColor Yellow
    Write-Host '当前仓库 git status：'
    if ($status.Output.Count -eq 0) { Write-Host '  （工作区干净）' } else { $status.Output | ForEach-Object { Write-Host "  $_" } }
    return
}

$add = Invoke-RepoGit -GitArgs @('add', '-A')
if ($add.ExitCode -ne 0) { throw "git add 失败：`n$($add.Output -join "`n")" }

$null = Invoke-RepoGit -GitArgs @('diff', '--cached', '--quiet')
if ($LASTEXITCODE -eq 0) {
    Write-Host ''
    Write-Host '已是最新，没有任何改动需要提交。' -ForegroundColor Green
    return
}

if (-not $Message) { $Message = "sync skills: $GeneratedDate [$($changedEntries.Count) 个技能变更]" }

$commit = Invoke-RepoGit -GitArgs @('commit', '-m', $Message)
if ($commit.ExitCode -ne 0) { throw "git commit 失败：`n$($commit.Output -join "`n")" }
$head = (Invoke-RepoGit -GitArgs @('rev-parse', '--short', 'HEAD')).Output | Select-Object -First 1
Write-Host ''
Write-Host "已提交：$head  $Message" -ForegroundColor Green

if ($NoPush) {
    Write-Host '未推送（-NoPush）。需要时执行：git -c http.proxy= -c https.proxy= push origin main'
    return
}

$push = Invoke-RepoGit -GitArgs @('push', 'origin', $DefaultBranch)
if ($push.ExitCode -ne 0) {
    Write-Host ''
    Write-Host "推送失败（本地已提交，稍后可重试）：`n$($push.Output -join "`n")" -ForegroundColor Yellow
    return
}
Write-Host "已推送到 origin/$DefaultBranch" -ForegroundColor Green
