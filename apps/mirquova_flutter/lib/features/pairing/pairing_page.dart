import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr/qr.dart';

import '../../adapters/pairing_transport.dart';
import '../../adapters/pairing_identity.dart';
import '../../core/pairing_invitation.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, required this.controller});
  final PairingController controller;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> with WidgetsBindingObserver {
  final _hostAlias = TextEditingController(text: Platform.localHostname);
  final _joinAlias = TextEditingController(text: Platform.localHostname);
  final _payload = TextEditingController();
  String? _address;
  List<String> _addresses = const [];
  String? _hostPayload;
  String? _hostFingerprint;
  bool _hostInvitationCopied = false;
  String? _error;
  PairingInvitation? _invitation;
  bool _fingerprintConfirmed = false;
  bool _busy = false;
  bool _scannerOpen = false;
  Future<List<TrustedPeer>>? _trustedList;
  Timer? _invitationExpiry;
  Timer? _joinInvitationExpiry;

  bool get _qrScannerAvailable =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

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
      final values = await widget.controller.localPrivateIpv4Addresses();
      if (mounted) {
        setState(() {
          _addresses = values;
          _address = values.firstOrNull;
        });
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
      _invitationExpiry?.cancel();
      _hostPayload = null;
      _hostFingerprint = null;
      _hostInvitationCopied = false;
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
    _invitationExpiry?.cancel();
    _clearInvitation();
    _hostAlias.dispose();
    _joinAlias.dispose();
    _payload.dispose();
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
    _invitationExpiry?.cancel();
    _invitationExpiry = null;
    _hostPayload = null;
    _hostFingerprint = null;
    _hostInvitationCopied = false;
    _clearInvitation();
    _payload.clear();
    widget.controller.stop();
    if (mounted && state != AppLifecycleState.detached) {
      setState(() => _error = 'Pairing stopped while Mirquova was hidden.');
    }
  }

  void _clearInvitation() {
    _joinInvitationExpiry?.cancel();
    _joinInvitationExpiry = null;
    _invitation?.dispose();
    _invitation = null;
    _fingerprintConfirmed = false;
  }

  Future<void> _host() async {
    if (_address == null) {
      setState(() => _error = 'No private IPv4 address is available.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await widget.controller.startHosting(
        localIpv4: _address!,
        hostAlias: _hostAlias.text.trim(),
      );
      final hostInvitation = PairingInvitation.parse(payload);
      final fingerprint = hostInvitation.fingerprintSha256;
      hostInvitation.dispose();
      if (mounted) {
        setState(() {
          _hostPayload = payload;
          _hostFingerprint = fingerprint;
          _hostInvitationCopied = false;
        });
        _invitationExpiry?.cancel();
        _invitationExpiry = Timer(const Duration(minutes: 2), () {
          if (!mounted) return;
          widget.controller.stop();
          setState(() {
            _hostPayload = null;
            _hostFingerprint = null;
            _hostInvitationCopied = false;
          });
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _parseInvitation(String payload) {
    _clearInvitation();
    try {
      final value = PairingInvitation.parse(payload.trim());
      _payload.clear();
      setState(() {
        _invitation = value;
        _fingerprintConfirmed = false;
        _error = null;
        _scannerOpen = false;
      });
      _joinInvitationExpiry = Timer(Duration(seconds: value.ttlSeconds), () {
        if (!mounted || !identical(_invitation, value)) return;
        setState(() {
          _clearInvitation();
          _payload.clear();
          _error = 'Invitation expired. Read a current invitation to pair.';
        });
      });
    } on Object catch (error) {
      setState(() => _error = 'Invitation could not be read: $error');
    }
  }

  Future<void> _join() async {
    final invitation = _invitation;
    if (invitation == null || !_fingerprintConfirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.join(
        invitation,
        alias: _joinAlias.text.trim(),
        fingerprintConfirmed: true,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      invitation.dispose();
      if (mounted) {
        setState(() {
          _clearInvitation();
        });
      }
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

  Future<void> _copyHostInvitation(String payload) async {
    try {
      await Clipboard.setData(ClipboardData(text: payload));
      if (!mounted) return;
      setState(() => _hostInvitationCopied = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Invitation copied. Treat it as a secret; it expires in two minutes.',
            ),
          ),
        );
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not copy the invitation. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.snapshot;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
            'Connect with an invitation. You choose who to trust.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Compare fingerprints through a separate trusted channel before pairing.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final host = _hostCard(context);
              final join = _joinCard(context);
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [host, const SizedBox(height: 16), join],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: host),
                  const SizedBox(width: 16),
                  Expanded(child: join),
                ],
              );
            },
          ),
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
  }

  Widget _hostCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            icon: Icons.qr_code_2,
            title: 'Invite a device',
            subtitle: 'Create an invitation on this device.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _hostAlias,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'This device name',
              prefixIcon: Icon(Icons.devices_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _address,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'LAN address'),
            items: [
              for (final address in _addresses)
                DropdownMenuItem(value: address, child: Text(address)),
            ],
            onChanged: (value) => setState(() => _address = value),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _host,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Create invitation'),
            ),
          ),
          if (_hostPayload case final payload?) ...[
            const SizedBox(height: 16),
            Center(child: _QrCode(payload: payload)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _copyHostInvitation(payload),
              icon: Icon(
                _hostInvitationCopied ? Icons.check : Icons.copy_outlined,
              ),
              label: Text(
                _hostInvitationCopied
                    ? 'Copy invitation again'
                    : 'Copy invitation',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This one-use invitation expires after two minutes. Share it only with the device you intend to pair. The host still has to approve the request.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Your SHA-256 fingerprint (compare with the other device):',
            ),
            SelectableText(_groupFingerprint(_hostFingerprint ?? '')),
            OutlinedButton.icon(
              onPressed: () {
                _invitationExpiry?.cancel();
                widget.controller.stop();
                setState(() {
                  _hostPayload = null;
                  _hostFingerprint = null;
                  _hostInvitationCopied = false;
                });
              },
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop invitation'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _joinCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            icon: Icons.add_link_outlined,
            title: 'Join a device',
            subtitle: 'Use an invitation from the other device.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _joinAlias,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Name shown to the host',
              prefixIcon: Icon(Icons.devices_outlined),
            ),
          ),
          const SizedBox(height: 20),
          if (_qrScannerAvailable && _invitation == null && !_scannerOpen)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _scannerOpen = true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Scan QR code'),
              ),
            ),
          if (_qrScannerAvailable && _invitation == null && !_scannerOpen) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or paste invitation',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (_scannerOpen)
            SizedBox(
              height: 240,
              child: MobileScanner(
                onDetect: (capture) {
                  final raw = capture.barcodes.firstOrNull?.rawValue;
                  if (raw != null) _parseInvitation(raw);
                },
              ),
            ),
          TextField(
            controller: _payload,
            enabled: !_busy,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Invitation text',
              hintText: 'Paste the invitation shared with you',
              alignLabelWithHint: true,
            ),
            onChanged: (value) {
              if (_invitation != null) {
                setState(_clearInvitation);
              }
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _parseInvitation(_payload.text),
              icon: const Icon(Icons.link),
              label: const Text('Read invitation'),
            ),
          ),
          if (_invitation case final invitation?) ...[
            const SizedBox(height: 12),
            Text(
              'Host fingerprint (SHA-256)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SelectableText(_groupFingerprint(invitation.fingerprintSha256)),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _fingerprintConfirmed,
              onChanged: (value) =>
                  setState(() => _fingerprintConfirmed = value ?? false),
              title: const Text(
                'I compared this fingerprint with the host through a trusted separate channel.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            FilledButton.icon(
              onPressed: _busy || !_fingerprintConfirmed ? null : _join,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Verify and request pairing'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _statusCard(PairingSnapshot snapshot) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (snapshot.status) {
            PairingStatus.waitingForPeer => 'Invitation is active',
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
            const Text(
              'The joining device completed certificate authentication. Compare its fingerprint through a trusted separate channel, and approve only if you initiated this request.',
            ),
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
          if (snapshot.errorCode != null) Text('Error: ${snapshot.errorCode}'),
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

class _QrCode extends StatelessWidget {
  const _QrCode({required this.payload});
  final String payload;
  @override
  Widget build(BuildContext context) {
    final code = QrCode(
      payload: QrPayload.fromString(payload),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    );
    final image = QrImage(code);
    return Semantics(
      label: 'Pairing invitation QR code',
      child: CustomPaint(
        size: const Size.square(220),
        painter: _QrPainter(image),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);
  final QrImage image;
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / (image.moduleCount + 8);
    final paint = Paint()..color = Colors.black;
    canvas.drawColor(Colors.white, BlendMode.src);
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (image.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(
              (col + 4) * cell,
              (row + 4) * cell,
              cell + .2,
              cell + .2,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}

String _groupFingerprint(String value) => [
  for (var i = 0; i < value.length; i += 4)
    value.substring(i, i + 4 > value.length ? value.length : i + 4),
].join(' ');
