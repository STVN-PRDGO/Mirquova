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
  final _host = TextEditingController();
  final _port = TextEditingController();
  bool _send = true;
  final _files = <_QueuedFile>[];
  String? _destination;
  String? _localAddress;
  List<String> _localAddresses = const [];
  String? _notice;
  TransferController? _transfer;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      await _readAddresses();
    } on Object {
      if (mounted) setState(() => _localAddresses = const []);
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
    final sorted = addresses.toList()..sort();
    setState(() {
      _localAddresses = sorted;
      _localAddress ??= sorted.isEmpty ? null : sorted.first;
    });
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
    _host.dispose();
    _port.dispose();
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
    final endpoint = ManualEndpoint.parse(_host.text, _port.text);
    if (endpoint == null || _files.isEmpty) {
      setState(() {
        _notice = 'Enter the receiver’s private IPv4 address and port, and choose a file.';
      });
      return;
    }
    List<TrustedPeer> peers;
    try {
      peers = await controller.trustedPeers.list();
    } on Object {
      if (!mounted) return;
      setState(() => _notice = 'Trusted devices could not be read.');
      return;
    }
    if (!mounted) return;
    if (peers.isEmpty) {
      setState(() => _notice = 'Pair a device before sending files.');
      return;
    }
    final peer = peers.length == 1 ? peers.single : await _choosePeer(peers);
    if (!mounted || peer == null) return;
    setState(() {
      _attach(controller);
      _notice = null;
    });
    await controller.send(
      peer: peer,
      host: endpoint.address,
      port: endpoint.port,
      paths: [for (final file in _files) file.path],
    );
  }

  Future<TrustedPeer?> _choosePeer(List<TrustedPeer> peers) {
    return showDialog<TrustedPeer>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Send to a paired device'),
        children: [
          for (final peer in peers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, peer),
              child: Text(peer.alias),
            ),
        ],
      ),
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
    if (address == null || destination == null) {
      setState(() {
        _notice = 'Choose a private address and a folder before receiving.';
      });
      return;
    }
    setState(() {
      _attach(controller);
      _notice = null;
    });
    await controller.receive(localIpv4: address, destination: destination);
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
        if (_send) ...[
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'Receiver private IPv4',
              helperText: 'Use the address shown on the paired device.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Receiver port'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _files.isEmpty ? null : _startSend,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send to paired device'),
          ),
        ] else ...[
          DropdownButtonFormField<String>(
            key: ValueKey(_localAddress),
            initialValue: _localAddresses.contains(_localAddress)
                ? _localAddress
                : null,
            decoration: const InputDecoration(
              labelText: 'This device’s private address',
            ),
            items: [
              for (final address in _localAddresses)
                DropdownMenuItem(value: address, child: Text(address)),
            ],
            onChanged: _localAddresses.isEmpty
                ? null
                : (value) => setState(() => _localAddress = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _destination == null ? null : _startReceive,
            icon: const Icon(Icons.downloading_outlined),
            label: const Text('Wait for a paired device'),
          ),
        ],
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          Text(transferStatusMessage(snapshot)),
          if (snapshot.endpoint != null) ...[
            const SizedBox(height: 8),
            SelectableText(snapshot.endpoint!),
          ],
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
                      : destination!),
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
