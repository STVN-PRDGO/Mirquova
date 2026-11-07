/// Shared listen port. The person using the app chooses a device name, not this port.
const mirquovaTransferPort = 40733;

enum TransferStatus {
  idle,
  listening,
  connecting,
  awaitingApproval,
  transferring,
  completed,
  rejected,
  stopped,
  error,
}

enum TransferRole { send, receive }

enum TransferFileState { pending, transferring, verified, failed }

class TransferFileSnapshot {
  const TransferFileSnapshot({
    required this.name,
    required this.size,
    required this.transferred,
    required this.state,
  });

  final String name;
  final int size;
  final int transferred;
  final TransferFileState state;
}

class TransferSnapshot {
  const TransferSnapshot({
    this.status = TransferStatus.idle,
    this.role,
    this.endpoint,
    this.files = const [],
    this.errorCode,
    this.peerIndex,
    this.peerIpv4,
  });

  final TransferStatus status;
  final TransferRole? role;
  final String? endpoint;
  final List<TransferFileSnapshot> files;
  final String? errorCode;

  /// Index into the trusted peer list the receiver was started with. Set only
  /// after the sender's certificate was verified.
  final int? peerIndex;
  final String? peerIpv4;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.size);
  int get transferredBytes =>
      files.fold(0, (sum, file) => sum + file.transferred);

  bool get finished => switch (status) {
    TransferStatus.completed ||
    TransferStatus.rejected ||
    TransferStatus.stopped ||
    TransferStatus.error => true,
    _ => false,
  };

  static TransferSnapshot fromJson(Map<String, dynamic> json) {
    final files = json['files'];
    return TransferSnapshot(
      status: _status(json['status'] as String?),
      role: switch (json['role']) {
        'send' => TransferRole.send,
        'receive' => TransferRole.receive,
        _ => null,
      },
      endpoint: json['endpoint'] as String?,
      errorCode: json['error_code'] as String?,
      peerIndex: (json['peer_index'] as num?)?.toInt(),
      peerIpv4: json['peer_ipv4'] as String?,
      files: files is! List
          ? const []
          : [
              for (final item in files)
                if (item is Map<String, dynamic>)
                  TransferFileSnapshot(
                    name: item['name'] as String? ?? '',
                    size: (item['size'] as num?)?.toInt() ?? 0,
                    transferred: (item['transferred'] as num?)?.toInt() ?? 0,
                    state: _fileState(item['state'] as String?),
                  ),
            ],
    );
  }
}

TransferStatus _status(String? value) => switch (value) {
  'listening' => TransferStatus.listening,
  'connecting' => TransferStatus.connecting,
  'awaiting_approval' => TransferStatus.awaitingApproval,
  'transferring' => TransferStatus.transferring,
  'completed' => TransferStatus.completed,
  'rejected' => TransferStatus.rejected,
  'stopped' => TransferStatus.stopped,
  'error' => TransferStatus.error,
  _ => TransferStatus.idle,
};

TransferFileState _fileState(String? value) => switch (value) {
  'transferring' => TransferFileState.transferring,
  'verified' => TransferFileState.verified,
  'failed' => TransferFileState.failed,
  _ => TransferFileState.pending,
};

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// A short rate label such as `12.4 MB/s`. Empty when the sample is too small.
String formatTransferRate(double bytesPerSecond) {
  if (bytesPerSecond < 1) return '';
  return '${formatBytes(bytesPerSecond.round())}/s';
}

/// Remaining time from the latest rate sample. Null until the rate is usable.
String? formatTransferEta(int remainingBytes, double? bytesPerSecond) {
  final rate = bytesPerSecond;
  if (rate == null || rate < 1 || remainingBytes <= 0) return null;
  final seconds = (remainingBytes / rate).round();
  if (seconds < 5) return 'A few seconds left';
  if (seconds < 90) return 'About $seconds seconds left';
  final minutes = (seconds / 60).ceil();
  return minutes == 1 ? 'About 1 minute left' : 'About $minutes minutes left';
}

String transferStatusMessage(TransferSnapshot snapshot) =>
    switch (snapshot.status) {
      TransferStatus.idle => 'No transfer is running.',
      TransferStatus.listening => 'Waiting for a paired device.',
      TransferStatus.connecting => 'Connecting to the trusted device.',
      TransferStatus.awaitingApproval =>
        'Review the file list before anything is saved.',
      TransferStatus.transferring =>
        'Transferring. Checksums are verified before a file is kept.',
      TransferStatus.completed =>
        'Transfer finished and the checksums matched.',
      TransferStatus.rejected =>
        snapshot.errorCode == 'no_answer'
            ? 'Nobody answered in time. No file was kept.'
            : 'The transfer was declined. No file was kept.',
      TransferStatus.stopped => 'The transfer was stopped.',
      TransferStatus.error =>
        snapshot.errorCode == 'network' && snapshot.transferredBytes > 0
            ? 'The connection dropped during transfer. Check which files finished on the receiving device before retrying.'
            : _error(snapshot.errorCode),
    };

String _error(String? code) => switch (code) {
  'network' => 'The device could not be reached. Open Mirquova on it and keep both devices on the same Wi-Fi.',
  'no_answer' => 'Nobody answered the request on the other device.',
  'tls_failed' =>
    'The device certificate was rejected. Pair again before transferring.',
  'conflict' => 'A file with that name is already in the destination. Nothing was overwritten.',
  'hash_mismatch' => 'The file did not match its checksum and was not kept.',
  'protocol' =>
    'The other device sent a transfer message this app does not accept.',
  'invalid_name' => 'That file name is not allowed.',
  'invalid_input' => 'Choose a paired device and a real file.',
  'storage' => 'The file could not be read or saved.',
  'cancelled' => 'The transfer was stopped.',
  'not_verified' => 'The receiver did not confirm the file.',
  _ => 'The transfer stopped before it could finish.',
};
