import 'dart:io';

import '../core/app_updates.dart';

/// Replaces a portable Windows install with a verified release ZIP, then
/// restarts. Extraction happens before exit so a bad archive changes nothing.
class WindowsSelfUpdate {
  const WindowsSelfUpdate({
    this.executable,
    this.parentPid,
    this.restart = true,
  });

  /// Defaults to the running app; tests point it at a scratch install.
  final String? executable;
  final int? parentPid;
  final bool restart;

  static const _extractScript = r'''
param([string]$Archive, [string]$Destination)
$ErrorActionPreference = 'Stop'
Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
''';

  static const _applyScript = r'''
param([int]$ParentId, [string]$Source, [string]$Target, [string]$Executable, [switch]$NoRestart)
Wait-Process -Id $ParentId -Timeout 60 -ErrorAction SilentlyContinue
# robocopy retries files Windows still holds open for a moment after exit.
robocopy $Source $Target /E /R:20 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -lt 8 -and -not $NoRestart) {
  Start-Process -FilePath $Executable -WorkingDirectory $Target
}
''';

  /// Returns once the updater is running; the caller must exit promptly.
  Future<void> stage(File archive) async {
    final executable = File(this.executable ?? Platform.resolvedExecutable);
    final target = executable.parent;
    final probe = File(
      '${target.path}${Platform.pathSeparator}.mirquova-update-probe',
    );
    try {
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      throw const UpdateFailure(
        'Mirquova is in a protected folder, so it cannot update itself. Move the Mirquova folder to Documents or Desktop, then try again.',
      );
    }
    final work = archive.parent.path;
    final staging = Directory('$work${Platform.pathSeparator}app');
    if (await staging.exists()) await staging.delete(recursive: true);
    final unpack = File('$work${Platform.pathSeparator}extract-update.ps1');
    await unpack.writeAsString(_extractScript);
    final extract = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      unpack.path,
      '-Archive',
      archive.path,
      '-Destination',
      staging.path,
    ]);
    final name = executable.uri.pathSegments.last;
    if (extract.exitCode != 0 ||
        !await File('${staging.path}${Platform.pathSeparator}$name').exists()) {
      throw const UpdateFailure(
        'The downloaded update could not be unpacked. Check free disk space, then try again.',
      );
    }
    final apply = File('$work${Platform.pathSeparator}apply-update.ps1');
    await apply.writeAsString(_applyScript);
    // Dart's detached start does not give PowerShell a working console, so
    // a normal PowerShell launches the hidden updater and returns at once.
    // Windows PowerShell splits an argument array on spaces, so the whole
    // command line is one quoted string. Install folders often contain spaces.
    final launch = File('$work${Platform.pathSeparator}launch-update.ps1');
    String windowsArg(String value) => '"$value"';
    final arguments = [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      windowsArg(apply.path),
      '-ParentId',
      '${parentPid ?? pid}',
      '-Source',
      windowsArg(staging.path),
      '-Target',
      windowsArg(target.path),
      '-Executable',
      windowsArg(executable.path),
      if (!restart) '-NoRestart',
    ].join(' ');
    final quotedArguments = "'${arguments.replaceAll("'", "''")}'";
    await launch.writeAsString(
      'Start-Process -FilePath powershell.exe -WindowStyle Hidden '
      '-ArgumentList $quotedArguments',
    );
    final started = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      launch.path,
    ]);
    if (started.exitCode != 0) {
      throw const UpdateFailure('The update could not be started. Try again.');
    }
  }
}
