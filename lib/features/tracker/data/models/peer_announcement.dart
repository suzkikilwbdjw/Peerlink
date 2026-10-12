import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

final RegExp _fileIdPattern = RegExp(r'^[0-9a-f]{64}$');

/// fileId = SHA-256 в hex: ровно 64 символа 0-9a-f.
bool isValidFileId(String id) => _fileIdPattern.hasMatch(id);

/// Файл в анонсе пира.
class AnnouncedFile extends Equatable {
  final String name;
  final int size;

  const AnnouncedFile({required this.name, required this.size});

  @override
  List<Object?> get props => [name, size];
}

/// Документ peers/{uid}: кто онлайн и какие файлы раздаёт.
///
/// Данные пишут другие пользователи, поэтому им нельзя доверять: всё
/// проверяется при разборе, а некорректные записи молча пропускаются.
class PeerAnnouncement extends Equatable {
  final String uid;
  final DateTime lastSeen;

  /// Ключ — fileId (SHA-256).
  final Map<String, AnnouncedFile> files;

  const PeerAnnouncement({
    required this.uid,
    required this.lastSeen,
    required this.files,
  });

  static PeerAnnouncement? tryParse(String uid, Map<String, dynamic>? data) {
    if (data == null) return null;

    // У только что записанного документа серверное время может быть ещё
    // null (локальная оценка). Такой документ пропускаем до следующего
    // снимка.
    final lastSeen = data['lastSeen'];
    if (lastSeen is! Timestamp) return null;

    final rawFiles = data['files'];
    if (rawFiles is! Map) return null;

    final files = <String, AnnouncedFile>{};

    for (final entry in rawFiles.entries) {
      final id = entry.key;
      final value = entry.value;

      if (id is! String || !isValidFileId(id) || value is! Map) continue;

      final name = value['name'];
      final size = value['size'];

      if (name is! String || name.isEmpty || name.length > 255) continue;
      if (size is! int || size <= 0) continue;

      files[id] = AnnouncedFile(name: name, size: size);
    }

    return PeerAnnouncement(
      uid: uid,
      lastSeen: lastSeen.toDate(),
      files: files,
    );
  }

  @override
  List<Object?> get props => [uid, lastSeen, files];
}
