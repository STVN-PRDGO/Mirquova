import 'package:flutter/material.dart';

import '../../adapters/package_updates.dart';
import '../../core/app_updates.dart';

class SystemUpdatesCard extends StatefulWidget {
  const SystemUpdatesCard({
    super.key,
    required this.updates,
    required this.readingVersion,
    required this.onRetryVersion,
    required this.packages,
  });

  final UpdateController? updates;
  final bool readingVersion;
  final VoidCallback onRetryVersion;
  final PackageUpdates packages;

  @override
  State<SystemUpdatesCard> createState() => _SystemUpdatesCardState();
}

class _SystemUpdatesCardState extends State<SystemUpdatesCard> {
  bool _askingPermission = false;

  Future<void> _check(UpdateController updates) async {
    setState(() {
      _askingPermission = true;
    });
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check GitHub for updates?'),
        content: const SingleChildScrollView(
          child: Text(
            'This check contacts api.github.com for Mirquova release information. GitHub receives your IP address and standard connection information. Your files and nearby-device information are not sent. Checks never run automatically.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check now'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _askingPermission = false);
    if (allowed == true) await updates.check();
  }

  @override
  Widget build(BuildContext context) {
    final updates = widget.updates;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
          listenable: Listenable.merge([updates, widget.packages]),
          builder: (context, _) => _content(context, updates),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, UpdateController? updates) {
    final status = updates?.status;
    final checking = status == UpdateStatus.checking;
    final release = status == UpdateStatus.available ? updates?.release : null;
    final lastChecked = updates?.lastChecked;
    final localizations = MaterialLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final statusText = switch (status) {
      UpdateStatus.idle => 'Ready to check',
      UpdateStatus.checking => 'Checking for updates...',
      UpdateStatus.available => 'New release available',
      UpdateStatus.upToDate => 'No newer version available',
      UpdateStatus.noRelease => 'No public release available',
      UpdateStatus.error => 'Could not check for updates',
      null =>
        widget.readingVersion
            ? 'Preparing update checks'
            : 'Read the installed version before checking for updates.',
    };
    final statusIcon = switch (status) {
      UpdateStatus.checking => Icons.sync,
      UpdateStatus.available => Icons.system_update_alt,
      UpdateStatus.upToDate => Icons.check_circle_outline,
      UpdateStatus.noRelease => Icons.public_off,
      UpdateStatus.error => Icons.error_outline,
      _ => Icons.info_outline,
    };
    final statusColor = switch (status) {
      UpdateStatus.available || UpdateStatus.upToDate => colors.primary,
      UpdateStatus.error => colors.error,
      _ => colors.onSurfaceVariant,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('System updates', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Keep your Mirquova app up to date.'),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(statusIcon, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        statusText,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.phone_android_outlined,
                    label: updates != null
                        ? 'Installed version: ${updates.currentVersion}'
                        : widget.readingVersion
                        ? 'Reading installed version...'
                        : 'Installed version unavailable',
                  ),
                  if (lastChecked != null)
                    _InfoChip(
                      icon: Icons.schedule_outlined,
                      label:
                          'Checked ${localizations.formatShortDate(lastChecked.toLocal())}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastChecked.toLocal()))}',
                    ),
                ],
              ),
              if (updates?.message != null) ...[
                const SizedBox(height: 12),
                Text(updates!.message!),
              ],
              if (checking && !MediaQuery.disableAnimationsOf(context)) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  semanticsLabel: 'Checking for updates',
                ),
              ],
            ],
          ),
        ),
        if (release != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.new_releases_outlined,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Published version: ${release.version}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A newer version is ready',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
                if (release.notes.isNotEmpty)
                  Material(
                    color: Colors.transparent,
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('What’s new'),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(release.notes),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(_installationHint(widget.packages.platform.packageName)),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed:
                  updates == null ||
                      checking ||
                      _askingPermission ||
                      widget.packages.busy
                  ? null
                  : () => _check(updates),
              icon: const Icon(Icons.system_update_outlined),
              label: const Text('Check for updates'),
            ),
            if (checking)
              OutlinedButton(
                onPressed: updates!.cancel,
                child: const Text('Cancel check'),
              ),
            if (updates == null && !widget.readingVersion)
              OutlinedButton(
                onPressed: widget.onRetryVersion,
                child: const Text('Retry version lookup'),
              ),
          ],
        ),
        if (release != null) ...[
          const SizedBox(height: 20),
          _PackagePanel(release: release, packages: widget.packages),
        ],
        const SizedBox(height: 16),
        const Text(
          'Checks and downloads are optional. No browser is required. Your system handles the final installation.',
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final labelWidth = constraints.maxWidth.isFinite
          ? (constraints.maxWidth - 48).clamp(80.0, constraints.maxWidth)
          : 240.0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: labelWidth),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PackagePanel extends StatelessWidget {
  const _PackagePanel({required this.release, required this.packages});
  final UpdateRelease release;
  final PackageUpdates packages;

  String _formatBytes(int value) {
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(0)} KB';
    }
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _download(BuildContext context, UpdateAsset asset) async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download this update?'),
        content: Text(
          'Download ${(asset.size / (1024 * 1024)).toStringAsFixed(1)} MB from GitHub and its release storage. The download is checked against its published SHA-256 digest. Installation starts only when you open the completed package.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download now'),
          ),
        ],
      ),
    );
    if (allowed == true && context.mounted) await packages.download(asset);
  }

  @override
  Widget build(BuildContext context) {
    final asset = packages.compatibleAsset(release);
    if (asset == null) {
      return Text(
        packages.platform.packageName == null
            ? 'In-app package updates are unavailable for this platform. Use your installation provider to update.'
            : 'This release has no compatible package with a published integrity digest. Try checking again after a package is published.',
      );
    }
    final current = packages.asset?.url == asset.url;
    final ready = current && packages.status == PackageStatus.ready;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Update download',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${(asset.size / (1024 * 1024)).toStringAsFixed(1)} MB • SHA-256 checked',
          ),
          if (current && packages.message != null) ...[
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(packages.message!)),
          ],
          if (current && packages.status == PackageStatus.downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: packages.progress,
              semanticsLabel: 'Downloading update',
              semanticsValue:
                  '${((packages.progress ?? 0) * 100).floor()}% downloaded',
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                '${_formatBytes(packages.received)} of ${_formatBytes(asset.size)} downloaded '
                '(${((packages.progress ?? 0) * 100).floor()}%)',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: packages.busy
                    ? null
                    : () => _download(context, asset),
                icon: const Icon(Icons.download_outlined),
                label: Text(ready ? 'Download again' : 'Download update'),
              ),
              if (packages.status == PackageStatus.downloading)
                OutlinedButton(
                  onPressed: packages.cancel,
                  child: const Text('Cancel download'),
                ),
              if (ready ||
                  (current && packages.status == PackageStatus.opening))
                OutlinedButton.icon(
                  onPressed: packages.busy ? null : packages.open,
                  icon: const Icon(Icons.install_desktop_outlined),
                  label: Text(
                    packages.status == PackageStatus.opening
                        ? 'Opening package...'
                        : 'Open downloaded update',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _installationHint(String? packageName) {
  if (packageName?.endsWith('.apk') ?? false) {
    return 'After the download finishes, open the APK and approve the installation in Android. If Android asks for permission, allow installs for Mirquova and open the package again.';
  }
  if (packageName?.endsWith('.zip') ?? false) {
    return 'After the download finishes, open the ZIP in your system archive app. Close Mirquova, then replace the complete app bundle with the extracted copy.';
  }
  if (packageName?.endsWith('.tar.gz') ?? false) {
    return 'After the download finishes, open the archive with your system archive app. Close Mirquova, then replace the complete app bundle with the extracted copy.';
  }
  return 'After the download finishes, open the package with your system. Follow its installation steps to complete the update.';
}
