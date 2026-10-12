import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:p2pchat/features/transfer/data/models/piece_manifest.dart';

class HashCancelledException implements Exception {
  const HashCancelledException();

  @override
  String toString() => 'Хеширование отменено';
}

/// Позволяет отменить уже запущенное хеширование.
class HashCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Результат индексации файла.
class ManifestResult {
  /// SHA-256 манифеста (hex): идентификатор файла в сети.
  final String fileId;

  /// Закодированный манифест (хеши всех кусков).
  final Uint8List manifestBytes;

  const ManifestResult({required this.fileId, required this.manifestBytes});
}

class _HashRequest {
  final SendPort sendPort;
  final String path;

  const _HashRequest(this.sendPort, this.path);
}

class FileHasher {
  /// Как часто изолят шлёт прогресс (в байтах).
  static const int _progressStep = 4 * 1024 * 1024;

  /// Индексирует файл: считает SHA-256 каждого куска и строит манифест.
  /// fileId результата это SHA-256 манифеста.
  ///
  /// Работает в отдельном изоляте и читает файл по одному куску (до 16 МБ):
  /// память не растёт, интерфейс не зависает. Бросает
  /// [HashCancelledException] при отмене.
  static Future<ManifestResult> buildManifest(
    String path, {
    void Function(int processed, int total)? onProgress,
    HashCancelToken? cancelToken,
  }) async {
    final result = await _run(_manifestEntry, path, onProgress, cancelToken);

    return ManifestResult(
      fileId: result[1] as String,
      manifestBytes: result[2] as Uint8List,
    );
  }

  /// SHA-256 всего файла (в сети больше не используется, оставлен как
  /// утилита).
  static Future<String> sha256Of(
    String path, {
    void Function(int processed, int total)? onProgress,
    HashCancelToken? cancelToken,
  }) async {
    final result = await _run(_hashEntry, path, onProgress, cancelToken);
    return result[1] as String;
  }

  /// Запускает [entry] в изоляте и ждёт сообщения 'done'. Изолят шлёт списки:
  /// ['progress', processed, total], ['done', ...результат], ['error', текст].
  static Future<List<Object?>> _run(
    void Function(_HashRequest) entry,
    String path,
    void Function(int processed, int total)? onProgress,
    HashCancelToken? cancelToken,
  ) async {
    if (cancelToken?.isCancelled ?? false) {
      throw const HashCancelledException();
    }

    final port = ReceivePort();
    final result = Completer<List<Object?>>();
    Isolate? isolate;

    port.listen((message) {
      if (message is! List || message.isEmpty) return;

      switch (message[0]) {
        case 'progress':
          onProgress?.call(message[1] as int, message[2] as int);
        case 'done':
          if (!result.isCompleted) result.complete(List<Object?>.of(message));
        case 'error':
          if (!result.isCompleted) {
            result.completeError(
              FileSystemException(message[1] as String, path),
            );
          }
      }
    });

    cancelToken?._onCancel = () {
      if (!result.isCompleted) {
        result.completeError(const HashCancelledException());
      }
    };

    try {
      isolate = await Isolate.spawn(entry, _HashRequest(port.sendPort, path));
      return await result.future;
    } finally {
      cancelToken?._onCancel = null;
      port.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}

/// Точка входа изолята: SHA-256 всего файла. Обязана быть top-level функцией.
Future<void> _hashEntry(_HashRequest request) async {
  final send = request.sendPort;

  try {
    final file = File(request.path);
    final total = await file.length();

    var processed = 0;
    var reported = 0;

    final stream = file.openRead().map((chunk) {
      processed += chunk.length;

      if (processed - reported >= FileHasher._progressStep) {
        reported = processed;
        send.send(['progress', processed, total]);
      }

      return chunk;
    });

    final digest = await sha256.bind(stream).first;

    send.send(['progress', total, total]);
    send.send(['done', digest.toString()]);
  } catch (e) {
    send.send(['error', e.toString()]);
  }
}

/// Точка входа изолята: манифест файла (хеши кусков).
Future<void> _manifestEntry(_HashRequest request) async {
  final send = request.sendPort;
  RandomAccessFile? raf;

  try {
    raf = await File(request.path).open();
    final size = await raf.length();

    if (size <= 0) throw StateError('Нельзя раздавать пустой файл');

    final pieceSize = PieceManifest.pieceSizeFor(size);
    final pieceCount = (size + pieceSize - 1) ~/ pieceSize;
    final hashes = Uint8List(pieceCount * PieceManifest.hashLength);

    var processed = 0;
    var reported = 0;

    for (var i = 0; i < pieceCount; i++) {
      final length = math.min(pieceSize, size - i * pieceSize);
      final bytes = await raf.read(length);

      if (bytes.length != length) {
        throw StateError('Файл изменился во время обработки');
      }

      final start = i * PieceManifest.hashLength;
      hashes.setRange(
        start,
        start + PieceManifest.hashLength,
        sha256.convert(bytes).bytes,
      );

      processed += length;

      if (processed - reported >= FileHasher._progressStep) {
        reported = processed;
        send.send(['progress', processed, size]);
      }
    }

    final manifest = PieceManifest(
      size: size,
      pieceSize: pieceSize,
      hashes: hashes,
    );
    final encoded = manifest.encode();

    send.send(['progress', size, size]);
    send.send(['done', manifest.fileId, encoded]);
  } catch (e) {
    send.send(['error', e is StateError ? e.message : e.toString()]);
  } finally {
    await raf?.close();
  }
}
