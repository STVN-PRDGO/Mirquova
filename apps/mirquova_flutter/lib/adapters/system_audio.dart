import 'dart:io';

import 'package:flutter/services.dart';

import '../core/cast_state.dart';

/// System playback audio for a screen share. This is not the microphone.
abstract interface class SystemAudio {
  bool get supported;
  Future<void> start();
  Future<Uint8List?> captureChunk();
  Future<void> play(CastAudioChunk chunk);

  /// True when this device pulls the playback clock itself.
  Future<bool> startClockedPlayback();
  Future<void> stopCapture();
  Future<void> stopPlayback();
  Future<void> stop();
}

class SilentSystemAudio implements SystemAudio {
  const SilentSystemAudio();

  @override
  bool get supported => false;
  @override
  Future<void> start() async {}
  @override
  Future<Uint8List?> captureChunk() async => null;
  @override
  Future<void> play(CastAudioChunk chunk) async {}
  @override
  Future<bool> startClockedPlayback() async => false;
  @override
  Future<void> stopCapture() async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> stop() async {}
}

/// Windows loopback capture and Android playback capture, played back as PCM.
class PlatformSystemAudio implements SystemAudio {
  PlatformSystemAudio({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.mirquova/app');

  final MethodChannel _channel;

  @override
  bool get supported => Platform.isWindows || Platform.isAndroid;

  @override
  Future<void> start() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('startSystemAudio');
    } on Object {
      // The picture can still be shared when system audio is unavailable.
    }
  }

  @override
  Future<Uint8List?> captureChunk() async {
    if (!supported) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'captureSystemAudio',
      );
      if (bytes == null || bytes.length < 4 || bytes.length.isOdd) return null;
      return bytes;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> play(CastAudioChunk chunk) async {
    if (!supported || chunk.pcm.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('playSystemAudio', {
        'pcm': chunk.pcm,
        'sampleRate': chunk.sampleRate,
        'channels': chunk.channels,
      });
    } on Object {
      // A missing playback device leaves the picture running.
    }
  }

  @override
  Future<bool> startClockedPlayback() async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('startSystemAudioPlayback') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> stopCapture() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stopSystemAudioCapture');
    } on Object {
      // Capture may already be stopped.
    }
  }

  @override
  Future<void> stopPlayback() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stopSystemAudioPlayback');
    } on Object {
      // Playback may already be stopped.
    }
  }

  @override
  Future<void> stop() async {
    await stopCapture();
    await stopPlayback();
  }
}
