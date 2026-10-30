import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/core/movie_hash.dart';
import 'package:mirquova/core/open_subtitles.dart';
import 'package:mirquova/core/playback.dart';
import 'package:mirquova/core/subtitles.dart';
import 'package:mirquova/core/transfer_state.dart';

void main() {
  test('srt parser keeps cue text and skips a broken block', () {
    final document = parseSrt('''
1
00:00:01,000 --> 00:00:02,500
Hello
there

not a cue

2
00:00:03.000 --> 00:00:04.000
Next
''');
    expect(document.cues, hasLength(2));
    expect(
      document.at(const Duration(milliseconds: 1500))?.text,
      'Hello\nthere',
    );
    expect(document.matching('next').single.text, 'Next');
    expect(document.at(const Duration(seconds: 9)), isNull);
  });

  test('movie hash of 128 KiB of zeros is the file length', () async {
    final file = File(
      '${Directory.systemTemp.path}/mirquova-hash-${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    await file.writeAsBytes(List<int>.filled(131072, 0));
    addTearDown(file.delete);
    expect(await openSubtitlesMovieHash(file.path), '0000000000020000');
    await file.writeAsBytes(const [1, 2, 3]);
    expect(await openSubtitlesMovieHash(file.path), isNull);
  });

  test(
    'subtitle search does not call the network without permission',
    () async {
      final transport = _Transport();
      final api = OpenSubtitlesApi(transport: transport);
      expect(
        () =>
            api.search(optedIn: false, apiKey: 'secret', query: 'private-name'),
        throwsA(isA<OpenSubtitlesDisabled>()),
      );
      expect(transport.calls, 0);
      expect(
        () => api.search(optedIn: true, apiKey: '', query: 'private-name'),
        throwsA(isA<OpenSubtitlesDisabled>()),
      );
      expect(transport.calls, 0);
    },
  );

  test(
    'subtitle search parses a fixture and ranks a content match first',
    () async {
      final transport = _Transport();
      final api = OpenSubtitlesApi(transport: transport);
      final results = await api.search(
        optedIn: true,
        apiKey: 'user-key',
        query: 'Example',
        movieHash: '0000000000020000',
      );
      expect(transport.calls, 1);
      expect(transport.lastUri?.host, 'api.opensubtitles.com');
      expect(transport.lastUri?.queryParameters['query'], 'Example');
      expect(transport.lastHeaders?['Api-Key'], 'user-key');
      expect(results.map((item) => item.fileName), [
        'matched.srt',
        'other.srt',
      ]);
      expect(results.first.hashMatch, isTrue);
      final text = await api.download(
        optedIn: true,
        apiKey: 'user-key',
        fileId: 7,
      );
      expect(text, contains('Hello'));
      expect(transport.downloadUri?.scheme, 'https');
    },
  );

  test('transfer snapshot reads a receiver approval offer', () {
    final snapshot = TransferSnapshot.fromJson({
      'status': 'awaiting_approval',
      'role': 'receive',
      'endpoint': '192.168.1.20:1234',
      'error_code': null,
      'files': [
        {'name': 'note.txt', 'size': 5, 'transferred': 0, 'state': 'pending'},
      ],
    });
    expect(snapshot.status, TransferStatus.awaitingApproval);
    expect(snapshot.files.single.name, 'note.txt');
    expect(snapshot.finished, isFalse);
  });

  test('playback controls a local engine without inventing a file', () async {
    final engine = _Engine();
    final playback = LocalPlayback();
    addTearDown(playback.dispose);
    expect(playback.hasMedia, isFalse);
    await playback.open(
      const LocalMedia(name: 'clip.mp4', path: r'C:\media\clip.mp4'),
      engine,
    );
    expect(playback.hasMedia, isTrue);
    expect(playback.name, 'clip.mp4');
    await playback.togglePlay();
    expect(engine.isPlaying, isTrue);
    await playback.seekBy(const Duration(seconds: 3));
    expect(engine.position, const Duration(seconds: 3));
    await playback.changeVolume(-0.25);
    expect(playback.volume, 0.75);
    playback.loadSubtitles(
      parseSrt('1\n00:00:01,000 --> 00:00:04,000\nCaption\n'),
      'clip.srt',
    );
    expect(playback.currentCue?.text, 'Caption');
    await playback.stop();
    expect(playback.hasMedia, isFalse);
    expect(engine.disposed, isTrue);
  });
}

class _Transport implements OpenSubtitleTransport {
  int calls = 0;
  Uri? lastUri;
  Map<String, String>? lastHeaders;
  Uri? downloadUri;

  @override
  Future<String> get(Uri uri, Map<String, String> headers) async {
    calls++;
    lastUri = uri;
    lastHeaders = headers;
    return '''
{"data":[
  {"attributes":{"language":"en","release":"web","moviehash_match":false,"files":[{"file_id":4,"file_name":"other.srt"}]}},
  {"attributes":{"language":"en","release":"disc","moviehash_match":true,"files":[{"file_id":7,"file_name":"matched.srt"}]}}
]}
''';
  }

  @override
  Future<String> post(Uri uri, Map<String, String> headers, String body) async {
    calls++;
    expect(uri.host, 'api.opensubtitles.com');
    expect(body, '{"file_id":7}');
    return '{"link":"https://downloads.example/subtitle.srt"}';
  }

  @override
  Future<String> download(Uri uri) async {
    downloadUri = uri;
    return '1\n00:00:00,000 --> 00:00:01,000\nHello\n';
  }
}

class _Engine implements PlaybackEngine {
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 10);
  @override
  bool isPlaying = false;
  bool disposed = false;
  final _listeners = <VoidCallback>[];

  @override
  Future<void> open(String path) async {}

  @override
  Future<void> play() async => isPlaying = true;

  @override
  Future<void> pause() async => isPlaying = false;

  @override
  Future<void> seek(Duration position) async => this.position = position;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> dispose() async => disposed = true;
}
