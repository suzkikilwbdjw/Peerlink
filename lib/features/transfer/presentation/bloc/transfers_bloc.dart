import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:p2pchat/features/tracker/data/models/network_file.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_info.dart';
import 'package:p2pchat/features/transfer/data/services/transfer_coordinator.dart';

part 'transfers_event.dart';
part 'transfers_state.dart';

/// Состояние всех передач для интерфейса. Вся работа с сетью живёт в
/// [TransferCoordinator], блок только хранит снимки и передаёт команды.
class TransfersBloc extends Bloc<TransfersEvent, TransfersState> {
  /// Сколько завершённых передач помнить (чтобы список не рос бесконечно).
  static const int _maxEntries = 200;

  final TransferCoordinator _coordinator;
  StreamSubscription<TransferInfo>? _subscription;

  TransfersBloc(this._coordinator) : super(const TransfersState()) {
    on<StartDownload>(_onStart);
    on<CancelTransfer>(_onCancel);
    on<PauseTransfer>(_onPause);
    on<ResumeTransfer>(_onResume);
    on<ClearFinishedTransfers>(_onClear);
    on<_TransferUpdated>(_onUpdated);

    _subscription = _coordinator.updates.listen(
      (info) => add(_TransferUpdated(info)),
    );

    // Показываем загрузки, прерванные до перезапуска приложения. Делаем это
    // после подписки, чтобы не пропустить обновления.
    _coordinator.restorePartials().catchError((Object e) {
      debugPrint('[TRANSFER] Не удалось восстановить загрузки: $e');
    });
  }

  void _onStart(StartDownload event, Emitter<TransfersState> emit) {
    // Повторное нажатие, пока файл уже скачивается, ничего не делает.
    if (state.isDownloading(event.file.id)) return;

    _coordinator.download(event.file).catchError((Object e) {
      debugPrint('[TRANSFER] Неожиданная ошибка загрузки: $e');
    });
  }

  void _onCancel(CancelTransfer event, Emitter<TransfersState> emit) {
    _coordinator.cancel(event.transferId);
  }

  void _onPause(PauseTransfer event, Emitter<TransfersState> emit) {
    _coordinator.pause(event.transferId);
  }

  void _onResume(ResumeTransfer event, Emitter<TransfersState> emit) {
    _coordinator.resume(event.transferId).catchError((Object e) {
      debugPrint('[TRANSFER] Не удалось возобновить загрузку: $e');
    });
  }

  void _onClear(ClearFinishedTransfers event, Emitter<TransfersState> emit) {
    emit(
      state.copyWith(
        transfers: state.transfers.where((t) => t.isActive).toList(),
      ),
    );
  }

  void _onUpdated(_TransferUpdated event, Emitter<TransfersState> emit) {
    final list = [...state.transfers];
    final index = list.indexWhere((t) => t.id == event.info.id);

    if (index >= 0) {
      list[index] = event.info;
    } else {
      list.insert(0, event.info);
    }

    // Старые завершённые записи отбрасываем с конца списка.
    while (list.length > _maxEntries) {
      final i = list.lastIndexWhere((t) => t.isFinished);
      if (i < 0) break;
      list.removeAt(i);
    }

    emit(state.copyWith(transfers: list));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
