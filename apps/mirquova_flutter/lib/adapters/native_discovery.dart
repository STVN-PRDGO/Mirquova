import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import '../core/discovery_port.dart';

typedef _Version = Uint32 Function();
typedef _Start = Int32 Function();
typedef _Stop = Void Function();
typedef _Snapshot = Pointer<Utf8> Function();
typedef _Free = Void Function(Pointer<Utf8>);
typedef _Presence = Int32 Function(Pointer<Uint8>, Uint32);

abstract interface class NativeDiscoveryApi {
  DiscoverySnapshot read();
  int startScan();
  void stopScan();
  int startPresence(String alias);
  void stopPresence();
}

class FfiDiscoveryApi implements NativeDiscoveryApi {
  FfiDiscoveryApi() {
    const override = String.fromEnvironment('MIRQUOVA_CORE_LIBRARY');
    final path = override.isNotEmpty
        ? override
        : Platform.isWindows
        ? '${File(Platform.resolvedExecutable).parent.path}/mirquova_core.dll'
        : Platform.isMacOS
        ? '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libmirquova_core.dylib'
        : Platform.isLinux
        ? '${File(Platform.resolvedExecutable).parent.path}/lib/libmirquova_core.so'
        : 'libmirquova_core.so';
    final library = Platform.isIOS && override.isEmpty
        ? DynamicLibrary.process()
        : DynamicLibrary.open(path);
    if (library.lookupFunction<_Version, int Function()>('mq_abi_version')() !=
        2) {
      throw const FormatException('Unsupported core ABI');
    }
    _start = library.lookupFunction<_Start, int Function()>(
      'mq_discovery_start',
    );
    _stop = library.lookupFunction<_Stop, void Function()>('mq_discovery_stop');
    _read = library.lookupFunction<_Snapshot, Pointer<Utf8> Function()>(
      'mq_discovery_snapshot',
    );
    _free = library.lookupFunction<_Free, void Function(Pointer<Utf8>)>(
      'mq_string_free',
    );
    _show = library
        .lookupFunction<_Presence, int Function(Pointer<Uint8>, int)>(
          'mq_presence_start',
        );
    _hide = library.lookupFunction<_Stop, void Function()>('mq_presence_stop');
  }
  late final int Function() _start;
  late final void Function() _stop;
  late final Pointer<Utf8> Function() _read;
  late final void Function(Pointer<Utf8>) _free;
  late final int Function(Pointer<Uint8>, int) _show;
  late final void Function() _hide;
  @override
  DiscoverySnapshot read() {
    final value = _read();
    if (value == nullptr) {
      throw StateError('No native snapshot');
    }
    try {
      return DiscoverySnapshot.fromJson(
        jsonDecode(value.toDartString()) as Map<String, dynamic>,
      );
    } finally {
      _free(value);
    }
  }

  @override
  int startScan() => _start();
  @override
  void stopScan() => _stop();
  @override
  int startPresence(String alias) {
    final bytes = alias.toNativeUtf8();
    try {
      return _show(bytes.cast<Uint8>(), utf8.encode(alias).length);
    } finally {
      malloc.free(bytes);
    }
  }

  @override
  void stopPresence() => _hide();
}

abstract interface class MulticastAccess {
  Future<void> acquire();
  Future<void> release();
}

class PlatformMulticastAccess implements MulticastAccess {
  static const _channel = MethodChannel('dev.mirquova/discovery');
  @override
  Future<void> acquire() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('acquire');
    }
  }

  @override
  Future<void> release() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('release');
    }
  }
}

class NativeDiscovery extends DiscoveryPort {
  NativeDiscovery({NativeDiscoveryApi? api, MulticastAccess? multicast})
    : _multicast = multicast ?? PlatformMulticastAccess() {
    try {
      _api = api ?? FfiDiscoveryApi();
      _value = _api!.read();
    } catch (_) {
      _value = const DiscoverySnapshot(
        status: DiscoveryStatus.unavailable,
        message: 'Discovery needs the updated native core. Rebuild or update the complete Mirquova bundle.',
      );
    }
  }
  NativeDiscoveryApi? _api;
  final MulticastAccess _multicast;
  DiscoverySnapshot _value = const DiscoverySnapshot();
  Timer? _timer;
  Future<void> _wifiQueue = Future.value();
  bool _held = false,
      _disposed = false,
      _pendingScan = false,
      _pendingPresence = false;
  int _scanGeneration = 0, _presenceGeneration = 0;
  @override
  DiscoverySnapshot get snapshot => _value;

  // Serialize platform calls; re-evaluate demand at execution time so a stale
  // release cannot drop a lock needed by a concurrent scan/presence request.
  Future<void> _syncMulticast() {
    _wifiQueue = _wifiQueue.catchError((Object _) {}).then((_) async {
      final wanted =
          !_disposed &&
          (_pendingScan ||
              _pendingPresence ||
              _value.status == DiscoveryStatus.scanning ||
              _value.presence.active);
      if (wanted == _held) {
        return;
      }
      if (wanted) {
        await _multicast.acquire();
        _held = true;
      } else {
        await _multicast.release();
        _held = false;
      }
    });
    return _wifiQueue;
  }

  void _schedule() {
    final busy =
        _pendingScan ||
        _pendingPresence ||
        _value.status == DiscoveryStatus.scanning ||
        _value.presence.active;
    if (!_disposed && busy) {
      _timer ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _poll(),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _poll() {
    if (_disposed || _api == null) {
      return;
    }
    try {
      _value = _api!.read();
    } catch (_) {
      _api!.stopScan();
      _api!.stopPresence();
      _value = const DiscoverySnapshot(
        status: DiscoveryStatus.error,
        message: 'Discovery stopped after a native-core error. Try restarting Mirquova.',
      );
    }
    _schedule();
    unawaited(_syncMulticast().catchError((Object _) {}));
    notifyListeners();
  }

  @override
  Future<void> start() async {
    if (_disposed ||
        _api == null ||
        _pendingScan ||
        _value.status == DiscoveryStatus.scanning) {
      return;
    }
    _pendingScan = true;
    final generation = ++_scanGeneration;
    try {
      await _syncMulticast();
      if (_disposed || generation != _scanGeneration) {
        return;
      }
      if (_api!.startScan() != 1) {
        throw StateError('Scan rejected');
      }
      _poll();
    } catch (_) {
      if (!_disposed && generation == _scanGeneration) {
        _value = _value.copyWith(
          status: DiscoveryStatus.error,
          message: 'Could not start scanning. Check local-network access.',
        );
        notifyListeners();
      }
    } finally {
      _pendingScan = false;
      _schedule();
      await _syncMulticast().catchError((Object _) {});
    }
  }

  @override
  Future<void> makeDiscoverable(String alias) async {
    if (_disposed ||
        _api == null ||
        _pendingPresence ||
        _value.presence.active) {
      return;
    }
    if (!PresenceState.validAlias(alias)) {
      return;
    }
    _pendingPresence = true;
    final generation = ++_presenceGeneration;
    try {
      await _syncMulticast();
      if (_disposed || generation != _presenceGeneration) {
        return;
      }
      if (_api!.startPresence(alias.trim()) != 1) {
        throw StateError('Visibility rejected');
      }
      _poll();
    } catch (_) {
      if (!_disposed && generation == _presenceGeneration) {
        _value = _value.copyWith(
          presence: const PresenceState(
            status: PresenceStatus.error,
            message:
                'Could not enable LAN visibility. Check local-network access.',
          ),
        );
        notifyListeners();
      }
    } finally {
      _pendingPresence = false;
      _schedule();
      await _syncMulticast().catchError((Object _) {});
    }
  }

  @override
  void stop() {
    _scanGeneration++;
    _api?.stopScan();
    _poll();
  }

  @override
  void hide() {
    _presenceGeneration++;
    _api?.stopPresence();
    _poll();
  }

  @override
  void dispose() {
    _disposed = true;
    _scanGeneration++;
    _presenceGeneration++;
    _api?.stopScan();
    _api?.stopPresence();
    _timer?.cancel();
    unawaited(_syncMulticast().catchError((Object _) {}));
    super.dispose();
  }
}
