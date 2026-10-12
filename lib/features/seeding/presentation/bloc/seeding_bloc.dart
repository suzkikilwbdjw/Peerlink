import 'dart:async';
import 'dart:io';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:p2pchat/features/seeding/data/repositories/seed_repository.dart';
import 'package:p2pchat/features/seeding/data/services/file_hasher.dart';
import 'package:p2pchat/features/transfer/data/services/manifest_store.dart';
import 'package:path/path.dart' as p;

part 'seeding_event.dart';
part 'seeding_state.dart';

/// Понятная пользователю причина, по которой файл нельзя добавить.
class _SeedException implements Exception {
  final String message;
  const _SeedException(this.message);
}

class SeedingBloc extends Bloc<SeedingEvent, SeedingState> {
  final SeedRepository _repository;

  /// Манифесты файлов: без манифеста файл раздавать нельзя.
  final ManifestStore _manifests;

  /// Токены отмены активного хеширования, ключ — путь к файлу.
  final Map<String, HashCancelToken> _tokens = {};

  SeedingBloc(this._repository, this._manifests) : super(const SeedingState()) {
    on<LoadSeeds>(_onLoad);
    on<RefreshSeedStatuses>(_onRefresh);

    // Файлы хешируются строго по очереди: диск один, параллелизм не ускорит.
    on<AddSeedFiles>(_onAddFiles, transformer: sequential());

    on<AddVerifiedSeed>(_onAddVerified);
    on<RemoveSeed>(_onRemove);
    on<CancelHashing>(_onCancelHashing);
    on<DismissHashingTask>(_onDismissTask);
  }

  // ---------------------------------------------------------------------------
  // Загрузка и проверка статусов
  // ---------------------------------------------------------------------------

  Future<void> _onLoad(LoadSeeds event, Emitter<SeedingState> emit) async {
    final entries = await _withStatuses(_repository.load());
    emit(state.copyWith(seeds: entries, loaded: true));
  }

  Future<void> _onRefresh(
    RefreshSeedStatuses event,
    Emitter<SeedingState> emit,
  ) async {
    final entries = await _withStatuses(
      state.seeds.map((e) => e.file).toList(),
    );
    emit(state.copyWith(seeds: entries));
  }

  Future<List<SeedEntry>> _withStatuses(List<SeedFile> files) {
    return Future.wait(
      files.map((f) async {
        var status = await _repository.checkStatus(f);

        // Файл на месте, но манифеста нет (запись от старой версии).
        if (status == SeedStatus.available && !await _manifests.exists(f.id)) {
          status = SeedStatus.unindexed;
        }

        return SeedEntry(file: f, status: status);
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Добавление файлов
  // ---------------------------------------------------------------------------

  Future<void> _onAddFiles(
    AddSeedFiles event,
    Emitter<SeedingState> emit,
  ) async {
    final seededPaths = state.seeds.map((e) => e.file.path).toSet();
    final activePaths = state.tasks
        .where((t) => !t.isFailed)
        .map((t) => t.path)
        .toSet();

    final newTasks = <HashingTask>[];

    for (final path in event.paths.toSet()) {
      final name = p.basename(path);

      if (seededPaths.contains(path) || activePaths.contains(path)) {
        newTasks.add(
          HashingTask.failed(path, name, 'Файл уже в списке раздачи'),
        );
      } else {
        newTasks.add(HashingTask(path: path, name: name));
      }
    }

    // Все задачи сразу видны в UI как "в очереди".
    emit(state.copyWith(tasks: [...state.tasks, ...newTasks]));

    for (final task in newTasks.where((t) => !t.isFailed)) {
      if (emit.isDone) return;

      // Задачу могли отменить, пока она стояла в очереди.
      final stillQueued = state.tasks.any(
        (t) => t.path == task.path && !t.isFailed,
      );
      if (!stillQueued) continue;

      await _hashAndRegister(task.path, emit);
    }
  }

  Future<void> _hashAndRegister(String path, Emitter<SeedingState> emit) async {
    final token = HashCancelToken();
    _tokens[path] = token;

    try {
      final file = File(path);

      if (!await file.exists()) {
        throw const _SeedException('Файл не найден');
      }

      final statBefore = await file.stat();

      if (statBefore.size == 0) {
        throw const _SeedException('Нельзя раздавать пустой файл');
      }

      emit(
        state.copyWith(
          tasks: _updateTask(
            path,
            (t) => t.copyWith(
              status: HashingStatus.hashing,
              processedBytes: 0,
              totalBytes: statBefore.size,
            ),
          ),
        ),
      );

      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

      final manifest = await FileHasher.buildManifest(
        path,
        cancelToken: token,
        onProgress: (processed, total) {
          if (emit.isDone) return;

          // Не перестраиваем UI чаще чем раз в 150 мс.
          final now = DateTime.now();
          final isLast = processed >= total;
          if (!isLast && now.difference(lastEmit).inMilliseconds < 150) return;
          lastEmit = now;

          emit(
            state.copyWith(
              tasks: _updateTask(
                path,
                (t) => t.copyWith(processedBytes: processed, totalBytes: total),
              ),
            ),
          );
        },
      );

      // Если файл меняли во время хеширования, хеш бесполезен.
      final statAfter = await file.stat();
      if (statAfter.size != statBefore.size ||
          statAfter.modified != statBefore.modified) {
        throw const _SeedException(
          'Файл изменился во время обработки. Добавьте его ещё раз.',
        );
      }

      // Тот же контент, но другой путь.
      if (state.seeds.any((e) => e.file.id == manifest.fileId)) {
        throw const _SeedException('Файл с таким содержимым уже раздаётся');
      }

      // Манифест сохраняем до добавления записи: без него файл раздавать нельзя.
      await _manifests.save(manifest.fileId, manifest.manifestBytes);

      final seed = SeedFile(
        id: manifest.fileId,
        name: p.basename(path),
        size: statAfter.size,
        path: path,
        modifiedAtMs: statAfter.modified.millisecondsSinceEpoch,
        addedAt: DateTime.now(),
      );

      emit(
        state.copyWith(
          seeds: [
            ...state.seeds,
            SeedEntry(file: seed, status: SeedStatus.available),
          ],
          tasks: state.tasks.where((t) => t.path != path).toList(),
        ),
      );

      await _persist();
    } on HashCancelledException {
      emit(
        state.copyWith(
          tasks: state.tasks.where((t) => t.path != path).toList(),
        ),
      );
    } on _SeedException catch (e) {
      _failTask(path, e.message, emit);
    } catch (e, stackTrace) {
      debugPrint('[SEED] Ошибка добавления $path: $e');
      debugPrint('$stackTrace');
      _failTask(path, 'Не удалось обработать файл: $e', emit);
    } finally {
      _tokens.remove(path);
    }
  }

  // ---------------------------------------------------------------------------
  // Файл с уже проверенным хешем (автораздача скачанного)
  // ---------------------------------------------------------------------------

  Future<void> _onAddVerified(
    AddVerifiedSeed event,
    Emitter<SeedingState> emit,
  ) async {
    try {
      final stat = await File(event.path).stat();

      if (stat.type == FileSystemEntityType.notFound || stat.size == 0) return;

      // Манифест сохранён движком загрузки; без него раздавать нельзя.
      if (!await _manifests.exists(event.fileId)) {
        debugPrint('[SEED] Нет манифеста для ${event.fileId}, пропускаем');
        return;
      }

      // Проверяем уже после await: за это время список мог измениться.
      final duplicate = state.seeds.any(
        (e) => e.file.id == event.fileId || e.file.path == event.path,
      );
      if (duplicate) return;

      final seed = SeedFile(
        id: event.fileId,
        name: p.basename(event.path),
        size: stat.size,
        path: event.path,
        modifiedAtMs: stat.modified.millisecondsSinceEpoch,
        addedAt: DateTime.now(),
      );

      emit(
        state.copyWith(
          seeds: [
            ...state.seeds,
            SeedEntry(file: seed, status: SeedStatus.available),
          ],
        ),
      );

      await _persist();
    } catch (e, stackTrace) {
      debugPrint(
        '[SEED] Не удалось добавить проверенный файл ${event.path}: $e',
      );
      debugPrint('$stackTrace');
    }
  }

  // ---------------------------------------------------------------------------
  // Остальные события
  // ---------------------------------------------------------------------------

  Future<void> _onRemove(RemoveSeed event, Emitter<SeedingState> emit) async {
    final remaining = state.seeds.where((e) => e.file.id != event.id).toList();
    if (remaining.length == state.seeds.length) return;

    // Сам файл на диске не трогаем: пользователь просто перестаёт его раздавать.
    emit(state.copyWith(seeds: remaining));
    await _persist();
  }

  void _onCancelHashing(CancelHashing event, Emitter<SeedingState> emit) {
    final token = _tokens[event.path];

    if (token != null) {
      // Хеширование уже идёт: изолят остановится, задача удалится в
      // _hashAndRegister.
      token.cancel();
    } else {
      // Задача ещё в очереди.
      emit(
        state.copyWith(
          tasks: state.tasks.where((t) => t.path != event.path).toList(),
        ),
      );
    }
  }

  void _onDismissTask(DismissHashingTask event, Emitter<SeedingState> emit) {
    emit(
      state.copyWith(
        tasks: state.tasks.where((t) => t.path != event.path).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Вспомогательное
  // ---------------------------------------------------------------------------

  /// Сохраняет актуальный список: читает state уже после emit.
  Future<void> _persist() {
    return _repository.save(state.seeds.map((e) => e.file).toList());
  }

  List<HashingTask> _updateTask(
    String path,
    HashingTask Function(HashingTask) update,
  ) {
    return state.tasks.map((t) => t.path == path ? update(t) : t).toList();
  }

  void _failTask(String path, String message, Emitter<SeedingState> emit) {
    if (emit.isDone) return;

    emit(
      state.copyWith(
        tasks: _updateTask(
          path,
          (t) => t.copyWith(status: HashingStatus.failed, error: message),
        ),
      ),
    );
  }

  @override
  Future<void> close() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    return super.close();
  }
}
