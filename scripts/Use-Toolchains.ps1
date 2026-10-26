# Dot-source this file: . .\scripts\Use-Toolchains.ps1
$projectRoot = Split-Path -Parent $PSScriptRoot
$localTools = Join-Path $projectRoot '.toolchains'
$env:RUSTUP_HOME = Join-Path $localTools 'rustup'
$env:CARGO_HOME = Join-Path $localTools 'cargo'
$env:PUB_CACHE = Join-Path $localTools 'pub-cache'
$env:FLUTTER_ROOT = Join-Path $localTools 'flutter'
$env:Path = (Join-Path $localTools 'flutter/bin') + ';' + (Join-Path $localTools 'cargo/bin') + ';' + $env:Path
$gcc = Join-Path $localTools 'gcc/mingw64/bin'
if (Test-Path -LiteralPath (Join-Path $gcc 'gcc.exe')) {
    $env:Path = $gcc + ';' + $env:Path
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = Join-Path $gcc 'gcc.exe'
}

$jdk = Get-ChildItem -LiteralPath $localTools -Directory -Filter 'jdk-17*' | Sort-Object Name -Descending | Select-Object -First 1
if ($jdk) {
    $env:JAVA_HOME = $jdk.FullName
    $env:Path = (Join-Path $jdk.FullName 'bin') + ';' + $env:Path
}
$androidSdk = Join-Path $localTools 'android-sdk'
if (Test-Path -LiteralPath (Join-Path $androidSdk 'cmdline-tools/latest/bin/sdkmanager.bat')) {
    $env:ANDROID_HOME = $androidSdk
    $env:ANDROID_SDK_ROOT = $androidSdk
    $env:ANDROID_NDK_HOME = Join-Path $androidSdk 'ndk/28.2.13676358'
    $env:GRADLE_USER_HOME = Join-Path $localTools 'gradle'
    $env:Path = (Join-Path $androidSdk 'platform-tools') + ';' + (Join-Path $androidSdk 'cmdline-tools/latest/bin') + ';' + $env:Path
}
