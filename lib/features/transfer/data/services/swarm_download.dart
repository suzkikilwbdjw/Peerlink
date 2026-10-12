import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:p2pchat/features/transfer/data/models/piece_manifest.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_info.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_protocol.dart';
import 'package:p2pchat/features/transfer/data/repositories/partial_download_repository.dart';
import 'package:p2pchat/features/transfer/data/services/file_name_utils.dart';
import 'package:p2pchat/features/transfer/data/services/manifest_store.dart';
import 'package:p2pchat/features/transfer/data/services/peer_transfer_handler.dart';
import 'package:p2pchat/features/transfer/data/services/speed_meter.dart';

class _PeerState {
  _PeerState(this.peerId, this.remote);

  final String peerId;
  final RemoteFile remote;

  /// Сколько кусков запрошено у пира и ещё не получено.
  int active = 0;

  /// Нарушения: таймауты кусков. Три подряд, и пир исключается.
  int strikes = 0;

  bool dropped = false;
}

/// Загрузка одного файла у нескольких раздающих сразу.
///
/// Как это устроено:
/// 1. Получаем манифест (хеши всех кусков): из локального хранилища или у
///    любого пира; его подлинность проверяется по fileId.
/// 2. Определяем, сколько уже скачано: по размеру .part на диске (с проверкой
///    последних кусков).
/// 3. Подключаемся к нескольким раздающим и раздаём им куски: у каждого
///    пира есть "конвейер" из нескольких одновременных запросов.
/// 4. Каждый полученный кусок проверяется по SHA-256 из манифеста. Испорченный
///    кусок отбрасывается, а пир исключается.
/// 5. Проверенные куски пишутся в файл СТРОГО ПО ПОРЯДКУ (куски, пришедшие
///    раньше, ждут в памяти в ограниченном окне). Поэтому размер .part всегда
///    говорит, сколько проверенных данных есть, и докачка не требует хранить
///    битовую карту.
///
/// Пауза, отмена, обрыв всех раздающих и ошибки диска завершают загрузку
/// через единую точку [_finish].
class SwarmDownload {
  final String fileId;
  final String name;
  final int size;

  /// Сколько раздающих используем одновременно.
  final int maxPeers;

  final Queue<String> _candidates;
  final Future<PeerTransferHandler> Function(String peerId) _connect;
  final ManifestStore _manifests;
  final PartialDownloadRepository _partials;
  final Future<Directory> Function() _downloadsDirectory;
  final void Function(TransferInfo info) _onUpdate;

  final Completer<String> _done = Completer<String>();
  final SpeedMeter _meter = SpeedMeter();

  final Map<String, _PeerState> _peers = {};

  /// Кто сейчас скачивает кусок (у конца файла один кусок может запрашиваться
  /// у двух пиров).
  final Map<int, Set<_PeerState>> _inFlight = {};

  /// Проверенные куски, ждущие своей очереди записи на диск.
  final Map<int, Uint8List> _buffered = {};

  PieceManifest? _manifest;
  File? _part;
  RandomAccessFile? _raf;
  String? _safeName;

  /// Следующий кусок, который нужно записать (все до него уже на диске).
  int _nextWrite = 0;

  /// Сколько байт проверено (записано и ждёт записи).
  int _verifiedBytes = 0;

  int _windowPieces = 8;
  int _depth = 1;

  int _connecting = 0;
  bool _diskReady = false;
  bool _writing = false;
  bool _finished = false;
  bool _discardData = false;

  Object? _lastError;
  Timer? _ticker;
  TransferInfo _info;

  SwarmDownload({
    required this.fileId,
    required this.name,
    required this.size,
    required List<String> seederIds,
    required this._connect,
    required this._manifests,
    required this._partials,
    required this._downloadsDirectory,
    required this._onUpdate,
    this.maxPeers = 4,
  }) : _candidates = Queue<String>.of(seederIds),
       _info = TransferInfo(
         id: TransferInfo.downloadIdFor(fileId),
         direction: TransferDirection.download,
         peerId: '',
         fileId: fileId,
         name: name,
         totalBytes: size,
         status: TransferStatus.connecting,
         startedAt: DateTime.now(),
       ) {
    // Ошибка в Completer без слушателя иначе станет необработанным исключением.
    _done.future.then((_) {}, onError: (_) {});
  }

  String get id => TransferInfo.downloadIdFor(fileId);

  // ===========================================================================
  // Запуск и управление
  // ===========================================================================

  /// Запускает загрузку. Future завершается путём к сохранённому файлу или
  /// ошибкой: [TransferPausedException], [TransferCancelledException],
  /// [TransferInterruptedException] (скачанная часть сохранена) либо другой
  /// (окончательный сбой). Итоговый статус всегда публикуется через onUpdate.
  Future<String> run() {
    _publish();
    unawaited(_start());
    return _done.future;
  }

  /// Пауза: скачанная часть остаётся на диске.
  Future<void> pause() {
    return _finish(
      const TransferPausedException(),
      status: TransferStatus.paused,
    );
  }

  /// Отмена: скачанная часть удаляется.
  Future<void> cancel() {
    return _finish(
      const TransferCancelledException(),
      status: TransferStatus.cancelled,
      keepData: false,
    );
  }

  Future<void> _start() async {
    try {
      // Запись о загрузке нужна, чтобы её можно было возобновить (в том
      // числе после перезапуска), даже если остановят на этапе подключения.
      await _partials.upsert(
        PartialDownload(fileId: fileId, name: name, size: size),
      );
      if (_finished) return;

      final dir = await _downloadsDirectory();
      await dir.create(recursive: true);
      if (_finished) return;

      _safeName = sanitizeFileName(name);
      _part = partFileFor(dir, name, fileId);

      await _obtainManifest();
      if (_finished) return;

      await _openDisk();

      if (_finished) {
        // Остановили, пока открывали файл: убираем за собой.
        try {
          await _raf?.close();
        } catch (_) {}
        _raf = null;

        if (_discardData) await _deletePart();
        return;
      }

      final manifest = _manifest!;

      // Окно кусков вперёд от записанного (память под "лишние" куски) и
      // глубина конвейера на пира подбираются по размеру куска.
      _windowPieces = (32 * 1024 * 1024 ~/ manifest.pieceSize)
          .clamp(4, 256)
          .toInt();
      _depth = (4 * 1024 * 1024 ~/ manifest.pieceSize).clamp(1, 4).toInt();

      _diskReady = true;
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _publish(),
      );
      _publish();

      if (_nextWrite >= manifest.pieceCount) {
        await _complete(); // всё уже было скачано
        return;
      }

      _afterPeerEvent();
    } catch (e) {
      await _finish(
        e,
        status: e is TransferInterruptedException
            ? TransferStatus.paused
            : TransferStatus.failed,
      );
    }
  }

  // ===========================================================================
  // Манифест
  // ===========================================================================

  Future<void> _obtainManifest() async {
    final local = await _manifests.loadManifest(fileId);

    if (local != null && local.size == size) {
      _manifest = local;
      return;
    }

    // Просим манифест у раздающих по очереди; первая удачная сессия
    // остаётся в работе как обычный пир.
    while (!_finished && _candidates.isNotEmpty) {
      final peerId = _candidates.removeFirst();
      RemoteFile? remote;

      try {
        final handler = await _connect(peerId);
        if (_finished) return;

        remote = await handler.openFile(fileId);

        if (remote.size != size) {
          throw const TransferRejectedException('invalid');
        }

        final bytes = await remote.fetchManifest();
        final manifest = PieceManifest.tryDecode(bytes);

        // Главная проверка: манифест подлинный, если его SHA-256 равен fileId.
        if (manifest == null ||
            manifest.fileId != fileId ||
            manifest.size != size) {
          throw const TransferRejectedException('invalid');
        }

        await _manifests.save(fileId, bytes);
        _manifest = manifest;

        if (_finished) {
          await remote.close();
        } else {
          _addPeer(peerId, remote);
        }
        return;
      } catch (e) {
        _lastError = e;
        await remote?.close();
      }
    }

    if (_finished) return;

    throw TransferInterruptedException(
      _lastError == null
          ? 'Нет доступных раздающих'
          : describeError(_lastError!),
    );
  }

  // ===========================================================================
  // Диск
  // ===========================================================================

  /// Находит, сколько проверенных данных уже на диске, и открывает файл для
  /// дозаписи в конец.
  Future<void> _openDisk() async {
    final manifest = _manifest!;
    final part = _part!;

    var resumeIndex = 0;

    if (await part.exists()) {
      final length = await part.length();

      // Сколько кусков записано целиком.
      final fullPieces = length >= size
          ? manifest.pieceCount
          : length ~/ manifest.pieceSize;

      resumeIndex = await _verifiedPrefix(part, manifest, fullPieces);
    }

    final resumeBytes = resumeIndex >= manifest.pieceCount
        ? size
        : resumeIndex * manifest.pieceSize;

    // Отбрасываем всё после последнего проверенного куска (недописанный
    // кусок, мусор). Делаем это отдельным коротким дескриптором.
    if (await part.exists()) {
      final trimmer = await part.open(mode: FileMode.append);
      try {
        await trimmer.truncate(resumeBytes);
      } finally {
        await trimmer.close();
      }
    }

    _raf = await part.open(mode: FileMode.writeOnlyAppend);
    _nextWrite = resumeIndex;
    _verifiedBytes = resumeBytes;
  }

  /// Возвращает, сколько первых кусков файла на диске можно считать
  /// проверенными. После сбоя (отключение питания) хвост файла мог быть
  /// записан не полностью, поэтому последние несколько кусков перепроверяются
  /// по манифесту, а при несовпадении откатываемся назад.
  Future<int> _verifiedPrefix(
    File part,
    PieceManifest manifest,
    int fullPieces,
  ) async {
    const checkLast = 4;

    RandomAccessFile? reader;

    try {
      reader = await part.open();

      var n = fullPieces;

      while (n > 0) {
        var ok = true;
        final from = math.max(0, n - checkLast);

        for (var i = n - 1; i >= from; i--) {
          if (!await _pieceOnDiskValid(reader, manifest, i)) {
            ok = false;
            break;
          }
        }

        if (ok) break;
        n--;
      }

      return n;
    } finally {
      await reader?.close();
    }
  }

  Future<bool> _pieceOnDiskValid(
    RandomAccessFile reader,
    PieceManifest manifest,
    int index,
  ) async {
    await reader.setPosition(manifest.pieceOffset(index));
    final data = await reader.read(manifest.pieceLength(index));
    return manifest.matches(index, data);
  }

  Future<void> _deletePart() async {
    try {
      final part = _part;
      if (part != null && await part.exists()) await part.delete();
    } catch (_) {}

    try {
      await _partials.remove(fileId);
    } catch (_) {}
  }

  // ===========================================================================
  // Пиры
  // ===========================================================================

  void _addPeer(String peerId, RemoteFile remote) {
    final peer = _PeerState(peerId, remote);
    _peers[peerId] = peer;

    remote.onBytes = _meter.add;
    remote.onClosed = (reason) {
      // Соединение потеряно или раздающий остановил раздачу.
      _lastError = reason;
      _dropPeer(peer);
      _afterPeerEvent();
    };
  }

  void _dropPeer(_PeerState peer) {
    if (peer.dropped) return;
    peer.dropped = true;

    if (identical(_peers[peer.peerId], peer)) _peers.remove(peer.peerId);

    // Закрытие сессии завершит все её запросы кусков ошибкой отмены, и эти
    // куски уйдут другим пирам.
    unawaited(peer.remote.close());
  }

  /// Подключаем новых раздающих, пока не набрано [maxPeers].
  void _connectMorePeers() {
    while (!_finished &&
        _peers.length + _connecting < maxPeers &&
        _candidates.isNotEmpty) {
      unawaited(_connectPeer(_candidates.removeFirst()));
    }
  }

  Future<void> _connectPeer(String peerId) async {
    _connecting++;

    try {
      final handler = await _connect(peerId);
      if (_finished) return;

      final remote = await handler.openFile(fileId);

      if (_finished) {
        unawaited(remote.close());
        return;
      }

      if (remote.size != size) {
        unawaited(remote.close());
        throw const TransferRejectedException('invalid');
      }

      _addPeer(peerId, remote);
    } catch (e) {
      _lastError = e;
    } finally {
      _connecting--;
    }

    _afterPeerEvent();
  }

  /// Что-то изменилось с пирами: докупаем пиров, раздаём куски, проверяем,
  /// не зашли ли мы в тупик.
  void _afterPeerEvent() {
    if (_finished) return;

    _connectMorePeers();
    _pump();
    _checkStalled();
  }

  /// Раздающие закончились, а файл не докачан: останавливаемся на паузе
  /// (скачанная часть сохранена, можно продолжить позже).
  void _checkStalled() {
    if (_finished || !_diskReady) return;
    if (_peers.isNotEmpty || _connecting > 0 || _candidates.isNotEmpty) return;
    if (_nextWrite >= _manifest!.pieceCount) return;

    unawaited(
      _finish(
        TransferInterruptedException(
          _lastError == null
              ? 'Нет доступных раздающих'
              : describeError(_lastError!),
        ),
        status: TransferStatus.paused,
      ),
    );
  }

  // ===========================================================================
  // Выбор и получение кусков
  // ===========================================================================

  /// Раздаёт свободные места в конвейерах пиров.
  void _pump() {
    if (_finished || !_diskReady) return;

    for (final peer in _peers.values.toList()) {
      while (!peer.dropped && !_finished && peer.active < _depth) {
        final index = _nextPieceFor(peer);
        if (index == null) break;

        _request(peer, index);
      }
    }
  }

  /// Какой кусок запросить у [peer]. Берём самый ранний из окна, который ещё
  /// никто не качает. Если таких нет (конец файла или медленный пир держит
  /// начало окна), дублируем самый ранний уже запрошенный кусок у другого
  /// пира: так хвост загрузки не зависит от одного медленного пира.
  int? _nextPieceFor(_PeerState peer) {
    final manifest = _manifest!;
    final limit = math.min(manifest.pieceCount, _nextWrite + _windowPieces);

    for (var i = _nextWrite; i < limit; i++) {
      if (_buffered.containsKey(i) || _inFlight.containsKey(i)) continue;
      return i;
    }

    for (var i = _nextWrite; i < limit; i++) {
      final holders = _inFlight[i];
      if (holders == null) continue;
      if (holders.contains(peer) || holders.length >= 2) continue;
      return i;
    }

    return null;
  }

  void _request(_PeerState peer, int index) {
    final length = _manifest!.pieceLength(index);

    peer.active++;
    _inFlight.putIfAbsent(index, () => {}).add(peer);

    unawaited(
      peer.remote
          .requestPiece(index, length)
          .then(
            (data) => _onPieceData(peer, index, data),
            onError: (Object e) => _onPieceFailed(peer, index, e),
          ),
    );
  }

  void _settle(_PeerState peer, int index) {
    peer.active--;

    final holders = _inFlight[index];
    if (holders != null) {
      holders.remove(peer);
      if (holders.isEmpty) _inFlight.remove(index);
    }
  }

  void _onPieceData(_PeerState peer, int index, Uint8List data) {
    _settle(peer, index);
    if (_finished) return;

    final manifest = _manifest!;

    // Кусок уже получен (дубликат у конца файла).
    if (index < _nextWrite || _buffered.containsKey(index)) {
      _pump();
      return;
    }

    if (!manifest.matches(index, data)) {
      // Подмена или повреждение данных: такому пиру больше не верим.
      _lastError = StateError('Раздающий прислал повреждённый кусок');
      _dropPeer(peer);
      _afterPeerEvent();
      return;
    }

    _buffered[index] = data;
    _verifiedBytes += data.length;

    // Если этот кусок запрашивали и у другого пира, останавливаем лишнюю загрузку.
    for (final other in (_inFlight[index]?.toList() ?? const <_PeerState>[])) {
      other.remote.cancelPiece(index);
    }

    unawaited(_writeReady());
    _pump();
  }

  void _onPieceFailed(_PeerState peer, int index, Object error) {
    _settle(peer, index);
    if (_finished) return;

    // Отменили мы сами (дубликат получен или пир исключён): кусок просто
    // вернётся в общий пул.
    if (error is TransferCancelledException) {
      _pump();
      return;
    }

    _lastError = error;

    if (error is TimeoutException) {
      peer.strikes++;
      if (peer.strikes >= 3) _dropPeer(peer);
    } else {
      _dropPeer(peer);
    }

    _afterPeerEvent();
  }

  // ===========================================================================
  // Запись на диск и завершение
  // ===========================================================================

  /// Пишет подряд все готовые куски, начиная с [_nextWrite].
  Future<void> _writeReady() async {
    if (_writing || _finished) return;
    _writing = true;

    var sinceFlush = 0;

    try {
      while (!_finished) {
        final data = _buffered.remove(_nextWrite);
        if (data == null) break;

        await _raf!.writeFrom(data);
        _nextWrite++;

        sinceFlush++;
        if (sinceFlush >= 16) {
          await _raf!.flush();
          sinceFlush = 0;
        }
      }
    } catch (e) {
      _writing = false;
      unawaited(
        _finish(
          TransferInterruptedException(describeError(e)),
          status: TransferStatus.paused,
        ),
      );
      return;
    }

    _writing = false;
    if (_finished) return;

    if (_nextWrite >= _manifest!.pieceCount) {
      await _complete();
    } else {
      _pump(); // окно сдвинулось: можно запрашивать дальше
    }
  }

  /// Все куски записаны: закрываем файл, переименовываем в итоговое имя.
  Future<void> _complete() async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();

    for (final peer in _peers.values.toList()) {
      peer.dropped = true;
      unawaited(peer.remote.close());
    }
    _peers.clear();

    try {
      await _raf?.flush();
      await _raf?.close();
      _raf = null;

      final part = _part!;
      final length = await part.length();

      if (length != size) {
        throw StateError('Размер на диске не совпадает: $length / $size');
      }

      final dir = await _downloadsDirectory();
      final target = await uniqueFile(dir, _safeName!);
      await part.rename(target.path);

      await _partials.remove(fileId);

      _info = _info.copyWith(
        status: TransferStatus.completed,
        transferredBytes: size,
        speedBps: 0,
        peerCount: 0,
        savedPath: target.path,
      );
      _onUpdate(_info);

      if (!_done.isCompleted) _done.complete(target.path);
    } catch (e) {
      _info = _info.copyWith(
        status: TransferStatus.failed,
        error: describeError(e),
        speedBps: 0,
        peerCount: 0,
      );
      _onUpdate(_info);

      if (!_done.isCompleted) _done.completeError(e);
    }
  }

  /// Единая точка остановки: пауза, отмена, обрыв, ошибка.
  ///
  /// [keepData]: оставить недокачанный файл (по умолчанию да).
  Future<void> _finish(
    Object error, {
    required TransferStatus status,
    bool keepData = true,
  }) async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();

    if (!keepData) _discardData = true;

    for (final peer in _peers.values.toList()) {
      peer.dropped = true;
      unawaited(peer.remote.close());
    }
    _peers.clear();

    // Дожидаемся, пока завершится текущая запись: закрывать файл во время
    // записи нельзя.
    while (_writing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    try {
      await _raf?.flush();
    } catch (_) {}
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;

    _buffered.clear();
    _inFlight.clear();

    if (!keepData) await _deletePart();

    final silent =
        error is TransferPausedException || error is TransferCancelledException;

    _info = _info.copyWith(
      status: status,
      transferredBytes: _writtenBytes(),
      speedBps: 0,
      peerCount: 0,
      error: silent ? null : describeError(error),
    );
    _onUpdate(_info);

    if (!_done.isCompleted) _done.completeError(error);
  }

  int _writtenBytes() {
    final manifest = _manifest;
    if (manifest == null) return 0;

    return _nextWrite >= manifest.pieceCount
        ? size
        : _nextWrite * manifest.pieceSize;
  }

  // ===========================================================================
  // Прогресс
  // ===========================================================================

  void _publish() {
    if (_finished) return;

    _info = _info.copyWith(
      status: (_diskReady && _peers.isNotEmpty)
          ? TransferStatus.active
          : TransferStatus.connecting,
      transferredBytes: _verifiedBytes,
      speedBps: _meter.bytesPerSecond,
      peerCount: _peers.length,
    );
    _onUpdate(_info);
  }
}
