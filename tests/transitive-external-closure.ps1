param([Parameter(Mandatory=$true)][string] $RepoRoot)

$ErrorActionPreference = "Stop"
$MechintPath = "deps/lib.scad.mechint"
$RootUtilPath = "deps/lib.scad.util"
$NestedUtilPath = "$MechintPath/ext/lib.scad.util"
$MechintRef = "bdd39925f2ad391b32fad7ba56770053d4d5e2bc"
$RootUtilRef = "da1892a201c3bfc78a65e10df84d4a8d142ae8f6"
$NestedUtilRef = "5c88cd9b6b118d376825927ed67e26aff6eaee2d"

Push-Location $RepoRoot
try {
    Remove-Item transitive-dirty-update.log -ErrorAction SilentlyContinue

    Add-Content -Path project.yml -Value @"

  - name: lib.scad.mechint
    role: external
    type: git-submodule
    url: https://github.com/brainboxemb/lib.scad.mechint.git
    path: deps/lib.scad.mechint
    ref: v0.1.6

  - name: lib.scad.util
    role: external
    type: git-submodule
    url: https://github.com/brainboxemb/lib.scad.util.git
    path: deps/lib.scad.util
    ref: v0.2.0
"@

    git submodule add https://github.com/brainboxemb/lib.scad.mechint.git $MechintPath
    if ($LASTEXITCODE -ne 0) { throw "Unable to add mechint fixture submodule." }
    git -C $MechintPath checkout --detach $MechintRef
    if ($LASTEXITCODE -ne 0) { throw "Unable to pin mechint fixture." }

    git submodule add https://github.com/brainboxemb/lib.scad.util.git $RootUtilPath
    if ($LASTEXITCODE -ne 0) { throw "Unable to add root util fixture submodule." }
    git -C $RootUtilPath checkout --detach $RootUtilRef
    if ($LASTEXITCODE -ne 0) { throw "Unable to pin root util fixture." }

    git add project.yml .gitmodules $MechintPath $RootUtilPath
    git commit -m "add transitive external fixture"
    if ($LASTEXITCODE -ne 0) { throw "Unable to commit transitive fixture." }

    git submodule deinit -f -- $MechintPath $RootUtilPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to deinitialize fixture dependencies." }
    Remove-Item -Recurse -Force $MechintPath, $RootUtilPath -ErrorAction SilentlyContinue

    .\bootstrap.ps1

    if ((git -C $MechintPath rev-parse HEAD).Trim() -ne $MechintRef) { throw "Wrong mechint revision." }
    if ((git -C $RootUtilPath rev-parse HEAD).Trim() -ne $RootUtilRef) { throw "Wrong root util revision." }
    if ((git -C $NestedUtilPath rev-parse HEAD).Trim() -ne $NestedUtilRef) { throw "Wrong nested util revision." }

    foreach ($Path in @("tools/tool.git-project", "tools/tool.scad-project")) {
        $MechintTool = (git -C $MechintPath submodule status -- $Path) -join [Environment]::NewLine
        if ($MechintTool -notmatch "^-") { throw "Nested mechint tooling was initialized: $Path" }

        $UtilTool = (git -C $NestedUtilPath submodule status -- $Path) -join [Environment]::NewLine
        if ($UtilTool -notmatch "^-") { throw "Nested util tooling was initialized: $Path" }
    }

    $Status = (.\update.ps1 status 2>&1) -join [Environment]::NewLine
    Write-Host $Status
    if ($Status -notmatch "nested\s+lib\.scad\.util.*OK.*owner=deps/lib\.scad\.mechint.*path=ext/lib\.scad\.util.*ref=v0\.1\.0") {
        throw "Nested clean status missing."
    }

    Add-Content -Path "$NestedUtilPath/README.md" -Value "owner-test dirty marker"
    $DirtyStatus = (.\update.ps1 status 2>&1) -join [Environment]::NewLine
    if ($DirtyStatus -notmatch "nested\s+lib\.scad\.util.*DIRTY.*owner=deps/lib\.scad\.mechint") {
        throw "Nested dirty status missing."
    }

    $Blocked = $false
    try {
        .\update.ps1 *> transitive-dirty-update.log
    } catch {
        $Blocked = $true
    }
    if (-not $Blocked) { throw "Update unexpectedly succeeded with dirty nested dependency." }

    git -C $NestedUtilPath checkout -- README.md
    if ($LASTEXITCODE -ne 0) { throw "Unable to restore nested util README." }
    Remove-Item transitive-dirty-update.log -ErrorAction SilentlyContinue

    if ((git -C $RootUtilPath rev-parse HEAD).Trim() -ne $RootUtilRef) { throw "Root util changed during dirty protection." }
    if ((git -C $NestedUtilPath rev-parse HEAD).Trim() -ne $NestedUtilRef) { throw "Nested util changed during dirty protection." }

    $ProjectPath = (Resolve-Path project.yml).Path
    $OriginalProject = [System.IO.File]::ReadAllText($ProjectPath)
    $ProjectLines = Get-Content project.yml
    $Changed = $false

    for ($Index = 0; $Index -lt $ProjectLines.Count; $Index++) {
        if (-not $Changed -and $ProjectLines[$Index].Trim() -eq "ref: v0.2.0") {
            $ProjectLines[$Index] = "    ref: v0.1.0"
            $Changed = $true
        }
    }
    if (-not $Changed) { throw "Unable to locate root util v0.2.0 ref in project.yml." }

    [System.IO.File]::WriteAllLines(
        $ProjectPath,
        $ProjectLines,
        [System.Text.UTF8Encoding]::new($false)
    )

    .\update.ps1

    if ((git -C $RootUtilPath rev-parse HEAD).Trim() -ne $NestedUtilRef) { throw "Root util did not move independently." }
    if ((git -C $NestedUtilPath rev-parse HEAD).Trim() -ne $NestedUtilRef) { throw "Nested util changed unexpectedly." }

    [System.IO.File]::WriteAllText(
        $ProjectPath,
        $OriginalProject,
        [System.Text.UTF8Encoding]::new($false)
    )

    .\update.ps1

    if ((git -C $RootUtilPath rev-parse HEAD).Trim() -ne $RootUtilRef) { throw "Root util did not restore." }
    if ((git -C $NestedUtilPath rev-parse HEAD).Trim() -ne $NestedUtilRef) { throw "Nested util moved during restore." }

    git -C $MechintPath submodule deinit -f -- ext/lib.scad.util | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to deinitialize nested util." }

    $Uninitialized = (.\update.ps1 status 2>&1) -join [Environment]::NewLine
    if ($Uninitialized -notmatch "nested\s+lib\.scad\.util.*UNINITIALIZED.*owner=deps/lib\.scad\.mechint") {
        throw "Nested uninitialized status missing."
    }

    .\update.ps1
    if ((git -C $NestedUtilPath rev-parse HEAD).Trim() -ne $NestedUtilRef) { throw "Nested util was not restored." }

    New-Item -ItemType Directory -Force -Path deps/local-sentinel | Out-Null
    Set-Content deps/local-sentinel/keep.txt "keep"

    .\update.ps1
    if (-not (Test-Path deps/local-sentinel/keep.txt)) { throw "Unrelated local path was deleted." }
    Remove-Item -Recurse -Force deps/local-sentinel

    $FinalStatus = (.\update.ps1 status 2>&1) -join [Environment]::NewLine
    Write-Host $FinalStatus
    if ($FinalStatus -match "nested .* (DIRTY|DIFF|UNINITIALIZED|MISSING_GITLINK|CYCLE)") {
        throw "Nested closure did not return clean."
    }

    $Dirty = (git status --porcelain) -join [Environment]::NewLine
    if ($Dirty) {
        throw ("Fixture did not return clean:" + [Environment]::NewLine + $Dirty)
    }
} finally {
    Pop-Location
}
