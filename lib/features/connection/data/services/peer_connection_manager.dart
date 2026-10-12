import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:p2pchat/features/connection/data/services/webrtc_services.dart';
import 'package:p2pchat/features/signaling/data/models/signal_message.dart';
import 'package:p2pchat/features/signaling/data/repositories/signaling_repository.dart';

enum PeerLinkStatus { connecting, connected, closed, failed }

/// Событие жизненного цикла соединения с пиром.
///
/// Шаг 4 подписывается на [PeerConnectionManager.events]: при status ==
/// connected создаёт обработчик передачи файлов для этого пира, при
/// closed/failed уничтожает его.
class PeerLinkEvent {
  final String peerId;
  final PeerLinkStatus status;

  /// true, если соединение начали мы (скачиваем), false, если к нам
  /// подключились (раздаём).
  final bool initiator;

  final String? error;

  const PeerLinkEvent({
    required this.peerId,
    required this.status,
    required this.initiator,
    this.error,
  });

  @override
  String toString() =>
      'PeerLinkEvent($peerId, $status, initiator=$initiator, $error)';
}

/// Состояние одного соединения внутри менеджера.
class _Link {
  _Link({
    required this.peerId,
    required this.sessionId,
    required this.initiator,
    Completer<void>? opened,
  }) : opened = opened ?? Completer<void>() {
    // Чтобы ошибка в Completer без слушателей не превращалась в
    // необработанное исключение (у входящих соединений connect() не ждёт).
    this.opened.future.then((_) {}, onError: (_) {});
  }

  final String peerId;
  final String sessionId;
  final bool initiator;

  /// Завершается, когда DataChannel открылся (или с ошибкой при провале).
  final Completer<void> opened;

  PeerLinkStatus status = PeerLinkStatus.connecting;

  /// Offer/answer доставлен в Firestore: после этого можно слать кандидатов.
  bool signalingReady = false;

  /// Удалённое описание применено: после этого можно принимать кандидатов.
  bool remoteDescriptionSet = false;

  /// Не завершать [opened] при закрытии: Completer передан новой ссылке
  /// (разрешение конфликта встречных offer).
  bool keepOpenedOnTeardown = false;

  final List<RTCIceCandidate> outgoing = [];

  Timer? timeout;
  Timer? flushTimer;
  Timer? disconnectTimer;
}

/// Единая точка управления P2P-соединениями.
///
/// Берёт на себя всё, что раньше делалось вручную через ConnectionBloc:
/// - инициатор: [connect] создаёт offer и отправляет его через Firestore;
/// - принимающая сторона: слушает свой inbox, отвечает answer'ом;
/// - обмен ICE-кандидатами (батчами, trickle ICE);
/// - таймауты, обрыв связи, разрешение конфликта встречных соединений;
/// - одно соединение на пира (ключ — uid пира).
class PeerConnectionManager {
  /// Сколько соединений держим одновременно (защита от перегрузки).
  static const int maxLinks = 10;

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration _disconnectGrace = Duration(seconds: 10);
  static const Duration _candidateFlushDelay = Duration(milliseconds: 300);

  final WebRTCService _webrtc;
  final SignalingRepository _signaling;
  final String _selfUid;

  /// Принимать ли входящие соединения прямо сейчас. Обычно: есть ли у нас
  /// что раздавать.
  final bool Function() _acceptIncoming;

  final Map<String, _Link> _links = {};
  final StreamController<PeerLinkEvent> _events = StreamController.broadcast();
  final Random _random = Random.secure();

  StreamSubscription<InboxUpdate>? _inboxSubscription;

  /// Сигналы обрабатываются строго по одному: иначе кандидаты могли бы
  /// обогнать setRemoteDescription.
  Future<void> _signalQueue = Future<void>.value();

  PeerConnectionManager({
    required this._webrtc,
    required this._signaling,
    required this._selfUid,
    bool Function()? acceptIncoming,
  }) : _acceptIncoming = acceptIncoming ?? (() => true);

  Stream<PeerLinkEvent> get events => _events.stream;

  bool isConnected(String peerId) {
    return _links[peerId]?.status == PeerLinkStatus.connected;
  }

  List<String> get connectedPeerIds => _links.values
      .where((l) => l.status == PeerLinkStatus.connected)
      .map((l) => l.peerId)
      .toList(growable: false);

  // ---------------------------------------------------------------------------
  // Публичный API
  // ---------------------------------------------------------------------------

  /// Начинает слушать входящие сигналы. Вызвать один раз после входа в Firebase.
  void start() {
    if (_inboxSubscription != null) return;

    _inboxSubscription = _signaling
        .watchInbox(_selfUid)
        .listen(
          _onInboxUpdate,
          onError: (Object e) => debugPrint('[LINK] Ошибка inbox: $e'),
        );
  }

  /// Подключается к пиру. Future завершается, когда DataChannel открыт, и
  /// падает с ошибкой при таймауте, отказе или обрыве.
  ///
  /// Повторный вызов для пира, к которому уже идёт подключение или есть
  /// соединение, не создаёт новое.
  Future<void> connect(String peerId) {
    if (peerId == _selfUid) {
      return Future.error(ArgumentError('Нельзя подключиться к самому себе'));
    }

    final existing = _links[peerId];
    if (existing != null) {
      return existing.status == PeerLinkStatus.connected
          ? Future<void>.value()
          : existing.opened.future;
    }

    if (_links.length >= maxLinks) {
      return Future.error(StateError('Слишком много активных соединений'));
    }

    final link = _Link(
      peerId: peerId,
      sessionId: _newSessionId(),
      initiator: true,
    );

    _links[peerId] = link;
    _emit(link);

    link.timeout = Timer(
      connectTimeout,
      () => _teardown(
        link,
        error: TimeoutException(
          'Пир не ответил за ${connectTimeout.inSeconds} с',
        ),
      ),
    );

    unawaited(_sendOffer(link));

    return link.opened.future;
  }

  /// Закрывает соединение с пиром (если оно есть) и уведомляет его.
  Future<void> disconnect(String peerId) async {
    final link = _links[peerId];
    if (link != null) await _teardown(link);
  }

  Future<void> dispose() async {
    await _inboxSubscription?.cancel();
    _inboxSubscription = null;

    for (final link in _links.values.toList()) {
      await _teardown(link);
    }

    await _events.close();
  }

  // ---------------------------------------------------------------------------
  // Инициатор
  // ---------------------------------------------------------------------------

  Future<void> _sendOffer(_Link link) async {
    final peerId = link.peerId;

    try {
      await _webrtc.initializePeer(peerId);
      if (!_alive(link)) return;

      _wire(link);

      // DataChannel создаёт инициатор, до создания offer.
      await _webrtc.createDataChannel(peerId: peerId);
      if (!_alive(link)) return;

      final offer = await _webrtc.createOffer(peerId: peerId);
      if (!_alive(link)) return;

      await _webrtc.setLocalDescription(offer, peerId: peerId);
      if (!_alive(link)) return;

      await _signaling.send(
        from: _selfUid,
        to: peerId,
        type: SignalType.offer,
        sessionId: link.sessionId,
        payload: {'type': offer.type, 'sdp': offer.sdp},
      );
      if (!_alive(link)) return;

      link.signalingReady = true;
      _scheduleFlush(link);
    } catch (e) {
      await _teardown(link, error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Входящие сигналы
  // ---------------------------------------------------------------------------

  void _onInboxUpdate(InboxUpdate update) {
    for (final message in update.added) {
      if (update.isInitial) {
        // Накопилось, пока приложение было закрыто: к таким offer'ам
        // отправитель давно перестал ждать.
        unawaited(_signaling.consume(_selfUid, message.id));
      } else {
        _enqueue(message);
      }
    }
  }

  void _enqueue(SignalMessage message) {
    _signalQueue = _signalQueue.then((_) async {
      try {
        await _handleSignal(message);
      } catch (e, stackTrace) {
        debugPrint('[LINK] Ошибка обработки сигнала ${message.type.name}: $e');
        debugPrint('$stackTrace');
      } finally {
        await _signaling.consume(_selfUid, message.id);
      }
    });
  }

  Future<void> _handleSignal(SignalMessage message) async {
    if (message.from == _selfUid) return;

    switch (message.type) {
      case SignalType.offer:
        await _onOffer(message);
      case SignalType.answer:
        await _onAnswer(message);
      case SignalType.candidates:
        await _onCandidates(message);
      case SignalType.bye:
        await _onBye(message);
    }
  }

  Future<void> _onOffer(SignalMessage message) async {
    final sdp = message.payload['sdp'];
    final type = message.payload['type'];

    if (sdp is! String ||
        type is! String ||
        sdp.isEmpty ||
        sdp.length > 50000) {
      return;
    }

    final from = message.from;

    if (!_acceptIncoming()) {
      debugPrint('[LINK] Offer от $from проигнорирован: нечего раздавать');
      return;
    }

    final existing = _links[from];
    Completer<void>? carriedOpened;

    if (existing != null) {
      // Повторная доставка того же offer.
      if (existing.sessionId == message.sessionId) return;

      // Конфликт: мы тоже подключаемся к этому пиру. Побеждает сторона с
      // меньшим uid: она остаётся инициатором, вторая отказывается от своей
      // попытки и отвечает на чужой offer.
      if (existing.initiator && existing.status == PeerLinkStatus.connecting) {
        if (_selfUid.compareTo(from) < 0) {
          debugPrint('[LINK] Встречные offer с $from: наш побеждает');
          return;
        }

        debugPrint('[LINK] Встречные offer с $from: отвечаем на чужой');
        carriedOpened = existing.opened;
        existing.keepOpenedOnTeardown = true;
      }

      // Остальное: пир начал новую сессию (перезапуск), старая не нужна.
      await _teardown(existing, sendBye: false);
    } else if (_links.length >= maxLinks) {
      debugPrint('[LINK] Offer от $from отклонён: слишком много соединений');
      return;
    }

    final link = _Link(
      peerId: from,
      sessionId: message.sessionId,
      initiator: false,
      opened: carriedOpened,
    );

    _links[from] = link;
    _emit(link);

    link.timeout = Timer(
      connectTimeout,
      () => _teardown(
        link,
        error: TimeoutException('Соединение с $from не установилось'),
      ),
    );

    try {
      await _webrtc.initializePeer(from);
      if (!_alive(link)) return;

      _wire(link);

      await _webrtc.setRemoteDescription(
        RTCSessionDescription(sdp, type),
        peerId: from,
      );
      if (!_alive(link)) return;
      link.remoteDescriptionSet = true;

      final answer = await _webrtc.createAnswer(peerId: from);
      if (!_alive(link)) return;

      await _webrtc.setLocalDescription(answer, peerId: from);
      if (!_alive(link)) return;

      await _signaling.send(
        from: _selfUid,
        to: from,
        type: SignalType.answer,
        sessionId: link.sessionId,
        payload: {'type': answer.type, 'sdp': answer.sdp},
      );
      if (!_alive(link)) return;

      link.signalingReady = true;
      _scheduleFlush(link);
    } catch (e) {
      await _teardown(link, error: e);
    }
  }

  Future<void> _onAnswer(SignalMessage message) async {
    final link = _links[message.from];

    if (link == null ||
        !link.initiator ||
        link.sessionId != message.sessionId ||
        link.remoteDescriptionSet) {
      return;
    }

    final sdp = message.payload['sdp'];
    final type = message.payload['type'];

    if (sdp is! String ||
        type is! String ||
        sdp.isEmpty ||
        sdp.length > 50000) {
      return;
    }

    try {
      await _webrtc.setRemoteDescription(
        RTCSessionDescription(sdp, type),
        peerId: link.peerId,
      );
      if (!_alive(link)) return;

      link.remoteDescriptionSet = true;
    } catch (e) {
      await _teardown(link, error: e);
    }
  }

  Future<void> _onCandidates(SignalMessage message) async {
    final link = _links[message.from];

    if (link == null ||
        link.sessionId != message.sessionId ||
        !link.remoteDescriptionSet) {
      debugPrint('[LINK] Кандидаты от ${message.from} отброшены (нет сессии)');
      return;
    }

    final list = message.payload['candidates'];
    if (list is! List) return;

    for (final item in list.take(100)) {
      if (item is! Map) continue;

      final candidate = item['candidate'];
      final sdpMid = item['sdpMid'];
      final sdpMLineIndex = item['sdpMLineIndex'];

      if (candidate is! String ||
          candidate.isEmpty ||
          candidate.length > 2000) {
        continue;
      }

      try {
        await _webrtc.addCandidate(
          RTCIceCandidate(
            candidate,
            sdpMid is String ? sdpMid : null,
            sdpMLineIndex is int ? sdpMLineIndex : null,
          ),
          peerId: link.peerId,
        );
      } catch (e) {
        debugPrint('[LINK] Не удалось добавить кандидата: $e');
      }

      if (!_alive(link)) return;
    }
  }

  Future<void> _onBye(SignalMessage message) async {
    final link = _links[message.from];

    if (link == null || link.sessionId != message.sessionId) return;

    // Пир сам закрыл соединение: отвечать "bye" не нужно.
    await _teardown(link, sendBye: false);
  }

  // ---------------------------------------------------------------------------
  // Подписка на события WebRTC и отправка кандидатов
  // ---------------------------------------------------------------------------

  void _wire(_Link link) {
    final peerId = link.peerId;

    _webrtc.setOnIceCandidate((candidate) {
      if (!_alive(link)) return;

      final text = candidate.candidate;
      if (text == null || text.isEmpty) return;

      link.outgoing.add(candidate);
      _scheduleFlush(link);
    }, peerId: peerId);

    _webrtc.setOnConnectionState(
      (state) => _onConnectionState(link, state),
      peerId: peerId,
    );

    _webrtc.setOnDataChannelState(
      (state) => _onChannelState(link, state),
      peerId: peerId,
    );
  }

  /// Кандидаты уходят пачками: так в Firestore пишется ~1-3 документа за
  /// соединение вместо десятков.
  void _scheduleFlush(_Link link) {
    if (!link.signalingReady || link.outgoing.isEmpty) return;
    if (link.flushTimer != null) return;

    link.flushTimer = Timer(_candidateFlushDelay, () => _flush(link));
  }

  Future<void> _flush(_Link link) async {
    link.flushTimer = null;

    if (!_alive(link) || link.status == PeerLinkStatus.connected) {
      link.outgoing.clear();
      return;
    }

    if (link.outgoing.isEmpty) return;

    final batch = List<RTCIceCandidate>.of(link.outgoing);
    link.outgoing.clear();

    try {
      await _signaling.send(
        from: _selfUid,
        to: link.peerId,
        type: SignalType.candidates,
        sessionId: link.sessionId,
        payload: {
          'candidates': [
            for (final c in batch)
              {
                'candidate': c.candidate,
                'sdpMid': c.sdpMid,
                'sdpMLineIndex': c.sdpMLineIndex,
              },
          ],
        },
      );
    } catch (e) {
      debugPrint('[LINK] Не удалось отправить кандидатов: $e');
    }

    // Кандидаты, появившиеся, пока шла отправка.
    _scheduleFlush(link);
  }

  void _onConnectionState(_Link link, RTCPeerConnectionState state) {
    if (!_alive(link)) return;

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        link.disconnectTimer?.cancel();
        link.disconnectTimer = null;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // Часто временное (смена сети): даём время восстановиться.
        link.disconnectTimer ??= Timer(
          _disconnectGrace,
          () => _teardown(link, error: StateError('Соединение потеряно')),
        );
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _teardown(link, error: StateError('Не удалось установить соединение'));
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _teardown(link, sendBye: false);
      default:
        break;
    }
  }

  void _onChannelState(_Link link, RTCDataChannelState state) {
    if (!_alive(link)) return;

    switch (state) {
      case RTCDataChannelState.RTCDataChannelOpen:
        _markConnected(link);
      case RTCDataChannelState.RTCDataChannelClosed:
        _teardown(
          link,
          sendBye: false,
          error: link.status == PeerLinkStatus.connected
              ? null
              : StateError('Канал закрылся до установки соединения'),
        );
      default:
        break;
    }
  }

  void _markConnected(_Link link) {
    if (link.status == PeerLinkStatus.connected) return;

    link.status = PeerLinkStatus.connected;

    link.timeout?.cancel();
    link.timeout = null;
    link.flushTimer?.cancel();
    link.flushTimer = null;
    link.outgoing.clear();

    if (!link.opened.isCompleted) link.opened.complete();

    _emit(link);
  }

  // ---------------------------------------------------------------------------
  // Завершение
  // ---------------------------------------------------------------------------

  Future<void> _teardown(
    _Link link, {
    Object? error,
    bool sendBye = true,
  }) async {
    // Ссылка уже закрыта или заменена новой.
    if (!_alive(link)) return;

    _links.remove(link.peerId);

    link.timeout?.cancel();
    link.flushTimer?.cancel();
    link.disconnectTimer?.cancel();
    link.outgoing.clear();

    link.status = error != null ? PeerLinkStatus.failed : PeerLinkStatus.closed;

    if (!link.keepOpenedOnTeardown) {
      if (!link.opened.isCompleted) {
        link.opened.completeError(error ?? StateError('Соединение закрыто'));
      }
      _emit(link, error: error);
    }

    if (sendBye && link.signalingReady) {
      unawaited(
        _signaling
            .send(
              from: _selfUid,
              to: link.peerId,
              type: SignalType.bye,
              sessionId: link.sessionId,
              payload: const {},
            )
            .catchError((Object e) {
              debugPrint('[LINK] Не удалось отправить bye: $e');
            }),
      );
    }

    try {
      await _webrtc.closePeer(link.peerId);
    } catch (e) {
      debugPrint('[LINK] Ошибка закрытия ${link.peerId}: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Вспомогательное
  // ---------------------------------------------------------------------------

  /// Эта ссылка всё ещё актуальна (не закрыта и не заменена новой).
  bool _alive(_Link link) => identical(_links[link.peerId], link);

  void _emit(_Link link, {Object? error}) {
    if (_events.isClosed) return;

    _events.add(
      PeerLinkEvent(
        peerId: link.peerId,
        status: link.status,
        initiator: link.initiator,
        error: error?.toString(),
      ),
    );
  }

  String _newSessionId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
