$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("moon-affected-" + [guid]::NewGuid().ToString('N'))
$InstallRoot = Join-Path $TempRoot 'moon-runtime'
$Repo = Join-Path $TempRoot 'repo'
$Results = Join-Path $Root 'moon-test-results'

function Get-ExecutionCount([string]$Repository) {
    $path = Join-Path $Repository 'fixture/moon/.executions/count.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 0 }
    return [int](Get-Content -LiteralPath $path -Raw).Trim()
}

function Assert-Decision([string]$Evidence, [bool]$Affected, [string]$Status) {
    $decision = Get-Content -LiteralPath (Join-Path $Evidence 'decision.json') -Raw | ConvertFrom-Json
    if ([bool]$decision.affected -ne $Affected) { throw "Unexpected affected decision in $Evidence" }
    if ($decision.status -ne $Status) { throw "Unexpected status in ${Evidence}: $($decision.status)" }
}

try {
    & git clone --quiet --no-hardlinks $Root $Repo
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone local Moon fixture repository.' }
    & git -C $Repo config user.email 'moon-affected-test@example.invalid'
    & git -C $Repo config user.name 'Moon affected test'

    $moon = (& (Join-Path $Root 'moon-project.ps1') bootstrap -InstallRoot $InstallRoot | Select-Object -Last 1).Trim()
    $env:MOON_BIN = $moon

    $baseRevision = (& git -C $Repo rev-parse HEAD).Trim()

    Add-Content -LiteralPath (Join-Path $Repo 'README.md') -Value "`nREADME-only preflight fixture change."
    & git -C $Repo add README.md
    & git -C $Repo commit --quiet -m 'Test README-only affected decision'
    $docsRevision = (& git -C $Repo rev-parse HEAD).Trim()

    $docsEvidence = Join-Path $Repo '.moon/preflight/docs'
    $docsResult = (& (Join-Path $Root 'moon-affected.ps1') 'fixture:cache.fixture' -Repo $Repo -Base $baseRevision -Head $docsRevision -InstallRoot $InstallRoot -EvidenceDir $docsEvidence | Select-Object -Last 1).Trim()
    if ($docsResult -ne 'false') { throw "README-only change should be unaffected, got: $docsResult" }
    if ((Get-ExecutionCount $Repo) -ne 0) { throw 'README-only preflight executed the producer.' }
    Assert-Decision $docsEvidence $false 'success'

    $aggregateDocsEvidence = Join-Path $Repo '.moon/preflight/aggregate-docs'
    $aggregateDocsResult = (& (Join-Path $Root 'moon-affected.ps1') 'fixture:cache.aggregate' -Repo $Repo -Base $baseRevision -Head $docsRevision -InstallRoot $InstallRoot -EvidenceDir $aggregateDocsEvidence | Select-Object -Last 1).Trim()
    if ($aggregateDocsResult -ne 'false') { throw "README-only aggregate should be unaffected, got: $aggregateDocsResult" }
    if ((Get-ExecutionCount $Repo) -ne 0) { throw 'README-only aggregate preflight executed the producer.' }
    Assert-Decision $aggregateDocsEvidence $false 'success'

    Add-Content -LiteralPath (Join-Path $Repo 'fixture/moon/input.txt') -Value "`nrelevant committed preflight change"
    & git -C $Repo add fixture/moon/input.txt
    & git -C $Repo commit --quiet -m 'Test affected task input decision'
    $inputRevision = (& git -C $Repo rev-parse HEAD).Trim()

    $inputEvidence = Join-Path $Repo '.moon/preflight/input'
    $inputResult = (& (Join-Path $Root 'moon-affected.ps1') 'fixture:cache.fixture' -Repo $Repo -Base $docsRevision -Head $inputRevision -InstallRoot $InstallRoot -EvidenceDir $inputEvidence | Select-Object -Last 1).Trim()
    if ($inputResult -ne 'true') { throw "Task input change should be affected, got: $inputResult" }
    if ((Get-ExecutionCount $Repo) -ne 0) { throw 'Affected preflight executed the producer.' }
    Assert-Decision $inputEvidence $true 'success'

    $aggregateEvidence = Join-Path $Repo '.moon/preflight/aggregate'
    $aggregateResult = (& (Join-Path $Root 'moon-affected.ps1') 'fixture:cache.aggregate' -Repo $Repo -Base $docsRevision -Head $inputRevision -InstallRoot $InstallRoot -EvidenceDir $aggregateEvidence | Select-Object -Last 1).Trim()
    if ($aggregateResult -ne 'true') { throw "Affected upstream task should affect aggregate target, got: $aggregateResult" }
    if ((Get-ExecutionCount $Repo) -ne 0) { throw 'Aggregate affected preflight executed the producer.' }
    Assert-Decision $aggregateEvidence $true 'success'
    $aggregateQuery = Get-Content -LiteralPath (Join-Path $aggregateEvidence 'affected-tasks.json') -Raw | ConvertFrom-Json
    $aggregateAffected = $aggregateQuery.options.affected.tasks.'fixture:cache.aggregate'
    if ($null -eq $aggregateAffected) { throw 'Aggregate affected evidence did not include fixture:cache.aggregate.' }
    if ($aggregateAffected.upstream -notcontains 'fixture:cache.fixture') { throw 'Aggregate affected evidence did not identify fixture:cache.fixture as affected upstream work.' }

    $conservativeEvidence = Join-Path $Repo '.moon/preflight/conservative'
    $conservativeResult = (& (Join-Path $Root 'moon-affected.ps1') 'fixture:cache.fixture' -Repo $Repo -Base 'refs/heads/does-not-exist' -Head $inputRevision -InstallRoot $InstallRoot -EvidenceDir $conservativeEvidence | Select-Object -Last 1).Trim()
    if ($conservativeResult -ne 'true') { throw "Missing revision should fail conservative, got: $conservativeResult" }
    if ((Get-ExecutionCount $Repo) -ne 0) { throw 'Conservative preflight executed the producer.' }
    Assert-Decision $conservativeEvidence $true 'conservative'

    New-Item -ItemType Directory -Force -Path $Results | Out-Null
    [ordered]@{
        platform = 'windows-x86_64'
        moon_version = '2.5.4'
        checks = [ordered]@{
            readme_only_unaffected = $true
            task_input_affected = $true
            aggregate_upstream_affected = $true
            aggregate_readme_only_unaffected = $true
            query_does_not_execute_producer = $true
            missing_revision_fails_conservative = $true
            explicit_base_head = $true
            moon_graph_propagation = $true
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Results 'windows-affected.json') -Encoding utf8

    Write-Host 'PASS Moon affected preflight on Windows'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
    Remove-Item Env:MOON_BIN -ErrorAction SilentlyContinue
}