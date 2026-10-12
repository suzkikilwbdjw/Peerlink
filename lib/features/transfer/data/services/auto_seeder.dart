import 'dart:async';

import 'package:p2pchat/features/seeding/presentation/bloc/seeding_bloc.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_info.dart';

/// Автоматически добавляет успешно скачанные файлы в раздачу.
///
/// Хеш считать заново не нужно: обработчик передачи уже сверил SHA-256 файла
/// с его fileId перед тем, как сообщить о завершении. Остальное (анонс в
/// сети) сделает SeedAnnouncer, который слушает SeedingBloc.
///
/// Включено ли автораздача, проверяется в момент завершения загрузки. Если
/// опция была выключена, файл можно добавить вручную кнопкой "Share a file".
class AutoSeeder {
  final Stream<TransferInfo> _transfers;
  final SeedingBloc _seeding;
  final bool Function() _isEnabled;

  /// Завершения, которые уже обработаны (защита от повторных событий).
  final Set<String> _handled = {};

  StreamSubscription<TransferInfo>? _subscription;

  AutoSeeder({
    required this._transfers,
    required this._seeding,
    required this._isEnabled,
  });

  void start() {
    _subscription ??= _transfers.listen(_onUpdate);
  }

  void _onUpdate(TransferInfo info) {
    if (info.direction != TransferDirection.download) return;
    if (info.status != TransferStatus.completed) return;

    final path = info.savedPath;
    if (path == null) return;

    // Ключ включает момент старта попытки: повторная загрузка того же файла
    // позже (после удаления) должна обрабатываться снова.
    final key = '${info.id}@${info.startedAt.microsecondsSinceEpoch}';
    if (!_handled.add(key)) return;

    if (!_isEnabled()) return;

    _seeding.add(AddVerifiedSeed(path: path, fileId: info.fileId));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
