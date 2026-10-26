import 'package:flutter/material.dart';

import '../../core/app_platform.dart';
import '../../core/app_updates.dart';

class SystemUpdatesCard extends StatefulWidget {
  const SystemUpdatesCard({
    super.key,
    required this.updates,
    required this.readingVersion,
    required this.onRetryVersion,
    required this.appPlatform,
  });

  final UpdateController? updates;
  final bool readingVersion;
  final VoidCallback onRetryVersion;
  final AppPlatform appPlatform;

  @override
  State<SystemUpdatesCard> createState() => _SystemUpdatesCardState();
}

class _SystemUpdatesCardState extends State<SystemUpdatesCard> {
  bool _askingPermission = false;
  bool _openingRelease = false;
  String? _openError;

  Future<void> _check(UpdateController updates) async {
    setState(() {
      _askingPermission = true;
      _openError = null;
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

  Future<void> _openRelease(UpdateRelease release) async {
    setState(() {
      _openingRelease = true;
      _openError = null;
    });
    try {
      await widget.appPlatform.openReleasePage(release.pageUrl);
    } on Exception {
      if (mounted) {
        setState(() {
          _openError = 'The release page could not be opened. Try again or copy the address below into your browser.';
        });
      }
    } finally {
      if (mounted) setState(() => _openingRelease = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updates = widget.updates;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: updates == null
            ? _content(context, null)
            : ListenableBuilder(
                listenable: updates,
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
            'Check the release page for a package compatible with your device and follow its installation steps. Close Mirquova before replacing the Windows app folder. On Android, follow the system installer prompts.',
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
                      _openingRelease
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
            if (release != null)
              OutlinedButton.icon(
                onPressed: _openingRelease || _askingPermission
                    ? null
                    : () => _openRelease(release),
                icon: const Icon(Icons.open_in_new_outlined),
                label: Text(
                  _openingRelease ? 'Opening browser...' : 'Open release page',
                ),
              ),
            if (updates == null && !widget.readingVersion)
              OutlinedButton(
                onPressed: widget.onRetryVersion,
                child: const Text('Retry version lookup'),
              ),
          ],
        ),
        if (_openError != null && release != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_openError!)),
          const SizedBox(height: 8),
          SelectableText(release.pageUrl.toString()),
        ],
        const SizedBox(height: 16),
        const Text(
          'Update checks are optional. Downloads and installation start only when you choose them on GitHub.',
        ),
      ],
    );
  }
}
