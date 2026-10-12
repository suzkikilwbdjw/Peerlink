import 'package:equatable/equatable.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'web_rtc_status.dart';

class PeerConnectionInfo extends Equatable {
  final String peerId;
  final WebRTCStatus status;
  final String? localDescription;
  final String? remoteDescription;
  final String? error;
  final List<RTCIceCandidate> localCandidates;

  const PeerConnectionInfo({
    required this.peerId,
    this.status = WebRTCStatus.disconnected,
    this.localDescription,
    this.remoteDescription,
    this.error,
    this.localCandidates = const [],
  });

  PeerConnectionInfo copyWith({
    WebRTCStatus? status,
    String? localDescription,
    String? remoteDescription,
    String? error,
    bool clearError = false,
    bool clearLocalDescription = false,
    bool clearRemoteDescription = false,
    List<RTCIceCandidate>? localCandidates,
    bool clearLocalCandidates = false,
  }) {
    return PeerConnectionInfo(
      peerId: peerId,
      status: status ?? this.status,
      localDescription: clearLocalDescription
          ? null
          : localDescription ?? this.localDescription,
      remoteDescription: clearRemoteDescription
          ? null
          : remoteDescription ?? this.remoteDescription,
      error: clearError ? null : error ?? this.error,
      localCandidates: clearLocalCandidates
          ? const []
          : localCandidates ?? this.localCandidates,
    );
  }

  @override
  List<Object?> get props => [
    peerId,
    status,
    localDescription,
    remoteDescription,
    error,
    localCandidates,
  ];
}
