import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:p2pchat/features/tracker/data/models/peer_announcement.dart'
    show isValidFileId;

/// Параметры протокола передачи файлов по DataChannel.
///
/// Протокол работает через "сессии". Скачивающий открывает сессию на
/// конкретный файл у раздающего, затем по одному запрашивает куски. Одно
/// соединение может нести несколько сессий (разные файлы) одновременно.
///
///   A -> B  dl_open      {sid, fileId}
///   B -> A  dl_ready     {sid, size, pieceSize, pieceCount, manifestLength}
///                        (или dl_reject {sid, reason})
///   A -> B  manifest_get {sid}
///   B -> A  [бинарные кадры kind=manifest]   манифест файла
///   A -> B  piece_get    {sid, index}
///   B -> A  [бинарные кадры kind=piece]      данные куска по 16 КБ
///   A -> B  piece_cancel {sid, index}        (необязательно)
///   A -> B  dl_close     {sid}
///   B -> A  dl_error     {sid, message}      раздача остановлена/сбой
///
/// Целостность обеспечивается манифестом: скачивающий проверяет SHA-256
/// каждого куска сам, поэтому подтверждения (ACK) не нужны, а кадры данных
/// можно получать от нескольких пиров параллельно.
class TransferProtocol {
  TransferProtocol._();

  /// Размер полезных данных в одном бинарном кадре.
  static const int chunkSize = 16 * 1024;

  /// Если за это время по запрошенному куску не пришло ни байта, запрос
  /// считается зависшим и кусок можно запросить у другого пира.
  static const Duration pieceIdleTimeout = Duration(seconds: 20);

  static const Duration openTimeout = Duration(seconds: 15);
  static const Duration manifestTimeout = Duration(seconds: 30);

  static const int maxControlMessageLength = 4096;

  /// Сколько сессий раздачи держим на одном соединении.
  static const int maxServeSessions = 4;

  /// Верхняя граница размера манифеста, которую готовы принять.
  static const int maxManifestLength = 8 * 1024 * 1024;
}

// =============================================================================
// Исключения
// =============================================================================

/// Передача отменена пользователем.
class TransferCancelledException implements Exception {
  const TransferCancelledException();

  String get message => 'Передача отменена';

  @override
  String toString() => message;
}

/// Загрузка поставлена на паузу пользователем (скачанная часть сохранена).
class TransferPausedException implements Exception {
  const TransferPausedException();

  String get message => 'Загрузка приостановлена';

  @override
  String toString() => message;
}

/// Передача прервана (обрыв связи, раздающие закончились), но скачанная
/// часть сохранена: загрузку можно продолжить.
class TransferInterruptedException implements Exception {
  final String message;

  const TransferInterruptedException(this.message);

  @override
  String toString() => message;
}

/// Раздающий отказался отдавать файл.
class TransferRejectedException implements Exception {
  final String reason;

  const TransferRejectedException(this.reason);

  String get message => switch (reason) {
    'not_found' => 'Раздающий больше не раздаёт этот файл',
    'unavailable' => 'Файл недоступен у раздающего',
    'busy' => 'Раздающий занят другими передачами',
    'invalid' => 'Раздающий прислал некорректные данные',
    _ => 'Раздающий отклонил запрос',
  };

  @override
  String toString() => message;
}

/// Человекочитаемый текст ошибки без технических префиксов.
String describeError(Object error) {
  if (error is StateError) return error.message;
  if (error is TimeoutException) {
    return error.message ?? 'Превышено время ожидания';
  }
  if (error is FileSystemException) {
    final path = error.path;
    return path == null || path.isEmpty
        ? error.message
        : '${error.message} ($path)';
  }
  return error.toString();
}

// =============================================================================
// Управляющие (текстовые JSON) сообщения
// =============================================================================

sealed class ControlMessage {
  /// Идентификатор сессии, выбирает скачивающий (uint32).
  final int sessionId;

  const ControlMessage(this.sessionId);

  String get type;

  Map<String, dynamic> toJson() => {'type': type, 'sid': sessionId};

  String encode() => jsonEncode(toJson());

  /// Разбирает сообщение от пира. Данным нельзя доверять: при любой
  /// некорректности возвращается null.
  static ControlMessage? tryParse(String text) {
    if (text.length > TransferProtocol.maxControlMessageLength) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }

    if (decoded is! Map<String, dynamic>) return null;

    final type = decoded['type'];
    final sid = decoded['sid'];

    if (type is! String) return null;
    if (sid is! int || sid < 0 || sid > 0xFFFFFFFF) return null;

    switch (type) {
      case 'dl_open':
        final fileId = decoded['fileId'];
        if (fileId is! String || !isValidFileId(fileId)) return null;
        return DlOpen(sid, fileId);

      case 'dl_ready':
        final size = decoded['size'];
        final pieceSize = decoded['pieceSize'];
        final pieceCount = decoded['pieceCount'];
        final manifestLength = decoded['manifestLength'];
        if (size is! int || size <= 0) return null;
        if (pieceSize is! int || pieceSize <= 0) return null;
        if (pieceCount is! int || pieceCount <= 0) return null;
        if (manifestLength is! int || manifestLength <= 0) return null;
        return DlReady(sid, size, pieceSize, pieceCount, manifestLength);

      case 'dl_reject':
        final reason = decoded['reason'];
        if (reason is! String || reason.length > 64) return null;
        return DlReject(sid, reason);

      case 'manifest_get':
        return ManifestGet(sid);

      case 'piece_get':
        final index = decoded['index'];
        if (index is! int || index < 0) return null;
        return PieceGet(sid, index);

      case 'piece_cancel':
        final index = decoded['index'];
        if (index is! int || index < 0) return null;
        return PieceCancel(sid, index);

      case 'dl_close':
        return DlClose(sid);

      case 'dl_error':
        final message = decoded['message'];
        if (message is! String || message.length > 300) return null;
        return DlError(sid, message);
    }

    return null;
  }
}

class DlOpen extends ControlMessage {
  final String fileId;

  const DlOpen(super.sessionId, this.fileId);

  @override
  String get type => 'dl_open';

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'fileId': fileId};
}

class DlReady extends ControlMessage {
  final int size;
  final int pieceSize;
  final int pieceCount;
  final int manifestLength;

  const DlReady(
    super.sessionId,
    this.size,
    this.pieceSize,
    this.pieceCount,
    this.manifestLength,
  );

  @override
  String get type => 'dl_ready';

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'size': size,
    'pieceSize': pieceSize,
    'pieceCount': pieceCount,
    'manifestLength': manifestLength,
  };
}

class DlReject extends ControlMessage {
  /// not_found | unavailable | busy | invalid
  final String reason;

  const DlReject(super.sessionId, this.reason);

  @override
  String get type => 'dl_reject';

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'reason': reason};
}

class ManifestGet extends ControlMessage {
  const ManifestGet(super.sessionId);

  @override
  String get type => 'manifest_get';
}

class PieceGet extends ControlMessage {
  final int index;

  const PieceGet(super.sessionId, this.index);

  @override
  String get type => 'piece_get';

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'index': index};
}

class PieceCancel extends ControlMessage {
  final int index;

  const PieceCancel(super.sessionId, this.index);

  @override
  String get type => 'piece_cancel';

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'index': index};
}

class DlClose extends ControlMessage {
  const DlClose(super.sessionId);

  @override
  String get type => 'dl_close';
}

class DlError extends ControlMessage {
  final String message;

  const DlError(super.sessionId, this.message);

  @override
  String get type => 'dl_error';

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'message': message};
}

// =============================================================================
// Бинарные кадры данных
// =============================================================================

/// Бинарное сообщение: 13 байт заголовка и до [TransferProtocol.chunkSize]
/// байт данных.
///
///   kind (1) | sessionId (4) | index (4) | offset (4) | payload
///
/// Для кусков index это номер куска, а offset смещение внутри него.
/// Для манифеста index всегда 0, а offset смещение внутри манифеста.
class SwarmFrame {
  static const int headerLength = 13;
  static const int kindPiece = 1;
  static const int kindManifest = 2;

  final int kind;
  final int sessionId;
  final int index;
  final int offset;
  final Uint8List payload;

  const SwarmFrame({
    required this.kind,
    required this.sessionId,
    required this.index,
    required this.offset,
    required this.payload,
  });

  static SwarmFrame? tryParse(Uint8List data) {
    if (data.length < headerLength) return null;

    final view = ByteData.sublistView(data);
    final kind = view.getUint8(0);

    if (kind != kindPiece && kind != kindManifest) return null;

    return SwarmFrame(
      kind: kind,
      sessionId: view.getUint32(1, Endian.big),
      index: view.getUint32(5, Endian.big),
      offset: view.getUint32(9, Endian.big),
      payload: Uint8List.sublistView(data, headerLength),
    );
  }

  /// Записывает заголовок в начало [frame]; данные пишутся после него
  /// (с позиции [headerLength]).
  static void writeHeader(
    Uint8List frame, {
    required int kind,
    required int sessionId,
    required int index,
    required int offset,
  }) {
    final view = ByteData.sublistView(frame);
    view.setUint8(0, kind);
    view.setUint32(1, sessionId, Endian.big);
    view.setUint32(5, index, Endian.big);
    view.setUint32(9, offset, Endian.big);
  }
}
