import 'dart:io' show NetworkInterface, InternetAddressType;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../adapters/native_transfer.dart';
import '../../adapters/pairing_identity.dart';
import '../../core/discovery_port.dart';
import '../../core/transfer_state.dart';
import '../../ui/surface_card.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key, required this.ensureTransfer});

  final Future<TransferController?> Function() ensureTransfer;

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  bool _send = true;
  final _files = <_QueuedFile>[];
  String? _destination;
  String? _localAddress;
  List<TrustedPeer> _peers = const [];
  String? _selectedFingerprint;
  String? _activeAlias;
  String? _notice;
  TransferController? _transfer;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
    _loadPeers();
  }

  Future<void> _loadAddresses() async {
    try {
      await _readAddresses();
    } on Object {
      if (mounted) setState(() => _localAddress = null);
    }
  }

  Future<void> _readAddresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final addresses = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (ManualEndpoint.parse(address.address, '1') != null) {
          addresses.add(address.address);
        }
      }
    }
    if (!mounted) return;
    final sorted = preferredLanAddresses(addresses);
    setState(() => _localAddress = sorted.firstOrNull);
  }

  Future<void> _loadPeers() async {
    final controller = _transfer ?? await widget.ensureTransfer();
    if (!mounted || controller == null) return;
    try {
      final peers = await controller.trustedPeers.list();
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _selectedFingerprint =
            peers.any((peer) => peer.fingerprintSha256 == _selectedFingerprint)
            ? _selectedFingerprint
            : (peers.length == 1 ? peers.single.fingerprintSha256 : null);
      });
    } on Object {
      if (mounted) {
        setState(() => _notice = 'Trusted devices could not be read.');
      }
    }
  }

  TrustedPeer? get _selectedPeer {
    for (final peer in _peers) {
      if (peer.fingerprintSha256 == _selectedFingerprint) return peer;
    }
    return null;
  }

  void _attach(TransferController controller) {
    if (!identical(_transfer, controller)) {
      _transfer?.removeListener(_onTransfer);
      _transfer = controller;
      controller.addListener(_onTransfer);
    }
  }

  void _onTransfer() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _transfer?.removeListener(_onTransfer);
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      for (final file in picked) {
        final path = file.path;
        if (path == null || _files.any((item) => item.path == path)) continue;
        _files.add(
          _QueuedFile(
            path: path,
            name: file.name,
            size: file.lengthSync() ?? 0,
          ),
        );
      }
      _notice = null;
    });
  }

  Future<void> _pickFolder() async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose where received files are saved',
    );
    if (!mounted || directory == null) return;
    setState(() => _destination = directory);
  }

  Future<void> _startSend() async {
    final controller = _transfer ?? await widget.ensureTransfer();
    if (!mounted) return;
    if (controller == null) {
      setState(
        () => _notice = 'Native transfer core is not available in this build.',
      );
      return;
    }
    final peer = _selectedPeer;
    if (peer == null || _files.isEmpty) {
      setState(() => _notice = 'Choose a paired device and a file.');
      return;
    }
    final host = peer.lanIpv4;
    if (host == null) {
      setState(() => _notice = 'Pair ${peer.alias} again, then send the file.');
      return;
    }
    setState(() {
      _attach(controller);
      _activeAlias = peer.alias;
      _notice = null;
    });
    await controller.send(
      peer: peer,
      host: host,
      port: mirquovaTransferPort,
      paths: [for (final file in _files) file.path],
    );
  }

  Future<void> _startReceive() async {
    final controller = _transfer ?? await widget.ensureTransfer();
    if (!mounted) return;
    if (controller == null) {
      setState(
        () => _notice = 'Native transfer core is not available in this build.',
      );
      return;
    }
    final address = _localAddress;
    final destination = _destination;
    if (_peers.isEmpty) {
      setState(() => _notice = 'Pair a device before receiving files.');
      return;
    }
    if (address == null || destination == null) {
      setState(() => _notice = 'Choose a folder before receiving.');
      return;
    }
    setState(() {
      _attach(controller);
      _activeAlias = _peers.length == 1 ? _peers.single.alias : null;
      _notice = null;
    });
    await controller.receive(localIpv4: address, destination: destination);
  }

  String _statusLine(TransferSnapshot snapshot) {
    if (snapshot.status == TransferStatus.listening) {
      final alias = _activeAlias;
      if (alias != null) return 'Waiting for $alias.';
    }
    if (snapshot.status == TransferStatus.connecting) {
      final alias = _activeAlias;
      if (alias != null) return 'Connecting to $alias.';
    }
    return transferStatusMessage(snapshot);
  }

  Widget _deviceNames() {
    final theme = Theme.of(context);
    if (_peers.isEmpty) {
      return Text(
        _send
            ? 'Pair a device before sending files.'
            : 'Pair a device before receiving files.',
      );
    }
    if (_peers.length == 1) {
      return Text(_peers.single.alias, style: theme.textTheme.titleMedium);
    }
    return Column(
      children: [
        for (final peer in _peers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_outlined),
            title: Text(peer.alias),
            selected: peer.fingerprintSha256 == _selectedFingerprint,
            onTap: () =>
                setState(() => _selectedFingerprint = peer.fingerprintSha256),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final snapshot = _transfer?.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'File transfer',
          subtitle: 'Files move only to a paired device, and only after the receiver approves the offer.',
        ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Send'),
                icon: Icon(Icons.upload_outlined),
              ),
              ButtonSegment(
                value: false,
                label: Text('Receive'),
                icon: Icon(Icons.download_outlined),
              ),
            ],
            selected: {_send},
            onSelectionChanged: (value) => setState(() => _send = value.first),
          ),
        ),
        const SizedBox(height: 20),
        _DropZone(
          sending: _send,
          files: _files,
          destination: _destination,
          onPickFiles: _pickFiles,
          onPickFolder: _pickFolder,
        ),
        const SizedBox(height: 16),
        _deviceNames(),
        const SizedBox(height: 12),
        if (_send)
          FilledButton.icon(
            onPressed: _files.isEmpty || _selectedPeer == null
                ? null
                : _startSend,
            icon: const Icon(Icons.send_outlined),
            label: Text(
              _selectedPeer == null
                  ? 'Send'
                  : 'Send to ${_selectedPeer!.alias}',
            ),
          )
        else
          FilledButton.icon(
            onPressed: _destination == null || _peers.isEmpty
                ? null
                : _startReceive,
            icon: const Icon(Icons.downloading_outlined),
            label: Text(
              _peers.length == 1
                  ? 'Receive from ${_peers.single.alias}'
                  : 'Receive from a paired device',
            ),
          ),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          Text(_statusLine(snapshot)),
          for (final file in snapshot.files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(file.name),
              subtitle: Text(
                '${file.transferred} / ${file.size} bytes · ${file.state.name}',
              ),
            ),
          if (snapshot.status == TransferStatus.awaitingApproval)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _transfer?.approve(),
                  child: const Text('Approve and save'),
                ),
                OutlinedButton(
                  onPressed: () => _transfer?.reject(),
                  child: const Text('Decline'),
                ),
              ],
            ),
          if (!snapshot.finished && snapshot.status != TransferStatus.idle)
            OutlinedButton(
              onPressed: () => _transfer?.stop(),
              child: const Text('Stop transfer'),
            ),
        ],
        if (_notice != null || _transfer?.message != null) ...[
          const SizedBox(height: 12),
          Text(
            _notice ?? _transfer!.message!,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _QueuedFile {
  const _QueuedFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.sending,
    required this.files,
    required this.destination,
    required this.onPickFiles,
    required this.onPickFolder,
  });

  final bool sending;
  final List<_QueuedFile> files;
  final String? destination;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          Icon(
            sending
                ? Icons.cloud_upload_outlined
                : Icons.cloud_download_outlined,
            size: 42,
            color: colors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            sending ? 'Files to send' : 'Incoming approval',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            sending
                ? (files.isEmpty
                      ? 'Choose files on this device. Nothing is sent until you start the transfer.'
                      : files.map((file) => file.name).join(', '))
                : (destination == null
                      ? 'Choose a folder. Files are written only after you approve an offer.'
                      : 'Folder ready. Files are written only after you approve an offer.'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: sending ? onPickFiles : onPickFolder,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(sending ? 'Select files' : 'Choose folder'),
          ),
        ],
      ),
    );
  }
}
