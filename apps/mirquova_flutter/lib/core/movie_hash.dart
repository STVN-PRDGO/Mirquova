import 'dart:io';
import 'dart:typed_data';

/// OpenSubtitles content identifier for the first and last 64 KiB.
/// This is not a security hash and is never sent unless a search is opted in.
Future<String?> openSubtitlesMovieHash(String path) async {
  const chunk = 65536;
  final file = File(path);
  final length = await file.length();
  if (length < chunk * 2) return null;
  final handle = await file.open();
  try {
    var hash = length;
    hash = await _addChunk(handle, hash, chunk);
    await handle.setPosition(length - chunk);
    hash = await _addChunk(handle, hash, chunk);
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  } finally {
    await handle.close();
  }
}

Future<int> _addChunk(RandomAccessFile handle, int hash, int bytes) async {
  final data = await handle.read(bytes);
  if (data.length != bytes) {
    throw const FileSystemException('Could not read the media file.');
  }
  final view = ByteData.sublistView(Uint8List.fromList(data));
  for (var offset = 0; offset < bytes; offset += 8) {
    hash = (hash + view.getUint64(offset, Endian.little)) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}
