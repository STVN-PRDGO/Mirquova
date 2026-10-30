import 'package:flutter/material.dart';

import '../ui/mirquova_mark.dart';
import 'app_section.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.onSelect,
    required this.child,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;
  final Widget child;

  static const _nav = <AppSection>[
    AppSection.home,
    AppSection.transfer,
    AppSection.cast,
    AppSection.player,
    AppSection.devices,
    AppSection.pair,
    AppSection.settings,
  ];

  static const _phoneNav = <AppSection>[
    AppSection.home,
    AppSection.transfer,
    AppSection.cast,
    AppSection.player,
    AppSection.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final largeText = scale > 1.3;
        final sidebar =
            constraints.maxWidth >= 900 &&
            constraints.maxHeight >= 640 &&
            !largeText;
        final drawer =
            constraints.maxWidth < 700 &&
            (largeText || constraints.maxHeight < 520);
        final bottomNav = !sidebar && !drawer;
        final highlight = switch (section) {
          AppSection.remote => AppSection.cast,
          _ => section,
        };
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: sidebar
              ? null
              : AppBar(
                  title: const _BrandLockup(compact: true),
                  automaticallyImplyLeading: drawer,
                ),
          drawer: drawer
              ? Drawer(
                  child: SafeArea(
                    child: ListView(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: _BrandLockup(),
                        ),
                        for (final item in _nav)
                          _DrawerRow(
                            section: item,
                            selected: highlight == item,
                            onSelect: onSelect,
                          ),
                      ],
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            child: sidebar
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Sidebar(section: highlight, onSelect: onSelect),
                      Expanded(child: _PageFrame(child: child)),
                    ],
                  )
                : _PageFrame(child: child),
          ),
          bottomNavigationBar: bottomNav
              ? _PhoneBar(section: highlight, onSelect: onSelect)
              : null,
        );
      },
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return SingleChildScrollView(
      key: ValueKey(child.runtimeType),
      padding: EdgeInsets.all(wide ? 28 : 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: child,
        ),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MirquovaMark(size: compact ? 28 : 36),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mirquova',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (!compact)
                Text(
                  'Every screen. One connection.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.section, required this.onSelect});

  final AppSection section;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final main = AppShell._nav.where((item) => item != AppSection.settings);
    return SizedBox(
      width: 236,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(right: BorderSide(color: colors.outline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 22, 16, 18),
              child: _BrandLockup(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final item in main)
                    _NavTile(
                      section: item,
                      selected: section == item,
                      onSelect: onSelect,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: _NavTile(
                section: AppSection.settings,
                selected: section == AppSection.settings,
                onSelect: onSelect,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.section,
    required this.selected,
    required this.onSelect,
  });

  final AppSection section;
  final bool selected;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? colors.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(section),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(_icon(section), size: 20, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        section.label,
                        style: TextStyle(
                          color: selected
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.section,
    required this.selected,
    required this.onSelect,
  });

  final AppSection section;
  final bool selected;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon(section)),
      title: Text(section.label),
      selected: selected,
      minTileHeight: 48,
      onTap: () {
        onSelect(section);
        Navigator.pop(context);
      },
    );
  }
}

class _PhoneBar extends StatelessWidget {
  const _PhoneBar({required this.section, required this.onSelect});

  final AppSection section;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outline)),
          ),
          child: Row(
            children: [
              for (final item in AppShell._phoneNav)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: section == item,
                    child: InkWell(
                      onTap: () => onSelect(item),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _icon(item),
                                size: 22,
                                color: section == item
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item == AppSection.player
                                    ? 'Player'
                                    : item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: section == item
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _icon(AppSection section) => switch (section) {
  AppSection.home => Icons.home_outlined,
  AppSection.transfer => Icons.swap_horiz,
  AppSection.cast => Icons.cast_outlined,
  AppSection.player => Icons.play_circle_outline,
  AppSection.devices => Icons.devices_outlined,
  AppSection.pair => Icons.verified_user_outlined,
  AppSection.remote => Icons.settings_remote_outlined,
  AppSection.settings => Icons.settings_outlined,
};
