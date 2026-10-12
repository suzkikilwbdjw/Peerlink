import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'peer_connection_session.dart';

class WebRTCService {
  // static const String defaultPeerId = 'manual';
  static const int chunkSize = 16 * 1024;
  static const int maxBufferedAmount = 256 * 1024;
  static const int bufferedAmountLowThreshold = 64 * 1024;

  final Map<String, PeerConnectionSession> _sessions = {};

  final Map<String, Future<void>> _initializations = {};

  PeerConnectionSession? getSession(String peerId) {
    return _sessions[peerId];
  }

  List<String> get connectedPeerIds => _sessions.entries
      .where(
        (entry) =>
            entry.value.dataChannel?.state ==
            RTCDataChannelState.RTCDataChannelOpen,
      )
      .map((entry) => entry.key)
      .toList(growable: false);

  // Совместимость со старым кодом, который использует один пир.
  // RTCPeerConnection? get peerConnection =>
  //     _sessions[defaultPeerId]?.peerConnection;

  // RTCDataChannel? get dataChannel => _sessions[defaultPeerId]?.dataChannel;

  // Старый callback для manual.
  void Function(RTCDataChannelMessage message)? onDataReceived;

  Map<String, dynamic> _peerConfiguration() {
    final turnUrlsString = dotenv.env['METERED_TURN_URLS'] ?? '';
    final turnUrls = turnUrlsString
        .split(',')
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();

    final stunUrl =
        dotenv.env['METERED_STUN_URL'] ?? 'stun:stun.l.google.com:19302';

    final iceServers = <Map<String, dynamic>>[
      {
        'urls': [stunUrl],
      },
    ];

    if (turnUrls.isNotEmpty) {
      iceServers.add({
        'urls': turnUrls,
        'username': dotenv.env['METERED_TURN_USERNAME'] ?? '',
        'credential': dotenv.env['METERED_TURN_CREDENTIAL'] ?? '',
      });
    }

    return {'iceServers': iceServers};
  }

  // Future<void> initialize() => initializePeer(defaultPeerId);

  Future<void> initializePeer(String peerId) async {
    if (_sessions.containsKey(peerId)) return;

    final existingInitialization = _initializations[peerId];
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }

    final initialization = _createPeerSession(peerId);
    _initializations[peerId] = initialization;

    try {
      await initialization;
    } finally {
      if (identical(_initializations[peerId], initialization)) {
        _initializations.remove(peerId);
      }
    }
  }

  Future<void> _createPeerSession(String peerId) async {
    final peer = await createPeerConnection(_peerConfiguration());

    final session = PeerConnectionSession(peerId: peerId, peerConnection: peer);

    _sessions[peerId] = session;

    peer.onIceCandidate = (candidate) {
      session.onIceCandidate?.call(candidate);
    };

    peer.onIceGatheringState = (state) {
      session.onIceGatheringState?.call(state);
    };

    peer.onIceConnectionState = (state) {
      session.onIceConnectionState?.call(state);
    };

    peer.onConnectionState = (state) {
      session.onConnectionState?.call(state);
    };

    peer.onDataChannel = (channel) {
      _configureDataChannel(session, channel);
    };
  }

  void setOnIceCandidate(
    void Function(RTCIceCandidate candidate) callback, {
    required String peerId, //= defaultPeerId,
  }) {
    _sessions[peerId]?.onIceCandidate = callback;
  }

  void setOnIceGatheringState(
    void Function(RTCIceGatheringState state) callback, {
    required String peerId, //= defaultPeerId,
  }) {
    _sessions[peerId]?.onIceGatheringState = callback;
  }

  void setOnIceConnectionState(
    void Function(RTCIceConnectionState state) callback, {
    required String peerId, //= defaultPeerId,
  }) {
    _sessions[peerId]?.onIceConnectionState = callback;
  }

  void setOnConnectionState(
    void Function(RTCPeerConnectionState state) callback, {
    required String peerId, //= defaultPeerId,
  }) {
    _sessions[peerId]?.onConnectionState = callback;
  }

  void setOnDataChannelState(
    void Function(RTCDataChannelState state) callback, {
    required String peerId,
  }) {
    _sessions[peerId]?.onDataChannelState = callback;
  }

  void setOnDataReceived(
    String peerId,
    void Function(RTCDataChannelMessage message) callback,
  ) {
    final session = _sessions[peerId];
    if (session == null) {
      throw StateError('Peer $peerId is not initialized');
    }
    session.onDataReceived = callback;
  }

  Future<RTCSessionDescription> createOffer({
    required String peerId, //= defaultPeerId,
  }) async {
    final session = _requireSession(peerId);
    return session.peerConnection.createOffer();
  }

  Future<RTCSessionDescription> createAnswer({
    required String peerId, //= defaultPeerId,
  }) async {
    final session = _requireSession(peerId);
    return session.peerConnection.createAnswer();
  }

  Future<void> setLocalDescription(
    RTCSessionDescription description, {
    required String peerId, //= defaultPeerId,
  }) async {
    final session = _requireSession(peerId);
    await session.peerConnection.setLocalDescription(description);
  }

  Future<void> setRemoteDescription(
    RTCSessionDescription description, {
    required String peerId, //= defaultPeerId,
  }) async {
    final session = _requireSession(peerId);
    await session.peerConnection.setRemoteDescription(description);
  }

  Future<void> addCandidate(
    RTCIceCandidate candidate, {
    required String peerId, //= defaultPeerId,
  }) async {
    final session = _requireSession(peerId);
    await session.peerConnection.addCandidate(candidate);
  }

  Future<void> createDataChannel({
    required String peerId /*= defaultPeerId*/,
  }) async {
    final session = _requireSession(peerId);

    if (session.dataChannel != null) {
      return;
    }

    final channel = await session.peerConnection.createDataChannel(
      'fileTransfer',
      RTCDataChannelInit(),
    );

    _configureDataChannel(session, channel);
  }

  void _configureDataChannel(
    PeerConnectionSession session,
    RTCDataChannel channel,
  ) {
    session.dataChannel = channel;

    channel.bufferedAmountLowThreshold = bufferedAmountLowThreshold;

    channel.onDataChannelState = (state) {
      debugPrint('[${session.peerId}] CHANNEL: $state');

      session.onDataChannelState?.call(state);

      final closed =
          state == RTCDataChannelState.RTCDataChannelClosing ||
          state == RTCDataChannelState.RTCDataChannelClosed;

      if (closed) {
        final waiter = session.bufferLowCompleter;
        session.bufferLowCompleter = null;

        if (waiter != null && !waiter.isCompleted) {
          waiter.completeError(
            StateError('DataChannel for ${session.peerId} closed: $state'),
          );
        }
      }
    };

    channel.onBufferedAmountLow = (amount) {
      debugPrint('[${session.peerId}] BUFFER LOW: $amount');

      final waiter = session.bufferLowCompleter;
      session.bufferLowCompleter = null;

      if (waiter != null && !waiter.isCompleted) {
        waiter.complete();
      }
    };

    channel.onMessage = (message) {
      session.onDataReceived?.call(message);
    };

    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      session.onDataChannelState?.call(RTCDataChannelState.RTCDataChannelOpen);
    }
  }

  // Старый метод: отправка через manual.
  // Future<void> sendData(String data) {
  //   return sendDataTo(defaultPeerId, data);
  // }

  // Future<void> sendBytes(Uint8List bytes) {
  //   return sendBytesTo(defaultPeerId, bytes);
  // }

  Future<void> sendDataTo(String peerId, String data) {
    final bytesCount = utf8.encode(data).length;

    return _enqueueSend(peerId, () async {
      final session = _requireSession(peerId);
      final channel = _requireOpenChannel(session);

      await _waitForBuffer(session, bytesCount);
      _ensureOpen(channel, peerId);

      await channel.send(RTCDataChannelMessage(data));
    });
  }

  Future<void> sendBytesTo(String peerId, Uint8List bytes) {
    if (bytes.isEmpty) {
      return Future<void>.value();
    }

    return _enqueueSend(peerId, () async {
      final session = _requireSession(peerId);
      final channel = _requireOpenChannel(session);

      await _waitForBuffer(session, bytes.length);
      _ensureOpen(channel, peerId);

      await channel.send(RTCDataChannelMessage.fromBinary(bytes));
    });
  }

  Future<void> _enqueueSend(String peerId, Future<void> Function() action) {
    final session = _requireSession(peerId);

    final result = session.sendQueue.then((_) => action());

    // Ошибка текущей отправки возвращается вызывающему коду,
    // но не ломает очередь для следующих операций.
    session.sendQueue = result.catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      debugPrint('[${session.peerId}] SEND ERROR: $error');
    });

    return result;
  }

  Future<void> _waitForBuffer(
    PeerConnectionSession session,
    int nextBytes,
  ) async {
    if (nextBytes > maxBufferedAmount) {
      throw ArgumentError('Message is larger than maxBufferedAmount');
    }

    final channel = _requireOpenChannel(session);

    while (true) {
      _ensureOpen(channel, session.peerId);

      final buffered = channel.bufferedAmount ?? 0;

      if (buffered + nextBytes <= maxBufferedAmount) {
        return;
      }

      if (session.bufferLowCompleter != null) {
        throw StateError('Another buffer waiter exists for ${session.peerId}');
      }

      final waiter = Completer<void>();
      session.bufferLowCompleter = waiter;

      // Повторная проверка после регистрации callback.
      final current = channel.bufferedAmount ?? 0;

      if (current + nextBytes <= maxBufferedAmount && !waiter.isCompleted) {
        waiter.complete();
      }

      debugPrint('[${session.peerId}] Waiting for buffer: $current bytes');

      try {
        await waiter.future.timeout(const Duration(seconds: 30));
      } finally {
        if (identical(session.bufferLowCompleter, waiter)) {
          session.bufferLowCompleter = null;
        }
      }
    }
  }

  RTCDataChannel _requireOpenChannel(PeerConnectionSession session) {
    final channel = session.dataChannel;

    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('DataChannel for ${session.peerId} is not open');
    }

    return channel;
  }

  void _ensureOpen(RTCDataChannel channel, String peerId) {
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('DataChannel for $peerId is not open');
    }
  }

  PeerConnectionSession _requireSession(String peerId) {
    final session = _sessions[peerId];

    if (session == null) {
      throw StateError('Peer $peerId is not initialized');
    }

    return session;
  }

  Future<void> closePeer(String peerId) async {
    final session = _sessions.remove(peerId);
    if (session == null) return;

    final waiter = session.bufferLowCompleter;
    session.bufferLowCompleter = null;

    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Peer $peerId is closing'));
    }

    try {
      await session.dataChannel?.close();
    } catch (e) {
      debugPrint('[$peerId] Error closing DataChannel: $e');
    }

    try {
      await session.peerConnection.close();
    } catch (e) {
      debugPrint('[$peerId] Error closing PeerConnection: $e');
    }
  }

  Future<void> closeAll() async {
    final peerIds = _sessions.keys.toList();

    for (final peerId in peerIds) {
      await closePeer(peerId);
    }

    onDataReceived = null;
  }
}
