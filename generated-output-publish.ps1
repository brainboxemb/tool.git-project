Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) { throw "ERROR: $Message" }
function Write-ActionOutput([string]$Key, [string]$Value) {
  if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Key=$Value" -Encoding utf8 }
}
function Invoke-GitChecked([string[]]$GitArgs) {
  $output = & git @GitArgs 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $($output -join [Environment]::NewLine)" }
  return @($output)
}

$sourceDir = $env:PUBLISH_SOURCE_DIR
$branchSuffix = $env:PUBLISH_BRANCH_SUFFIX
$sourceRevisionInput = $env:PUBLISH_SOURCE_REVISION
$token = $env:PUBLISH_TOKEN
$prNumber = $env:PUBLISH_PR_NUMBER
$prHeadRef = $env:PUBLISH_PR_HEAD_REF
$prHeadSha = $env:PUBLISH_PR_HEAD_SHA
$prHeadRepository = $env:PUBLISH_PR_HEAD_REPOSITORY
$repository = $env:GITHUB_REPOSITORY
$serverUrl = if ($env:GITHUB_SERVER_URL) { $env:GITHUB_SERVER_URL.TrimEnd('/') } else { 'https://github.com' }
$remoteUrl = $env:PUBLISH_REMOTE_URL

if (-not $sourceDir) { Fail 'PUBLISH_SOURCE_DIR is required' }
if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { Fail "prepared generated-output directory does not exist: $sourceDir" }
if (Test-Path -LiteralPath (Join-Path $sourceDir '.git')) { Fail 'prepared generated-output directory must not contain .git metadata' }
if (-not (Get-ChildItem -LiteralPath $sourceDir -Force | Select-Object -First 1)) { Fail "prepared generated-output directory is empty: $sourceDir" }
if ($branchSuffix -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Fail "invalid generated-output branch suffix: $branchSuffix" }
if (-not $repository) { Fail 'GITHUB_REPOSITORY is required' }
if (-not $token) { Fail 'publication token is required' }
if (-not $remoteUrl) { $remoteUrl = "$serverUrl/$repository.git" }

$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$credentialFile = Join-Path $tempRoot ("generated-output-credentials-" + [Guid]::NewGuid().ToString('N'))
$publishRepo = Join-Path $tempRoot ("generated-output-publish-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $publishRepo | Out-Null
$serverHost = ([Uri]$serverUrl).Host
[IO.File]::WriteAllText($credentialFile, "https://x-access-token:${token}@${serverHost}`n")

function Invoke-GitCredentialed([string[]]$GitArgs) {
  $allArgs = @('-c', "credential.helper=store --file=$credentialFile") + $GitArgs
  return (Invoke-GitChecked -GitArgs $allArgs)
}
function Get-RemoteRef([string]$Ref) {
  $lines = Invoke-GitCredentialed -GitArgs @('ls-remote', $remoteUrl, $Ref)
  if (-not $lines) { return '' }
  return (($lines[0] -split '\s+')[0]).Trim()
}
function Resolve-TagCommit([string]$Tag) {
  $lines = Invoke-GitCredentialed -GitArgs @('ls-remote', $remoteUrl, "refs/tags/$Tag", "refs/tags/$Tag^{}")
  $peeled = ''
  $direct = ''
  foreach ($line in $lines) {
    $parts = $line -split '\s+'
    if ($parts.Count -lt 2) { continue }
    if ($parts[1] -match '\^\{\}$') { if (-not $peeled) { $peeled = $parts[0] } }
    elseif (-not $direct) { $direct = $parts[0] }
  }
  if ($peeled) { return $peeled }
  return $direct
}
function Get-CurrentSourceRevision {
  if ($env:GITHUB_EVENT_NAME -eq 'pull_request') {
    if ($prHeadRepository -ne $repository) { Fail 'generated-output publication is only allowed for same-repository pull requests' }
    if ($prNumber -notmatch '^[1-9][0-9]*$') { Fail 'missing or invalid pull-request number' }
    if (-not $prHeadRef) { Fail 'missing pull-request head ref' }
    & git check-ref-format "refs/heads/$prHeadRef" *> $null
    if ($LASTEXITCODE -ne 0) { Fail "invalid pull-request head ref: $prHeadRef" }
    return (Get-RemoteRef "refs/heads/$prHeadRef")
  }
  if ($env:GITHUB_REF -eq 'refs/heads/main') { return (Get-RemoteRef 'refs/heads/main') }
  if ($env:GITHUB_REF -like 'refs/tags/v*') {
    if ($env:GITHUB_REF_NAME -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { Fail "release tag must match vX.Y.Z: $($env:GITHUB_REF_NAME)" }
    return (Resolve-TagCommit $env:GITHUB_REF_NAME)
  }
  Fail "generated-output publication is only allowed for same-repository pull requests, main, or vX.Y.Z release tags; got $($env:GITHUB_REF)"
}

try {
  if ($env:GITHUB_EVENT_NAME -eq 'pull_request') {
    if ($prHeadRepository -ne $repository) { Fail 'generated-output publication is only allowed for same-repository pull requests' }
    if ($prNumber -notmatch '^[1-9][0-9]*$') { Fail 'missing or invalid pull-request number' }
    if (-not $prHeadRef) { Fail 'missing pull-request head ref' }
    $targetBranch = "dev/pr-$prNumber/$branchSuffix"
    $publicationContext = "pull request #$prNumber"
  } elseif ($env:GITHUB_REF -eq 'refs/heads/main') {
    $targetBranch = "prod/$branchSuffix"
    $publicationContext = 'main'
  } elseif ($env:GITHUB_REF -like 'refs/tags/v*') {
    if ($env:GITHUB_REF_NAME -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { Fail "release tag must match vX.Y.Z: $($env:GITHUB_REF_NAME)" }
    $targetBranch = "rel/$($env:GITHUB_REF_NAME)/$branchSuffix"
    $publicationContext = "release tag $($env:GITHUB_REF_NAME)"
  } else {
    Fail "generated-output publication is only allowed for same-repository pull requests, main, or vX.Y.Z release tags; got $($env:GITHUB_REF)"
  }

  $currentRevision = (Get-CurrentSourceRevision).Trim()
  if ($currentRevision -notmatch '^[0-9a-f]{40}$') { Fail "could not resolve current source revision for $publicationContext" }

  $sourceRevision = $sourceRevisionInput
  if (-not $sourceRevision) {
    if ($env:GITHUB_EVENT_NAME -eq 'pull_request') { $sourceRevision = $prHeadSha }
    elseif ($env:GITHUB_REF -like 'refs/tags/v*') { $sourceRevision = $currentRevision }
    else { $sourceRevision = $env:GITHUB_SHA }
  }
  if ($sourceRevision -notmatch '^[0-9a-f]{40}$') { Fail 'source revision must be an exact 40-character commit SHA' }

  Write-ActionOutput 'target_branch' $targetBranch
  Write-ActionOutput 'source_revision' $sourceRevision

  if ($sourceRevision -ne $currentRevision) {
    Write-Host "Skipping stale generated-output publication for ${publicationContext}: run source $sourceRevision, current source $currentRevision."
    Write-ActionOutput 'published' 'false'
    Write-ActionOutput 'reason' 'stale-before-staging'
    return
  }

  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'init', '-q') | Out-Null
  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'config', 'user.name', 'github-actions[bot]') | Out-Null
  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com') | Out-Null
  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'config', 'credential.helper', "store --file=$credentialFile") | Out-Null
  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'remote', 'add', 'origin', $remoteUrl) | Out-Null
  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'switch', '--orphan', 'generated-output-publication') | Out-Null
  Get-ChildItem -LiteralPath $sourceDir -Force | Copy-Item -Destination $publishRepo -Recurse -Force
  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'add', '-A') | Out-Null
  & git -C $publishRepo diff --cached --quiet
  $diffCode = $LASTEXITCODE
  if ($diffCode -eq 0) { Fail 'prepared generated-output tree produced no publishable files' }
  if ($diffCode -ne 1) { Fail "git diff --cached failed with exit code $diffCode" }
  Invoke-GitChecked -GitArgs @('-C', $publishRepo, 'commit', '-q', '-m', "Publish generated output to $targetBranch") | Out-Null

  if ($env:PUBLISH_BEFORE_PUSH_DELAY_SECONDS -and $env:PUBLISH_BEFORE_PUSH_DELAY_SECONDS -ne '0') {
    Start-Sleep -Seconds ([double]$env:PUBLISH_BEFORE_PUSH_DELAY_SECONDS)
  }
  $latestRevision = (Get-CurrentSourceRevision).Trim()
  if ($latestRevision -notmatch '^[0-9a-f]{40}$') { Fail "could not resolve latest source revision for $publicationContext" }
  if ($sourceRevision -ne $latestRevision) {
    Write-Host "Skipping stale generated-output publication for ${publicationContext}: source advanced to $latestRevision before push."
    Write-ActionOutput 'published' 'false'
    Write-ActionOutput 'reason' 'stale-before-push'
    return
  }

  Invoke-GitCredentialed -GitArgs @('-C', $publishRepo, 'push', '--force', 'origin', "HEAD:refs/heads/$targetBranch") | Out-Null
  Write-Host "Published generated output from $sourceRevision to $targetBranch"
  Write-ActionOutput 'published' 'true'
  Write-ActionOutput 'reason' 'published'
} finally {
  Remove-Item -LiteralPath $credentialFile -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $publishRepo -Recurse -Force -ErrorAction SilentlyContinue
}
