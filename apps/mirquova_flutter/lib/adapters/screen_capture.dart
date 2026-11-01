import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class ScreenCapture {
  bool get active;
  bool get supported;
  Future<bool> start();
  Future<Uint8List?> captureFrame();
  Future<void> stop();
}

/// Platform screen capture for Mirquova-to-Mirquova casting.
///
/// Windows captures a JPEG on each call. Android asks for MediaProjection
/// once, then each call reads the latest frame. Other platforms stay off.
class PlatformScreenCapture implements ScreenCapture {
  PlatformScreenCapture({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.mirquova/app');

  final MethodChannel _channel;
  bool _active = false;

  @override
  bool get active => _active;
  @override
  bool get supported => Platform.isWindows || Platform.isAndroid;

  @override
  Future<bool> start() async {
    if (_active) return true;
    if (!supported) return false;
    if (Platform.isWindows) {
      _active = true;
      return true;
    }
    try {
      final allowed = await _channel.invokeMethod<bool>('startScreenCapture');
      _active = allowed == true;
      return _active;
    } on Object {
      _active = false;
      return false;
    }
  }

  @override
  Future<Uint8List?> captureFrame() async {
    if (!_active) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('captureFrame');
      if (bytes == null || bytes.length < 4) return null;
      if (bytes[0] != 0xff || bytes[1] != 0xd8 || bytes[2] != 0xff) {
        return null;
      }
      return bytes;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopScreenCapture');
    } on Object {
      // The next start asks for capture permission again.
    }
  }
}
