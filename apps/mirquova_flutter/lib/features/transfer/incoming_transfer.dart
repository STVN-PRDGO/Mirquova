import 'package:flutter/material.dart';

import '../../adapters/native_transfer.dart';
import '../../core/transfer_state.dart';

/// Shown over any screen while a paired device waits for an answer. It closes
/// itself when the offer ends, for example when the sender cancels.
class IncomingTransferDialog extends StatefulWidget {
  const IncomingTransferDialog({super.key, required this.service});

  final TransferService service;

  @override
  State<IncomingTransferDialog> createState() => _IncomingTransferDialogState();
}

class _IncomingTransferDialogState extends State<IncomingTransferDialog> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted || _closed) return;
    if (!widget.service.incomingNeedsAnswer) {
      _closed = true;
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  void _answer(bool accept) {
    if (_closed) return;
    _closed = true;
    accept ? widget.service.approve() : widget.service.reject();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = widget.service.incoming;
    final sender = widget.service.incomingPeer?.alias ?? 'A paired device';
    final files = snapshot.files;
    final count = files.length == 1 ? '1 file' : '${files.length} files';
    return AlertDialog(
      icon: Icon(Icons.download_rounded, color: theme.colorScheme.primary),
      title: Text('$sender wants to send $count'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final file in files)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(formatBytes(file.size)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total ${formatBytes(snapshot.totalBytes)}. Saved to ${widget.service.folder ?? 'your downloads'}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _answer(false),
          child: const Text('Decline'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => _answer(true),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}

String incomingResultMessage(IncomingResult result) {
  final snapshot = result.snapshot;
  final count = snapshot.files.length == 1
      ? '1 file'
      : '${snapshot.files.length} files';
  return switch (snapshot.status) {
    TransferStatus.completed =>
      'Received $count from ${result.senderAlias}. Saved to ${result.folder}.',
    TransferStatus.rejected when snapshot.errorCode == 'no_answer' =>
      'A request from ${result.senderAlias} expired. Nothing was saved.',
    TransferStatus.rejected => 'Declined files from ${result.senderAlias}.',
    _ =>
      'Receiving from ${result.senderAlias} failed. ${transferStatusMessage(snapshot)}',
  };
}
