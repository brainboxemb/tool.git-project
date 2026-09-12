$ErrorActionPreference = "Stop"

$ToolPath = "tools/tool.git-project"
$ToolUrl = "https://github.com/brainboxemb/tool.git-project.git"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git was not found in PATH." }
$Root = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $Root) { throw "Run bootstrap.ps1 from inside a Git repository." }
$Root = $Root.Trim()

$Entry = & git -C $Root ls-files --stage -- $ToolPath 2>$null
if ($LASTEXITCODE -ne 0 -or $Entry -notmatch '^160000\s') {
    Write-Host "Registering bootstrap dependency: $ToolPath"
    & git -C $Root submodule add --force $ToolUrl $ToolPath
    if ($LASTEXITCODE -ne 0) { throw "Unable to register $ToolPath." }
}

& git -C $Root submodule sync -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to synchronize $ToolPath." }
& git -C $Root submodule update --init -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to initialize $ToolPath." }

& (Join-Path $Root "$ToolPath/git-project.ps1") bootstrap -RepoRoot $Root
if ($LASTEXITCODE -ne 0) { throw "Generic project bootstrap failed." }
