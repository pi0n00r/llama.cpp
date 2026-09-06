# AI-NOTICE:Schema-Version=0.1
# AI-NOTICE:License=MIT
# AI-NOTICE:Project=llama.cpp-pi0n00r
# AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp

[CmdletBinding()]
param(
    [string]$Repository = "https://github.com/pi0n00r/llama.cpp.git",
    [string]$Branch = "master",
    [string]$LockFile = "llama-source.lock"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Repository -notmatch '^[A-Za-z0-9:/._@+\-]+$') {
    throw "Invalid llama.cpp repository URL."
}
if ($Branch -notmatch '^[A-Za-z0-9._/\-]+$') {
    throw "Invalid llama.cpp branch name."
}

$ref = "refs/heads/$Branch"
$remote = @(& git ls-remote --exit-code --refs $Repository $ref 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Could not resolve $Repository at $ref."
}

$matches = @($remote | Where-Object { $_ -match '^([0-9a-fA-F]{40})\s+refs/heads/' })
if ($matches.Count -ne 1) {
    throw "Expected exactly one commit for $Repository at $ref."
}
$revision = ([regex]::Match($matches[0], '^([0-9a-fA-F]{40})\s+')).Groups[1].Value.ToLowerInvariant()

$resolvedLock = [System.IO.Path]::GetFullPath($LockFile)
$lockDirectory = [System.IO.Path]::GetDirectoryName($resolvedLock)
if (-not [System.IO.Directory]::Exists($lockDirectory)) {
    throw "Lock-file directory does not exist: $lockDirectory"
}

$temporaryLock = "$resolvedLock.tmp.$PID"
$content = @(
    "LLAMA_REPO=$Repository"
    "LLAMA_BRANCH=$Branch"
    "LLAMA_VERSION=$revision"
) -join "`n"

try {
    [System.IO.File]::WriteAllText(
        $temporaryLock,
        "$content`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    Move-Item -LiteralPath $temporaryLock -Destination $resolvedLock -Force
} finally {
    Remove-Item -LiteralPath $temporaryLock -Force -ErrorAction SilentlyContinue
}

$env:LLAMA_REPO = $Repository
$env:LLAMA_VERSION = $revision

[pscustomobject]@{
    Repository = $Repository
    Branch = $Branch
    Revision = $revision
    LockFile = $resolvedLock
}
