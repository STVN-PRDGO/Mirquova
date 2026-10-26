$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $projectRoot '.toolchains')) { . "$PSScriptRoot/Use-Toolchains.ps1" }
Push-Location $projectRoot
try {
    cargo build -p mirquova-core --lib --locked
    if ($LASTEXITCODE -ne 0) { throw 'Native core build failed.' }
    $env:MIRQUOVA_CORE_BUNDLE = Join-Path $projectRoot 'target/debug/mirquova_core.dll'
    $preview = Join-Path $projectRoot 'local-evidence/windows-native.png'
    Push-Location (Join-Path $projectRoot 'apps/mirquova_flutter')
    try {
        flutter test integration_test/native_discovery_test.dart -d windows --reporter expanded "--dart-define=MIRQUOVA_PREVIEW_PATH=$preview"
        if ($LASTEXITCODE -ne 0) { throw 'Windows native integration test failed.' }
    } finally { Pop-Location }
} finally { Pop-Location }
