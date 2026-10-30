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
  });

  final TransferStatus status;
  final TransferRole? role;
  final String? endpoint;
  final List<TransferFileSnapshot> files;
  final String? errorCode;

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

String transferStatusMessage(
  TransferSnapshot snapshot,
) => switch (snapshot.status) {
  TransferStatus.idle => 'No transfer is running.',
  TransferStatus.listening =>
    'Waiting for a trusted device${snapshot.endpoint == null ? '' : ' on ${snapshot.endpoint}'}.',
  TransferStatus.connecting => 'Connecting to the trusted device.',
  TransferStatus.awaitingApproval =>
    'Review the file list before anything is saved.',
  TransferStatus.transferring =>
    'Transferring. Checksums are verified before a file is kept.',
  TransferStatus.completed => 'Transfer finished and the checksums matched.',
  TransferStatus.rejected => 'The transfer was declined. No file was kept.',
  TransferStatus.stopped => 'The transfer was stopped.',
  TransferStatus.error => _error(snapshot.errorCode),
};

String _error(String? code) => switch (code) {
  'network' => 'The paired device could not be reached on this LAN.',
  'tls_failed' =>
    'The device certificate was rejected. Pair again before transferring.',
  'conflict' => 'A file with that name is already in the destination. Nothing was overwritten.',
  'hash_mismatch' => 'The file did not match its checksum and was not kept.',
  'protocol' =>
    'The other device sent a transfer message this app does not accept.',
  'invalid_name' => 'That file name is not allowed.',
  'invalid_input' =>
    'Choose a private LAN address, a paired device, and a real file.',
  'storage' => 'The file could not be read or saved.',
  'cancelled' => 'The transfer was stopped.',
  'not_verified' => 'The receiver did not confirm the file.',
  _ => 'The transfer stopped before it could finish.',
};
