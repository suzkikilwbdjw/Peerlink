import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:p2pchat/features/tracker/data/models/peer_announcement.dart'
    show isValidFileId;
import 'package:shared_preferences/shared_preferences.dart';

/// Недокачанный файл. Сами данные лежат в .part на диске, а здесь только то,
/// что нужно, чтобы показать загрузку после перезапуска и найти раздающих:
/// какой файл (fileId), как называется и какого размера.
class PartialDownload extends Equatable {
  final String fileId;
  final String name;
  final int size;

  const PartialDownload({
    required this.fileId,
    required this.name,
    required this.size,
  });

  factory PartialDownload.fromJson(Map<String, dynamic> json) {
    final fileId = json['fileId'];
    final name = json['name'];
    final size = json['size'];

    if (fileId is! String ||
        !isValidFileId(fileId) ||
        name is! String ||
        name.isEmpty ||
        size is! int ||
        size <= 0) {
      throw const FormatException('Некорректная запись PartialDownload');
    }

    return PartialDownload(fileId: fileId, name: name, size: size);
  }

  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'name': name,
    'size': size,
  };

  @override
  List<Object?> get props => [fileId, name, size];
}

/// Список недокачанных загрузок в shared_preferences (один JSON-массив).
class PartialDownloadRepository {
  static const String _storageKey = 'partial_downloads_v1';

  final SharedPreferences _prefs;

  PartialDownloadRepository(this._prefs);

  List<PartialDownload> load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint('[PARTIAL] Повреждённый JSON в хранилище: $e');
      return const [];
    }

    if (decoded is! List) return const [];

    final result = <PartialDownload>[];

    for (final item in decoded) {
      if (item is! Map) continue;

      try {
        result.add(PartialDownload.fromJson(Map<String, dynamic>.from(item)));
      } catch (e) {
        debugPrint('[PARTIAL] Пропущена некорректная запись: $e');
      }
    }

    return result;
  }

  Future<void> upsert(PartialDownload download) async {
    final list = load().where((e) => e.fileId != download.fileId).toList()
      ..add(download);

    await _save(list);
  }

  Future<void> remove(String fileId) async {
    final list = load();
    final next = list.where((e) => e.fileId != fileId).toList();

    if (next.length == list.length) return;
    await _save(next);
  }

  Future<void> _save(List<PartialDownload> list) async {
    final ok = await _prefs.setString(
      _storageKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );

    if (!ok) {
      throw StateError('Не удалось сохранить список недокачанных загрузок');
    }
  }
}
