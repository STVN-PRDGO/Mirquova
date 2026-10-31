import 'dart:convert';

import 'package:flutter/foundation.dart';

class PeerCandidate {
  const PeerCandidate({
    required this.id,
    required this.name,
    required this.addresses,
    required this.port,
  });
  final String id;
  final String name;
  final List<String> addresses;
  final int port;
  // mDNS and manually entered addresses never authenticate a device.
  bool get verified => false;

  factory PeerCandidate.fromJson(Map<String, dynamic> json) {
    if (json['verified'] != false || json['port'] != 0) {
      throw const FormatException('Discovery cannot establish trust.');
    }
    return PeerCandidate(
      id: json['id'] as String,
      name: json['name'] as String,
      addresses: List<String>.from(json['addresses'] as List),
      port: json['port'] as int,
    );
  }
}

enum DiscoveryStatus { idle, scanning, complete, stopped, error, unavailable }

enum PresenceStatus { hidden, starting, visible, stopping, error }

class PresenceState {
  const PresenceState({
    this.status = PresenceStatus.hidden,
    this.alias,
    this.remainingSeconds = 0,
    this.message,
  });
  final PresenceStatus status;
  final String? alias;
  final int remainingSeconds;
  final String? message;
  bool get active =>
      status == PresenceStatus.starting ||
      status == PresenceStatus.visible ||
      status == PresenceStatus.stopping;
  factory PresenceState.fromJson(Map<String, dynamic> json) => PresenceState(
    status: PresenceStatus.values.byName(json['status'] as String),
    alias: json['alias'] as String?,
    remainingSeconds: json['remaining_seconds'] as int,
    message: json['error'] as String?,
  );
  static bool validAlias(String alias) =>
      alias.trim().isNotEmpty &&
      utf8.encode(alias).length <= 64 &&
      !RegExp(r'[\x00-\x1F\x7F-\x9F\u202A-\u202E\u2066-\u2069]')
          .hasMatch(alias);
}

class DiscoverySnapshot {
  const DiscoverySnapshot({
    this.status = DiscoveryStatus.idle,
    this.peers = const [],
    this.message,
    this.presence = const PresenceState(),
  });
  final DiscoveryStatus status;
  final List<PeerCandidate> peers;
  final String? message;
  final PresenceState presence;
  DiscoverySnapshot copyWith({
    DiscoveryStatus? status,
    List<PeerCandidate>? peers,
    String? message,
    PresenceState? presence,
  }) => DiscoverySnapshot(
    status: status ?? this.status,
    peers: peers ?? this.peers,
    message: message,
    presence: presence ?? this.presence,
  );

  factory DiscoverySnapshot.fromJson(Map<String, dynamic> json) {
    if (json['abi_version'] != 2) {
      throw const FormatException('Unsupported native ABI.');
    }
    final status = DiscoveryStatus.values.byName(json['status'] as String);
    final records = json['peers'] as Map<String, dynamic>;
    if (records.length > 128) {
      throw const FormatException('Too many candidates.');
    }
    return DiscoverySnapshot(
      status: status,
      peers: records.values
          .map(
            (item) =>
                PeerCandidate.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      message: json['error'] as String?,
      presence: PresenceState.fromJson(
        json['presence'] as Map<String, dynamic>,
      ),
    );
  }
}

abstract class DiscoveryPort extends ChangeNotifier {
  DiscoverySnapshot get snapshot;
  Future<void> start();
  void stop();
  Future<void> makeDiscoverable(String alias);
  void hide();
}

class ManualEndpoint {
  const ManualEndpoint(this.address, this.port);
  final String address;
  final int port;
  String get key => '$address:$port';

  static ManualEndpoint? parse(String address, String port) {
    // First spike accepts only RFC1918 IPv4 literals: no URL, DNS, or credentials.
    final parts = address.trim().split('.');
    if (parts.length != 4) {
      return null;
    }
    final bytes = <int>[];
    for (final part in parts) {
      if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part)) {
        return null;
      }
      final byte = int.parse(part);
      if (byte > 255) {
        return null;
      }
      bytes.add(byte);
    }
    final private =
        bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
    final trimmedPort = port.trim();
    final parsedPort = RegExp(r'^[0-9]{1,5}$').hasMatch(trimmedPort)
        ? int.tryParse(trimmedPort)
        : null;
    if (!private ||
        parsedPort == null ||
        parsedPort < 1 ||
        parsedPort > 65535) {
      return null;
    }
    return ManualEndpoint(bytes.join('.'), parsedPort);
  }
}

/// Prefer a normal home-LAN address over virtual and emulator ranges.
List<String> preferredLanAddresses(Iterable<String> addresses) {
  final values = addresses.toList();
  values.sort((a, b) {
    final rank = _lanRank(a).compareTo(_lanRank(b));
    return rank == 0 ? a.compareTo(b) : rank;
  });
  return values;
}

int _lanRank(String address) {
  if (address.startsWith('192.168.')) return 0;
  if (address.startsWith('10.')) return 1;
  return 2;
}
