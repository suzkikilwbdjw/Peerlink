import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class PeerConnectionSession {
  final String peerId;
  final RTCPeerConnection peerConnection;

  RTCDataChannel? dataChannel;

  Future<void> sendQueue = Future<void>.value();

  Completer<void>? bufferLowCompleter;

  void Function(RTCIceCandidate candidate)? onIceCandidate;
  void Function(RTCIceGatheringState state)? onIceGatheringState;
  void Function(RTCIceConnectionState state)? onIceConnectionState;
  void Function(RTCPeerConnectionState state)? onConnectionState;
  void Function(RTCDataChannelMessage message)? onDataReceived;
  void Function(RTCDataChannelState state)? onDataChannelState;

  PeerConnectionSession({required this.peerId, required this.peerConnection});
}
