import 'dart:convert';

class OpenSubtitlesDisabled implements Exception {
  const OpenSubtitlesDisabled();
}

class SubtitleCandidate {
  const SubtitleCandidate({
    required this.fileId,
    required this.fileName,
    required this.language,
    required this.release,
    required this.hashMatch,
  });

  final int fileId;
  final String fileName;
  final String language;
  final String release;
  final bool hashMatch;
}

abstract interface class OpenSubtitleTransport {
  Future<String> get(Uri uri, Map<String, String> headers);
  Future<String> post(Uri uri, Map<String, String> headers, String body);
  Future<String> download(Uri uri);
}

class OpenSubtitlesApi {
  OpenSubtitlesApi({
    required this.transport,
    this.userAgent = 'Mirquova v0.3.0',
    Uri? endpoint,
  }) : endpoint = endpoint ?? defaultEndpoint;

  static final defaultEndpoint = Uri.parse(
    'https://api.opensubtitles.com/api/v1',
  );

  final OpenSubtitleTransport transport;
  final String userAgent;
  final Uri endpoint;

  Future<List<SubtitleCandidate>> search({
    required bool optedIn,
    required String apiKey,
    required String query,
    String? movieHash,
    String language = 'en',
  }) async {
    final key = _key(optedIn, apiKey);
    final title = query.trim();
    if (title.isEmpty) {
      throw const FormatException('Enter a title before searching.');
    }
    final parameters = <String, String>{
      'query': title,
      'languages': language.trim().isEmpty ? 'en' : language.trim(),
    };
    if (movieHash != null && RegExp(r'^[0-9a-f]{16}$').hasMatch(movieHash)) {
      parameters['moviehash'] = movieHash;
    }
    final uri = endpoint.replace(
      path: '${endpoint.path}/subtitles',
      queryParameters: parameters,
    );
    _requireApi(uri);
    return parseSubtitleSearch(await transport.get(uri, _headers(key)));
  }

  Future<String> download({
    required bool optedIn,
    required String apiKey,
    required int fileId,
  }) async {
    final key = _key(optedIn, apiKey);
    if (fileId <= 0) {
      throw const FormatException('That subtitle result cannot be downloaded.');
    }
    final uri = endpoint.replace(path: '${endpoint.path}/download');
    _requireApi(uri);
    final response = await transport.post(uri, {
      ..._headers(key),
      'Content-Type': 'application/json',
    }, '{"file_id":$fileId}');
    return transport.download(parseDownloadLink(response));
  }

  Map<String, String> _headers(String apiKey) => {
    'Api-Key': apiKey,
    'User-Agent': userAgent,
    'Accept': 'application/json',
  };
}

String _key(bool optedIn, String apiKey) {
  if (!optedIn) throw const OpenSubtitlesDisabled();
  final key = apiKey.trim();
  if (key.isEmpty || key.length > 128 || key.contains(RegExp(r'\s'))) {
    throw const OpenSubtitlesDisabled();
  }
  return key;
}

void _requireApi(Uri uri) {
  if (uri.scheme != 'https' || uri.host != 'api.opensubtitles.com') {
    throw const FormatException('Subtitle search host was rejected.');
  }
}

List<SubtitleCandidate> parseSubtitleSearch(String body) {
  if (body.length > 1024 * 1024) {
    throw const FormatException('Subtitle search response is too large.');
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Subtitle response was not a JSON object.');
  }
  final data = decoded['data'];
  if (data is! List) return const [];
  final results = <SubtitleCandidate>[];
  for (final item in data) {
    if (item is! Map) continue;
    final attributes = item['attributes'];
    if (attributes is! Map) continue;
    final files = attributes['files'];
    if (files is! List || files.isEmpty || files.first is! Map) continue;
    final file = files.first as Map;
    final fileId = file['file_id'];
    final fileName = file['file_name'];
    if (fileId is! int || fileName is! String || fileName.trim().isEmpty) {
      continue;
    }
    results.add(
      SubtitleCandidate(
        fileId: fileId,
        fileName: fileName.trim(),
        language: attributes['language'] is String
            ? attributes['language'] as String
            : '',
        release: attributes['release'] is String
            ? attributes['release'] as String
            : '',
        hashMatch: attributes['moviehash_match'] == true,
      ),
    );
  }
  results.sort((a, b) {
    if (a.hashMatch != b.hashMatch) return a.hashMatch ? -1 : 1;
    return a.fileName.compareTo(b.fileName);
  });
  return results;
}

Uri parseDownloadLink(String body) {
  if (body.length > 64 * 1024) {
    throw const FormatException('Subtitle download response is too large.');
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic> || decoded['link'] is! String) {
    throw const FormatException('Subtitle download link is missing.');
  }
  final uri = Uri.tryParse(decoded['link'] as String);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('Subtitle download link was rejected.');
  }
  return uri;
}
