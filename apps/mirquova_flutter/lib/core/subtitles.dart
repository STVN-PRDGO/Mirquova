class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  bool contains(Duration position) => position >= start && position < end;
}

class SubtitleDocument {
  const SubtitleDocument(this.cues);

  final List<SubtitleCue> cues;

  SubtitleCue? at(Duration position) {
    for (final cue in cues) {
      if (cue.contains(position)) return cue;
    }
    return null;
  }

  List<SubtitleCue> matching(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final cue in cues)
        if (cue.text.toLowerCase().contains(needle)) cue,
    ];
  }
}

/// Parses a SubRip document. Invalid blocks are skipped. This does not
/// contact a subtitle service.
SubtitleDocument parseSrt(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final cues = <SubtitleCue>[];
  for (final block in normalized.split('\n\n')) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) continue;
    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0) continue;
    final range = _timing(lines[timingIndex]);
    if (range == null) continue;
    final text = lines.skip(timingIndex + 1).join('\n').trim();
    if (text.isEmpty) continue;
    cues.add(SubtitleCue(start: range.$1, end: range.$2, text: text));
  }
  return SubtitleDocument(cues);
}

(Duration, Duration)? _timing(String line) {
  final parts = line.split('-->');
  if (parts.length != 2) return null;
  final start = _timestamp(parts[0]);
  final end = _timestamp(parts[1]);
  if (start == null || end == null || end < start) return null;
  return (start, end);
}

Duration? _timestamp(String value) {
  final match = RegExp(r'(\d+):(\d{2}):(\d{2})[,.](\d{1,3})')
      .firstMatch(value.trim());
  if (match == null) return null;
  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  final seconds = int.parse(match.group(3)!);
  final millis = int.parse(match.group(4)!.padRight(3, '0'));
  if (minutes > 59 || seconds > 59) return null;
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}
