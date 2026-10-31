import 'dart:async';

import 'package:flutter/material.dart';

import 'adapters/github_updates.dart';
import 'adapters/native_app_platform.dart';
import 'adapters/native_transfer.dart';
import 'adapters/package_updates.dart';
import 'adapters/pairing_identity.dart';
import 'adapters/pairing_transport.dart';
import 'core/app_platform.dart';
import 'core/app_updates.dart';
import 'core/discovery_port.dart';
import 'core/playback.dart';
import 'features/cast/cast_page.dart';
import 'features/home/home_page.dart';
import 'features/nearby/nearby_page.dart';
import 'features/pairing/pairing_page.dart';
import 'features/player/player_page.dart';
import 'features/remote/remote_page.dart';
import 'features/settings/settings_page.dart';
import 'features/transfer/transfer_page.dart';
import 'shell/app_section.dart';
import 'shell/app_shell.dart';
import 'theme.dart';

class MirquovaApp extends StatefulWidget {
  const MirquovaApp({
    super.key,
    required this.discovery,
    this.appPlatform = const NativeAppPlatform(),
    this.updateSource,
    this.packageUpdates,
  });

  final DiscoveryPort discovery;
  final AppPlatform appPlatform;
  final UpdateSource? updateSource;
  final PackageUpdates? packageUpdates;

  @override
  State<MirquovaApp> createState() => _MirquovaAppState();
}

class _MirquovaAppState extends State<MirquovaApp> with WidgetsBindingObserver {
  ThemeMode _theme = ThemeMode.system;
  AppSection _section = AppSection.home;
  final _manualEndpoints = <ManualEndpoint>[];
  UpdateController? _updates;
  bool _readingVersion = true;
  late final PackageUpdates _packages;
  PairingController? _pairing;
  TransferController? _transfer;
  final _playback = LocalPlayback();

  @override
  void initState() {
    super.initState();
    _packages = widget.packageUpdates ?? PackageUpdates();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadInstalledVersion());
  }

  Future<void> _loadInstalledVersion() async {
    setState(() => _readingVersion = true);
    UpdateController? updates;
    try {
      final info = await widget.appPlatform.readBuildInfo();
      updates = UpdateController(
        currentVersion: AppVersion.parse(
          info.version,
          buildNumber: info.buildNumber,
        ),
        source: widget.updateSource ?? GitHubUpdateSource(),
      );
    } on Exception {
      // An unknown installed version must never be treated as an older build.
    }
    if (!mounted) {
      updates?.dispose();
      return;
    }
    setState(() {
      _updates?.dispose();
      _updates = updates;
      _readingVersion = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.discovery.stop();
      widget.discovery.hide();
      _pairing?.stop();
      _transfer?.stop();
      unawaited(_playback.stop());
      _updates?.cancel();
      _packages.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.discovery.dispose();
    _updates?.dispose();
    _packages.dispose();
    _pairing?.dispose();
    _transfer?.dispose();
    _playback.dispose();
    super.dispose();
  }

  void _open(AppSection section) => setState(() => _section = section);

  Widget _page() => switch (_section) {
    AppSection.home => HomePage(
      discovery: widget.discovery,
      manualEndpoints: _manualEndpoints,
      onOpen: _open,
    ),
    AppSection.transfer => TransferPage(ensureTransfer: _ensureTransfer),
    AppSection.cast => CastPage(
      discovery: widget.discovery,
      onOpenDevices: () => _open(AppSection.devices),
      onOpenRemote: () => _open(AppSection.remote),
    ),
    AppSection.player => PlayerPage(playback: _playback),
    AppSection.devices => NearbyPage(
      discovery: widget.discovery,
      manualEndpoints: _manualEndpoints,
      onAdd: (endpoint) => setState(() {
        if (!_manualEndpoints.any((item) => item.key == endpoint.key)) {
          _manualEndpoints.add(endpoint);
        }
      }),
      onRemove: (endpoint) => setState(() => _manualEndpoints.remove(endpoint)),
    ),
    AppSection.pair => _pairingPage(),
    AppSection.remote => RemotePage(
      onBack: () => _open(AppSection.cast),
      onHome: () => _open(AppSection.home),
      playback: _playback,
    ),
    AppSection.settings => SettingsPage(
      theme: _theme,
      onThemeChanged: (value) => setState(() => _theme = value),
      updates: _updates,
      readingVersion: _readingVersion,
      onRetryVersion: _loadInstalledVersion,
      packages: _packages,
      onOpenDevices: () => _open(AppSection.devices),
      onOpenPair: () => _open(AppSection.pair),
    ),
  };

  Widget _pairingPage() {
    try {
      return PairingPage(
        controller: _pairingController(),
        discovery: widget.discovery,
      );
    } on Object catch (error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pair devices',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          const Text(
            'Native core setup needed. Pairing requires the bundled Mirquova core.',
          ),
          const SizedBox(height: 8),
          SelectableText('$error'),
        ],
      );
    }
  }

  Future<TransferController?> _ensureTransfer() async {
    final existing = _transfer;
    if (existing != null) return existing;
    try {
      final pairingStore = FlutterPairingSecretStore();
      final controller = TransferController(
        identities: PairingIdentityRepository(
          api: FfiPairingIdentityApi(),
          store: pairingStore,
        ),
        trustedPeers: PairingTrustRepository(store: pairingStore),
      );
      if (!mounted) {
        controller.dispose();
        return null;
      }
      setState(() => _transfer = controller);
      return controller;
    } on Object {
      return null;
    }
  }

  PairingController _pairingController() {
    return _pairing ??= () {
      final pairingStore = FlutterPairingSecretStore();
      return PairingController(
        identities: PairingIdentityRepository(
          api: FfiPairingIdentityApi(),
          store: pairingStore,
        ),
        trustedPeers: PairingTrustRepository(store: pairingStore),
      );
    }();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mirquova',
    debugShowCheckedModeBanner: false,
    theme: mirquovaTheme(Brightness.light),
    darkTheme: mirquovaTheme(Brightness.dark),
    themeMode: _theme,
    home: AppShell(section: _section, onSelect: _open, child: _page()),
  );
}
