[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PluginRoot,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$AddonId,

    [string]$ModRoot = (Join-Path $env:APPDATA 'FreeCAD\v1-1\Mod'),

    [switch]$Remove,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PluginRoot -PathType Container)) {
    throw "Plugin directory does not exist: $PluginRoot"
}

$resolvedPlugin = (Resolve-Path -LiteralPath $PluginRoot).ProviderPath.TrimEnd('\')
$targetPath = Join-Path $ModRoot $AddonId

if ($Remove) {
    $link = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
    if (-not $link) {
        Write-Host "No development link exists at $targetPath"
        exit 0
    }

    if (-not ($link.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to remove a real directory: $targetPath"
    }
    if ($link.LinkType -notin @('Junction', 'SymbolicLink')) {
        throw "Refusing to remove unsupported link type '$($link.LinkType)': $targetPath"
    }

    $linkTarget = @($link.Target)[0]
    if (-not $linkTarget) {
        throw "Cannot determine the target of $targetPath"
    }
    $resolvedLinkTarget = [IO.Path]::GetFullPath($linkTarget).TrimEnd('\')
    if ($resolvedLinkTarget -ne $resolvedPlugin) {
        throw "Link target mismatch. Expected '$resolvedPlugin', found '$resolvedLinkTarget'."
    }

    if ($DryRun) {
        Write-Host "[DRY RUN] Remove junction $targetPath -> $resolvedPlugin"
        exit 0
    }

    Remove-Item -LiteralPath $targetPath -Force
    Write-Host "Removed development link: $targetPath"
    exit 0
}

$existing = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
if ($existing) {
    if (-not ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to replace a real directory: $targetPath"
    }
    if ($existing.LinkType -notin @('Junction', 'SymbolicLink')) {
        throw "Refusing to replace unsupported link type '$($existing.LinkType)': $targetPath"
    }

    $existingTarget = @($existing.Target)[0]
    $resolvedExistingTarget = [IO.Path]::GetFullPath($existingTarget).TrimEnd('\')
    if ($resolvedExistingTarget -eq $resolvedPlugin) {
        Write-Host "Development link already exists: $targetPath -> $resolvedPlugin"
        exit 0
    }
    throw "Refusing to replace a link that points elsewhere: $targetPath -> $resolvedExistingTarget"
}

if ($DryRun) {
    Write-Host "[DRY RUN] Create junction $targetPath -> $resolvedPlugin"
    exit 0
}

if (-not (Test-Path -LiteralPath $ModRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $ModRoot | Out-Null
}

New-Item -ItemType Junction -Path $targetPath -Target $resolvedPlugin | Out-Null
Write-Host "Created development link: $targetPath -> $resolvedPlugin"
