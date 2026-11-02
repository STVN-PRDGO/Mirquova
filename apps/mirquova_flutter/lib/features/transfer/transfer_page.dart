import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../adapters/native_transfer.dart';
import '../../adapters/pairing_identity.dart';
import '../../core/transfer_state.dart';
import '../../ui/surface_card.dart';

/// Choose files, then tap a paired device. Receiving needs no setup: the app
/// listens on its own and asks before saving anything.
class TransferPage extends StatefulWidget {
  const TransferPage({
    super.key,
    required this.service,
    required this.onOpenPair,
    this.pickFiles,
    this.pickFolder,
  });

  final TransferService? service;
  final VoidCallback onOpenPair;
  final Future<List<PickedTransferFile>> Function()? pickFiles;
  final Future<String?> Function()? pickFolder;

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class PickedTransferFile {
  const PickedTransferFile({
    required this.path,
    required this.name,
    required this.size,
  });
  final String path;
  final String name;
  final int size;
}

class _TransferPageState extends State<TransferPage> {
  final _files = <PickedTransferFile>[];
  int _sampleBytes = 0;
  DateTime _sampleAt = DateTime.now();
  double? _bytesPerSecond;
  bool _sampling = false;

  @override
  void initState() {
    super.initState();
    widget.service?.addListener(_sampleRate);
    widget.service?.reloadPeers();
  }

  @override
  void dispose() {
    widget.service?.removeListener(_sampleRate);
    super.dispose();
  }

  void _sampleRate() {
    final service = widget.service;
    if (service == null || !mounted) return;
    final snapshot = service.outgoing;
    if (snapshot.status != TransferStatus.transferring) {
      _sampling = false;
      _sampleBytes = 0;
      _bytesPerSecond = null;
      _sampleAt = DateTime.now();
      return;
    }
    if (!_sampling) {
      _sampling = true;
      _sampleBytes = snapshot.transferredBytes;
      _sampleAt = DateTime.now();
      _bytesPerSecond = null;
      return;
    }
    final now = DateTime.now();
    final elapsed = now.difference(_sampleAt).inMilliseconds;
    final bytes = snapshot.transferredBytes;
    if (elapsed >= 400 && bytes >= _sampleBytes) {
      _bytesPerSecond = (bytes - _sampleBytes) * 1000 / elapsed;
      _sampleBytes = bytes;
      _sampleAt = now;
    }
  }

  Future<List<PickedTransferFile>> _defaultPickFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    return [
      for (final file in picked)
        if (file.path != null)
          PickedTransferFile(
            path: file.path!,
            name: file.name,
            size: file.lengthSync() ?? 0,
          ),
    ];
  }

  Future<void> _chooseFiles() async {
    final picked = await (widget.pickFiles ?? _defaultPickFiles)();
    if (!mounted || picked.isEmpty) return;
    widget.service?.clearSend();
    setState(() {
      for (final file in picked) {
        if (_files.any((item) => item.path == file.path)) continue;
        _files.add(file);
      }
    });
  }

  Future<void> _changeFolder() async {
    final service = widget.service;
    if (service == null) return;
    final path =
        await (widget.pickFolder ??
            () => FilePicker.getDirectoryPath(
              dialogTitle: 'Choose where received files are saved',
            ))();
    if (path == null) return;
    await service.setFolder(path);
  }

  Future<void> _sendTo(TrustedPeer peer) async {
    final service = widget.service;
    if (service == null || _files.isEmpty || service.sending) return;
    await service.send(
      peer: peer,
      paths: [for (final file in _files) file.path],
    );
    if (mounted && service.outgoing.status == TransferStatus.completed) {
      setState(_files.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    const header = PageHeader(
      title: 'Send files',
      subtitle: 'Choose files, then tap a device. The other device accepts before anything is saved.',
    );
    if (service == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          SizedBox(height: 16),
          EmptyPanel(
            icon: Icons.error_outline,
            title: 'File transfer is unavailable',
            message: 'This build does not include the Mirquova native core. Install the full app package.',
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          _ReceiveStatus(service: service, onChangeFolder: _changeFolder),
          const SizedBox(height: 16),
          if (service.peers.isEmpty)
            EmptyPanel(
              icon: Icons.devices_other_outlined,
              title: 'No paired devices yet',
              message: 'Pair once, and the devices can send files to each other any time Mirquova is open on both.',
              action: FilledButton.icon(
                onPressed: widget.onOpenPair,
                icon: const Icon(Icons.radar_outlined),
                label: const Text('Pair a device'),
              ),
            )
          else ...[
            _FilesCard(
              files: _files,
              enabled: !service.sending,
              onChoose: _chooseFiles,
              onRemove: (file) => setState(() => _files.remove(file)),
            ),
            const SizedBox(height: 20),
            Text(
              _files.isEmpty ? 'Your devices' : 'Tap a device to send',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final peer in service.peers)
                  _DeviceTile(
                    peer: peer,
                    enabled: _files.isNotEmpty && !service.sending,
                    active:
                        service.outgoingPeer?.fingerprintSha256 ==
                        peer.fingerprintSha256,
                    onTap: () => _sendTo(peer),
                  ),
                _AddDeviceTile(onTap: widget.onOpenPair),
              ],
            ),
            if (service.outgoingPeer != null) ...[
              const SizedBox(height: 20),
              _SendProgress(service: service, bytesPerSecond: _bytesPerSecond),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReceiveStatus extends StatelessWidget {
  const _ReceiveStatus({required this.service, required this.onChangeFolder});

  final TransferService service;
  final VoidCallback onChangeFolder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final problem = service.receiveProblem;
    final ready = service.receiving && problem == null;
    final color = problem != null
        ? colors.error
        : ready
        ? Colors.green.shade600
        : colors.onSurfaceVariant;
    final label =
        problem ??
        (ready
            ? 'Ready to receive from paired devices'
            : service.peers.isEmpty
            ? 'Pair a device to receive files'
            : 'Starting…');
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            ready ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                if (service.folder != null)
                  Text(
                    'Saves to ${service.folder}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (service.peers.isNotEmpty)
            TextButton(
              onPressed: onChangeFolder,
              child: const Text('Change folder'),
            ),
        ],
      ),
    );
  }
}

class _FilesCard extends StatelessWidget {
  const _FilesCard({
    required this.files,
    required this.enabled,
    required this.onChoose,
    required this.onRemove,
  });

  final List<PickedTransferFile> files;
  final bool enabled;
  final VoidCallback onChoose;
  final ValueChanged<PickedTransferFile> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = files.fold(0, (sum, file) => sum + file.size);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          if (files.isEmpty) ...[
            Icon(Icons.upload_file_outlined, size: 40, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              'Choose what to send',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
          ] else ...[
            for (final file in files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(formatBytes(file.size)),
                trailing: IconButton(
                  tooltip: 'Remove ${file.name}',
                  onPressed: enabled ? () => onRemove(file) : null,
                  icon: const Icon(Icons.close),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${files.length} ${files.length == 1 ? 'file' : 'files'} · ${formatBytes(total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.tonalIcon(
            onPressed: enabled ? onChoose : null,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(files.isEmpty ? 'Choose files' : 'Add more'),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.peer,
    required this.enabled,
    required this.active,
    required this.onTap,
  });

  final TrustedPeer peer;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send to ${peer.alias}',
      child: Material(
        color: active ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: enabled || active ? 1 : 0.55,
            child: SizedBox(
              width: 132,
              height: 120,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    child: const Icon(Icons.devices_outlined),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      peer.alias,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddDeviceTile extends StatelessWidget {
  const _AddDeviceTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 132,
          height: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 28, color: colors.primary),
              const SizedBox(height: 10),
              const Text('Pair another'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendProgress extends StatelessWidget {
  const _SendProgress({required this.service, required this.bytesPerSecond});

  final TransferService service;
  final double? bytesPerSecond;

  @override
  Widget build(BuildContext context) {
    final snapshot = service.outgoing;
    final alias = service.outgoingPeer?.alias ?? 'the device';
    final total = snapshot.totalBytes;
    final progress = total == 0 ? null : snapshot.transferredBytes / total;
    final title = switch (snapshot.status) {
      TransferStatus.connecting => 'Connecting to $alias…',
      TransferStatus.awaitingApproval => 'Waiting for $alias to accept…',
      TransferStatus.transferring => 'Sending to $alias',
      TransferStatus.completed => 'Sent to $alias',
      _ => service.sendMessage ?? transferStatusMessage(snapshot),
    };
    final done = !service.sending;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(switch (snapshot.status) {
                TransferStatus.completed => Icons.check_circle,
                TransferStatus.error ||
                TransferStatus.rejected => Icons.error_outline,
                _ => Icons.send_outlined,
              }, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (!done) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: snapshot.status == TransferStatus.transferring
                  ? progress
                  : null,
            ),
            if (snapshot.status == TransferStatus.transferring &&
                total > 0) ...[
              const SizedBox(height: 6),
              Text(_progressLine(snapshot, bytesPerSecond)),
              if (snapshot.files.length > 1) ...[
                const SizedBox(height: 8),
                for (final file in snapshot.files)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${file.name} · ${formatBytes(file.transferred)} of ${formatBytes(file.size)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
          ],
          if (done &&
              snapshot.status != TransferStatus.completed &&
              service.sendMessage != null &&
              title != service.sendMessage) ...[
            const SizedBox(height: 8),
            Text(service.sendMessage!),
          ],
          const SizedBox(height: 12),
          done
              ? TextButton(
                  onPressed: service.clearSend,
                  child: const Text('Done'),
                )
              : OutlinedButton(
                  onPressed: service.cancelSend,
                  child: const Text('Cancel'),
                ),
        ],
      ),
    );
  }
}

String _progressLine(TransferSnapshot snapshot, double? bytesPerSecond) {
  final amount =
      '${formatBytes(snapshot.transferredBytes)} of ${formatBytes(snapshot.totalBytes)}';
  final rate = bytesPerSecond == null ? '' : formatTransferRate(bytesPerSecond);
  final eta = formatTransferEta(
    snapshot.totalBytes - snapshot.transferredBytes,
    bytesPerSecond,
  );
  return [amount, if (rate.isNotEmpty) rate, ?eta].join(' · ');
}
