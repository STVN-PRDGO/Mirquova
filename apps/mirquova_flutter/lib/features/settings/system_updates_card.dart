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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('System updates', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Keep your Mirquova app up to date.'),
        const SizedBox(height: 16),
        Text(
          updates != null
              ? 'Installed version: ${updates.currentVersion}'
              : widget.readingVersion
              ? 'Reading installed version...'
              : 'Installed version unavailable',
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(switch (status) {
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
          }, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (updates?.message != null) ...[
          const SizedBox(height: 8),
          Text(updates!.message!),
        ],
        if (checking && !MediaQuery.disableAnimationsOf(context)) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(semanticsLabel: 'Checking for updates'),
        ],
        if (lastChecked != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last checked: ${localizations.formatShortDate(lastChecked.toLocal())}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastChecked.toLocal()))}',
          ),
        ],
        if (release != null) ...[
          const SizedBox(height: 16),
          Text(
            'Published version: ${release.version}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (release.notes.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('What\u2019s new'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(release.notes),
                ),
                const SizedBox(height: 16),
              ],
            ),
          const SizedBox(height: 8),
          const Text(
            'Download the update here, then open the package to finish with your system. Desktop previews require closing Mirquova and replacing the complete app bundle. Android requires system installation approval.',
          ),
        ],
        const SizedBox(height: 16),
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

class _PackagePanel extends StatelessWidget {
  const _PackagePanel({required this.release, required this.packages});
  final UpdateRelease release;
  final PackageUpdates packages;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Update download', style: Theme.of(context).textTheme.titleMedium),
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
          ),
          const SizedBox(height: 8),
          Text('${((packages.progress ?? 0) * 100).floor()}% downloaded'),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: packages.busy ? null : () => _download(context, asset),
              icon: const Icon(Icons.download_outlined),
              label: Text(ready ? 'Download again' : 'Download update'),
            ),
            if (packages.status == PackageStatus.downloading)
              OutlinedButton(
                onPressed: packages.cancel,
                child: const Text('Cancel download'),
              ),
            if (ready || (current && packages.status == PackageStatus.opening))
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
    );
  }
}
