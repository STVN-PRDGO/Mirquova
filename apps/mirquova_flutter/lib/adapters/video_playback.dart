import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_win/video_player_win.dart';

import '../core/playback.dart';

bool _windowsBackendReady = false;

class VideoPlaybackEngine implements PlaybackEngine {
  VideoPlayerController? _controller;

  @override
  Future<void> open(String path) async {
    if (Platform.isWindows && !_windowsBackendReady) {
      WindowsVideoPlayer.registerWith();
      _windowsBackendReady = true;
    }
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    _controller = controller;
  }

  VideoPlayerController get _ready {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('No media is open.');
    }
    return controller;
  }

  @override
  Future<void> play() => _ready.play();

  @override
  Future<void> pause() => _ready.pause();

  @override
  Future<void> seek(Duration position) => _ready.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _ready.setVolume(volume);

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  void addListener(VoidCallback listener) => _controller?.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller?.removeListener(listener);

  @override
  Widget buildView() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return VideoPlayer(controller);
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
