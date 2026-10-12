import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:p2pchat/features/connection/data/services/webrtc_services.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:p2pchat/features/transfer/data/models/piece_manifest.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_info.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_protocol.dart';
import 'package:p2pchat/features/transfer/data/services/manifest_store.dart';
import 'package:p2pchat/features/transfer/data/services/speed_meter.dart';

/// Конечная точка протокола передачи на ОДНОМ соединении с пиром.
///
/// У неё две роли одновременно:
/// - раздающая: отвечает на dl_open / manifest_get / piece_get и отдаёт
///   данные из файла (сессии раздачи, [_ServeSession]);
/// - клиентская: [openFile] открывает сессию у раздающего и возвращает
///   [RemoteFile], через который движок загрузки запрашивает куски.
///
/// Решение, какие куски у кого брать, здесь не принимается: этим занимается
/// SwarmDownload. Обработчик только передаёт данные и сообщает об ошибках.
class PeerTransferHandler {
  static const Duration _emitInterval = Duration(milliseconds: 200);

  final String peerId;
  final WebRTCService _webrtc;

  /// Файл, который мы сейчас готовы раздавать, или null.
  final SeedFile? Function(String fileId) _lookupSeed;

  final ManifestStore _manifests;
  final void Function(TransferInfo info) _onUpdate;

  final Map<int, _ServeSession> _serving = {};
  final Map<int, RemoteFile> _remote = {};
  int _nextSessionId = 1;

  /// Входящие сообщения обрабатываются строго по порядку.
  Future<void> _inbound = Future<void>.value();

  /// Отдача данных идёт отдельной очередью (по одному заданию), чтобы медленная
  /// отправка не задерживала обработку входящих сообщений (например, отмену).
  Future<void> _serveChain = Future<void>.value();

  bool _disposed = false;

  PeerTransferHandler({
    required this.peerId,
    required this._webrtc,
    required this._lookupSeed,
    required this._manifests,
    required this._onUpdate,
  });

  // ===========================================================================
  // Вход: сообщения DataChannel
  // ===========================================================================

  /// Передайте сюда каждое сообщение из DataChannel этого пира.
  void onMessage(RTCDataChannelMessage message) {
    if (_disposed) return;

    _inbound = _inbound.then((_) => _process(message));
  }

  Future<void> _process(RTCDataChannelMessage message) async {
    try {
      if (message.isBinary) {
        final frame = SwarmFrame.tryParse(message.binary);
        if (frame != null) _remote[frame.sessionId]?._onFrame(frame);
        return;
      }

      final control = ControlMessage.tryParse(message.text);

      if (control == null) {
        debugPrint(
          '[TRANSFER][$peerId] Некорректное сообщение проигнорировано',
        );
        return;
      }

      switch (control) {
        case DlOpen c:
          await _onDlOpen(c);
        case DlReady c:
          _remote[c.sessionId]?._onReady(c);
        case DlReject c:
          _remote[c.sessionId]?._onReject(c);
        case ManifestGet c:
          _onManifestGet(c);
        case PieceGet c:
          _onPieceGet(c);
        case PieceCancel c:
          _serving[c.sessionId]?.cancelled.add(c.index);
        case DlClose c:
          final session = _serving[c.sessionId];
          if (session != null) _closeServe(session);
        case DlError c:
          _remote[c.sessionId]?._terminate(
            TransferInterruptedException('Раздающий: ${c.message}'),
          );
      }
    } catch (e, stackTrace) {
      debugPrint('[TRANSFER][$peerId] Ошибка обработки сообщения: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _send(ControlMessage message) {
    return _webrtc.sendDataTo(peerId, message.encode());
  }

  /// Отправка, ошибки которой не важны (закрытие, отмена).
  Future<void> _trySend(ControlMessage message) async {
    try {
      await _send(message);
    } catch (_) {}
  }

  // ===========================================================================
  // Клиентская роль: мы скачиваем
  // ===========================================================================

  /// Открывает сессию на файл [fileId] у этого пира.
  ///
  /// Бросает [TransferRejectedException], если пир отказал, и другие
  /// исключения при сбоях. Пир при этом не обязан отдавать весь файл: куски
  /// запрашиваются через возвращённый [RemoteFile].
  Future<RemoteFile> openFile(String fileId) async {
    if (_disposed) {
      throw const TransferInterruptedException('Соединение закрыто');
    }

    final sid = _nextSessionId++;
    final remote = RemoteFile._(this, sid, fileId);
    _remote[sid] = remote;

    try {
      await _send(DlOpen(sid, fileId));

      await remote._ready.future.timeout(
        TransferProtocol.openTimeout,
        onTimeout: () => throw TimeoutException('Раздающий не ответил'),
      );

      return remote;
    } catch (e) {
      _remote.remove(sid);
      remote._failQuietly(e);
      rethrow;
    }
  }

  // ===========================================================================
  // Раздающая роль: у нас просят файл
  // ===========================================================================

  Future<void> _onDlOpen(DlOpen m) async {
    final sid = m.sessionId;

    if (_serving.containsKey(sid)) return;

    if (_serving.length >= TransferProtocol.maxServeSessions) {
      await _send(DlReject(sid, 'busy'));
      return;
    }

    final seed = _lookupSeed(m.fileId);

    if (seed == null) {
      await _send(DlReject(sid, 'not_found'));
      return;
    }

    // Файл мог пропасть или измениться с момента добавления.
    final stat = await File(seed.path).stat();

    if (stat.type == FileSystemEntityType.notFound ||
        stat.size != seed.size ||
        stat.modified.millisecondsSinceEpoch != seed.modifiedAtMs) {
      await _send(DlReject(sid, 'unavailable'));
      return;
    }

    final manifestBytes = await _manifests.loadBytes(m.fileId);
    final manifest = manifestBytes == null
        ? null
        : PieceManifest.tryDecode(manifestBytes);

    if (manifestBytes == null ||
        manifest == null ||
        manifest.size != seed.size) {
      await _send(DlReject(sid, 'unavailable'));
      return;
    }

    // Пока читали диск, могли прислать тот же sid ещё раз.
    if (_serving.containsKey(sid) || _disposed) return;

    final session = _ServeSession(
      sid: sid,
      seed: seed,
      manifest: manifest,
      manifestBytes: manifestBytes,
      info: TransferInfo(
        id: 'ul-$peerId-$sid',
        direction: TransferDirection.upload,
        peerId: peerId,
        fileId: seed.id,
        name: seed.name,
        totalBytes: seed.size,
        status: TransferStatus.active,
        startedAt: DateTime.now(),
      ),
    );

    _serving[sid] = session;
    _onUpdate(session.info);

    await _send(
      DlReady(
        sid,
        manifest.size,
        manifest.pieceSize,
        manifest.pieceCount,
        manifestBytes.length,
      ),
    );
  }

  void _onManifestGet(ManifestGet m) {
    final s = _serving[m.sessionId];
    if (s == null || s.closed) return;

    _enqueueServe(() => _serveManifest(s));
  }

  void _onPieceGet(PieceGet m) {
    final s = _serving[m.sessionId];
    if (s == null || s.closed) return;

    // Повторный запрос отменённого куска отменяет отмену.
    s.cancelled.remove(m.index);

    _enqueueServe(() => _servePiece(s, m.index));
  }

  /// Ставит задание отдачи в очередь. Задания не должны бросать исключения.
  void _enqueueServe(Future<void> Function() job) {
    _serveChain = _serveChain.then((_) => job()).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('[TRANSFER][$peerId] Ошибка отдачи: $e');
    });
  }

  Future<void> _serveManifest(_ServeSession s) async {
    if (s.closed) return;

    try {
      final bytes = s.manifestBytes;

      for (var offset = 0; offset < bytes.length;) {
        if (s.closed) return;

        final n = math.min(TransferProtocol.chunkSize, bytes.length - offset);
        final frame = Uint8List(SwarmFrame.headerLength + n);

        SwarmFrame.writeHeader(
          frame,
          kind: SwarmFrame.kindManifest,
          sessionId: s.sid,
          index: 0,
          offset: offset,
        );
        frame.setRange(
          SwarmFrame.headerLength,
          SwarmFrame.headerLength + n,
          bytes,
          offset,
        );

        await _webrtc.sendBytesTo(peerId, frame);
        offset += n;
      }
    } catch (e) {
      await _failServe(s, e);
    }
  }

  Future<void> _servePiece(_ServeSession s, int index) async {
    if (s.closed) return;

    // Запрос отменили, пока он стоял в очереди.
    if (s.cancelled.remove(index)) return;

    final manifest = s.manifest;

    if (index < 0 || index >= manifest.pieceCount) {
      await _failServe(s, StateError('Неверный номер куска'));
      return;
    }

    try {
      final raf = s.raf ??= await File(s.seed.path).open();

      final length = manifest.pieceLength(index);
      await raf.setPosition(manifest.pieceOffset(index));

      var sent = 0;

      while (sent < length) {
        if (s.closed) return;
        if (s.cancelled.remove(index)) return;

        final n = math.min(TransferProtocol.chunkSize, length - sent);
        final frame = Uint8List(SwarmFrame.headerLength + n);

        SwarmFrame.writeHeader(
          frame,
          kind: SwarmFrame.kindPiece,
          sessionId: s.sid,
          index: index,
          offset: sent,
        );

        // Читаем прямо в кадр после заголовка: без лишнего копирования.
        final read = await raf.readInto(
          frame,
          SwarmFrame.headerLength,
          SwarmFrame.headerLength + n,
        );

        if (read != n) {
          throw StateError('Файл на диске изменился во время раздачи');
        }

        await _webrtc.sendBytesTo(peerId, frame);

        sent += n;
        s.served += n;
        s.meter.add(n);

        final now = DateTime.now();
        if (now.difference(s.lastEmit) >= _emitInterval) {
          s.lastEmit = now;
          s.info = s.info.copyWith(
            transferredBytes: math.min(s.served, s.seed.size),
            speedBps: s.meter.bytesPerSecond,
          );
          _onUpdate(s.info);
        }
      }
    } catch (e) {
      await _failServe(s, e);
    }
  }

  /// Раздача этой сессии прервалась по нашей ошибке (выполняется в очереди
  /// отдачи, поэтому файл закрывать безопасно).
  Future<void> _failServe(_ServeSession s, Object error) async {
    if (s.closed) return;

    s.closed = true;
    _serving.remove(s.sid);

    s.info = s.info.copyWith(
      status: TransferStatus.failed,
      error: describeError(error),
      transferredBytes: math.min(s.served, s.seed.size),
      speedBps: 0,
    );
    _onUpdate(s.info);

    try {
      await s.raf?.close();
    } catch (_) {}
    s.raf = null;

    unawaited(_trySend(DlError(s.sid, describeError(error))));
  }

  /// Нормальное закрытие сессии раздачи (закрыл скачивающий или соединение).
  void _closeServe(_ServeSession s) {
    if (s.closed) return;

    s.closed = true;
    _serving.remove(s.sid);

    s.info = s.info.copyWith(
      status: s.served > 0
          ? TransferStatus.completed
          : TransferStatus.cancelled,
      transferredBytes: math.min(s.served, s.seed.size),
      speedBps: 0,
    );
    _onUpdate(s.info);

    // Закрываем файл в очереди отдачи: сейчас им может пользоваться задание.
    _enqueueServe(() async {
      try {
        await s.raf?.close();
      } catch (_) {}
      s.raf = null;
    });
  }

  /// Останавливает все сессии раздачи файла [fileId] (кнопка "Stop seeding").
  /// Скачивающие получают dl_error и ищут другого раздающего.
  void stopServing(String fileId) {
    for (final s in _serving.values.toList()) {
      if (s.seed.id != fileId) continue;

      unawaited(_trySend(DlError(s.sid, 'Раздача остановлена')));
      _closeServe(s);
    }
  }

  // ===========================================================================
  // Завершение работы
  // ===========================================================================

  /// Вызывается, когда соединение с пиром закрыто.
  Future<void> dispose({String reason = 'Соединение закрыто'}) async {
    _disposed = true;

    for (final remote in _remote.values.toList()) {
      remote._terminate(TransferInterruptedException(reason));
    }
    _remote.clear();

    for (final s in _serving.values.toList()) {
      _closeServe(s);
    }
  }
}

// =============================================================================
// Клиентская сторона: файл у конкретного раздающего
// =============================================================================

/// Открытая сессия на файл у одного раздающего.
///
/// Через неё движок загрузки получает манифест и запрашивает куски. Целостность
/// кусков здесь не проверяется: это делает вызывающий код по манифесту.
class RemoteFile {
  RemoteFile._(this._handler, this.sessionId, this.fileId) {
    // Ошибка в Completer без слушателя иначе станет необработанным исключением.
    _ready.future.then((_) {}, onError: (_) {});
  }

  final PeerTransferHandler _handler;
  final int sessionId;
  final String fileId;

  final Completer<void> _ready = Completer<void>();

  // Заполняются, когда пришёл dl_ready.
  int size = 0;
  int pieceSize = 0;
  int pieceCount = 0;
  int manifestLength = 0;

  /// Вызывается один раз, если сессия закрыта НЕ нами: обрыв связи, раздающий
  /// остановил раздачу, нарушение протокола.
  void Function(Object reason)? onClosed;

  /// Сколько байт данных пришло (для измерения скорости).
  void Function(int bytes)? onBytes;

  bool _closed = false;
  _PendingManifest? _manifest;
  final Map<int, _PendingPiece> _pieces = {};

  String get peerId => _handler.peerId;

  bool get isClosed => _closed;

  /// Скачивает манифест файла. Здесь он не проверяется: вызывающий код
  /// должен сверить SHA-256 манифеста с [fileId].
  Future<Uint8List> fetchManifest() async {
    if (_closed) throw const TransferInterruptedException('Сессия закрыта');
    if (_manifest != null) throw StateError('Манифест уже запрашивается');

    if (manifestLength <= 0 ||
        manifestLength > TransferProtocol.maxManifestLength) {
      throw const TransferRejectedException('invalid');
    }

    final pending = _PendingManifest(Uint8List(manifestLength));
    _manifest = pending;

    try {
      await _handler._send(ManifestGet(sessionId));

      return await pending.completer.future.timeout(
        TransferProtocol.manifestTimeout,
        onTimeout: () =>
            throw TimeoutException('Раздающий не прислал манифест'),
      );
    } finally {
      _manifest = null;
    }
  }

  /// Запрашивает кусок [index] длиной [length] байт. Future завершается
  /// данными куска, когда пришли все байты, или ошибкой:
  /// - [TimeoutException]: данные перестали приходить;
  /// - [TransferCancelledException]: запрос отменён ([cancelPiece], [close]);
  /// - [TransferInterruptedException]: связь потеряна;
  /// - [StateError]: раздающий нарушил протокол.
  Future<Uint8List> requestPiece(int index, int length) {
    if (_closed) {
      return Future<Uint8List>.error(
        const TransferInterruptedException('Сессия закрыта'),
      );
    }

    if (_pieces.containsKey(index)) {
      return Future<Uint8List>.error(StateError('Кусок уже запрошен'));
    }

    final pending = _PendingPiece(index, Uint8List(length));
    _pieces[index] = pending;
    _armPieceTimer(pending);

    _handler._send(PieceGet(sessionId, index)).catchError((Object e) {
      _failPiece(pending, TransferInterruptedException(describeError(e)));
    });

    return pending.completer.future;
  }

  /// Отменяет запрос куска (например, он уже получен у другого пира).
  void cancelPiece(int index) {
    final pending = _pieces[index];
    if (pending == null) return;

    _failPiece(pending, const TransferCancelledException());
    unawaited(_handler._trySend(PieceCancel(sessionId, index)));
  }

  /// Закрывает сессию по нашей инициативе. Все ожидающие запросы завершаются
  /// [TransferCancelledException]; [onClosed] не вызывается.
  Future<void> close() async {
    if (_closed) return;

    _closed = true;
    _handler._remote.remove(sessionId);
    _failAll(const TransferCancelledException());

    await _handler._trySend(DlClose(sessionId));
  }

  // ---- Обработка входящих данных -------------------------------------------

  void _onReady(DlReady c) {
    if (_ready.isCompleted) return;

    final expectedPieces = (c.size + c.pieceSize - 1) ~/ c.pieceSize;
    final expectedManifest =
        PieceManifest.headerLength + c.pieceCount * PieceManifest.hashLength;

    final valid =
        c.pieceSize >= 16 * 1024 &&
        c.pieceSize <= PieceManifest.maxPieceSize &&
        c.pieceCount == expectedPieces &&
        c.pieceCount <= PieceManifest.maxPieces &&
        c.manifestLength == expectedManifest;

    if (!valid) {
      _ready.completeError(const TransferRejectedException('invalid'));
      return;
    }

    size = c.size;
    pieceSize = c.pieceSize;
    pieceCount = c.pieceCount;
    manifestLength = c.manifestLength;

    _ready.complete();
  }

  void _onReject(DlReject c) {
    if (_ready.isCompleted) return;

    _ready.completeError(TransferRejectedException(c.reason));
  }

  void _onFrame(SwarmFrame f) {
    if (_closed) return;

    if (f.kind == SwarmFrame.kindManifest) {
      final pending = _manifest;
      if (pending == null) return;

      final end = f.offset + f.payload.length;

      if (f.offset != pending.received || end > pending.buffer.length) {
        pending.completer.completeError(StateError('Нарушен порядок данных'));
        return;
      }

      pending.buffer.setRange(f.offset, end, f.payload);
      pending.received = end;

      if (pending.received == pending.buffer.length &&
          !pending.completer.isCompleted) {
        pending.completer.complete(pending.buffer);
      }
      return;
    }

    final pending = _pieces[f.index];

    // Кадр отменённого или неизвестного куска.
    if (pending == null) return;

    final end = f.offset + f.payload.length;

    if (f.offset != pending.received || end > pending.buffer.length) {
      _failPiece(pending, StateError('Раздающий нарушил порядок данных'));
      unawaited(_handler._trySend(PieceCancel(sessionId, f.index)));
      return;
    }

    pending.buffer.setRange(f.offset, end, f.payload);
    pending.received = end;
    onBytes?.call(f.payload.length);

    if (pending.received == pending.buffer.length) {
      _pieces.remove(pending.index);
      pending.timer?.cancel();

      if (!pending.completer.isCompleted) {
        pending.completer.complete(pending.buffer);
      }
    } else {
      _armPieceTimer(pending);
    }
  }

  void _armPieceTimer(_PendingPiece pending) {
    pending.timer?.cancel();
    pending.timer = Timer(TransferProtocol.pieceIdleTimeout, () {
      _failPiece(pending, TimeoutException('Раздающий не присылает данные'));
      unawaited(_handler._trySend(PieceCancel(sessionId, pending.index)));
    });
  }

  void _failPiece(_PendingPiece pending, Object error) {
    if (!identical(_pieces[pending.index], pending)) return;

    _pieces.remove(pending.index);
    pending.timer?.cancel();

    if (!pending.completer.isCompleted) pending.completer.completeError(error);
  }

  void _failAll(Object error) {
    for (final pending in _pieces.values.toList()) {
      _failPiece(pending, error);
    }

    final manifest = _manifest;
    if (manifest != null && !manifest.completer.isCompleted) {
      manifest.completer.completeError(error);
    }

    if (!_ready.isCompleted) _ready.completeError(error);
  }

  /// Закрытие НЕ по нашей инициативе: обрыв связи, dl_error, нарушение.
  void _terminate(Object reason) {
    if (_closed) return;

    _closed = true;
    _handler._remote.remove(sessionId);
    _failAll(reason);

    onClosed?.call(reason);
  }

  /// Ошибка при открытии: сессия уже не нужна, но [onClosed] не вызываем.
  void _failQuietly(Object error) {
    _closed = true;
    _failAll(error);
  }
}

class _PendingPiece {
  _PendingPiece(this.index, this.buffer) {
    completer.future.then((_) {}, onError: (_) {});
  }

  final int index;
  final Uint8List buffer;
  int received = 0;
  final Completer<Uint8List> completer = Completer<Uint8List>();
  Timer? timer;
}

class _PendingManifest {
  _PendingManifest(this.buffer) {
    completer.future.then((_) {}, onError: (_) {});
  }

  final Uint8List buffer;
  int received = 0;
  final Completer<Uint8List> completer = Completer<Uint8List>();
}

// =============================================================================
// Раздающая сторона: сессия
// =============================================================================

class _ServeSession {
  _ServeSession({
    required this.sid,
    required this.seed,
    required this.manifest,
    required this.manifestBytes,
    required this.info,
  });

  final int sid;
  final SeedFile seed;
  final PieceManifest manifest;
  final Uint8List manifestBytes;

  TransferInfo info;
  final SpeedMeter meter = SpeedMeter();
  DateTime lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  /// Сколько байт отдано в этой сессии.
  int served = 0;

  RandomAccessFile? raf;
  bool closed = false;

  /// Куски, запрос которых отменён скачивающим.
  final Set<int> cancelled = {};
}
