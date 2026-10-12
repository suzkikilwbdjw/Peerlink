import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:p2pchat/features/connection/data/services/peer_connection_manager.dart';
import 'package:p2pchat/features/connection/data/services/webrtc_services.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:p2pchat/features/tracker/data/models/network_file.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_info.dart';
import 'package:p2pchat/features/transfer/data/models/transfer_protocol.dart';
import 'package:p2pchat/features/transfer/data/repositories/partial_download_repository.dart';
import 'package:p2pchat/features/transfer/data/services/file_name_utils.dart';
import 'package:p2pchat/features/transfer/data/services/manifest_store.dart';
import 'package:p2pchat/features/transfer/data/services/peer_transfer_handler.dart';
import 'package:p2pchat/features/transfer/data/services/swarm_download.dart';

/// Связывает соединения и передачи файлов.
///
/// - при открытии соединения создаёт [PeerTransferHandler] и подключает его
///   к DataChannel: он одновременно раздаёт файлы и умеет скачивать;
/// - [download] запускает [SwarmDownload]: загрузку файла по кускам сразу у
///   нескольких раздающих;
/// - [pause], [resume], [cancel] управляют загрузкой;
/// - все обновления прогресса (и загрузок, и раздач) отдаёт одним потоком
///   [updates].
class TransferCoordinator {
  final PeerConnectionManager _manager;
  final WebRTCService _webrtc;
  final SeedFile? Function(String fileId) _lookupSeed;
  final Future<Directory> Function() _downloadsDirectory;
  final ManifestStore _manifests;
  final PartialDownloadRepository _partials;

  /// Кто сейчас раздаёт файл (нужно, чтобы возобновить загрузку без каталога,
  /// например после перезапуска приложения).
  final Future<List<String>> Function(String fileId) _findSeeders;

  final Map<String, PeerTransferHandler> _handlers = {};
  final Map<String, SwarmDownload> _downloads = {};
  final Set<String> _resuming = {};
  final StreamController<TransferInfo> _updates = StreamController.broadcast();
  final Random _random = Random.secure();

  StreamSubscription<PeerLinkEvent>? _linkSubscription;

  TransferCoordinator({
    required this._manager,
    required this._webrtc,
    required this._lookupSeed,
    required this._downloadsDirectory,
    required this._manifests,
    required this._partials,
    required this._findSeeders,
  });

  Stream<TransferInfo> get updates => _updates.stream;

  /// Вызвать один раз, после [PeerConnectionManager.start].
  void start() {
    _linkSubscription ??= _manager.events.listen(_onLinkEvent);
  }

  void _onLinkEvent(PeerLinkEvent event) {
    switch (event.status) {
      case PeerLinkStatus.connected:
        // Для входящих соединений (мы раздаём) это единственное место, где
        // создаётся обработчик.
        _ensureHandler(event.peerId);
      case PeerLinkStatus.closed:
      case PeerLinkStatus.failed:
        _removeHandler(event.peerId, event.error);
      case PeerLinkStatus.connecting:
        break;
    }
  }

  PeerTransferHandler? _ensureHandler(String peerId) {
    final existing = _handlers[peerId];
    if (existing != null) return existing;

    final handler = PeerTransferHandler(
      peerId: peerId,
      webrtc: _webrtc,
      lookupSeed: _lookupSeed,
      manifests: _manifests,
      onUpdate: _emit,
    );

    try {
      _webrtc.setOnDataReceived(peerId, handler.onMessage);
    } catch (e) {
      debugPrint('[TRANSFER] Не удалось подключить обработчик к $peerId: $e');
      return null;
    }

    _handlers[peerId] = handler;
    return handler;
  }

  void _removeHandler(String peerId, String? reason) {
    final handler = _handlers.remove(peerId);
    if (handler != null) {
      unawaited(handler.dispose(reason: reason ?? 'Соединение закрыто'));
    }
  }

  /// Подключается к пиру и возвращает обработчик его соединения.
  Future<PeerTransferHandler> _connectHandler(String peerId) async {
    await _manager.connect(peerId);

    final handler = _ensureHandler(peerId);
    if (handler == null) {
      throw StateError('Не удалось подготовить канал передачи');
    }

    return handler;
  }

  // ---------------------------------------------------------------------------
  // Недокачанные загрузки
  // ---------------------------------------------------------------------------

  /// Показывает в списке загрузки, прерванные до перезапуска приложения.
  /// Вызывается один раз, когда интерфейс уже подписан на [updates].
  Future<void> restorePartials() async {
    for (final partial in _partials.load()) {
      final length = await _partLength(partial.name, partial.fileId);

      // Файла нет или он больше ожидаемого: запись бесполезна.
      if (length < 0 || length > partial.size) {
        await _discardPartial(partial.fileId, partial.name);
        continue;
      }

      _emit(_infoFor(partial, length, TransferStatus.paused));
    }
  }

  TransferInfo _infoFor(
    PartialDownload partial,
    int length,
    TransferStatus status, {
    String? error,
  }) {
    return TransferInfo(
      id: TransferInfo.downloadIdFor(partial.fileId),
      direction: TransferDirection.download,
      peerId: '',
      fileId: partial.fileId,
      name: partial.name,
      totalBytes: partial.size,
      transferredBytes: length < 0 ? 0 : length,
      status: status,
      error: error,
      startedAt: DateTime.now(),
    );
  }

  PartialDownload? _partialById(String id) {
    for (final partial in _partials.load()) {
      if (TransferInfo.downloadIdFor(partial.fileId) == id) return partial;
    }
    return null;
  }

  /// Размер .part на диске; -1, если файла нет.
  Future<int> _partLength(String name, String fileId) async {
    try {
      final dir = await _downloadsDirectory();
      final part = partFileFor(dir, name, fileId);
      return await part.exists() ? await part.length() : -1;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _discardPartial(String fileId, String name) async {
    try {
      final dir = await _downloadsDirectory();
      final part = partFileFor(dir, name, fileId);
      if (await part.exists()) await part.delete();
    } catch (e) {
      debugPrint('[TRANSFER] Не удалось удалить .part: $e');
    }

    try {
      await _partials.remove(fileId);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Скачивание
  // ---------------------------------------------------------------------------

  /// Скачивает [file] у всех доступных раздающих сразу (до нескольких
  /// одновременно). Если на диске уже есть часть, продолжает с неё. Ход
  /// выполнения приходит в [updates]; метод сам не бросает исключений, а итог
  /// (успех, пауза, ошибка, отмена) сообщает статусом.
  Future<void> download(NetworkFile file) async {
    final id = TransferInfo.downloadIdFor(file.id);
    if (_downloads.containsKey(id)) return;

    // Порядок раздающих случайный, чтобы нагрузка распределялась по сети.
    final seeders = List<String>.of(file.seederIds)..shuffle(_random);

    final engine = SwarmDownload(
      fileId: file.id,
      name: file.name,
      size: file.size,
      seederIds: seeders,
      connect: _connectHandler,
      manifests: _manifests,
      partials: _partials,
      downloadsDirectory: _downloadsDirectory,
      onUpdate: _emit,
    );

    // Регистрируем сразу, до первого await: повторный вызов будет отброшен.
    _downloads[id] = engine;

    try {
      await engine.run();
    } catch (e) {
      // Итоговый статус уже опубликован движком.
      debugPrint('[TRANSFER] Загрузка $id завершилась: ${describeError(e)}');
    } finally {
      _downloads.remove(id);
    }
  }

  /// Пауза идущей загрузки. Скачанные куски остаются на диске.
  void pause(String id) {
    final engine = _downloads[id];
    if (engine != null) unawaited(engine.pause());
  }

  /// Возобновляет приостановленную загрузку: находит раздающих по fileId и
  /// продолжает с места остановки. Работает и после перезапуска приложения.
  Future<void> resume(String id) async {
    if (_downloads.containsKey(id) || !_resuming.add(id)) return;

    try {
      final partial = _partialById(id);
      if (partial == null) return;

      final length = await _partLength(partial.name, partial.fileId);
      _emit(_infoFor(partial, length, TransferStatus.connecting));

      final List<String> seeders;
      try {
        seeders = await _findSeeders(partial.fileId);
      } catch (e) {
        _emit(
          _infoFor(
            partial,
            length,
            TransferStatus.paused,
            error: describeError(e),
          ),
        );
        return;
      }

      if (seeders.isEmpty) {
        _emit(
          _infoFor(
            partial,
            length,
            TransferStatus.paused,
            error: 'Сейчас никто не раздаёт этот файл',
          ),
        );
        return;
      }

      await download(
        NetworkFile(
          id: partial.fileId,
          name: partial.name,
          size: partial.size,
          seederIds: seeders,
        ),
      );
    } finally {
      _resuming.remove(id);
    }
  }

  /// Отмена загрузки (идущей, ожидающей подключения или приостановленной).
  /// Скачанные куски удаляются.
  void cancel(String id) {
    final engine = _downloads[id];

    if (engine != null) {
      unawaited(engine.cancel());
      return;
    }

    // Нет активной загрузки: отменяем приостановленную.
    final partial = _partialById(id);
    if (partial != null) {
      unawaited(_discardPartial(partial.fileId, partial.name));
      _emit(_infoFor(partial, 0, TransferStatus.cancelled));
    }
  }

  // ---------------------------------------------------------------------------
  // Раздача
  // ---------------------------------------------------------------------------

  /// Прерывает все активные раздачи файла [fileId]. Вызовите при "Stop seeding",
  /// иначе скачивающие продолжат получать этот файл. Они получат ошибку и
  /// найдут другого раздающего.
  void stopServing(String fileId) {
    for (final handler in _handlers.values) {
      handler.stopServing(fileId);
    }
  }

  // ---------------------------------------------------------------------------

  void _emit(TransferInfo info) {
    if (!_updates.isClosed) _updates.add(info);
  }

  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    _linkSubscription = null;

    for (final engine in _downloads.values.toList()) {
      unawaited(engine.pause());
    }

    for (final peerId in _handlers.keys.toList()) {
      _removeHandler(peerId, 'Приложение закрывается');
    }

    await _updates.close();
  }
}
