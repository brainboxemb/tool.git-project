# Managed-Source: brainboxemb/tool.git-project/bootstrap/consumer-bootstrap.ps1
# Managed-Source-Version: @TOOL_GIT_PROJECT_VERSION@
# Managed-Source-Revision: @TOOL_GIT_PROJECT_REVISION@
# Managed-Local-Patch: none
$ErrorActionPreference = "Stop"

$ToolPath = "tools/tool.git-project"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git was not found in PATH." }
$Root = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $Root) { throw "Run bootstrap.ps1 from inside a Git repository." }
$Root = $Root.Trim()

$Entry = (& git -C $Root ls-files --stage -- $ToolPath 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $Entry -or $Entry -notmatch '^160000\s+([0-9a-fA-F]{40})\s') {
    throw "Bootstrap dependency '$ToolPath' is not a committed gitlink. Register tool.git-project once with 'git submodule add https://github.com/brainboxemb/tool.git-project.git $ToolPath', pin the desired commit, and commit .gitmodules + the gitlink."
}
$Expected = $Matches[1].ToLowerInvariant()
$ToolRoot = Join-Path $Root $ToolPath

$Current = $null
if (Test-Path -LiteralPath $ToolRoot -PathType Container) {
    $Top = (& git -C $ToolRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -eq 0 -and $Top) {
        $Current = ((& git -C $ToolRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim().ToLowerInvariant())
        $Dirty = (& git -C $ToolRoot status --porcelain 2>$null)
        if ($LASTEXITCODE -ne 0) { throw "Unable to inspect bootstrap engine state." }
        if ($Dirty) {
            throw "Bootstrap engine 'tool.git-project' has local changes; refusing to align it to the committed gitlink."
        }
    }
}

& git -C $Root submodule sync -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to synchronize $ToolPath." }
if ($Current -and $Current -ne $Expected) {
    Write-Host "Aligning bootstrap tool.git-project: $Current -> $Expected (committed gitlink)"
}
& git -C $Root submodule update --init -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to initialize/align $ToolPath." }

$Actual = ((& git -C $ToolRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim().ToLowerInvariant())
if ($LASTEXITCODE -ne 0 -or $Actual -ne $Expected) {
    throw "Bootstrap engine did not align to committed gitlink $Expected."
}

& (Join-Path $ToolRoot "git-project.ps1") bootstrap -RepoRoot $Root
if ($LASTEXITCODE -ne 0) { throw "Generic project bootstrap failed." }
