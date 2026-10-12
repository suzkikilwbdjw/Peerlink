part of 'transfers_bloc.dart';

abstract class TransfersEvent extends Equatable {
  const TransfersEvent();

  @override
  List<Object?> get props => [];
}

/// Нажата кнопка "Download" в каталоге.
class StartDownload extends TransfersEvent {
  final NetworkFile file;

  const StartDownload(this.file);

  @override
  List<Object?> get props => [file];
}

/// Отмена загрузки (кнопка "Cancel"). Скачанная часть удаляется.
class CancelTransfer extends TransfersEvent {
  final String transferId;

  const CancelTransfer(this.transferId);

  @override
  List<Object?> get props => [transferId];
}

/// Пауза идущей загрузки (кнопка "Pause"). Скачанная часть сохраняется.
class PauseTransfer extends TransfersEvent {
  final String transferId;

  const PauseTransfer(this.transferId);

  @override
  List<Object?> get props => [transferId];
}

/// Продолжить приостановленную загрузку (кнопка "Resume").
class ResumeTransfer extends TransfersEvent {
  final String transferId;

  const ResumeTransfer(this.transferId);

  @override
  List<Object?> get props => [transferId];
}

/// Убрать из списка завершённые, неудавшиеся и отменённые передачи.
class ClearFinishedTransfers extends TransfersEvent {
  const ClearFinishedTransfers();
}

class _TransferUpdated extends TransfersEvent {
  final TransferInfo info;

  const _TransferUpdated(this.info);

  @override
  List<Object?> get props => [info];
}
