import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';

import '../../adapters/pairing_transport.dart';
import '../../adapters/pairing_identity.dart';
import '../../core/discovery_port.dart';
import '../../core/pairing_invitation.dart';
import 'pairing_offer.dart';
import 'sonar_field.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({
    super.key,
    required this.controller,
    this.discovery,
    this.fetchOffer,
  });
  final PairingController controller;
  final DiscoveryPort? discovery;
  final Future<String> Function(List<String> addresses)? fetchOffer;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> with WidgetsBindingObserver {
  final _alias = TextEditingController(text: Platform.localHostname);
  String? _address;
  String? _error;
  bool _busy = false;
  bool _ready = false;
  String? _selectedPeerId;
  String? _connectHint;
  Future<List<TrustedPeer>>? _trustedList;
  PairingOffer? _offer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _trustedList = widget.controller.trustedPeers.list();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      final values = preferredLanAddresses(
        await widget.controller.localPrivateIpv4Addresses(),
      );
      if (mounted) {
        setState(() => _address = values.firstOrNull);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _changed() {
    if (!mounted) return;
    if ({
      PairingStatus.expired,
      PairingStatus.paired,
      PairingStatus.rejected,
      PairingStatus.stopped,
      PairingStatus.error,
    }.contains(widget.controller.snapshot.status)) {
      unawaited(_closeOffer());
      _ready = false;
    }
    if (widget.controller.snapshot.status == PairingStatus.paired) {
      _trustedList = widget.controller.trustedPeers.list();
    }
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    unawaited(_closeOffer());
    _alias.dispose();
    widget.controller.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!{
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    }.contains(state)) {
      return;
    }
    unawaited(_closeOffer());
    _ready = false;
    widget.controller.stop();
    if (mounted && state != AppLifecycleState.detached) {
      setState(() => _error = 'Pairing stopped while Mirquova was hidden.');
    }
  }

  Future<void> _closeOffer() async {
    final offer = _offer;
    _offer = null;
    if (offer != null) await offer.close();
  }

  Future<void> _readyForDevices() async {
    if (_address == null) {
      setState(() => _error = 'No private IPv4 address is available.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final discovery = widget.discovery;
      if (discovery != null) {
        await discovery.makeDiscoverable(_alias.text.trim());
      }
      final payload = await widget.controller.startHosting(
        localIpv4: _address!,
        port: mirquovaPairListenPort,
        hostAlias: _alias.text.trim(),
      );
      if (widget.fetchOffer == null) {
        final offer = _offer ?? await PairingOffer.start();
        offer.payload = payload;
        _offer = offer;
      }
      if (mounted) setState(() => _ready = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(PeerCandidate peer) async {
    setState(() {
      _selectedPeerId = peer.id;
      _connectHint = null;
      _error = null;
      _busy = true;
    });
    PairingInvitation? invitation;
    try {
      if (!_ready) await _readyForDevices();
      if (!mounted || _error != null) return;
      final payload = await (widget.fetchOffer ?? PairingOffer.fetch)(
        peer.addresses,
      );
      invitation = PairingInvitation.parse(payload);
      await _closeOffer();
      _ready = false;
      await widget.controller.join(
        invitation,
        alias: _alias.text.trim(),
        fingerprintConfirmed: true,
      );
      if (mounted) {
        setState(() => _connectHint = 'Waiting for ${peer.name} to approve.');
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not reach ${peer.name}. Press Scan on both devices, then tap the name again.',
        );
      }
    } finally {
      invitation?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recoverCorruptIdentity() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset this device identity?'),
        content: const SingleChildScrollView(
          child: Text(
            'The saved pairing identity is corrupt and cannot be used. Resetting deletes that saved identity and creates a new one the next time you pair. Devices that trusted the old identity may need to pair with this device again. Your trusted peer list is kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset identity and continue'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.resetCorruptIdentity();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PeerCandidate? get _selectedPeer {
    final peers = widget.discovery?.snapshot.peers ?? const <PeerCandidate>[];
    for (final peer in peers) {
      if (peer.id == _selectedPeerId) return peer;
    }
    return null;
  }

  void _selectPeer(PeerCandidate peer) {
    if (_busy) return;
    unawaited(_connect(peer));
  }

  @override
  Widget build(BuildContext context) {
    final discovery = widget.discovery;
    return ListenableBuilder(
      listenable: discovery ?? widget.controller,
      builder: (context, _) {
        final status = widget.controller.snapshot;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final reduce = MediaQuery.disableAnimationsOf(context);
        final scanning = discovery?.snapshot.status == DiscoveryStatus.scanning;
        final peers = discovery?.snapshot.peers ?? const <PeerCandidate>[];
        final selected = _selectedPeer;
        return Theme(
          data: theme.copyWith(
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              floatingLabelStyle: TextStyle(color: colors.primary),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pair devices',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Press Scan on both devices, then tap a name. The other device approves the request.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SonarField(
                    peers: peers,
                    scanning: scanning,
                    selectedId: selected?.id,
                    onSelect: _selectPeer,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  scanning
                      ? 'Scanning nearby devices'
                      : peers.isEmpty
                      ? 'No nearby devices yet'
                      : '${peers.length} nearby. None of these are connected.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                child: selected == null
                    ? const SizedBox(
                        key: ValueKey('none'),
                        width: double.infinity,
                      )
                    : _SelectedDevice(
                        key: ValueKey(selected.id),
                        name: selected.name,
                        hint: _connectHint,
                        busy: _busy,
                        onConnect: () => _selectPeer(selected),
                      ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () {
                            if (scanning || _ready) {
                              discovery?.stop();
                              discovery?.hide();
                              unawaited(_closeOffer());
                              widget.controller.stop();
                              setState(() => _ready = false);
                              return;
                            }
                            discovery?.start();
                            unawaited(_readyForDevices());
                          },
                    icon: Icon(
                      scanning || _ready
                          ? Icons.stop_outlined
                          : Icons.radar_outlined,
                    ),
                    label: Text(scanning || _ready ? 'Stop' : 'Scan'),
                  ),
                ],
              ),
              if (_ready) ...[
                const SizedBox(height: 12),
                const Text(
                  'This device is ready. Tap a name to connect. Approve the request on the other device.',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _errorBox(_error!),
                if (widget.controller.identityRecoveryRequired) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _recoverCorruptIdentity,
                    icon: const Icon(Icons.key_off_outlined),
                    label: const Text('Reset corrupt pairing identity'),
                  ),
                ],
              ],
              if (status.status != PairingStatus.idle) ...[
                const SizedBox(height: 18),
                _statusCard(status),
              ],
              const SizedBox(height: 18),
              _trustedDevicesCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _statusCard(PairingSnapshot snapshot) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (snapshot.status) {
            PairingStatus.waitingForPeer => 'Waiting for the other device',
            PairingStatus.connecting => 'Connecting securely…',
            PairingStatus.awaitingApproval => 'Pairing request',
            PairingStatus.paired => 'Device paired',
            PairingStatus.rejected => 'Request rejected',
            PairingStatus.expired => 'Invitation expired',
            PairingStatus.stopped => 'Pairing stopped',
            PairingStatus.error => 'Pairing failed',
            PairingStatus.idle => '',
          }, style: Theme.of(context).textTheme.titleLarge),
          if (snapshot.peerAlias != null) ...[
            const SizedBox(height: 8),
            Text('Device name: ${snapshot.peerAlias}'),
          ],
          if (snapshot.status == PairingStatus.paired) ...[
            const SizedBox(height: 8),
            Text(
              widget.controller.savingTrust
                  ? 'Saving the verified device…'
                  : widget.controller.trustSaveFailed
                  ? 'The connection succeeded, but saving this trusted device failed.'
                  : 'Verified device saved on this device.',
            ),
          ],
          if (snapshot.awaitingApproval) ...[
            const SizedBox(height: 8),
            const Text('Approve only if you asked this device to connect.'),
            if (snapshot.peerCaCertificateDer case final certificate?) ...[
              const SizedBox(height: 6),
              const Text('Joining device fingerprint (SHA-256)'),
              SelectableText(
                _groupFingerprint(sha256.convert(certificate).toString()),
              ),
            ],
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: widget.controller.approve,
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: widget.controller.reject,
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
          if (snapshot.errorCode case final code?)
            Text(_plainPairingError(code)),
          if (snapshot.status == PairingStatus.connecting)
            OutlinedButton(
              onPressed: widget.controller.stop,
              child: const Text('Cancel pairing'),
            ),
          if (widget.controller.trustSaveFailed)
            TextButton(
              onPressed: widget.controller.retryTrustSave,
              child: const Text('Retry saving trusted device'),
            ),
        ],
      ),
    ),
  );

  Widget _errorBox(String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Semantics(
      liveRegion: true,
      child: Text(
        value,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );

  Widget _trustedDevicesCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            icon: Icons.verified_user_outlined,
            title: 'Trusted devices',
            subtitle: 'Devices you have verified on this installation.',
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<TrustedPeer>>(
            future: _trustedList,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Trusted-device storage is unavailable or corrupt. Pairing fails closed when trust cannot be saved.',
                );
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              if (snapshot.data!.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'No devices are trusted yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final peer in snapshot.data!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(peer.alias),
                      subtitle: SelectableText(
                        _groupFingerprint(peer.fingerprintSha256),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await widget.controller.trustedPeers.revoke(
                            peer.fingerprintSha256,
                          );
                          if (mounted) {
                            setState(
                              () => _trustedList = widget
                                  .controller
                                  .trustedPeers
                                  .list(),
                            );
                          }
                        },
                        child: const Text('Revoke'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _SelectedDevice extends StatelessWidget {
  const _SelectedDevice({
    super.key,
    required this.name,
    required this.hint,
    required this.busy,
    required this.onConnect,
  });

  final String name;
  final String? hint;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect to $name',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Tap connects. The other device still has to approve.',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(hint!, style: TextStyle(color: colors.onSurface)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : onConnect,
                child: const Text('Connect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _plainPairingError(String code) => switch (code) {
  'bootstrap_connect' || 'mutual_connect' => 'Could not reach the other device. Press Scan on both devices, then tap the name again.',
  _ => 'Pairing failed ($code).',
};

String _groupFingerprint(String value) => [
  for (var i = 0; i < value.length; i += 4)
    value.substring(i, i + 4 > value.length ? value.length : i + 4),
].join(' ');
