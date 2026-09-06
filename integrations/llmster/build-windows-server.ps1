# AI-NOTICE:Schema-Version=0.1
# AI-NOTICE:License=MIT
# AI-NOTICE:Project=llama.cpp-pi0n00r
# AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$Evidence,
    [ValidateRange(1, 4)][int]$Jobs = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Source = (Resolve-Path -LiteralPath $Source).Path
$Output = [IO.Path]::GetFullPath($Output)
$Evidence = [IO.Path]::GetFullPath($Evidence)
$build = Join-Path $Source 'build-windows-rocm'
if (Test-Path -LiteralPath $Output) { throw 'Candidate output already exists.' }
New-Item -ItemType Directory -Path $Output, $Evidence -Force | Out-Null

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with $LASTEXITCODE" }
}

$venv = 'C:\TheRock\build\.venv\Scripts'
$env:PATH = "$venv;$env:PATH"
$rocm = (& rocm-sdk path --root).Trim()
if ($LASTEXITCODE -ne 0 -or -not $rocm) { throw 'ROCm SDK root unavailable.' }
$rocmBin = (& rocm-sdk path --bin).Trim()
if ($LASTEXITCODE -ne 0 -or -not $rocmBin) { throw 'ROCm SDK bin unavailable.' }
$env:HIP_PATH = $rocm
$env:HIP_PLATFORM = 'amd'
$env:HIP_DEVICE_LIB_PATH = Join-Path $rocm 'lib\llvm\amdgcn\bitcode'
$env:LLVM_PATH = Join-Path $rocm 'lib\llvm'
$env:PATH = "$rocmBin;$env:PATH"
$compiler = Join-Path $rocm 'lib\llvm\bin\clang.exe'
$cppCompiler = Join-Path $rocm 'lib\llvm\bin\clang++.exe'
$sdkInventory = Get-ChildItem -LiteralPath $rocm -Recurse -File |
    Select-Object @{n='path';e={$_.FullName.Substring($rocm.Length + 1)}}, Length
$sdkInventory | ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath (Join-Path $Evidence 'rocm-sdk-inventory.json')

# Import MSVC's developer environment into this process, never the machine.
$vswhere = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'MSVC x64 build tools unavailable.' }
$devShell = Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
Import-Module $devShell
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'

$revision = (& git -C $Source rev-parse HEAD).Trim()
if ($revision -ne $env:LLAMA_SOURCE_SHA) { throw 'Source checkout differs from reviewed SHA.' }
& $compiler --version | Set-Content -LiteralPath (Join-Path $Evidence 'compiler.txt')
if ($LASTEXITCODE -ne 0) { throw 'ROCm compiler unavailable.' }
& python -m pip freeze | Set-Content -LiteralPath (Join-Path $Evidence 'python-packages.txt')
if ($LASTEXITCODE -ne 0) { throw 'Could not record SDK package versions.' }

$configure = @(
    '-S', $Source, '-B', $build, '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    "-DCMAKE_PREFIX_PATH=$rocm",
    "-DCMAKE_C_COMPILER=$compiler",
    "-DCMAKE_CXX_COMPILER=$cppCompiler",
    "-DHIP_PATH=$rocm",
    '-DBUILD_SHARED_LIBS=ON',
    '-DGGML_BACKEND_DL=ON',
    '-DGGML_NATIVE=OFF',
    '-DGGML_CPU=ON',
    '-DGGML_OPENMP=OFF',
    '-DGGML_HIP=ON',
    '-DGPU_TARGETS=gfx1151',
    '-DGGML_CUDA=OFF',
    '-DGGML_VULKAN=OFF',
    '-DLLAMA_OPENSSL=OFF',
    '-DLLAMA_BUILD_SERVER=ON',
    '-DLLAMA_BUILD_UI=OFF',
    '-DLLAMA_BUILD_TESTS=ON'
)
Invoke-Checked cmake $configure
Copy-Item -LiteralPath (Join-Path $build 'CMakeCache.txt') -Destination $Evidence
Invoke-Checked cmake @('--build', $build, '--parallel', "$Jobs", '--target',
    'llama-server', 'ggml-hip', 'test-chat-template', 'test-chat-peg-parser',
    'test-chat-auto-parser')

$bin = Join-Path $build 'bin'
if (-not (Test-Path -LiteralPath (Join-Path $bin 'ggml-hip.dll'))) {
    throw 'HIP backend was not produced.'
}
Invoke-Checked ctest @('--test-dir', $build, '--output-on-failure', '--no-tests=error',
    '-R', '^(test-chat-template|test-chat-peg-parser|test-chat-auto-parser)$')

# Only the standalone subprocess is packaged; no LM Studio bindings are replaced.
$redistVersions = Get-ChildItem -LiteralPath (Join-Path $vs 'VC\Redist\MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending
if (-not $redistVersions) { throw 'MSVC redistributable not found.' }
$redist = Join-Path $redistVersions[0].FullName 'x64'
Invoke-Checked python @((Join-Path $PSScriptRoot 'package-windows-server.py'),
    '--compiled', $bin, '--sdk', $rocm, '--redist', $redist,
    '--source', $Source, '--output', $Output, '--evidence', $Evidence)

$server = Join-Path $Output 'bin\llama-server.exe'
# Prove launch without the build SDK or MSVC directories in PATH.
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
& $server --version 2>&1 | Set-Content -LiteralPath (Join-Path $Evidence 'server-version.txt')
if ($LASTEXITCODE -ne 0) { throw 'Packaged server --version failed.' }
& $server --help 2>&1 | Set-Content -LiteralPath (Join-Path $Evidence 'server-help.txt')
if ($LASTEXITCODE -ne 0) { throw 'Packaged server --help failed.' }

$manifest = Get-ChildItem -LiteralPath $Output -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        name = $_.FullName.Substring($Output.Length + 1).Replace('\', '/')
        bytes = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
[ordered]@{
    source = $revision
    rocm = $env:ROCM_VERSION
    architecture = 'x64'
    gpuTarget = 'gfx1151'
    compiler = $compiler
    configure = $configure
    files = @($manifest)
    scope = 'Candidate only; no GPU, LM Studio integration or production certification.'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Evidence 'build-manifest.json')
