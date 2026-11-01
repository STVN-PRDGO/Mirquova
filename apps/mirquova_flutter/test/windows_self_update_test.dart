@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/adapters/windows_self_update.dart';
import 'package:mirquova/core/app_updates.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mirquova update test ');
  });

  tearDown(() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        await root.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  });

  Future<File> write(String path, String contents) async {
    final file = File('${root.path}\\$path');
    await file.parent.create(recursive: true);
    return file.writeAsString(contents);
  }

  Future<File> zip(String folder) async {
    final archive = File(
      '${root.path}\\updates\\download-1\\Mirquova-preview-windows-x64.zip',
    );
    await archive.parent.create(recursive: true);
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Compress-Archive -Path '${root.path}\\$folder\\*' -DestinationPath '${archive.path}'",
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return archive;
  }

  test(
    'replaces the install after the app exits and keeps other files',
    () async {
      final executable = await write('install\\mirquova.exe', 'old');
      await write('install\\data\\app.so', 'old');
      await write('install\\notes.txt', 'mine');
      await write('release\\mirquova.exe', 'new');
      await write('release\\data\\app.so', 'new');
      await write('release\\data\\extra.dat', 'added');
      final archive = await zip('release');
      final app = await Process.start('powershell.exe', [
        '-NoProfile',
        '-Command',
        'Start-Sleep -Seconds 2',
      ]);

      await WindowsSelfUpdate(
        executable: executable.path,
        parentPid: app.pid,
        restart: false,
      ).stage(archive);
      expect(
        await executable.readAsString(),
        'old',
        reason: 'nothing changes while the app is still running',
      );
      await app.exitCode;

      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (await executable.readAsString() != 'new' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(await executable.readAsString(), 'new');
      final install = '${root.path}\\install';
      expect(await File('$install\\data\\app.so').readAsString(), 'new');
      expect(await File('$install\\data\\extra.dat').readAsString(), 'added');
      expect(await File('$install\\notes.txt').readAsString(), 'mine');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a package without the app leaves the install untouched', () async {
    final executable = await write('install\\mirquova.exe', 'old');
    await write('release\\something-else.exe', 'new');
    final archive = await zip('release');
    await expectLater(
      WindowsSelfUpdate(
        executable: executable.path,
        parentPid: pid,
        restart: false,
      ).stage(archive),
      throwsA(isA<UpdateFailure>()),
    );
    expect(await executable.readAsString(), 'old');
  });
}
