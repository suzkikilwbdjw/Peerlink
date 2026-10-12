import 'package:equatable/equatable.dart';

enum TransferDirection { download, upload }

enum TransferStatus {
  /// Ищем раздающего и устанавливаем соединение (или ждём очереди).
  connecting,

  /// Запрос отправлен, ждём ответ раздающего.
  requesting,

  /// Идёт передача данных.
  active,

  /// Приостановлена пользователем или прервана (обрыв, раздающий ушёл).
  /// Недокачанный файл сохранён, загрузку можно продолжить.
  paused,

  /// Данные получены, проверяется SHA-256.
  verifying,

  completed,
  failed,
  cancelled,
}

/// Снимок состояния одной передачи. Неизменяемый: каждое обновление это
/// новый объект.
class TransferInfo extends Equatable {
  final String id;
  final TransferDirection direction;
  final String peerId;
  final String fileId;
  final String name;
  final int totalBytes;
  final int transferredBytes;

  /// Текущая скорость, байт/с (скользящее окно ~3 с).
  final double speedBps;

  final TransferStatus status;
  final String? error;

  /// Путь к сохранённому файлу (только для завершённых загрузок).
  final String? savedPath;

  final DateTime startedAt;

  /// Сколько раздающих участвует в загрузке прямо сейчас (для раздачи 0).
  final int peerCount;

  const TransferInfo({
    required this.id,
    required this.direction,
    required this.peerId,
    required this.fileId,
    required this.name,
    required this.totalBytes,
    required this.status,
    required this.startedAt,
    this.transferredBytes = 0,
    this.speedBps = 0,
    this.error,
    this.savedPath,
    this.peerCount = 0,
  });

  bool get isFinished =>
      status == TransferStatus.completed ||
      status == TransferStatus.failed ||
      status == TransferStatus.cancelled;

  /// Не завершена: идёт, ждёт или приостановлена.
  bool get isActive => !isFinished;

  bool get isPaused => status == TransferStatus.paused;

  /// Выполняется прямо сейчас (не пауза и не завершена).
  bool get isRunning => isActive && !isPaused;

  /// Идентификатор загрузки файла для интерфейса. Он один и тот же при
  /// повторных попытках и докачке, поэтому запись в списке обновляется на месте.
  static String downloadIdFor(String fileId) => 'dl-$fileId';

  double get progress =>
      totalBytes == 0 ? 0 : (transferredBytes / totalBytes).clamp(0.0, 1.0);

  /// Оценка оставшегося времени; null, если скорость неизвестна.
  Duration? get eta {
    if (isFinished || speedBps <= 0) return null;

    final remaining = totalBytes - transferredBytes;
    if (remaining <= 0) return null;

    return Duration(seconds: (remaining / speedBps).ceil());
  }

  TransferInfo copyWith({
    String? peerId,
    int? totalBytes,
    int? transferredBytes,
    double? speedBps,
    TransferStatus? status,
    String? error,
    String? savedPath,
    int? peerCount,
  }) {
    return TransferInfo(
      id: id,
      direction: direction,
      peerId: peerId ?? this.peerId,
      fileId: fileId,
      name: name,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      speedBps: speedBps ?? this.speedBps,
      status: status ?? this.status,
      error: error ?? this.error,
      savedPath: savedPath ?? this.savedPath,
      startedAt: startedAt,
      peerCount: peerCount ?? this.peerCount,
    );
  }

  @override
  List<Object?> get props => [
    id,
    direction,
    peerId,
    fileId,
    name,
    totalBytes,
    transferredBytes,
    speedBps,
    status,
    error,
    savedPath,
    startedAt,
    peerCount,
  ];
}
