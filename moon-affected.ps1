[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Task,

    [Parameter(Mandatory = $true)]
    [string]$Base,

    [Parameter(Mandatory = $true)]
    [string]$Head,

    [string]$Repo = '.',
    [string]$InstallRoot,
    [string]$EvidenceDir = '.moon/preflight'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-Repository([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Repository directory does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Write-Decision(
    [bool]$Affected,
    [string]$Status,
    [string]$Reason,
    [string]$MoonVersion
) {
    [ordered]@{
        schema_version = 1
        tool = 'tool.git-project/moon-affected'
        moon_version = $MoonVersion
        task = $Task
        base = $Base
        head = $Head
        affected = $Affected
        status = $Status
        reason = $Reason
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'decision.json') -Encoding utf8
}

function Return-Conservative([string]$Reason, [string]$MoonVersion = 'unknown') {
    Write-Decision -Affected $true -Status 'conservative' -Reason $Reason -MoonVersion $MoonVersion
    Write-Output 'true'
    exit 0
}

if ($Task -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*:[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Affected preflight requires a fully-qualified Moon task target: $Task"
}

$Repository = Resolve-Repository $Repo
if (-not [System.IO.Path]::IsPathRooted($EvidenceDir)) {
    $EvidenceDir = Join-Path $Repository $EvidenceDir
}
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
Set-Content -LiteralPath (Join-Path $EvidenceDir 'changed-files.json') -Value '' -Encoding utf8
Set-Content -LiteralPath (Join-Path $EvidenceDir 'affected-tasks.json') -Value '' -Encoding utf8

& git -C $Repository rev-parse --verify --quiet "${Base}^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { Return-Conservative "base-revision-not-found:$Base" }
& git -C $Repository rev-parse --verify --quiet "${Head}^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { Return-Conservative "head-revision-not-found:$Head" }

$moonProject = Join-Path $ScriptDir 'moon-project.ps1'
try {
    if ($InstallRoot) {
        $moon = (& $moonProject bootstrap -InstallRoot $InstallRoot 2> (Join-Path $EvidenceDir 'bootstrap.log') | Select-Object -Last 1).Trim()
    }
    else {
        $moon = (& $moonProject bootstrap 2> (Join-Path $EvidenceDir 'bootstrap.log') | Select-Object -Last 1).Trim()
    }
}
catch {
    Return-Conservative 'moon-bootstrap-failed'
}

$moonVersion = (& $moon --version 2>&1 | Out-String).Trim()

try {
    if ($InstallRoot) {
        & $moonProject validate -Repo $Repository -InstallRoot $InstallRoot *> (Join-Path $EvidenceDir 'validate.log')
    }
    else {
        & $moonProject validate -Repo $Repository *> (Join-Path $EvidenceDir 'validate.log')
    }
    if ($LASTEXITCODE -ne 0) { Return-Conservative 'moon-repository-validation-failed' $moonVersion }
}
catch {
    Return-Conservative 'moon-repository-validation-failed' $moonVersion
}

Push-Location $Repository
try {
    & $moon task $Task --json 1> (Join-Path $EvidenceDir 'task.json') 2> (Join-Path $EvidenceDir 'task-error.log')
    if ($LASTEXITCODE -ne 0) { Return-Conservative 'moon-task-not-found-or-invalid' $moonVersion }

    & $moon query changed-files --base $Base --head $Head 1> (Join-Path $EvidenceDir 'changed-files.json') 2> (Join-Path $EvidenceDir 'changed-files-error.log')
    if ($LASTEXITCODE -ne 0) { Return-Conservative 'moon-changed-files-query-failed' $moonVersion }

    $project, $taskId = $Task.Split(':', 2)
    $projectRegex = '^' + [regex]::Escape($project) + '$'
    $taskRegex = '^' + [regex]::Escape($taskId) + '$'
    $changedJson = Get-Content -LiteralPath (Join-Path $EvidenceDir 'changed-files.json') -Raw

    $changedJson | & $moon query tasks --affected --project $projectRegex --id $taskRegex 1> (Join-Path $EvidenceDir 'affected-tasks.json') 2> (Join-Path $EvidenceDir 'affected-tasks-error.log')
    if ($LASTEXITCODE -ne 0) { Return-Conservative 'moon-affected-task-query-failed' $moonVersion }
}
finally {
    Pop-Location
}

try {
    $affectedQuery = Get-Content -LiteralPath (Join-Path $EvidenceDir 'affected-tasks.json') -Raw | ConvertFrom-Json
    $projectTasks = $affectedQuery.tasks.$project
    $affected = $null -ne $projectTasks -and $null -ne $projectTasks.$taskId
}
catch {
    Return-Conservative 'moon-affected-task-result-invalid' $moonVersion
}

if ($affected) {
    Write-Decision -Affected $true -Status 'success' -Reason 'task-affected' -MoonVersion $moonVersion
    Write-Output 'true'
}
else {
    Write-Decision -Affected $false -Status 'success' -Reason 'task-unaffected' -MoonVersion $moonVersion
    Write-Output 'false'
}
