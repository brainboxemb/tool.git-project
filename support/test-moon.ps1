$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("moon-regression-" + [guid]::NewGuid().ToString('N'))
$InstallRoot = Join-Path $TempRoot 'moon-runtime'
$Fresh = Join-Path $TempRoot 'worktree'
$Results = Join-Path $Root 'moon-test-results'

function Get-ExecutionCount([string]$Repository) {
    $path = Join-Path $Repository 'fixture/moon/.executions/count.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 0 }
    return [int](Get-Content -LiteralPath $path -Raw).Trim()
}

function Remove-Generated([string]$Repository) {
    foreach ($relative in @('fixture/moon/out', 'fixture/moon/.executions', '.moon/cache', '.moon/invocations')) {
        $path = Join-Path $Repository $relative
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
}

try {
    Set-Location $Root

    # Existing dependency tooling remains valid before a Moon runtime exists.
    & (Join-Path $Root 'git-project.ps1') validate -RepoRoot (Join-Path $Root 'fixture') *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Git-only validation failed before Moon bootstrap.' }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $moon = (& (Join-Path $Root 'moon-project.ps1') bootstrap -InstallRoot $InstallRoot | Select-Object -Last 1).Trim()
    $timer.Stop()
    $bootstrapMs = [int64]$timer.ElapsedMilliseconds
    $env:MOON_BIN = $moon

    & (Join-Path $Root 'moon-project.ps1') validate -Repo $Root -InstallRoot $InstallRoot *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Moon repository validation failed.' }

    $cachePaths = @(& (Join-Path $Root 'moon-project.ps1') cache-paths -Repo $Root)
    if ($cachePaths.Count -ne 2) { throw 'Expected exactly two portable Moon cache paths.' }
    if ($cachePaths[0] -ne (Join-Path $Root '.moon/cache/hashes')) { throw "Unexpected hashes cache path: $($cachePaths[0])" }
    if ($cachePaths[1] -ne (Join-Path $Root '.moon/cache/outputs')) { throw "Unexpected outputs cache path: $($cachePaths[1])" }

    Remove-Generated $Root

    & (Join-Path $Root 'moon-project.ps1') run 'fixture:cache.fixture' -Repo $Root -InstallRoot $InstallRoot -EvidenceDir '.moon/invocations/cold' *> $null
    if ((Get-ExecutionCount $Root) -ne 1) { throw 'Cold Moon task did not execute exactly once.' }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'fixture/moon/out/artifact.txt'))) { throw 'Cold artifact missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'fixture/moon/out/evidence/execution.log'))) { throw 'Cold producer evidence missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $Root '.moon/invocations/cold/materialization.json'))) { throw 'Cold materialization evidence missing.' }

    & (Join-Path $Root 'moon-project.ps1') run 'fixture:cache.fixture' -Repo $Root -InstallRoot $InstallRoot -EvidenceDir '.moon/invocations/exact' *> $null
    if ((Get-ExecutionCount $Root) -ne 1) { throw 'Exact rerun unexpectedly executed the producer.' }

    Remove-Item -LiteralPath (Join-Path $Root 'fixture/moon/out') -Recurse -Force
    & (Join-Path $Root 'moon-project.ps1') run 'fixture:cache.fixture' -Repo $Root -InstallRoot $InstallRoot -EvidenceDir '.moon/invocations/local-hydration' *> $null
    if ((Get-ExecutionCount $Root) -ne 1) { throw 'Local hydration unexpectedly executed the producer.' }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'fixture/moon/out/artifact.txt'))) { throw 'Local hydration did not restore artifact.' }

    & git -C $Root worktree add --detach $Fresh HEAD *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create fresh regression worktree.' }
    New-Item -ItemType Directory -Force -Path (Join-Path $Fresh '.moon/cache') | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root '.moon/cache/hashes') -Destination (Join-Path $Fresh '.moon/cache/hashes') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Root '.moon/cache/outputs') -Destination (Join-Path $Fresh '.moon/cache/outputs') -Recurse -Force

    & (Join-Path $Root 'moon-project.ps1') run 'fixture:cache.fixture' -Repo $Fresh -InstallRoot $InstallRoot -EvidenceDir '.moon/invocations/fresh-hydration' *> $null
    if ((Get-ExecutionCount $Fresh) -ne 0) { throw 'Fresh cache hydration executed the producer.' }
    if (-not (Test-Path -LiteralPath (Join-Path $Fresh 'fixture/moon/out/artifact.txt'))) { throw 'Fresh cache hydration did not restore artifact.' }

    Add-Content -LiteralPath (Join-Path $Fresh 'README.md') -Value "`nunrelated change"
    & (Join-Path $Root 'moon-project.ps1') run 'fixture:cache.fixture' -Repo $Fresh -InstallRoot $InstallRoot -EvidenceDir '.moon/invocations/unrelated' *> $null
    if ((Get-ExecutionCount $Fresh) -ne 0) { throw 'Unrelated change unexpectedly executed the producer.' }

    Add-Content -LiteralPath (Join-Path $Fresh 'fixture/moon/input.txt') -Value "`nrelevant change"
    & (Join-Path $Root 'moon-project.ps1') run 'fixture:cache.fixture' -Repo $Fresh -InstallRoot $InstallRoot -EvidenceDir '.moon/invocations/relevant' *> $null
    if ((Get-ExecutionCount $Fresh) -ne 1) { throw 'Relevant input change did not execute the producer.' }

    New-Item -ItemType Directory -Force -Path $Results | Out-Null
    [ordered]@{
        platform = 'windows-x86_64'
        moon_version = '2.5.4'
        bootstrap_ms = $bootstrapMs
        checks = [ordered]@{
            git_core_without_moon = $true
            cold_execution = $true
            exact_rerun_skips_command = $true
            local_hydration_skips_command = $true
            fresh_hydration_skips_command = $true
            unrelated_change_stays_cached = $true
            relevant_change_executes = $true
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Results 'windows.json') -Encoding utf8

    Write-Host "PASS Moon production interface on Windows (bootstrap_ms=$bootstrapMs)"
}
finally {
    Set-Location $Root
    Remove-Generated $Root
    & git -C $Root worktree remove --force $Fresh *> $null
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
    Remove-Item Env:MOON_BIN -ErrorAction SilentlyContinue
}
