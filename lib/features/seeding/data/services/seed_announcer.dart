import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:p2pchat/features/seeding/presentation/bloc/seeding_bloc.dart';
import 'package:p2pchat/features/tracker/data/repositories/tracker_repository.dart';

/// Держит анонс в Firebase в соответствии с локальным списком раздач.
///
/// - слушает [SeedingBloc] и публикует список, когда он меняется
///   (с задержкой, чтобы пакет добавленных файлов ушёл одной записью);
/// - раз в [heartbeatInterval] подтверждает, что пир онлайн;
/// - анонсирует только файлы со статусом available (на месте и не изменены);
/// - если запись не удалась (нет сети), следующий heartbeat повторит попытку.
///
/// SeedingBloc про трекер ничего не знает: связь только через его stream.
class SeedAnnouncer {
  /// Должен быть заметно меньше TTL, который использует каталог
  /// (по умолчанию 5 минут). 2 минуты, это 720 записей в сутки на пира.
  static const Duration heartbeatInterval = Duration(minutes: 2);

  static const Duration _debounce = Duration(milliseconds: 600);

  final TrackerRepository _tracker;
  final String _uid;
  final SeedingBloc _seeding;

  StreamSubscription<SeedingState>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _debounceTimer;

  List<SeedFile> _desired = const [];
  String? _desiredKey; // null до первого загруженного состояния
  String? _publishedKey; // что сейчас лежит в Firestore (по нашим данным)

  bool _busy = false;
  bool _again = false;
  bool _started = false;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  SeedAnnouncer({
    required this._tracker,
    required this._uid,
    required this._seeding,
  });

  void start() {
    if (_started) return;
    _started = true;

    _subscription = _seeding.stream.listen(_onSeedingState);
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _beat());

    _onSeedingState(_seeding.state);
  }

  void _onSeedingState(SeedingState state) {
    // Пока список не прочитан с диска, "пустой список" ничего не значит.
    if (!state.loaded) return;

    final ready =
        state.seeds
            .where((entry) => entry.canSeed)
            .map((entry) => entry.file)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    final key = _keyOf(ready);
    if (key == _desiredKey) return;

    _desired = ready;
    _desiredKey = key;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _reconcile);
  }

  String _keyOf(List<SeedFile> files) {
    return files.map((f) => '${f.id}:${f.size}:${f.name}').join('|');
  }

  /// Приводит Firestore к желаемому состоянию. Параллельные вызовы
  /// схлопываются: если запись уже идёт, после неё выполнится ещё один проход.
  Future<void> _reconcile() async {
    if (_busy) {
      _again = true;
      return;
    }

    _busy = true;

    try {
      do {
        _again = false;

        final files = _desired;
        final key = _desiredKey;

        if (key == null || key == _publishedKey) continue;

        if (files.isEmpty) {
          await _tracker.withdraw(_uid);
        } else {
          await _tracker.publish(_uid, files);
        }

        _publishedKey = key;
        _lastWrite = DateTime.now();
      } while (_again);
    } catch (e) {
      // _publishedKey не изменился, значит следующий heartbeat повторит попытку.
      debugPrint('[TRACKER] Не удалось обновить анонс: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _beat() async {
    await _reconcile(); // заодно повторяет неудавшуюся публикацию

    if (_busy || _desired.isEmpty) return;

    // Только что записали, heartbeat не нужен.
    if (DateTime.now().difference(_lastWrite) < heartbeatInterval ~/ 2) return;

    try {
      await _tracker.heartbeat(_uid);
      _lastWrite = DateTime.now();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        // Документ удалили (например, по TTL). Публикуем заново.
        _publishedKey = null;
        await _reconcile();
      } else {
        debugPrint('[TRACKER] Heartbeat: ${e.code} ${e.message}');
      }
    } catch (e) {
      debugPrint('[TRACKER] Heartbeat: $e');
    }
  }

  /// Останавливает синхронизацию и по возможности убирает пира из сети.
  /// Если закрыть приложение не получилось корректно, пир исчезнет из
  /// каталога сам, когда истечёт TTL.
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();

    _started = false;

    try {
      await _tracker.withdraw(_uid);
    } catch (e) {
      debugPrint('[TRACKER] Не удалось убрать анонс при выходе: $e');
    }
  }
}
