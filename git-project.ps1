param(
    [Parameter(Position = 0)]
    [ValidateSet("validate", "bootstrap", "status", "update")]
    [string] $Command = "status",

    [string] $RepoRoot = ""
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string] $WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]] $Args,
        [switch] $Capture,
        [switch] $AllowFailure
    )

    if ($Capture) {
        $Output = & git -C $WorkingDirectory @Args 2>&1
    } else {
        & git -C $WorkingDirectory @Args
        $Output = $null
    }

    $Code = $LASTEXITCODE
    if (-not $AllowFailure -and $Code -ne 0) {
        throw "git $($Args -join ' ') failed in '$WorkingDirectory' with exit code $Code."
    }

    return [PSCustomObject]@{ Code = $Code; Output = $Output }
}

function Unquote-Value {
    param([string] $Value)
    $Result = $Value.Trim()
    if ($Result.Length -ge 2) {
        if (($Result.StartsWith('"') -and $Result.EndsWith('"')) -or
            ($Result.StartsWith("'") -and $Result.EndsWith("'"))) {
            return $Result.Substring(1, $Result.Length - 2)
        }
    }
    return $Result
}

function Resolve-RepoRoot {
    param([string] $Requested)

    if ($Requested) {
        $Resolved = (Resolve-Path $Requested).Path
        $Check = Invoke-Git -WorkingDirectory $Resolved -Args @("rev-parse", "--show-toplevel") -Capture
        return ($Check.Output | Select-Object -First 1).Trim()
    }

    $Here = (Get-Location).Path
    $Check = Invoke-Git -WorkingDirectory $Here -Args @("rev-parse", "--show-toplevel") -Capture
    return ($Check.Output | Select-Object -First 1).Trim()
}

function Flush-Item {
    param([string] $Section, $Current, [System.Collections.ArrayList] $Profiles, [System.Collections.ArrayList] $Dependencies)
    if (-not $Current) { return }
    if ($Section -eq "profiles") { [void]$Profiles.Add([PSCustomObject]$Current) }
    if ($Section -eq "dependencies") { [void]$Dependencies.Add([PSCustomObject]$Current) }
}

function Read-ProjectModel {
    param([string] $Root)

    $ProjectFile = Join-Path $Root "project.yml"
    if (-not (Test-Path $ProjectFile -PathType Leaf)) {
        throw "project.yml not found at $ProjectFile"
    }

    $SchemaVersion = $null
    $ProjectName = ""
    $Section = ""
    $Current = $null
    $Profiles = [System.Collections.ArrayList]@()
    $Dependencies = [System.Collections.ArrayList]@()

    foreach ($Raw in Get-Content $ProjectFile) {
        if (-not $Raw.Trim() -or $Raw.TrimStart().StartsWith("#")) { continue }

        $Indent = $Raw.Length - $Raw.TrimStart().Length
        if ($Raw.Substring(0, $Indent) -match "`t") { throw "Tabs are not supported in project.yml indentation." }
        $Text = $Raw.Trim()

        if ($Indent -eq 0) {
            Flush-Item -Section $Section -Current $Current -Profiles $Profiles -Dependencies $Dependencies
            $Current = $null

            if ($Text -match '^schema_version:\s*(.+)$') {
                $SchemaVersion = [int](Unquote-Value $Matches[1])
                $Section = ""
            } elseif ($Text -eq "project:") {
                $Section = "project"
            } elseif ($Text -eq "profiles:") {
                $Section = "profiles"
            } elseif ($Text -eq "dependencies:") {
                $Section = "dependencies"
            } else {
                throw "Unsupported top-level project.yml entry: $Text"
            }
            continue
        }

        if ($Section -eq "project") {
            if ($Indent -ne 2 -or $Text -notmatch '^name:\s*(.+)$') {
                throw "Only project.name is supported in generic project.yml v1."
            }
            $ProjectName = Unquote-Value $Matches[1]
            continue
        }

        if ($Section -eq "profiles") {
            if ($Indent -eq 2 -and $Text -match '^-\s*type:\s*(.+)$') {
                Flush-Item -Section $Section -Current $Current -Profiles $Profiles -Dependencies $Dependencies
                $Current = [ordered]@{ Type = (Unquote-Value $Matches[1]); Config = "" }
                continue
            }
            if ($Current -and $Indent -eq 4 -and $Text -match '^config:\s*(.+)$') {
                $Current.Config = Unquote-Value $Matches[1]
                continue
            }
            throw "Unsupported profiles entry: $Text"
        }

        if ($Section -eq "dependencies") {
            if ($Indent -eq 2 -and $Text -match '^-\s*name:\s*(.+)$') {
                Flush-Item -Section $Section -Current $Current -Profiles $Profiles -Dependencies $Dependencies
                $Current = [ordered]@{ Name = (Unquote-Value $Matches[1]); Role = ""; Type = ""; Url = ""; Path = ""; Ref = "" }
                continue
            }
            if ($Current -and $Indent -eq 4 -and $Text -match '^([^:]+):\s*(.*)$') {
                $Key = $Matches[1].Trim()
                $Value = Unquote-Value $Matches[2]
                switch ($Key) {
                    "role" { $Current.Role = $Value }
                    "type" { $Current.Type = $Value }
                    "url"  { $Current.Url = $Value }
                    "path" { $Current.Path = $Value }
                    "ref"  { $Current.Ref = $Value }
                    default { throw "Unsupported dependency field '$Key'." }
                }
                continue
            }
            throw "Unsupported dependencies entry: $Text"
        }

        throw "Entry outside a supported project.yml section: $Text"
    }

    Flush-Item -Section $Section -Current $Current -Profiles $Profiles -Dependencies $Dependencies

    if ($SchemaVersion -ne 1) { throw "schema_version must be 1." }
    if (-not $ProjectName) { throw "project.name is required." }

    $ProfileTypes = @{}
    foreach ($Profile in $Profiles) {
        if (-not $Profile.Type -or -not $Profile.Config) { throw "Each profile requires type and config." }
        if ($ProfileTypes.ContainsKey($Profile.Type)) { throw "Duplicate profile type '$($Profile.Type)'." }
        $ProfileTypes[$Profile.Type] = $true
        $ProfilePath = Join-Path $Root $Profile.Config
        if (-not (Test-Path $ProfilePath -PathType Leaf)) { throw "Profile config not found: $($Profile.Config)" }
    }

    $Names = @{}
    $Paths = @{}
    foreach ($Dependency in $Dependencies) {
        foreach ($Field in @("Name", "Role", "Type", "Url", "Path", "Ref")) {
            if (-not $Dependency.$Field) { throw "Dependency is missing $Field." }
        }
        if ($Dependency.Type -ne "git-submodule") { throw "Unsupported dependency type '$($Dependency.Type)' for $($Dependency.Name)." }
        if ([System.IO.Path]::IsPathRooted($Dependency.Path)) { throw "Dependency path must be relative: $($Dependency.Path)" }
        $Segments = $Dependency.Path -split '[\\/]'
        if ($Segments -contains "..") { throw "Dependency path may not escape repository: $($Dependency.Path)" }
        if ($Names.ContainsKey($Dependency.Name)) { throw "Duplicate dependency name '$($Dependency.Name)'." }
        if ($Paths.ContainsKey($Dependency.Path)) { throw "Duplicate dependency path '$($Dependency.Path)'." }
        $Names[$Dependency.Name] = $true
        $Paths[$Dependency.Path] = $true
    }

    return [PSCustomObject]@{
        SchemaVersion = $SchemaVersion
        ProjectName = $ProjectName
        Profiles = @($Profiles)
        Dependencies = @($Dependencies)
    }
}

function Test-Gitlink {
    param([string] $Root, [string] $Path)
    $Result = Invoke-Git -WorkingDirectory $Root -Args @("ls-files", "--stage", "--", $Path) -Capture -AllowFailure
    return ($Result.Code -eq 0 -and (($Result.Output -join "`n") -match '^160000\s'))
}

function Get-SubmoduleName {
    param([string] $Root, [string] $Path)
    $Modules = Join-Path $Root ".gitmodules"
    if (-not (Test-Path $Modules -PathType Leaf)) { return $null }
    $Rows = Invoke-Git -WorkingDirectory $Root -Args @("config", "-f", ".gitmodules", "--get-regexp", '^submodule\..*\.path$') -Capture -AllowFailure
    if ($Rows.Code -ne 0) { return $null }
    foreach ($Line in $Rows.Output) {
        $Parts = $Line -split '\s+', 2
        if ($Parts.Count -eq 2 -and $Parts[1].Trim() -eq $Path) {
            return ($Parts[0] -replace '^submodule\.', '' -replace '\.path$', '')
        }
    }
    return $null
}

function Ensure-Registration {
    param([string] $Root, $Dependency)

    $Path = $Dependency.Path
    $FullPath = Join-Path $Root $Path
    $Name = Get-SubmoduleName -Root $Root -Path $Path

    if (-not (Test-Gitlink -Root $Root -Path $Path)) {
        if (Test-Path $FullPath) {
            $Children = @(Get-ChildItem -Force $FullPath -ErrorAction SilentlyContinue)
            if ($Children.Count -eq 0) {
                Remove-Item -Force $FullPath
            } elseif (-not (Test-Path (Join-Path $FullPath ".git"))) {
                throw "Cannot register '$Path': target contains non-submodule files."
            }
        }
        $Parent = Split-Path $FullPath -Parent
        if ($Parent -and -not (Test-Path $Parent)) { New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
        Write-Host "Registering $($Dependency.Name) at $Path"
        Invoke-Git -WorkingDirectory $Root -Args @("submodule", "add", "--force", $Dependency.Url, $Path) | Out-Null
        $Name = Get-SubmoduleName -Root $Root -Path $Path
    }

    if (-not $Name) {
        $Name = $Dependency.Name
        Invoke-Git -WorkingDirectory $Root -Args @("config", "-f", ".gitmodules", "submodule.$Name.path", $Path) | Out-Null
        Invoke-Git -WorkingDirectory $Root -Args @("config", "-f", ".gitmodules", "submodule.$Name.url", $Dependency.Url) | Out-Null
    } else {
        $CurrentUrl = Invoke-Git -WorkingDirectory $Root -Args @("config", "-f", ".gitmodules", "--get", "submodule.$Name.url") -Capture -AllowFailure
        if ($CurrentUrl.Code -ne 0 -or ($CurrentUrl.Output | Select-Object -First 1).Trim() -ne $Dependency.Url) {
            Invoke-Git -WorkingDirectory $Root -Args @("config", "-f", ".gitmodules", "submodule.$Name.url", $Dependency.Url) | Out-Null
        }
    }

    Invoke-Git -WorkingDirectory $Root -Args @("submodule", "sync", "--", $Path) | Out-Null
    Invoke-Git -WorkingDirectory $Root -Args @("submodule", "update", "--init", "--", $Path) | Out-Null
}

function Assert-CleanDependency {
    param([string] $FullPath, [string] $Name)
    $Result = Invoke-Git -WorkingDirectory $FullPath -Args @("status", "--porcelain") -Capture
    if ($Result.Output) { throw "Dependency '$Name' has local changes; refusing checkout/update." }
}

function Resolve-DependencyCommit {
    param([string] $FullPath, [string] $Ref, [switch] $Fetch)

    if ($Fetch) {
        Invoke-Git -WorkingDirectory $FullPath -Args @("fetch", "origin", "--prune", "--tags") | Out-Null
    }

    $Candidates = @()
    if ($Ref -match '^[0-9a-fA-F]{40}$') { $Candidates += "$Ref^{commit}" }
    $Candidates += "refs/tags/$Ref^{commit}"
    $Candidates += "origin/$Ref^{commit}"
    $Candidates += "$Ref^{commit}"

    foreach ($Candidate in $Candidates) {
        $Result = Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "--verify", $Candidate) -Capture -AllowFailure
        if ($Result.Code -eq 0) { return ($Result.Output | Select-Object -First 1).Trim() }
    }
    return $null
}

function Sync-Dependency {
    param([string] $Root, $Dependency, [string] $Mode)

    Ensure-Registration -Root $Root -Dependency $Dependency
    $FullPath = Join-Path $Root $Dependency.Path
    Assert-CleanDependency -FullPath $FullPath -Name $Dependency.Name

    $Expected = Resolve-DependencyCommit -FullPath $FullPath -Ref $Dependency.Ref -Fetch
    if (-not $Expected) { throw "Unable to resolve ref '$($Dependency.Ref)' for $($Dependency.Name)." }
    $Current = (Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "HEAD") -Capture).Output | Select-Object -First 1
    $Current = $Current.Trim()

    if ($Current -ne $Expected) {
        Write-Host "$Mode $($Dependency.Name): $Current -> $Expected ($($Dependency.Ref))"
        Invoke-Git -WorkingDirectory $FullPath -Args @("checkout", "--detach", $Expected) | Out-Null
    } else {
        Write-Host "$($Dependency.Name): already at $Expected ($($Dependency.Ref))"
    }
}

function Show-Status {
    param([string] $Root, $Model)

    foreach ($Dependency in $Model.Dependencies) {
        $FullPath = Join-Path $Root $Dependency.Path
        $Gitlink = Test-Gitlink -Root $Root -Path $Dependency.Path
        if (-not $Gitlink -or -not (Test-Path $FullPath)) {
            Write-Host ("{0,-28} MISSING  ref={1} path={2}" -f $Dependency.Name, $Dependency.Ref, $Dependency.Path)
            continue
        }

        $CurrentResult = Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "HEAD") -Capture -AllowFailure
        if ($CurrentResult.Code -ne 0) {
            Write-Host ("{0,-28} UNINITIALIZED ref={1} path={2}" -f $Dependency.Name, $Dependency.Ref, $Dependency.Path)
            continue
        }

        $Current = ($CurrentResult.Output | Select-Object -First 1).Trim()
        $Expected = Resolve-DependencyCommit -FullPath $FullPath -Ref $Dependency.Ref
        $Dirty = (Invoke-Git -WorkingDirectory $FullPath -Args @("status", "--porcelain") -Capture).Output
        $State = if ($Dirty) { "DIRTY" } elseif ($Expected -and $Expected -eq $Current) { "OK" } elseif ($Expected) { "DIFF" } else { "UNKNOWN" }
        Write-Host ("{0,-28} {1,-7} current={2} ref={3}" -f $Dependency.Name, $State, $Current.Substring(0, 12), $Dependency.Ref)
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git was not found in PATH." }

$Root = Resolve-RepoRoot -Requested $RepoRoot
$Model = Read-ProjectModel -Root $Root

switch ($Command) {
    "validate" {
        Write-Host "project.yml valid: $($Model.ProjectName) ($($Model.Dependencies.Count) dependencies, $($Model.Profiles.Count) profiles)"
    }
    "status" {
        Show-Status -Root $Root -Model $Model
    }
    "bootstrap" {
        foreach ($Dependency in $Model.Dependencies) { Sync-Dependency -Root $Root -Dependency $Dependency -Mode "Bootstrapping" }
        Write-Host ""
        Show-Status -Root $Root -Model $Model
        Write-Host ""
        Write-Host "Bootstrap complete. Review parent changes with: git status"
    }
    "update" {
        foreach ($Dependency in $Model.Dependencies) { Sync-Dependency -Root $Root -Dependency $Dependency -Mode "Updating" }
        Write-Host ""
        Show-Status -Root $Root -Model $Model
        Write-Host ""
        Write-Host "Update complete. Review project.yml and gitlink changes before committing."
    }
}
