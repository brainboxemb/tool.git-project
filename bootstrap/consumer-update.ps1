# Managed-Source: brainboxemb/tool.git-project/bootstrap/consumer-update.ps1
# Managed-Source-Version: @TOOL_GIT_PROJECT_VERSION@
# Managed-Source-Revision: @TOOL_GIT_PROJECT_REVISION@
# Managed-Local-Patch: none
param(
    [ValidateSet("update", "status")]
    [string] $Command = "update"
)

$ErrorActionPreference = "Stop"
$ToolPath = "tools/tool.git-project"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was not found in PATH."
}

$Root = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $Root) {
    throw "Run update.ps1 from inside a Git repository."
}
$Root = $Root.Trim()

$Entry = (& git -C $Root ls-files --stage -- $ToolPath 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $Entry -or $Entry -notmatch '^160000\s+([0-9a-fA-F]{40})\s') {
    throw "Bootstrap dependency '$ToolPath' is not a committed gitlink."
}
$Expected = $Matches[1].ToLowerInvariant()
$ToolRoot = Join-Path $Root $ToolPath
$Tool = Join-Path $ToolRoot "git-project.ps1"

function Get-BootstrapHead {
    if (-not (Test-Path -LiteralPath $ToolRoot -PathType Container)) { return $null }
    $Top = (& git -C $ToolRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $Top) { return $null }
    return ((& git -C $ToolRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim().ToLowerInvariant())
}

function Get-BootstrapVersion {
    $VersionFile = Join-Path $ToolRoot "VERSION"
    if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) { return "unknown" }
    $Value = (Get-Content -LiteralPath $VersionFile | Select-Object -First 1).Trim()
    if (-not $Value) { return "unknown" }
    if ($Value.StartsWith("v")) { return $Value }
    return "v$Value"
}

function Show-BootstrapMismatch {
    param([string] $State, [string] $Current)
    $CurrentLabel = if ($Current) { $Current.Substring(0, 12) } else { "-" }
    Write-Host ("{0,-28} BOOTSTRAP state={1,-13} current={2} gitlink={3} version={4}" -f
        "tool.git-project",
        $State,
        $CurrentLabel,
        $Expected.Substring(0, 12),
        (Get-BootstrapVersion))
}

$Current = Get-BootstrapHead

if ($Command -eq "status") {
    if (-not $Current) {
        Show-BootstrapMismatch -State "UNINITIALIZED" -Current ""
        throw "Bootstrap engine is not initialized. Run .\bootstrap.ps1 or .\update.ps1."
    }

    $Dirty = (& git -C $ToolRoot status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect bootstrap engine state." }
    if ($Dirty) {
        Show-BootstrapMismatch -State "DIRTY" -Current $Current
        throw "Bootstrap engine has local changes; status will not execute modified tool code."
    }
    if ($Current -ne $Expected) {
        Show-BootstrapMismatch -State "DIFF" -Current $Current
        throw "Bootstrap engine differs from the committed gitlink. Run .\update.ps1 to align it."
    }

    & $Tool status -RepoRoot $Root
    if ($LASTEXITCODE -ne 0) { throw "Generic project status failed." }
    return
}

if ($Current) {
    $Dirty = (& git -C $ToolRoot status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect bootstrap engine state." }
    if ($Dirty) {
        throw "Bootstrap engine 'tool.git-project' has local changes; refusing to align it to the committed gitlink."
    }
}

& git -C $Root submodule sync -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to synchronize $ToolPath." }

if ($Current -and $Current -ne $Expected) {
    Write-Host "Aligning bootstrap tool.git-project: $Current -> $Expected (committed gitlink)"
}
& git -C $Root submodule update --init -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to initialize/align $ToolPath." }

$Current = Get-BootstrapHead
if (-not $Current -or $Current -ne $Expected) {
    throw "Bootstrap engine did not align to committed gitlink $Expected."
}
if (-not (Test-Path -LiteralPath $Tool -PathType Leaf)) {
    throw "Bootstrap engine entrypoint not found at $Tool"
}

& $Tool update -RepoRoot $Root
if ($LASTEXITCODE -ne 0) { throw "Generic project update failed." }
