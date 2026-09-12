$ErrorActionPreference = "Stop"

$ToolPath = "tools/tool.git-project"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git was not found in PATH." }
$Root = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $Root) { throw "Run bootstrap.ps1 from inside a Git repository." }
$Root = $Root.Trim()

$Entry = & git -C $Root ls-files --stage -- $ToolPath 2>$null
if ($LASTEXITCODE -ne 0 -or $Entry -notmatch '^160000\s') {
    throw "Bootstrap dependency '$ToolPath' is not a committed gitlink. Register tool.git-project once with 'git submodule add https://github.com/brainboxemb/tool.git-project.git $ToolPath', pin the desired commit, and commit .gitmodules + the gitlink."
}

& git -C $Root submodule sync -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to synchronize $ToolPath." }
& git -C $Root submodule update --init -- $ToolPath
if ($LASTEXITCODE -ne 0) { throw "Unable to initialize $ToolPath." }

& (Join-Path $Root "$ToolPath/git-project.ps1") bootstrap -RepoRoot $Root
if ($LASTEXITCODE -ne 0) { throw "Generic project bootstrap failed." }
