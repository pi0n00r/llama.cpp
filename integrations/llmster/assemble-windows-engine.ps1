# AI-NOTICE:Schema-Version=0.1
# AI-NOTICE:License=MIT
# AI-NOTICE:Project=llama.cpp-pi0n00r
# AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseEngine,
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$BuildEvidence,
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$Evidence,
    [Parameter(Mandatory)][string]$SourceSha,
    [Parameter(Mandatory)][string]$NewName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false))
}

function Assert-Within {
    param([string]$Root, [string]$Path)
    $prefix = $Root.TrimEnd('\') + '\'
    if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact path escapes its root: $Path"
    }
}

$base = (Resolve-Path -LiteralPath $BaseEngine).Path
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
$buildEvidenceRoot = (Resolve-Path -LiteralPath $BuildEvidence).Path
$outputRoot = [IO.Path]::GetFullPath($Output)
$evidenceRoot = [IO.Path]::GetFullPath($Evidence)
if ($SourceSha -notmatch '^[0-9a-f]{40}$') { throw 'SourceSha must be a full lowercase Git SHA.' }
if ($NewName -notmatch '^llama\.cpp-win-x86_64-amd-rocm-avx2-[a-z0-9-]+$') {
    throw 'NewName must identify a distinct Windows ROCm backend.'
}
if ((Test-Path -LiteralPath $outputRoot) -or (Test-Path -LiteralPath $evidenceRoot)) {
    throw 'Output and evidence paths must both be new.'
}
foreach ($root in @($base, $candidateRoot)) {
    if ($outputRoot.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
        $outputRoot.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Output cannot overlap an input.'
    }
}

$baseManifestPath = Join-Path $base 'backend-manifest.json'
$baseManifest = Get-Content -Raw -LiteralPath $baseManifestPath | ConvertFrom-Json
if ($baseManifest.engine -ne 'llama.cpp' -or $baseManifest.platform -ne 'win' -or
    $baseManifest.gpu.framework -ne 'ROCm' -or
    $baseManifest.engine_protocol_server.executable_relative_path -ne
        'fork-engine/bin/llama-server.exe') {
    throw 'Base is not the expected LM Studio Windows ROCm server-backed engine.'
}
if ($baseManifest.name -eq $NewName) { throw 'NewName must differ from the base engine.' }
foreach ($name in @('llm_engine_rocm.node', 'liblmstudio_bindings_rocm.node',
                    'backend-manifest.json', 'engine-protocol-server-artifacts.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $base $name) -PathType Leaf)) {
        throw "Base engine is incomplete: $name"
    }
}

$buildManifest = Get-Content -Raw -LiteralPath (Join-Path $buildEvidenceRoot 'build-manifest.json') |
    ConvertFrom-Json
if ($buildManifest.source -ne $SourceSha -or $buildManifest.gpuTarget -ne 'gfx1151' -or
    $buildManifest.architecture -ne 'x64') {
    throw 'Candidate evidence does not match the requested source, GPU or architecture.'
}
$expected = @{}
foreach ($file in @($buildManifest.files)) {
    $relative = [string]$file.name
    if ($relative -match '(^/|^[A-Za-z]:|(^|/)\.\.(/|$))' -or $expected.ContainsKey($relative)) {
        throw "Invalid or duplicate candidate path: $relative"
    }
    $path = [IO.Path]::GetFullPath((Join-Path $candidateRoot $relative.Replace('/', '\')))
    Assert-Within $candidateRoot $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Candidate file is missing: $relative"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne [string]$file.sha256) {
        throw "Candidate hash differs from build evidence: $relative"
    }
    $expected[$relative] = $true
}
$actualFiles = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File)
if ($actualFiles.Count -ne $expected.Count) {
    throw 'Candidate contains unmanifested or missing files.'
}
foreach ($file in $actualFiles) {
    $relative = $file.FullName.Substring($candidateRoot.Length + 1).Replace('\', '/')
    if (-not $expected.ContainsKey($relative)) {
        throw "Candidate contains an unmanifested file: $relative"
    }
}
foreach ($relative in @('bin/llama-server.exe', 'bin/ggml-hip.dll', 'bin/ggml-cpu.dll',
                       'bin/ggml-base.dll', 'bin/llama.dll',
                       '.kpack/blas_lib_gfx1151.kpack')) {
    if (-not $expected.ContainsKey($relative)) { throw "Required candidate file absent: $relative" }
}
foreach ($relative in @('bin/rocblas', 'bin/hipblaslt')) {
    $runtimePath = Join-Path $candidateRoot $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) {
        throw "Required ROCm runtime data absent: $relative"
    }
}

# The base is never edited. Do not copy its obsolete fork-engine just to discard it.
New-Item -ItemType Directory -Path $outputRoot | Out-Null
Get-ChildItem -LiteralPath $base -Force |
    Where-Object { $_.Name -ne 'fork-engine' } |
    Copy-Item -Destination $outputRoot -Recurse -Force
$forkRoot = Join-Path $outputRoot 'fork-engine'
Copy-Item -LiteralPath $candidateRoot -Destination $forkRoot -Recurse -Force

$manifestPath = Join-Path $outputRoot 'backend-manifest.json'
$assembledManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$assembledManifest.name = $NewName
Write-JsonFile $manifestPath $assembledManifest

$artifactsPath = Join-Path $outputRoot 'engine-protocol-server-artifacts.json'
$artifacts = Get-Content -Raw -LiteralPath $artifactsPath | ConvertFrom-Json
$artifacts.executable_relative_path = 'fork-engine/bin/llama-server.exe'
$artifacts.files = @(
    Get-ChildItem -LiteralPath $forkRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($outputRoot.Length + 1).Replace('\', '/')
        [ordered]@{
            relative_path = $relative
            executable = ($relative -eq 'fork-engine/bin/llama-server.exe')
        }
    }
)
Write-JsonFile $artifactsPath $artifacts

$bindings = @('llm_engine_rocm.node', 'liblmstudio_bindings_rocm.node')
$bindingHashes = @()
foreach ($name in $bindings) {
    $original = (Get-FileHash -LiteralPath (Join-Path $base $name) -Algorithm SHA256).Hash
    $copied = (Get-FileHash -LiteralPath (Join-Path $outputRoot $name) -Algorithm SHA256).Hash
    if ($original -ne $copied) { throw "LM Studio binding changed: $name" }
    $bindingHashes += [ordered]@{ name = $name; sha256 = $copied.ToLowerInvariant() }
}
New-Item -ItemType Directory -Path $evidenceRoot | Out-Null
Write-JsonFile (Join-Path $evidenceRoot 'engine-assembly.json') ([ordered]@{
    source = $SourceSha
    baseEngine = $baseManifest.name
    assembledEngine = $NewName
    engineVersion = $baseManifest.version
    gpuTarget = 'gfx1151'
    artifactCount = @($artifacts.files).Count
    serverSha256 = (Get-FileHash -LiteralPath (Join-Path $forkRoot 'bin\llama-server.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    bindings = $bindingHashes
    scope = 'Side-by-side candidate; not selected, loaded or production qualified.'
})
Write-Output "Assembled $NewName from $SourceSha; runtime selection was not changed."
