param([ValidateSet('debug')][string]$Mode = 'debug')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $projectRoot '.toolchains')) { . "$PSScriptRoot/Use-Toolchains.ps1" }
if (-not $env:ANDROID_NDK_HOME -or -not (Test-Path -LiteralPath $env:ANDROID_NDK_HOME)) {
    throw 'Set ANDROID_NDK_HOME to the installed NDK before building.'
}
Push-Location $projectRoot
try {
    cargo ndk -t arm64-v8a --platform 24 -o apps/mirquova_flutter/android/app/src/main/jniLibs build -p mirquova-core --lib --release --locked
    if ($LASTEXITCODE -ne 0) { throw 'Android native core build failed.' }
    Push-Location (Join-Path $projectRoot 'apps/mirquova_flutter')
    try {
        flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
        flutter build apk --debug --target-platform android-arm64
        if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
    } finally { Pop-Location }
} finally { Pop-Location }
