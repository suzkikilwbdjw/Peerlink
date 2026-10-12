part of 'transfers_bloc.dart';

class TransfersState extends Equatable {
  /// Все передачи (загрузки и раздачи), новые в начале.
  final List<TransferInfo> transfers;

  const TransfersState({this.transfers = const []});

  // ---- Вкладка "Transfers" ------------------------------------------------

  /// Идущие и приостановленные загрузки.
  List<TransferInfo> get activeDownloads => transfers
      .where((t) => t.direction == TransferDirection.download && t.isActive)
      .toList(growable: false);

  /// Завершённые, неудавшиеся и отменённые загрузки.
  List<TransferInfo> get finishedDownloads => transfers
      .where((t) => t.direction == TransferDirection.download && t.isFinished)
      .toList(growable: false);

  // ---- Вкладка "My Seeding Files" ------------------------------------------

  List<TransferInfo> get activeUploads => transfers
      .where((t) => t.direction == TransferDirection.upload && t.isActive)
      .toList(growable: false);

  /// Сколько байт файла отдано другим пирам за эту сессию.
  /// (Накопление между запусками приложения появится вместе с хранением
  /// статистики.)
  int uploadedBytes(String fileId) {
    return transfers
        .where(
          (t) => t.direction == TransferDirection.upload && t.fileId == fileId,
        )
        .fold<int>(0, (sum, t) => sum + t.transferredBytes);
  }

  /// Суммарная скорость отдачи файла по всем получателям, байт/с.
  double uploadSpeed(String fileId) {
    return transfers
        .where(
          (t) =>
              t.direction == TransferDirection.upload &&
              t.fileId == fileId &&
              t.isActive,
        )
        .fold<double>(0, (sum, t) => sum + t.speedBps);
  }

  /// Идёт ли сейчас загрузка этого файла (для состояния кнопки Download).
  /// Приостановленная загрузка не считается идущей.
  bool isDownloading(String fileId) {
    return transfers.any(
      (t) =>
          t.direction == TransferDirection.download &&
          t.fileId == fileId &&
          t.isRunning,
    );
  }

  /// Есть ли приостановленная загрузка этого файла (кнопка Resume).
  bool hasPaused(String fileId) {
    return transfers.any(
      (t) =>
          t.direction == TransferDirection.download &&
          t.fileId == fileId &&
          t.isPaused,
    );
  }

  /// Суммарные скорости для боковой панели.
  double get totalDownloadSpeed =>
      activeDownloads.fold<double>(0, (sum, t) => sum + t.speedBps);

  double get totalUploadSpeed =>
      activeUploads.fold<double>(0, (sum, t) => sum + t.speedBps);

  TransfersState copyWith({List<TransferInfo>? transfers}) {
    return TransfersState(transfers: transfers ?? this.transfers);
  }

  @override
  List<Object?> get props => [transfers];
}
