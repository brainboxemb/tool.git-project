[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('bootstrap', 'validate', 'cache-paths', 'run', 'help')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Task,

    [string]$Repo = '.',
    [string]$InstallRoot,
    [string]$EvidenceDir
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeManifest = Join-Path $ScriptDir 'moon/runtime.env'

function Fail([string]$Message) {
    throw $Message
}

function Read-RuntimeManifest {
    if (-not (Test-Path -LiteralPath $RuntimeManifest -PathType Leaf)) {
        Fail "Moon runtime manifest not found: $RuntimeManifest"
    }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $RuntimeManifest) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $parts = $line.Split('=', 2)
        if ($parts.Count -ne 2) { Fail "Invalid Moon runtime manifest line: $line" }
        $values[$parts[0]] = $parts[1]
    }
    return $values
}

$Runtime = Read-RuntimeManifest
$MoonVersion = $Runtime['MOON_VERSION']

function Get-DefaultInstallRoot {
    if ($env:MOON_INSTALL_ROOT) { return $env:MOON_INSTALL_ROOT }
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'brainboxemb/tool.git-project/moon') }
    if ($HOME) { return (Join-Path $HOME '.cache/brainboxemb/tool.git-project/moon') }
    Fail 'Cannot determine Moon install root; set MOON_INSTALL_ROOT.'
}

if (-not $InstallRoot) {
    $InstallRoot = Get-DefaultInstallRoot
}

function Test-MoonVersion([string]$Candidate) {
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { return $false }
    try {
        $output = (& $Candidate --version 2>&1 | Out-String).Trim()
        return $output.Contains($MoonVersion)
    }
    catch {
        return $false
    }
}

function Install-PinnedMoon([string]$Root) {
    $installDir = Join-Path $Root "$MoonVersion/windows-x86_64"
    $target = Join-Path $installDir 'moon.exe'
    if (Test-MoonVersion $target) { return $target }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("moon-bootstrap-" + [guid]::NewGuid().ToString('N'))
    $archive = Join-Path $tempDir 'moon.zip'
    $extract = Join-Path $tempDir 'extract'
    New-Item -ItemType Directory -Force -Path $extract | Out-Null

    try {
        Invoke-WebRequest -Uri $Runtime['MOON_WINDOWS_X86_64_URL'] -OutFile $archive
        $digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
        if ($digest -ne $Runtime['MOON_WINDOWS_X86_64_SHA256']) {
            Fail "Moon archive digest mismatch: $digest"
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
        $moon = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'moon.exe' | Select-Object -First 1
        if (-not $moon) { Fail 'moon.exe not found after extraction.' }
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
        Copy-Item -LiteralPath $moon.FullName -Destination $target -Force
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    }

    if (-not (Test-MoonVersion $target)) {
        Fail "Bootstrapped Moon does not report expected version $MoonVersion."
    }
    return $target
}

function Resolve-Moon([string]$Root) {
    if ($env:MOON_BIN) {
        if (-not (Test-MoonVersion $env:MOON_BIN)) {
            Fail "MOON_BIN does not point to Moon ${MoonVersion}: $($env:MOON_BIN)"
        }
        return $env:MOON_BIN
    }

    $discovered = Get-Command moon -ErrorAction SilentlyContinue
    if ($discovered -and (Test-MoonVersion $discovered.Source)) {
        return $discovered.Source
    }

    return Install-PinnedMoon $Root
}

function Resolve-Repo([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Fail "Repository directory does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-MoonRepository([string]$Repository, [string]$Root) {
    $workspace = Join-Path $Repository '.moon/workspace.yml'
    $tasks = Join-Path $Repository 'moon.yml'
    if (-not (Test-Path -LiteralPath $workspace -PathType Leaf)) { Fail "Missing Moon workspace configuration: $workspace" }
    if (-not (Test-Path -LiteralPath $tasks -PathType Leaf)) { Fail "Missing Moon task configuration: $tasks" }

    & git -C $Repository rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { Fail "Not a Git worktree: $Repository" }

    $moon = Resolve-Moon $Root
    if (-not (Test-MoonVersion $moon)) { Fail "Resolved Moon runtime is not version $MoonVersion." }
}

switch ($Command) {
    'help' {
        Write-Host 'Usage:'
        Write-Host '  .\moon-project.ps1 bootstrap [-InstallRoot PATH]'
        Write-Host '  .\moon-project.ps1 validate [-Repo PATH] [-InstallRoot PATH]'
        Write-Host '  .\moon-project.ps1 cache-paths [-Repo PATH]'
        Write-Host '  .\moon-project.ps1 run TASK [-Repo PATH] [-InstallRoot PATH] [-EvidenceDir PATH]'
        exit 0
    }

    'bootstrap' {
        $moon = Install-PinnedMoon $InstallRoot
        Write-Output $moon
        exit 0
    }

    'validate' {
        $repository = Resolve-Repo $Repo
        Assert-MoonRepository $repository $InstallRoot
        Write-Output "OK moon repository: version=$MoonVersion repo=$repository"
        exit 0
    }

    'cache-paths' {
        $repository = Resolve-Repo $Repo
        Write-Output (Join-Path $repository $Runtime['MOON_CACHE_HASHES'])
        Write-Output (Join-Path $repository $Runtime['MOON_CACHE_OUTPUTS'])
        exit 0
    }

    'run' {
        if (-not $Task) { Fail 'run requires a Moon task name' }
        if ($Task -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]*$') { Fail "Unsafe Moon task name: $Task" }

        $repository = Resolve-Repo $Repo
        Assert-MoonRepository $repository $InstallRoot
        $moon = Resolve-Moon $InstallRoot

        if (-not $EvidenceDir) {
            $safeTask = $Task.Replace(':', '_')
            $EvidenceDir = ".moon/invocations/$safeTask"
        }
        if (-not [System.IO.Path]::IsPathRooted($EvidenceDir)) {
            $EvidenceDir = Join-Path $repository $EvidenceDir
        }
        New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

        $logFile = Join-Path $EvidenceDir 'moon.log'
        $jsonFile = Join-Path $EvidenceDir 'materialization.json'
        $sourceRevision = (& git -C $repository rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { Fail 'Cannot determine source revision.' }
        $moonVersionOutput = (& $moon --version 2>&1 | Out-String).Trim()
        $toolVersion = (Get-Content -LiteralPath (Join-Path $ScriptDir 'VERSION') -Raw).Trim()
        $startedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $timer = [System.Diagnostics.Stopwatch]::StartNew()

        Push-Location $repository
        try {
            & $moon run $Task --log info 2>&1 | Tee-Object -FilePath $logFile
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        $timer.Stop()
        $finishedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $status = if ($exitCode -eq 0) { 'success' } else { 'failure' }

        [ordered]@{
            schema_version = 1
            tool_git_project_version = $toolVersion
            moon_version = $moonVersionOutput
            task = $Task
            source_revision = $sourceRevision
            status = $status
            exit_code = $exitCode
            started_at = $startedAt
            finished_at = $finishedAt
            duration_ms = [int64]$timer.ElapsedMilliseconds
        } | ConvertTo-Json | Set-Content -LiteralPath $jsonFile -Encoding utf8

        if ($exitCode -ne 0) { exit $exitCode }
        exit 0
    }
}
