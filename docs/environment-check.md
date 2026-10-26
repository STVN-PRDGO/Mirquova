# Environment inventory

Inspected 2026-10-26, Windows PowerShell, from D:\uplb-certificate. Read-only probes preceded creation of D:\Mirquova.

| Command/probe | Observed result |
| --- | --- |
| node --version | v24.14.1 |
| npm.cmd --version | 11.11.0 |
| git --version | git version 2.55.0.windows.5 |
| Get-Command flutter,dart,rustc,cargo,adb,java,cmake,cl | No matching commands on PATH |
| Get-Command rtk,rea | No matching commands on PATH |
| rtk --version / rtk read ... | CommandNotFoundException |
| /Users/ra/.codex/RTK.md | File not found |
| %USERPROFILE%/.codex/RTK.md | Test-Path returned False |
| ANDROID_HOME, ANDROID_SDK_ROOT, JAVA_HOME, FLUTTER_ROOT | No values returned by Get-ChildItem Env: probes |
| REA-named connected tools | None advertised in this session |

Additional exact-path probes found no files at C:/src/flutter/bin/flutter.bat, C:/flutter/bin/flutter.bat, %USERPROFILE%/development/flutter/bin/flutter.bat, %USERPROFILE%/.cargo/bin/cargo.exe, %USERPROFILE%/AppData/Local/Android/Sdk/platform-tools/adb.exe, or C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe.

These observations establish tools unavailable through the checked paths; they do not prove no SDK exists anywhere on disk. No recursive system scan was performed. No SDK license was accepted, device connected, signing key generated or application data modified.

## Recovery sequence

1. Locate any existing toolchain before installing duplicates. Use official Flutter Windows/Android setup instructions for the chosen current stable version; record exact versions.
2. Configure Flutter/Dart, Windows C++ desktop build components, Android SDK/NDK and compatible JDK. Run flutter doctor -v and resolve platform-specific failures.
3. Configure a Rust toolchain and the Android targets selected for actual devices. Confirm cargo/rustc versions and host linker availability.
4. Generate the real app and Rust workspace only after those probes pass. Check analyzer, unit tests, Windows build and Android debug build separately.
5. Run device tests on Windows and a physical Android device; keep emulator and hardware evidence distinct.
6. Review REA host requirements only when there is a concrete analysis target; see rea-findings.md.

No Flutter/Rust application checks were runnable in this preparation step. Workspace documentation checks are recorded separately in acceptance.md.

## Implementation update

The inventory above records initial preparation, before SDK installation. During iteration 01, project-local Flutter 3.47.8 / Dart 3.13.7 and Rust 1.99.1 GNU plus GCC were installed. Rust builds/tests and Flutter analysis/widget/native bridge tests now pass. Visual Studio and Android SDK remain absent; actual build attempts failed with those prerequisite errors. See iteration-01.md and build-and-run.md. No global PATH was modified.

## Iteration 02 update

Native prerequisites are now installed and flutter doctor reports no issues. Build Tools 2022 17.14.43 and Windows SDK 10.0.26100 are registered on the machine. Project-local Temurin JDK 17.0.20.1+1, Android SDK/build tools 36, NDK 28.2.13676358 and cargo-ndk 4.1.2 support a verified ARM64 debug APK build. The Windows release build and actual desktop integration test pass. Standard SDK licenses were accepted; global PATH was not edited. See iteration-02.md for evidence and remaining device gates.

## Preview 03 update

Windows release and Android ARM64 debug builds pass at 0.2.0+2. The real Windows runner now exercises opt-in visibility and self filtering; two explicit same-host multicast tests pass. A fresh Android device probe found no connected devices. See iteration-03.md for the current evidence.
