import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:equatable/equatable.dart';
import 'package:p2pchat/features/connection/data/models/peer_connection_info.dart';
import 'package:p2pchat/features/connection/data/models/web_rtc_status.dart';
import 'package:p2pchat/features/connection/data/services/webrtc_services.dart';

part 'connection_state.dart';
part 'connection_event.dart';

class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionState> {
  final WebRTCService _webRTCService;

  ConnectionBloc(this._webRTCService) : super(const ConnectionState()) {
    on<InitializePeer>(_onInitializePeer);
    on<CreateOffer>(_onCreateOffer);
    on<CreateAnswer>(_onCreateAnswer);
    on<SetAnswer>(_onSetAnswer);
    on<AddIceCandidates>(_onAddIceCandidates);
    on<DisconnectPeer>(_onDisconnectPeer);
    on<LocalIceCandidateReceivedForPeer>(_onLocalIceCandidateReceived);
    on<PeerConnectionStatusChanged>(_onPeerConnectionStatusChanged);
    on<PeerIceConnectionStateChanged>(_onPeerIceConnectionStateChanged);
  }

  Future<void> _ensurePeer(String peerId) async {
    await _webRTCService.initializePeer(peerId);

    _webRTCService.setOnIceCandidate((candidate) {
      add(LocalIceCandidateReceivedForPeer(peerId, candidate));
    }, peerId: peerId);

    _webRTCService.setOnConnectionState((connectionState) {
      add(PeerConnectionStatusChanged(peerId, connectionState));
    }, peerId: peerId);

    _webRTCService.setOnIceConnectionState((iceState) {
      add(PeerIceConnectionStateChanged(peerId, iceState));
    }, peerId: peerId);
  }

  Future<void> _onInitializePeer(
    InitializePeer event,
    Emitter<ConnectionState> emit,
  ) async {
    final peerId = event.peerId;

    if (_webRTCService.getSession(peerId) != null) {
      return;
    }

    final currentPeer = state.peer(peerId);

    emit(
      state.updatePeer(
        currentPeer.copyWith(
          status: WebRTCStatus.initializing,
          clearError: true,
          clearLocalDescription: true,
          clearRemoteDescription: true,
          clearLocalCandidates: true,
        ),
      ),
    );

    try {
      await _ensurePeer(peerId);

      emit(
        state.updatePeer(
          state
              .peer(peerId)
              .copyWith(status: WebRTCStatus.disconnected, clearError: true),
        ),
      );
    } catch (e) {
      _setError(emit, peerId, e);
    }
  }

  Future<void> _onCreateOffer(
    CreateOffer event,
    Emitter<ConnectionState> emit,
  ) async {
    final peerId = event.peerId;

    try {
      await _ensurePeer(peerId);

      _updatePeer(
        emit,
        PeerConnectionInfo(peerId: peerId, status: WebRTCStatus.creatingOffer),
      );

      // Создавать DataChannel должен инициатор.
      await _webRTCService.createDataChannel(peerId: peerId);

      final offer = await _webRTCService.createOffer(peerId: peerId);

      await _webRTCService.setLocalDescription(offer, peerId: peerId);

      final offerJson = jsonEncode({'type': offer.type, 'sdp': offer.sdp});

      _updatePeer(
        emit,
        state
            .peer(peerId)
            .copyWith(
              status: WebRTCStatus.waitingForAnswer,
              localDescription: offerJson,
              clearError: true,
            ),
      );
    } catch (e) {
      _setError(emit, peerId, e);
    }
  }

  Future<void> _onCreateAnswer(
    CreateAnswer event,
    Emitter<ConnectionState> emit,
  ) async {
    final peerId = event.peerId;

    try {
      await _ensurePeer(peerId);

      _updatePeer(
        emit,
        PeerConnectionInfo(
          peerId: peerId,
          status: WebRTCStatus.creatingAnswer,
          remoteDescription: event.offerJson,
        ),
      );

      final offerMap = jsonDecode(event.offerJson) as Map<String, dynamic>;

      final offer = RTCSessionDescription(
        offerMap['sdp'] as String?,
        offerMap['type'] as String?,
      );

      await _webRTCService.setRemoteDescription(offer, peerId: peerId);

      final answer = await _webRTCService.createAnswer(peerId: peerId);

      await _webRTCService.setLocalDescription(answer, peerId: peerId);

      final answerJson = jsonEncode({'type': answer.type, 'sdp': answer.sdp});

      _updatePeer(
        emit,
        state
            .peer(peerId)
            .copyWith(
              status: WebRTCStatus.waitingForIceCandidates,
              localDescription: answerJson,
              clearError: true,
            ),
      );
    } catch (e) {
      _setError(emit, peerId, e);
    }
  }

  Future<void> _onSetAnswer(
    SetAnswer event,
    Emitter<ConnectionState> emit,
  ) async {
    final peerId = event.peerId;

    try {
      await _ensurePeer(peerId);

      final answerMap = jsonDecode(event.answerJson) as Map<String, dynamic>;

      final answer = RTCSessionDescription(
        answerMap['sdp'] as String?,
        answerMap['type'] as String?,
      );

      await _webRTCService.setRemoteDescription(answer, peerId: peerId);

      _updatePeer(
        emit,
        state
            .peer(peerId)
            .copyWith(
              status: WebRTCStatus.connecting,
              remoteDescription: event.answerJson,
              clearError: true,
            ),
      );
    } catch (e) {
      _setError(emit, peerId, e);
    }
  }

  Future<void> _onAddIceCandidates(
    AddIceCandidates event,
    Emitter<ConnectionState> emit,
  ) async {
    final peerId = event.peerId;

    try {
      await _ensurePeer(peerId);

      final decoded = jsonDecode(event.candidatesJson);
      if (decoded is! List) {
        throw const FormatException('ICE candidates must be a JSON array');
      }

      for (final item in decoded) {
        if (item is! Map) continue;

        final candidate = RTCIceCandidate(
          item['candidate'] as String?,
          item['sdpMid'] as String?,
          item['sdpMLineIndex'] as int?,
        );

        await _webRTCService.addCandidate(candidate, peerId: peerId);
      }

      _updatePeer(emit, state.peer(peerId).copyWith(clearError: true));
    } catch (e) {
      _setError(emit, peerId, e);
    }
  }

  Future<void> _onDisconnectPeer(
    DisconnectPeer event,
    Emitter<ConnectionState> emit,
  ) async {
    try {
      await _webRTCService.closePeer(event.peerId);
      emit(state.removePeer(event.peerId));
    } catch (e) {
      _setError(emit, event.peerId, e);
    }
  }

  void _onLocalIceCandidateReceived(
    LocalIceCandidateReceivedForPeer event,
    Emitter<ConnectionState> emit,
  ) {
    final current = state.peer(event.peerId);
    final updatedCandidates = [...current.localCandidates, event.candidate];

    _updatePeer(emit, current.copyWith(localCandidates: updatedCandidates));
  }

  void _onPeerConnectionStatusChanged(
    PeerConnectionStatusChanged event,
    Emitter<ConnectionState> emit,
  ) {
    final status = switch (event.connectionState) {
      RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
        WebRTCStatus.connected,
      RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
        WebRTCStatus.connecting,
      RTCPeerConnectionState.RTCPeerConnectionStateFailed => WebRTCStatus.error,
      RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
        WebRTCStatus.disconnected,
      _ => state.peer(event.peerId).status,
    };

    final info = state.peer(event.peerId);

    _updatePeer(
      emit,
      info.copyWith(
        status: status,
        error: status == WebRTCStatus.error ? 'WebRTC connection failed' : null,
        clearError: status != WebRTCStatus.error,
      ),
    );
  }

  void _onPeerIceConnectionStateChanged(
    PeerIceConnectionStateChanged event,
    Emitter<ConnectionState> emit,
  ) {
    final current = state.peer(event.peerId);

    switch (event.iceState) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _updatePeer(
          emit,
          current.copyWith(status: WebRTCStatus.connected, clearError: true),
        );
        break;

      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        if (current.status != WebRTCStatus.connected) {
          _updatePeer(emit, current.copyWith(status: WebRTCStatus.connecting));
        }
        break;

      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _updatePeer(
          emit,
          current.copyWith(
            status: WebRTCStatus.error,
            error: 'ICE connection failed',
          ),
        );
        break;

      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        _updatePeer(emit, current.copyWith(status: WebRTCStatus.disconnected));
        break;

      default:
        break;
    }
  }

  void _updatePeer(Emitter<ConnectionState> emit, PeerConnectionInfo info) {
    emit(state.updatePeer(info));
  }

  void _setError(Emitter<ConnectionState> emit, String peerId, Object error) {
    _updatePeer(
      emit,
      state
          .peer(peerId)
          .copyWith(status: WebRTCStatus.error, error: error.toString()),
    );
  }

  @override
  Future<void> close() async {
    await super.close();
    _webRTCService.closeAll();
  }
}
