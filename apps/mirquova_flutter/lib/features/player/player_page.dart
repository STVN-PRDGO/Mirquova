import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../adapters/open_subtitles_http.dart';
import '../../adapters/video_playback.dart';
import '../../core/movie_hash.dart';
import '../../core/open_subtitles.dart';
import '../../core/playback.dart';
import '../../core/subtitles.dart';
import '../../ui/surface_card.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.playback,
    this.createEngine = VideoPlaybackEngine.new,
    this.subtitles,
  });

  final LocalPlayback playback;
  final PlaybackEngine Function() createEngine;
  final OpenSubtitlesApi? subtitles;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _query = TextEditingController();
  final _apiKey = TextEditingController();
  bool _optIn = false;
  bool _searching = false;
  List<SubtitleCandidate> _results = const [];
  String? _subtitleNotice;
  bool _fullscreen = false;

  @override
  void dispose() {
    _query.dispose();
    _apiKey.clear();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _openMedia() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (!mounted || path == null) return;
    await widget.playback.open(
      LocalMedia(name: picked!.name, path: path),
      widget.createEngine(),
    );
  }

  Future<void> _importSubtitle() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['srt'],
    );
    final path = picked?.path;
    if (!mounted || path == null) return;
    try {
      final text = await File(path).readAsString();
      final document = parseSrt(text);
      if (document.cues.isEmpty) {
        setState(() => _subtitleNotice = 'That file has no SubRip cues.');
        return;
      }
      widget.playback.loadSubtitles(document, picked!.name);
      setState(
        () => _subtitleNotice = 'Loaded ${document.cues.length} local cues.',
      );
    } on Object {
      if (mounted) {
        setState(
          () => _subtitleNotice = 'The subtitle file could not be read.',
        );
      }
    }
  }

  Future<void> _search() async {
    final playback = widget.playback;
    final local = playback.subtitles?.matching(_query.text) ?? const [];
    if (!_optIn || _apiKey.text.trim().isEmpty) {
      setState(() {
        _results = const [];
        _subtitleNotice = local.isEmpty
            ? 'OpenSubtitles was not contacted. Turn on permission and add your own API key to search.'
            : 'Showing matches in the loaded subtitle. OpenSubtitles was not contacted.';
      });
      return;
    }
    setState(() {
      _searching = true;
      _subtitleNotice = 'Searching OpenSubtitles with the file name only.';
    });
    try {
      String? hash;
      final path = playback.path;
      if (path != null) {
        try {
          hash = await openSubtitlesMovieHash(path);
        } on Object {
          hash = null;
        }
      }
      final api =
          widget.subtitles ??
          OpenSubtitlesApi(transport: IoOpenSubtitleTransport());
      final results = await api.search(
        optedIn: true,
        apiKey: _apiKey.text,
        query: _query.text.trim().isEmpty
            ? (playback.name ?? '')
            : _query.text.trim(),
        movieHash: hash,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _subtitleNotice = results.isEmpty
            ? 'OpenSubtitles returned no matches.'
            : 'Choose a result to download it for this session.';
      });
    } on OpenSubtitlesDisabled {
      if (mounted) {
        setState(() => _subtitleNotice = 'OpenSubtitles was not contacted.');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _subtitleNotice = error is FormatException
              ? error.message
              : 'Online subtitles are unavailable. Local subtitles still work.';
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _download(SubtitleCandidate candidate) async {
    setState(() => _searching = true);
    try {
      final api =
          widget.subtitles ??
          OpenSubtitlesApi(transport: IoOpenSubtitleTransport());
      final text = await api.download(
        optedIn: _optIn,
        apiKey: _apiKey.text,
        fileId: candidate.fileId,
      );
      final document = parseSrt(text);
      if (document.cues.isEmpty) {
        throw const FormatException(
          'The download did not contain SubRip cues.',
        );
      }
      widget.playback.loadSubtitles(document, candidate.fileName);
      if (!mounted) return;
      setState(
        () =>
            _subtitleNotice = 'Loaded ${candidate.fileName} for this session.',
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _subtitleNotice = error is FormatException
              ? error.message
              : 'The subtitle could not be downloaded.';
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.playback,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final library = _Library(
          playback: widget.playback,
          onOpen: _openMedia,
          createEngine: widget.createEngine,
        );
        final stage = _Stage(
          playback: widget.playback,
          fullscreen: _fullscreen,
          onFullscreen: () => setState(() => _fullscreen = true),
          createEngine: widget.createEngine,
        );
        final subtitles = _Subtitles(
          playback: widget.playback,
          query: _query,
          apiKey: _apiKey,
          optedIn: _optIn,
          searching: _searching,
          results: _results,
          notice: _subtitleNotice,
          onOptIn: (value) => setState(() => _optIn = value),
          onSearch: _search,
          onImport: _importSubtitle,
          onDownload: _download,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Media player',
              subtitle: 'Opens files on this device. Online subtitles are sent only after you opt in with your own API key.',
            ),
            const SizedBox(height: 20),
            if (!wide)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stage,
                  const SizedBox(height: 16),
                  subtitles,
                  const SizedBox(height: 16),
                  library,
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 220, child: library),
                  const SizedBox(width: 16),
                  Expanded(child: stage),
                  const SizedBox(width: 16),
                  SizedBox(width: 300, child: subtitles),
                ],
              ),
            if (_fullscreen)
              _Fullscreen(
                playback: widget.playback,
                onClose: () => setState(() => _fullscreen = false),
              ),
          ],
        );
      },
    );
  }
}

class _Library extends StatelessWidget {
  const _Library({
    required this.playback,
    required this.onOpen,
    required this.createEngine,
  });

  final LocalPlayback playback;
  final VoidCallback onOpen;
  final PlaybackEngine Function() createEngine;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Library', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (playback.library.isEmpty)
            const Text('No local media yet.')
          else
            for (final item in playback.library)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                onTap: () => playback.open(item, createEngine()),
              ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Open file'),
          ),
        ],
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.playback,
    required this.fullscreen,
    required this.onFullscreen,
    required this.createEngine,
  });

  final LocalPlayback playback;
  final bool fullscreen;
  final VoidCallback onFullscreen;
  final PlaybackEngine Function() createEngine;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = playback.duration.inMilliseconds;
    final fraction = duration == 0
        ? 0.0
        : playback.position.inMilliseconds / duration;
    final cue = playback.currentCue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF070B14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (playback.hasMedia && !fullscreen)
                    playback.buildView()
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.play_circle_outline,
                          size: 56,
                          color: Color(0xFF4C9BFF),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          playback.error ??
                              playback.name ??
                              'No media selected',
                          style: const TextStyle(
                            color: Color(0xFFF4F7FC),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  if (cue != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: playback.subtitleBackground
                              ? const Color(0xCC000000)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            cue.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16 * playback.subtitleScale,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          playback.name ?? 'Nothing playing',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Slider(
          value: fraction.clamp(0, 1).toDouble(),
          onChanged: playback.hasMedia
              ? (value) => playback.seekTo(value)
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_clock(playback.position)),
            Text(_clock(playback.duration)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: playback.library.length < 2
                  ? null
                  : () => playback.openRelative(-1, createEngine),
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              tooltip: playback.playing ? 'Pause' : 'Play',
              onPressed: playback.hasMedia ? playback.togglePlay : null,
              icon: Icon(playback.playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Next',
              onPressed: playback.library.length < 2
                  ? null
                  : () => playback.openRelative(1, createEngine),
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: 'Volume',
              onPressed: playback.hasMedia
                  ? () => playback.changeVolume(playback.volume > 0 ? -1 : 1)
                  : null,
              icon: const Icon(Icons.volume_up_outlined),
            ),
            IconButton(
              tooltip: 'Fullscreen',
              onPressed: playback.hasMedia ? onFullscreen : null,
              icon: const Icon(Icons.fullscreen),
            ),
          ],
        ),
      ],
    );
  }
}

class _Fullscreen extends StatelessWidget {
  const _Fullscreen({required this.playback, required this.onClose});

  final LocalPlayback playback;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: playback.buildView()),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onClose,
              child: const Text('Leave full screen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Subtitles extends StatelessWidget {
  const _Subtitles({
    required this.playback,
    required this.query,
    required this.apiKey,
    required this.optedIn,
    required this.searching,
    required this.results,
    required this.notice,
    required this.onOptIn,
    required this.onSearch,
    required this.onImport,
    required this.onDownload,
  });

  final LocalPlayback playback;
  final TextEditingController query;
  final TextEditingController apiKey;
  final bool optedIn;
  final bool searching;
  final List<SubtitleCandidate> results;
  final String? notice;
  final ValueChanged<bool> onOptIn;
  final VoidCallback onSearch;
  final VoidCallback onImport;
  final ValueChanged<SubtitleCandidate> onDownload;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Subtitles', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            playback.subtitleLabel == null
                ? 'No subtitle track is loaded.'
                : 'Loaded ${playback.subtitleLabel}.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: query,
            decoration: const InputDecoration(
              labelText: 'Title or words to find',
            ),
            onSubmitted: (_) => onSearch(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: apiKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'OpenSubtitles API key',
              helperText:
                  'Kept in memory for this screen only. It is not saved.',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: optedIn,
            onChanged: searching ? null : (value) => onOptIn(value ?? false),
            title: const Text('Send this search to OpenSubtitles.com'),
            subtitle: const Text(
              'The file name and, for files of at least 128 KiB, a content identifier are sent. The folder path is not.',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: searching ? null : onSearch,
                child: Text(searching ? 'Working' : 'Search'),
              ),
              OutlinedButton(
                onPressed: onImport,
                child: const Text('Import local subtitle'),
              ),
            ],
          ),
          if (notice != null) ...[const SizedBox(height: 8), Text(notice!)],
          for (final result in results)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(result.fileName),
              subtitle: Text(
                [
                  if (result.language.isNotEmpty) result.language,
                  if (result.hashMatch) 'content match',
                  if (result.release.isNotEmpty) result.release,
                ].join(' · '),
              ),
              onTap: searching ? null : () => onDownload(result),
            ),
          const SizedBox(height: 12),
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: playback.subtitleScale,
            min: 0.8,
            max: 2,
            onChanged: playback.subtitles == null
                ? null
                : playback.setSubtitleScale,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Subtitle background'),
            value: playback.subtitleBackground,
            onChanged: playback.subtitles == null
                ? null
                : playback.setSubtitleBackground,
          ),
        ],
      ),
    );
  }
}

String _clock(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${value.inHours > 0 ? '${value.inHours}:' : ''}$minutes:$seconds';
}
