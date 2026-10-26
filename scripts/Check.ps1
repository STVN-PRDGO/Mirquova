param([switch]$SkipNativeBridge)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $projectRoot '.toolchains')) { . "$PSScriptRoot/Use-Toolchains.ps1" }
function Invoke-Checked([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Check failed (exit $LASTEXITCODE): $Command" }
}
Push-Location $projectRoot
try {
    Invoke-Checked { cargo fmt --all -- --check }
    Invoke-Checked { cargo clippy --workspace --all-targets --locked -- -D warnings }
    Invoke-Checked { cargo test --workspace --locked }
    Invoke-Checked { cargo build -p mirquova-core --lib --locked }
    $nativeLibrary = Join-Path $projectRoot 'target/debug/mirquova_core.dll'
    Push-Location (Join-Path $projectRoot 'apps/mirquova_flutter')
    try {
        Invoke-Checked { flutter pub get --enforce-lockfile }
        Invoke-Checked { dart format --output=none --set-exit-if-changed lib test integration_test }
        Invoke-Checked { flutter analyze }
        if ($SkipNativeBridge) { Invoke-Checked { flutter test --reporter expanded } }
        else { Invoke-Checked { flutter test --reporter expanded "--dart-define=MIRQUOVA_CORE_LIBRARY=$nativeLibrary" } }
    } finally { Pop-Location }
} finally { Pop-Location }
