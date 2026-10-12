import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Хранит список раздаваемых файлов в shared_preferences (один JSON-массив).
class SeedRepository {
  static const String _storageKey = 'seed_files_v1';

  final SharedPreferences _prefs;

  SeedRepository(this._prefs);

  List<SeedFile> load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint('[SEED] Повреждённый JSON в хранилище: $e');
      return const [];
    }

    if (decoded is! List) return const [];

    final result = <SeedFile>[];

    for (final item in decoded) {
      if (item is! Map) continue;

      try {
        result.add(SeedFile.fromJson(Map<String, dynamic>.from(item)));
      } catch (e) {
        debugPrint('[SEED] Пропущена некорректная запись: $e');
      }
    }

    return result;
  }

  Future<void> save(List<SeedFile> files) async {
    final json = jsonEncode(files.map((f) => f.toJson()).toList());
    final ok = await _prefs.setString(_storageKey, json);

    if (!ok) {
      throw StateError('Не удалось сохранить список раздач');
    }
  }

  /// Дешёвая проверка файла на диске без пересчёта хеша:
  /// сравниваются существование, размер и время изменения.
  Future<SeedStatus> checkStatus(SeedFile seed) async {
    try {
      final file = File(seed.path);

      if (!await file.exists()) return SeedStatus.missing;

      final stat = await file.stat();

      if (stat.size != seed.size ||
          stat.modified.millisecondsSinceEpoch != seed.modifiedAtMs) {
        return SeedStatus.modified;
      }

      return SeedStatus.available;
    } on FileSystemException {
      return SeedStatus.missing;
    }
  }
}
