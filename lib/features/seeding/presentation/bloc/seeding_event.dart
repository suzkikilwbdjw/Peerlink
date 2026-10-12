part of 'seeding_bloc.dart';

abstract class SeedingEvent extends Equatable {
  const SeedingEvent();

  @override
  List<Object?> get props => [];
}

/// Прочитать сохранённый список раздач и проверить файлы на диске.
/// Отправляйте при старте приложения.
class LoadSeeds extends SeedingEvent {
  const LoadSeeds();
}

/// Заново проверить, на месте ли файлы (например, при возврате в окно
/// приложения или при открытии вкладки "My Seeding Files").
class RefreshSeedStatuses extends SeedingEvent {
  const RefreshSeedStatuses();
}

/// Добавить файлы в раздачу по путям (результат FilePicker).
class AddSeedFiles extends SeedingEvent {
  final List<String> paths;

  const AddSeedFiles(this.paths);

  @override
  List<Object?> get props => [paths];
}

/// Добавить в раздачу файл, чей SHA-256 уже проверен (скачанный и
/// сверенный с fileId). Хеширование пропускается.
///
/// Только для внутреннего использования (AutoSeeder): путь и хеш должны
/// быть доверенными, а не пришедшими из сети напрямую.
class AddVerifiedSeed extends SeedingEvent {
  final String path;
  final String fileId;

  const AddVerifiedSeed({required this.path, required this.fileId});

  @override
  List<Object?> get props => [path, fileId];
}

/// Прекратить раздачу. Файл на диске остаётся нетронутым.
class RemoveSeed extends SeedingEvent {
  final String id;

  const RemoveSeed(this.id);

  @override
  List<Object?> get props => [id];
}

/// Отменить хеширование файла (идущее или стоящее в очереди).
class CancelHashing extends SeedingEvent {
  final String path;

  const CancelHashing(this.path);

  @override
  List<Object?> get props => [path];
}

/// Убрать из списка задачу с ошибкой.
class DismissHashingTask extends SeedingEvent {
  final String path;

  const DismissHashingTask(this.path);

  @override
  List<Object?> get props => [path];
}
