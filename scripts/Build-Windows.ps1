param([ValidateSet('debug','release')][string]$Mode = 'debug')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $projectRoot '.toolchains')) { . "$PSScriptRoot/Use-Toolchains.ps1" }
Push-Location $projectRoot
try {
    if ($Mode -eq 'release') { cargo build -p mirquova-core --lib --release --locked }
    else { cargo build -p mirquova-core --lib --locked }
    if ($LASTEXITCODE -ne 0) { throw 'Native core build failed.' }
    $env:MIRQUOVA_CORE_BUNDLE = (Join-Path $projectRoot "target/$Mode/mirquova_core.dll") -replace '\\', '/'
    Push-Location (Join-Path $projectRoot 'apps/mirquova_flutter')
    try {
        flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
        $atlCompat = Join-Path $projectRoot 'apps/mirquova_flutter/windows/atl_compat'
        $env:CL = "/I`"$atlCompat`" $env:CL"
        flutter build windows "--$Mode"
        if ($LASTEXITCODE -ne 0) { throw 'Windows app build failed. Check Visual Studio C++ tooling.' }
    } finally { Pop-Location }
} finally { Pop-Location }
