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

function Test-DependencyRepoInitialized {
    param([string] $FullPath)

    if (-not (Test-Path $FullPath -PathType Container)) { return $false }
    $Top = Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "--show-toplevel") -Capture -AllowFailure
    if ($Top.Code -ne 0) { return $false }

    $ResolvedTop = ($Top.Output | Select-Object -First 1).Trim()
    if (-not $ResolvedTop) { return $false }

    $TrimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $Expected = [System.IO.Path]::GetFullPath($FullPath).TrimEnd($TrimChars)
    $Actual = [System.IO.Path]::GetFullPath($ResolvedTop).TrimEnd($TrimChars)
    return ($Expected -eq $Actual)
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

    if (-not (Test-DependencyRepoInitialized -FullPath $FullPath)) {
        Invoke-Git -WorkingDirectory $Root -Args @("submodule", "update", "--init", "--", $Path) | Out-Null
    }
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
        if (-not $Gitlink -or -not (Test-DependencyRepoInitialized -FullPath $FullPath)) {
            Write-Host ("{0,-28} UNINITIALIZED ref={1} path={2}" -f $Dependency.Name, $Dependency.Ref, $Dependency.Path)
            continue
        }

        $Current = ((Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "HEAD") -Capture).Output | Select-Object -First 1).Trim()
        $Expected = Resolve-DependencyCommit -FullPath $FullPath -Ref $Dependency.Ref
        $Dirty = (Invoke-Git -WorkingDirectory $FullPath -Args @("status", "--porcelain") -Capture).Output
        $State = if ($Dirty) { "DIRTY" } elseif ($Expected -and $Expected -eq $Current) { "OK" } elseif ($Expected) { "DIFF" } else { "UNKNOWN" }
        Write-Host ("{0,-28} {1,-7} current={2} ref={3}" -f $Dependency.Name, $State, $Current.Substring(0, 12), $Dependency.Ref)
    }
}


function Normalize-RepositoryUrl {
    param([string] $Url)
    $Value = $Url.Trim().TrimEnd('/')
    if ($Value.EndsWith('.git')) { $Value = $Value.Substring(0, $Value.Length - 4) }
    if ($Value -match '^git@github\.com:(.+)$') { $Value = "https://github.com/$($Matches[1])" }
    return $Value
}

function Get-GitlinkCommit {
    param([string] $Owner, [string] $Path)
    $Result = Invoke-Git -WorkingDirectory $Owner -Args @("ls-files", "--stage", "--", $Path) -Capture -AllowFailure
    $Text = $Result.Output -join "`n"
    if ($Result.Code -eq 0 -and $Text -match '^160000\s+([0-9a-fA-F]{40})\s+') {
        return $Matches[1]
    }
    return $null
}

function Assert-NestedRefConsistency {
    param([string] $FullPath, [string] $Ref, [string] $Gitlink)

    Invoke-Git -WorkingDirectory $FullPath -Args @("fetch", "origin", "--prune", "--tags") | Out-Null

    if ($Ref -match '^[0-9a-fA-F]{40}$') {
        if ($Ref -ne $Gitlink) {
            throw "Nested dependency ref $Ref does not match committed gitlink $Gitlink at $FullPath."
        }
        return
    }

    $Tag = Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "--verify", "refs/tags/$Ref^{commit}") -Capture -AllowFailure
    if ($Tag.Code -eq 0) {
        $Resolved = ($Tag.Output | Select-Object -First 1).Trim()
        if ($Resolved -ne $Gitlink) {
            throw "Nested dependency tag $Ref resolves to $Resolved but owner gitlink is $Gitlink at $FullPath."
        }
        return
    }

    $Branch = Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "--verify", "origin/$Ref^{commit}") -Capture -AllowFailure
    if ($Branch.Code -ne 0) {
        throw "Unable to resolve nested dependency ref '$Ref' at $FullPath."
    }
}

function Initialize-ExternalClosure {
    param([string] $Owner, [string[]] $Lineage)

    $OwnerModel = Read-ProjectModel -Root $Owner
    foreach ($Dependency in $OwnerModel.Dependencies) {
        if ($Dependency.Role -ne "external") { continue }
        if ($Dependency.Type -ne "git-submodule") {
            throw "Unsupported transitive external dependency type '$($Dependency.Type)' for $($Dependency.Name)."
        }

        $Normalized = Normalize-RepositoryUrl $Dependency.Url
        if ($Lineage -contains $Normalized) {
            throw "Dependency cycle detected through $($Dependency.Url) while walking $Owner."
        }

        $Gitlink = Get-GitlinkCommit -Owner $Owner -Path $Dependency.Path
        if (-not $Gitlink) {
            throw "External dependency '$($Dependency.Name)' is not a committed gitlink at $Owner/$($Dependency.Path)."
        }

        $SubmoduleName = Get-SubmoduleName -Root $Owner -Path $Dependency.Path
        if (-not $SubmoduleName) {
            throw "No .gitmodules entry found for $Owner/$($Dependency.Path)."
        }
        $Configured = Invoke-Git -WorkingDirectory $Owner -Args @("config", "-f", ".gitmodules", "--get", "submodule.$SubmoduleName.url") -Capture -AllowFailure
        $ConfiguredUrl = if ($Configured.Code -eq 0) { ($Configured.Output | Select-Object -First 1).Trim() } else { "" }
        if ((Normalize-RepositoryUrl $ConfiguredUrl) -ne $Normalized) {
            throw "URL mismatch for $Owner/$($Dependency.Path): project.yml=$($Dependency.Url) .gitmodules=$ConfiguredUrl"
        }

        Invoke-Git -WorkingDirectory $Owner -Args @("submodule", "sync", "--", $Dependency.Path) | Out-Null
        Invoke-Git -WorkingDirectory $Owner -Args @("submodule", "update", "--init", "--", $Dependency.Path) | Out-Null

        $FullPath = Join-Path $Owner $Dependency.Path
        if (-not (Test-DependencyRepoInitialized -FullPath $FullPath)) {
            throw "Unable to initialize transitive external dependency '$($Dependency.Name)' at $FullPath."
        }
        Assert-CleanDependency -FullPath $FullPath -Name $Dependency.Name

        $Current = ((Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "HEAD") -Capture).Output | Select-Object -First 1).Trim()
        if ($Current -ne $Gitlink) {
            throw "Nested dependency '$($Dependency.Name)' checked out $Current but owner gitlink requires $Gitlink."
        }

        Assert-NestedRefConsistency -FullPath $FullPath -Ref $Dependency.Ref -Gitlink $Gitlink
        Write-Host "external $($Dependency.Name) owner=$Owner path=$($Dependency.Path) current=$($Current.Substring(0, 12)) ref=$($Dependency.Ref)"

        Initialize-ExternalClosure -Owner $FullPath -Lineage @($Lineage + $Normalized)
    }
}

function Initialize-RootExternalClosure {
    param([string] $Root, $Model)

    $RootUrlResult = Invoke-Git -WorkingDirectory $Root -Args @("remote", "get-url", "origin") -Capture -AllowFailure
    $RootLineage = @()
    if ($RootUrlResult.Code -eq 0 -and $RootUrlResult.Output) {
        $RootLineage += Normalize-RepositoryUrl (($RootUrlResult.Output | Select-Object -First 1).Trim())
    }

    foreach ($Dependency in $Model.Dependencies) {
        if ($Dependency.Role -ne "external") { continue }
        $FullPath = Join-Path $Root $Dependency.Path
        $Lineage = @($RootLineage + (Normalize-RepositoryUrl $Dependency.Url))
        Initialize-ExternalClosure -Owner $FullPath -Lineage $Lineage
    }
}


function Get-OwnerRelativeLabel {
    param([string] $Owner)
    $OwnerFull = [System.IO.Path]::GetFullPath($Owner).TrimEnd('\','/')
    $RootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    if ($OwnerFull -eq $RootFull) { return "." }
    return [System.IO.Path]::GetRelativePath($RootFull, $OwnerFull).Replace("\", "/")
}

function Show-NestedExternalStatus {
    param([string] $Owner, [string[]] $Lineage)

    $OwnerModel = Read-ProjectModel -Root $Owner
    foreach ($Dependency in $OwnerModel.Dependencies) {
        if ($Dependency.Role -ne "external") { continue }

        $Normalized = Normalize-RepositoryUrl $Dependency.Url
        if ($Lineage -contains $Normalized) {
            Write-Output ("nested {0,-24} CYCLE         owner={1} path={2} ref={3}" -f $Dependency.Name, (Get-OwnerRelativeLabel $Owner), $Dependency.Path, $Dependency.Ref)
            continue
        }

        $Gitlink = Get-GitlinkCommit -Owner $Owner -Path $Dependency.Path
        if (-not $Gitlink) {
            Write-Output ("nested {0,-24} MISSING_GITLINK owner={1} path={2} ref={3}" -f $Dependency.Name, (Get-OwnerRelativeLabel $Owner), $Dependency.Path, $Dependency.Ref)
            continue
        }

        $FullPath = Join-Path $Owner $Dependency.Path
        if (-not (Test-DependencyRepoInitialized -FullPath $FullPath)) {
            Write-Output ("nested {0,-24} UNINITIALIZED owner={1} path={2} gitlink={3} ref={4}" -f $Dependency.Name, (Get-OwnerRelativeLabel $Owner), $Dependency.Path, $Gitlink.Substring(0, 12), $Dependency.Ref)
            continue
        }

        $Current = ((Invoke-Git -WorkingDirectory $FullPath -Args @("rev-parse", "HEAD") -Capture).Output | Select-Object -First 1).Trim()
        $Dirty = (Invoke-Git -WorkingDirectory $FullPath -Args @("status", "--porcelain") -Capture).Output
        $State = if ($Dirty) { "DIRTY" } elseif ($Current -eq $Gitlink) { "OK" } else { "DIFF" }
        Write-Output ("nested {0,-24} {1,-13} owner={2} path={3} current={4} gitlink={5} ref={6}" -f $Dependency.Name, $State, (Get-OwnerRelativeLabel $Owner), $Dependency.Path, $Current.Substring(0, 12), $Gitlink.Substring(0, 12), $Dependency.Ref)

        Show-NestedExternalStatus -Owner $FullPath -Lineage @($Lineage + $Normalized)
    }
}

function Show-RootExternalStatus {
    param([string] $Root, $Model)

    $RootUrlResult = Invoke-Git -WorkingDirectory $Root -Args @("remote", "get-url", "origin") -Capture -AllowFailure
    $RootLineage = @()
    if ($RootUrlResult.Code -eq 0 -and $RootUrlResult.Output) {
        $RootLineage += Normalize-RepositoryUrl (($RootUrlResult.Output | Select-Object -First 1).Trim())
    }

    foreach ($Dependency in $Model.Dependencies) {
        if ($Dependency.Role -ne "external") { continue }
        $FullPath = Join-Path $Root $Dependency.Path
        if (-not (Test-DependencyRepoInitialized -FullPath $FullPath)) { continue }
        $Lineage = @($RootLineage + (Normalize-RepositoryUrl $Dependency.Url))
        Show-NestedExternalStatus -Owner $FullPath -Lineage $Lineage
    }
}

function Show-FullStatus {
    param([string] $Root, $Model)
    Show-Status -Root $Root -Model $Model
    Show-RootExternalStatus -Root $Root -Model $Model
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git was not found in PATH." }

$Root = Resolve-RepoRoot -Requested $RepoRoot
$Model = Read-ProjectModel -Root $Root

switch ($Command) {
    "validate" {
        Write-Host "project.yml valid: $($Model.ProjectName) ($($Model.Dependencies.Count) dependencies, $($Model.Profiles.Count) profiles)"
    }
    "status" {
        Show-FullStatus -Root $Root -Model $Model
    }
    "bootstrap" {
        foreach ($Dependency in $Model.Dependencies) { Sync-Dependency -Root $Root -Dependency $Dependency -Mode "Bootstrapping" }
        Initialize-RootExternalClosure -Root $Root -Model $Model
        Write-Host ""
        Show-FullStatus -Root $Root -Model $Model
        Write-Host ""
        Write-Host "Bootstrap complete. Review parent changes with: git status"
    }
    "update" {
        foreach ($Dependency in $Model.Dependencies) { Sync-Dependency -Root $Root -Dependency $Dependency -Mode "Updating" }
        Initialize-RootExternalClosure -Root $Root -Model $Model
        Write-Host ""
        Show-FullStatus -Root $Root -Model $Model
        Write-Host ""
        Write-Host "Update complete. Review project.yml and gitlink changes before committing."
    }
}

# Native commands used by read-only status may legitimately return non-zero
# through AllowFailure. Reaching this point means the tool operation itself succeeded.
exit 0
