param(
    [ValidateSet("check", "refresh")]
    [string] $Command = "check",
    [string] $RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was not found in PATH."
}

$ToolRoot = Split-Path $PSScriptRoot -Parent
$VersionFile = Join-Path $ToolRoot "VERSION"
if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
    throw "tool.git-project VERSION file not found at $VersionFile"
}
$ToolVersion = (Get-Content -LiteralPath $VersionFile | Select-Object -First 1).Trim()
$ToolRevision = (& git -C $ToolRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or -not $ToolRevision) {
    throw "Unable to resolve tool.git-project source revision."
}

if ($RepoRoot) {
    $Root = (& git -C $RepoRoot rev-parse --show-toplevel).Trim()
} else {
    $Root = (& git rev-parse --show-toplevel).Trim()
}
if ($LASTEXITCODE -ne 0 -or -not $Root) {
    throw "Unable to resolve consumer repository root."
}

$ManagedLaunchers = @(
    [PSCustomObject]@{ Source = "bootstrap/consumer-bootstrap.ps1"; Target = "bootstrap.ps1" },
    [PSCustomObject]@{ Source = "bootstrap/consumer-bootstrap.sh"; Target = "bootstrap.sh" },
    [PSCustomObject]@{ Source = "bootstrap/consumer-update.ps1"; Target = "update.ps1" },
    [PSCustomObject]@{ Source = "bootstrap/consumer-update.sh"; Target = "update.sh" }
)
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Render-ManagedLauncher {
    param([string] $SourcePath)
    $SourceFile = Join-Path $ToolRoot $SourcePath
    $Text = [System.IO.File]::ReadAllText($SourceFile)
    return $Text.Replace("@TOOL_GIT_PROJECT_VERSION@", $ToolVersion).Replace("@TOOL_GIT_PROJECT_REVISION@", $ToolRevision)
}

function Get-LocalPatchMarker {
    param([string] $Text)
    $Match = [regex]::Match($Text, '(?m)^# Managed-Local-Patch:\s*(.+?)\s*$')
    if (-not $Match.Success) { return "" }
    return $Match.Groups[1].Value.Trim()
}

foreach ($Launcher in $ManagedLaunchers) {
    $Expected = Render-ManagedLauncher $Launcher.Source
    $TargetFile = Join-Path $Root $Launcher.Target
    $Current = if (Test-Path -LiteralPath $TargetFile -PathType Leaf) {
        [System.IO.File]::ReadAllText($TargetFile)
    } else {
        ""
    }

    if ($Current -eq $Expected) { continue }

    $Patch = Get-LocalPatchMarker $Current
    if ($Patch -and $Patch -ne "none") {
        Write-Warning "Managed launcher '$($Launcher.Target)' has declared local patch '$Patch'; preserving it. Canonical source: brainboxemb/tool.git-project/$($Launcher.Source)@$ToolVersion ($ToolRevision)."
        continue
    }

    if ($Command -eq "check") {
        Write-Warning "Managed launcher drift: '$($Launcher.Target)' differs from brainboxemb/tool.git-project/$($Launcher.Source)@$ToolVersion ($ToolRevision)."
        continue
    }

    [System.IO.File]::WriteAllText($TargetFile, $Expected, $Utf8NoBom)
    Write-Host "Refreshed managed launcher: $($Launcher.Target) <- brainboxemb/tool.git-project/$($Launcher.Source)@$ToolVersion ($($ToolRevision.Substring(0, 12)))"
}
