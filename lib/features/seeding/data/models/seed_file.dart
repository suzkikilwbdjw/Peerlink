import 'package:equatable/equatable.dart';

/// Файл, который пользователь раздаёт в сеть.
///
/// [id] — SHA-256 содержимого (hex). Это "info-hash" нашей сети: один и тот же
/// файл от разных раздающих получает один и тот же id.
///
/// Сохраняется в shared_preferences как JSON.
class SeedFile extends Equatable {
  final String id;
  final String name;
  final int size;

  /// Абсолютный путь на диске. Сам файл мы не копируем и не перемещаем.
  final String path;

  /// mtime файла (мс) на момент хеширования. Нужен, чтобы дёшево понять,
  /// что файл изменили, не пересчитывая хеш.
  final int modifiedAtMs;

  final DateTime addedAt;

  const SeedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.path,
    required this.modifiedAtMs,
    required this.addedAt,
  });

  factory SeedFile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final size = json['size'];
    final path = json['path'];
    final modifiedAtMs = json['modifiedAtMs'];
    final addedAtMs = json['addedAtMs'];

    if (id is! String ||
        name is! String ||
        size is! int ||
        path is! String ||
        modifiedAtMs is! int ||
        addedAtMs is! int) {
      throw const FormatException('Некорректная запись SeedFile');
    }

    return SeedFile(
      id: id,
      name: name,
      size: size,
      path: path,
      modifiedAtMs: modifiedAtMs,
      addedAt: DateTime.fromMillisecondsSinceEpoch(addedAtMs),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'path': path,
    'modifiedAtMs': modifiedAtMs,
    'addedAtMs': addedAt.millisecondsSinceEpoch,
  };

  @override
  List<Object?> get props => [id, name, size, path, modifiedAtMs, addedAt];
}

/// Состояние файла на диске относительно сохранённых данных.
enum SeedStatus {
  /// Файл на месте, размер и дата изменения совпадают. Можно раздавать.
  available,

  /// Файл удалён или перемещён.
  missing,

  /// Файл изменён после добавления: хеш больше не соответствует содержимому.
  modified,

  /// Для файла нет манифеста (запись создана старой версией приложения):
  /// раздавать нельзя, нужно удалить запись и добавить файл заново.
  unindexed,
}

/// SeedFile + его актуальный статус на диске (в shared_preferences не хранится).
class SeedEntry extends Equatable {
  final SeedFile file;
  final SeedStatus status;

  const SeedEntry({required this.file, required this.status});

  /// Только такие файлы можно анонсировать в сеть и отдавать пирам.
  bool get canSeed => status == SeedStatus.available;

  @override
  List<Object?> get props => [file, status];
}
