/// Shared listen port. Pairing chooses the device, not this number.
const mirquovaCastPort = 40734;

enum CastStatus {
  idle,
  listening,
  connecting,
  awaitingApproval,
  casting,
  rejected,
  stopped,
  error,
}

enum CastRole { send, receive }

class CastSnapshot {
  const CastSnapshot({
    this.status = CastStatus.idle,
    this.role,
    this.endpoint,
    this.errorCode,
    this.width,
    this.height,
    this.frames = 0,
    this.peerIndex,
    this.peerIpv4,
  });

  final CastStatus status;
  final CastRole? role;
  final String? endpoint;
  final String? errorCode;
  final int? width;
  final int? height;
  final int frames;
  final int? peerIndex;
  final String? peerIpv4;

  bool get finished => switch (status) {
    CastStatus.rejected || CastStatus.stopped || CastStatus.error => true,
    _ => false,
  };

  static CastSnapshot fromJson(Map<String, dynamic> json) => CastSnapshot(
    status: _status(json['status'] as String?),
    role: switch (json['role']) {
      'send' => CastRole.send,
      'receive' => CastRole.receive,
      _ => null,
    },
    endpoint: json['endpoint'] as String?,
    errorCode: json['error_code'] as String?,
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
    frames: (json['frames'] as num?)?.toInt() ?? 0,
    peerIndex: (json['peer_index'] as num?)?.toInt(),
    peerIpv4: json['peer_ipv4'] as String?,
  );
}

CastStatus _status(String? value) => switch (value) {
  'listening' => CastStatus.listening,
  'connecting' => CastStatus.connecting,
  'awaiting_approval' => CastStatus.awaitingApproval,
  'casting' => CastStatus.casting,
  'rejected' => CastStatus.rejected,
  'stopped' => CastStatus.stopped,
  'error' => CastStatus.error,
  _ => CastStatus.idle,
};

String castStatusMessage(CastSnapshot snapshot) => switch (snapshot.status) {
  CastStatus.idle => 'No cast is running.',
  CastStatus.listening => 'Waiting for a paired device.',
  CastStatus.connecting => 'Connecting to the trusted device.',
  CastStatus.awaitingApproval =>
    'Review the screen-share request before anything is shown.',
  CastStatus.casting => 'Sharing a live screen on this LAN.',
  CastStatus.rejected =>
    snapshot.errorCode == 'no_answer'
        ? 'Nobody answered in time. Nothing was shown.'
        : 'The screen share was declined.',
  CastStatus.stopped => 'The screen share was stopped.',
  CastStatus.error => _error(snapshot.errorCode),
};

String _error(String? code) => switch (code) {
  'network' => 'The device could not be reached. Open Mirquova on it and keep both devices on the same Wi-Fi.',
  'no_answer' => 'Nobody answered the request on the other device.',
  'tls_failed' =>
    'The device certificate was rejected. Pair again before casting.',
  'protocol' =>
    'The other device sent a cast message this app does not accept.',
  'invalid_input' => 'Choose a paired device that can receive a screen share.',
  'cancelled' => 'The screen share was stopped.',
  'capture' => 'This device could not capture its screen.',
  _ => 'The screen share stopped before it could finish.',
};
