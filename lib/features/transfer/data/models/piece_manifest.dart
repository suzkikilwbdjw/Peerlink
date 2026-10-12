import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Манифест файла: размер, размер куска и SHA-256 каждого куска.
///
/// fileId файла это SHA-256 закодированного манифеста (как infohash в
/// BitTorrent). Поэтому манифест можно получить от ЛЮБОГО пира и проверить
/// по fileId, а затем проверять каждый кусок отдельно. Это позволяет
/// скачивать разные куски у разных пиров и сразу отбрасывать испорченные.
///
/// Формат (все числа big-endian):
///   "P2PM1" (5 байт) | size (8) | pieceSize (4) | hash[0] (32) | ... | hash[N-1] (32)
///
/// Размер куска зависит только от размера файла ([pieceSizeFor]), поэтому
/// один и тот же файл у разных пользователей даёт один и тот же fileId.
class PieceManifest {
  static const int minPieceSize = 256 * 1024;
  static const int maxPieceSize = 16 * 1024 * 1024;

  /// К этому числу кусков стремимся: манифест остаётся небольшим (~64 КБ).
  static const int targetMaxPieces = 2048;

  static const int hashLength = 32;

  /// Верхняя граница при разборе чужого манифеста.
  static const int maxPieces = 200000;

  static const String magic = 'P2PM1';
  static const int headerLength = 5 + 8 + 4;

  final int size;
  final int pieceSize;

  /// pieceCount * 32 байт, хеши кусков подряд.
  final Uint8List _hashes;

  Uint8List? _encoded;
  String? _fileId;

  PieceManifest({
    required this.size,
    required this.pieceSize,
    required this._hashes,
  });

  /// Размер куска для файла заданного размера: наименьшая степень двойки
  /// от 256 КБ, при которой кусков не больше [targetMaxPieces] (но не больше 16 МБ).
  static int pieceSizeFor(int size) {
    var pieceSize = minPieceSize;

    while (pieceSize < maxPieceSize &&
        (size + pieceSize - 1) ~/ pieceSize > targetMaxPieces) {
      pieceSize *= 2;
    }

    return pieceSize;
  }

  int get pieceCount => (size + pieceSize - 1) ~/ pieceSize;

  int pieceOffset(int index) => index * pieceSize;

  /// Длина куска [index] (последний обычно короче).
  int pieceLength(int index) => math.min(pieceSize, size - index * pieceSize);

  /// Совпадает ли SHA-256 данных с хешем куска [index].
  bool matches(int index, Uint8List data) {
    if (index < 0 || index >= pieceCount) return false;
    if (data.length != pieceLength(index)) return false;

    final digest = sha256.convert(data).bytes;
    final start = index * hashLength;

    for (var i = 0; i < hashLength; i++) {
      if (digest[i] != _hashes[start + i]) return false;
    }

    return true;
  }

  Uint8List encode() => _encoded ??= _encodeNow();

  Uint8List _encodeNow() {
    final out = Uint8List(headerLength + _hashes.length);

    out.setRange(0, 5, magic.codeUnits);

    final view = ByteData.sublistView(out);
    view.setUint64(5, size, Endian.big);
    view.setUint32(13, pieceSize, Endian.big);

    out.setRange(headerLength, out.length, _hashes);
    return out;
  }

  /// SHA-256 манифеста в hex (64 символа).
  String get fileId => _fileId ??= sha256.convert(encode()).toString();

  /// Разбирает чужой манифест. Данным нельзя доверять: проверяются формат,
  /// размеры и согласованность. Возвращает null при любой некорректности.
  static PieceManifest? tryDecode(Uint8List bytes) {
    if (bytes.length < headerLength) return null;

    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) return null;
    }

    final view = ByteData.sublistView(bytes);
    final size = view.getUint64(5, Endian.big);
    final pieceSize = view.getUint32(13, Endian.big);

    if (size <= 0 || size > (1 << 50)) return null;
    if (pieceSize < 16 * 1024 || pieceSize > maxPieceSize) return null;

    final count = (size + pieceSize - 1) ~/ pieceSize;
    if (count > maxPieces) return null;

    if (bytes.length != headerLength + count * hashLength) return null;

    return PieceManifest(
      size: size,
      pieceSize: pieceSize,
      hashes: Uint8List.fromList(bytes.sublist(headerLength)),
    );
  }
}
