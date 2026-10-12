part of 'seeding_bloc.dart';

enum HashingStatus { queued, hashing, failed }

/// Файл, который ещё обрабатывается (или не удалось обработать).
/// Идентификатор задачи — путь к файлу.
class HashingTask extends Equatable {
  final String path;
  final String name;
  final HashingStatus status;
  final int processedBytes;
  final int totalBytes;
  final String? error;

  const HashingTask({
    required this.path,
    required this.name,
    this.status = HashingStatus.queued,
    this.processedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  const HashingTask.failed(String path, String name, String error)
    : this(path: path, name: name, status: HashingStatus.failed, error: error);

  bool get isFailed => status == HashingStatus.failed;

  double get progress =>
      totalBytes == 0 ? 0 : (processedBytes / totalBytes).clamp(0.0, 1.0);

  HashingTask copyWith({
    HashingStatus? status,
    int? processedBytes,
    int? totalBytes,
    String? error,
  }) {
    return HashingTask(
      path: path,
      name: name,
      status: status ?? this.status,
      processedBytes: processedBytes ?? this.processedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
    path,
    name,
    status,
    processedBytes,
    totalBytes,
    error,
  ];
}

class SeedingState extends Equatable {
  /// false, пока список не прочитан из shared_preferences.
  final bool loaded;

  /// Файлы, которые уже раздаются (или раздавались, но пропали с диска).
  final List<SeedEntry> seeds;

  /// Файлы, которые сейчас хешируются, ждут очереди или завершились ошибкой.
  final List<HashingTask> tasks;

  const SeedingState({
    this.loaded = false,
    this.seeds = const [],
    this.tasks = const [],
  });

  SeedingState copyWith({
    bool? loaded,
    List<SeedEntry>? seeds,
    List<HashingTask>? tasks,
  }) {
    return SeedingState(
      loaded: loaded ?? this.loaded,
      seeds: seeds ?? this.seeds,
      tasks: tasks ?? this.tasks,
    );
  }

  @override
  List<Object?> get props => [loaded, seeds, tasks];
}
