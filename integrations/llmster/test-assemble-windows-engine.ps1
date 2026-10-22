# AI-NOTICE:Schema-Version=0.1
# AI-NOTICE:License=MIT
# AI-NOTICE:Project=llama.cpp-pi0n00r
# AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Join-Path $env:TEMP ('llmster-assembly-' + [Guid]::NewGuid().ToString('N'))
$base = Join-Path $root 'base'
$candidate = Join-Path $root 'candidate'
$buildEvidence = Join-Path $root 'build-evidence'
$output = Join-Path $root 'assembled'
$evidence = Join-Path $root 'assembly-evidence'
$source = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$name = 'llama.cpp-win-x86_64-amd-rocm-avx2-oc-test'
try {
    foreach ($path in @($base, $candidate, $buildEvidence)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    $baseManifest = [ordered]@{
        name = 'llama.cpp-win-x86_64-amd-rocm-avx2-base'
        version = '2.33.0'
        engine = 'llama.cpp'
        platform = 'win'
        gpu = @{ framework = 'ROCm' }
        engine_protocol_server = @{ executable_relative_path = 'fork-engine/bin/llama-server.exe' }
    }
    $baseManifest | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $base 'backend-manifest.json')
    [ordered]@{
        schema_version = 1
        runtime_kind = 'llama-server'
        executable_relative_path = 'fork-engine/bin/llama-server.exe'
        files = @()
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $base 'engine-protocol-server-artifacts.json')
    foreach ($file in @('llm_engine_rocm.node', 'liblmstudio_bindings_rocm.node')) {
        Set-Content -LiteralPath (Join-Path $base $file) -Value 'retained binding'
    }
    $oldFork = Join-Path $base 'fork-engine\bin'
    New-Item -ItemType Directory -Path $oldFork -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $oldFork 'llama-server.exe') -Value 'old server'

    $paths = @(
        'bin/llama-server.exe', 'bin/ggml-hip.dll', 'bin/ggml-cpu.dll',
        'bin/ggml-base.dll', 'bin/llama.dll',
        '.kpack/blas_lib_gfx1151.kpack',
        'bin/rocblas/marker', 'bin/hipblaslt/marker'
    )
    $files = @(
        foreach ($relative in $paths) {
            $path = Join-Path $candidate $relative.Replace('/', '\')
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            Set-Content -LiteralPath $path -Value $relative
            [ordered]@{
                name = $relative
                sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    )
    [ordered]@{
        source = $source
        gpuTarget = 'gfx1151'
        architecture = 'x64'
        files = $files
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $buildEvidence 'build-manifest.json')

    & (Join-Path $PSScriptRoot 'assemble-windows-engine.ps1') -BaseEngine $base -Candidate $candidate -BuildEvidence $buildEvidence -Output $output -Evidence $evidence -SourceSha $source -NewName $name
    $assembled = Get-Content -Raw -LiteralPath (Join-Path $output 'backend-manifest.json') |
        ConvertFrom-Json
    $artifacts = Get-Content -Raw -LiteralPath (Join-Path $output 'engine-protocol-server-artifacts.json') |
        ConvertFrom-Json
    if ($assembled.name -ne $name -or @($artifacts.files).Count -ne $paths.Count) {
        throw 'Assembled engine manifest is incomplete.'
    }
    if ((Get-Content -Raw -LiteralPath (Join-Path $output 'fork-engine\bin\llama-server.exe')) -notmatch
        'bin/llama-server.exe') {
        throw 'Candidate server was not installed in the assembled engine.'
    }
    if ((Get-Content -Raw -LiteralPath (Join-Path $base 'fork-engine\bin\llama-server.exe')) -notmatch
        'old server') {
        throw 'Base engine was modified.'
    }
    $bad = Get-Content -Raw -LiteralPath (Join-Path $buildEvidence 'build-manifest.json') |
        ConvertFrom-Json
    $bad.files[0].sha256 = '0' * 64
    $bad | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $buildEvidence 'build-manifest.json')
    $held = $false
    try {
        & (Join-Path $PSScriptRoot 'assemble-windows-engine.ps1') -BaseEngine $base -Candidate $candidate -BuildEvidence $buildEvidence -Output (Join-Path $root 'bad-output') -Evidence (Join-Path $root 'bad-evidence') -SourceSha $source -NewName 'llama.cpp-win-x86_64-amd-rocm-avx2-oc-bad'
    } catch {
        $held = $true
    }
    if (-not $held -or (Test-Path -LiteralPath (Join-Path $root 'bad-output'))) {
        throw 'A hash mismatch did not hold before copying.'
    }
    Write-Output 'Engine assembly positive and hash-mismatch negative checks passed.'
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
