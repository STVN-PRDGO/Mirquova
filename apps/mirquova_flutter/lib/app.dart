import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'adapters/auto_update.dart';
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
import 'core/transfer_state.dart';
import 'features/cast/cast_page.dart';
import 'features/home/home_page.dart';
import 'features/nearby/nearby_page.dart';
import 'features/pairing/pairing_page.dart';
import 'features/player/player_page.dart';
import 'features/remote/remote_page.dart';
import 'features/settings/settings_page.dart';
import 'features/transfer/incoming_transfer.dart';
import 'features/transfer/transfer_page.dart';
import 'shell/app_section.dart';
import 'shell/app_shell.dart';
import 'theme.dart';
import 'ui/launch_intro.dart';

class MirquovaApp extends StatefulWidget {
  const MirquovaApp({
    super.key,
    required this.discovery,
    this.appPlatform = const NativeAppPlatform(),
    this.updateSource,
    this.packageUpdates,
    this.autoUpdate,
    this.enableTransfer = true,
    this.showIntro = true,
  });

  final DiscoveryPort discovery;
  final AppPlatform appPlatform;
  final UpdateSource? updateSource;
  final PackageUpdates? packageUpdates;
  final AutoUpdate Function(PackageUpdates packages)? autoUpdate;

  /// Starts the background receiver at launch. Widget tests turn it off.
  final bool enableTransfer;

  final bool showIntro;

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
  late final AutoUpdate _autoUpdate;
  PairingController? _pairing;
  TransferService? _transfer;
  bool _incomingOpen = false;
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _playback = LocalPlayback();

  @override
  void initState() {
    super.initState();
    _packages = widget.packageUpdates ?? PackageUpdates();
    _autoUpdate =
        (widget.autoUpdate?.call(_packages) ??
              AutoUpdate(
                settings: FlutterPairingSecretStore(),
                packages: _packages,
              ))
          ..beforeInstall = _announceInstall;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadInstalledVersion());
    if (widget.enableTransfer) _startTransfer();
  }

  bool _canInstallUpdate() {
    final transfer = _transfer;
    final transferring =
        transfer != null &&
        (transfer.sending ||
            transfer.incomingNeedsAnswer ||
            transfer.incoming.status == TransferStatus.transferring);
    return WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed &&
        !transferring;
  }

  void _runAutoUpdate({bool force = false}) {
    final updates = _updates;
    if (updates == null) return;
    unawaited(
      _autoUpdate.run(updates, canInstall: _canInstallUpdate, force: force),
    );
  }

  Future<void> _announceInstall() async {
    final version = _updates?.release?.version;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          Platform.isWindows
              ? 'Installing Mirquova ${version ?? 'update'}. It restarts in a moment.'
              : 'Mirquova ${version ?? 'update'} is ready. Confirm the install.',
        ),
      ),
    );
    if (Platform.isWindows) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _setAutoUpdate(bool value) async {
    await _autoUpdate.setEnabled(value);
    if (value) _runAutoUpdate(force: true);
  }

  void _startTransfer() {
    try {
      final pairingStore = FlutterPairingSecretStore();
      _transfer = TransferService(
        identities: PairingIdentityRepository(
          api: FfiPairingIdentityApi(),
          store: pairingStore,
        ),
        trustedPeers: PairingTrustRepository(store: pairingStore),
        settings: pairingStore,
        discovery: widget.discovery,
      )..addListener(_onTransfer);
      unawaited(_transfer!.startReceiving());
    } on Object {
      _transfer = null;
    }
  }

  void _onTransfer() {
    final transfer = _transfer;
    if (transfer == null || !mounted) return;
    final context = _navigator.currentContext;
    if (transfer.incomingNeedsAnswer && !_incomingOpen && context != null) {
      _incomingOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => IncomingTransferDialog(service: transfer),
        ).whenComplete(() => _incomingOpen = false),
      );
    }
    final result = transfer.takeLastIncoming();
    if (result != null) {
      _messenger.currentState?.showSnackBar(
        SnackBar(content: Text(incomingResultMessage(result))),
      );
    }
    if (_autoUpdate.installPending) {
      unawaited(_autoUpdate.installIfPending(_canInstallUpdate));
    }
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
    await _autoUpdate.load();
    if (mounted) _runAutoUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_transfer?.startReceiving());
      if (_autoUpdate.installPending) {
        unawaited(_autoUpdate.installIfPending(_canInstallUpdate));
      } else {
        _runAutoUpdate();
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // A minimized desktop window keeps receiving; phones and TVs stop
      // listening once Mirquova leaves the screen.
      final keepReceiving =
          state == AppLifecycleState.hidden &&
          !(Platform.isAndroid || Platform.isIOS) &&
          (_transfer?.receiving ?? false);
      widget.discovery.stop();
      if (!keepReceiving) {
        widget.discovery.hide();
        _transfer?.pauseReceiving();
      }
      _pairing?.stop();
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
    _autoUpdate.dispose();
    _packages.dispose();
    _pairing?.dispose();
    _transfer?.removeListener(_onTransfer);
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
    AppSection.transfer => TransferPage(
      service: _transfer,
      onOpenPair: () => _open(AppSection.pair),
    ),
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
      autoUpdate: _autoUpdate,
      onAutoUpdateChanged: _setAutoUpdate,
      onOpenDevices: () => _open(AppSection.devices),
      onOpenPair: () => _open(AppSection.pair),
    ),
  };

  Widget _pairingPage() {
    try {
      return PairingPage(
        controller: _pairingController(),
        discovery: widget.discovery,
        onTrustChanged: () => unawaited(_transfer?.reloadPeers()),
        onOpenTransfer: () => _open(AppSection.transfer),
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
    navigatorKey: _navigator,
    scaffoldMessengerKey: _messenger,
    title: 'Mirquova',
    debugShowCheckedModeBanner: false,
    theme: mirquovaTheme(Brightness.light),
    darkTheme: mirquovaTheme(Brightness.dark),
    themeMode: _theme,
    builder: (context, child) => widget.showIntro
        ? LaunchIntro(child: child ?? const SizedBox.shrink())
        : child ?? const SizedBox.shrink(),
    home: AppShell(section: _section, onSelect: _open, child: _page()),
  );
}
