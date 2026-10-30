import 'package:flutter/widgets.dart';

import 'subtitles.dart';

abstract class PlaybackEngine {
  Future<void> open(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Duration get position;
  Duration get duration;
  bool get isPlaying;
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  Widget buildView();
  Future<void> dispose();
}

class LocalMedia {
  const LocalMedia({required this.name, required this.path});

  final String name;
  final String path;
}

class LocalPlayback extends ChangeNotifier {
  PlaybackEngine? _engine;
  final library = <LocalMedia>[];
  String? name;
  String? path;
  String? error;
  SubtitleDocument? subtitles;
  String? subtitleLabel;
  double subtitleScale = 1;
  bool subtitleBackground = true;
  double volume = 1;
  bool _disposed = false;

  bool get hasMedia => name != null && error == null && _engine != null;
  Widget buildView() => _engine?.buildView() ?? const SizedBox.shrink();
  Duration get position => _engine?.position ?? Duration.zero;
  Duration get duration => _engine?.duration ?? Duration.zero;
  bool get playing => _engine?.isPlaying ?? false;
  SubtitleCue? get currentCue => subtitles?.at(position);

  Future<void> open(LocalMedia media, PlaybackEngine engine) async {
    final previous = _engine;
    _engine = null;
    previous?.removeListener(_changed);
    await previous?.dispose();
    name = media.name;
    path = media.path;
    error = null;
    subtitles = null;
    subtitleLabel = null;
    try {
      await engine.open(media.path);
      await engine.setVolume(volume);
      engine.addListener(_changed);
      _engine = engine;
      if (!library.any((item) => item.path == media.path)) {
        library.insert(0, media);
      }
    } on Object {
      await engine.dispose();
      error = 'This file could not be opened for playback.';
    }
    _changed();
  }

  void loadSubtitles(SubtitleDocument document, String label) {
    subtitles = document;
    subtitleLabel = label;
    _changed();
  }

  void setSubtitleScale(double value) {
    subtitleScale = value;
    _changed();
  }

  void setSubtitleBackground(bool value) {
    subtitleBackground = value;
    _changed();
  }

  Future<void> togglePlay() async {
    final engine = _engine;
    if (engine == null) return;
    if (engine.isPlaying) {
      await engine.pause();
    } else {
      await engine.play();
    }
    _changed();
  }

  Future<void> seekBy(Duration delta) async {
    final engine = _engine;
    if (engine == null) return;
    final next = engine.position + delta;
    final max = engine.duration;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && next > max ? max : next);
    await engine.seek(clamped);
    _changed();
  }

  Future<void> seekTo(double fraction) async {
    final engine = _engine;
    if (engine == null || engine.duration == Duration.zero) return;
    final milliseconds = (engine.duration.inMilliseconds * fraction).round();
    await engine.seek(Duration(milliseconds: milliseconds));
    _changed();
  }

  Future<void> changeVolume(double delta) async {
    volume = (volume + delta).clamp(0, 1).toDouble();
    await _engine?.setVolume(volume);
    _changed();
  }

  Future<void> stop() async {
    final engine = _engine;
    _engine = null;
    engine?.removeListener(_changed);
    await engine?.dispose();
    name = null;
    path = null;
    error = null;
    subtitles = null;
    subtitleLabel = null;
    _changed();
  }

  Future<void> openRelative(int delta, PlaybackEngine Function() create) async {
    if (library.isEmpty || path == null) return;
    final index = library.indexWhere((item) => item.path == path);
    if (index < 0) return;
    final next = index + delta;
    if (next < 0 || next >= library.length) return;
    await open(library[next], create());
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final engine = _engine;
    _engine = null;
    engine?.removeListener(_changed);
    engine?.dispose();
    super.dispose();
  }
}
