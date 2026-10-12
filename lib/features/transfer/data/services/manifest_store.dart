import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:p2pchat/features/transfer/data/models/piece_manifest.dart';
import 'package:path/path.dart' as p;

/// Хранит манифесты файлов на диске: <папка>/&ltfileId&gt.manifest.
///
/// Манифест нужен в двух случаях:
/// - раздающему, чтобы отдавать его скачивающим;
/// - скачивающему, чтобы проверять куски и продолжать загрузку после
///   перезапуска, не спрашивая манифест у пира заново.
///
/// Манифест хранится отдельно от shared_preferences: он занимает десятки
/// килобайт на файл, а preferences читается целиком при каждом запуске.
class ManifestStore {
  final Future<Directory> Function() _directory;

  ManifestStore({required this._directory});

  Future<File> _file(String fileId) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, '$fileId.manifest'));
  }

  /// Сохраняет манифест. Запись идёт через временный файл, чтобы сбой
  /// посреди записи не оставил битый манифест.
  Future<void> save(String fileId, Uint8List bytes) async {
    final file = await _file(fileId);
    final temp = File('${file.path}.tmp');

    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  Future<bool> exists(String fileId) async {
    try {
      return await (await _file(fileId)).exists();
    } catch (_) {
      return false;
    }
  }

  /// Байты манифеста; null, если его нет или он повреждён (SHA-256 не
  /// совпал с fileId).
  Future<Uint8List?> loadBytes(String fileId) async {
    try {
      final file = await _file(fileId);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();

      if (sha256.convert(bytes).toString() != fileId) {
        debugPrint('[MANIFEST] Манифест $fileId повреждён, удаляем');
        await file.delete();
        return null;
      }

      return bytes;
    } catch (e) {
      debugPrint('[MANIFEST] Не удалось прочитать манифест $fileId: $e');
      return null;
    }
  }

  Future<PieceManifest?> loadManifest(String fileId) async {
    final bytes = await loadBytes(fileId);
    if (bytes == null) return null;

    return PieceManifest.tryDecode(bytes);
  }

  Future<void> delete(String fileId) async {
    try {
      final file = await _file(fileId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
