part of 'connection_bloc.dart';

class ConnectionState extends Equatable {
  static const String defaultPeerId = 'manual';

  final Map<String, PeerConnectionInfo> peers;

  const ConnectionState({this.peers = const {}});

  PeerConnectionInfo peer(String peerId) {
    return peers[peerId] ?? PeerConnectionInfo(peerId: peerId);
  }

  PeerConnectionInfo get _manual => peer(defaultPeerId);

  WebRTCStatus get status => _manual.status;
  String? get localDescription => _manual.localDescription;
  String? get remoteDescription => _manual.remoteDescription;
  String? get error => _manual.error;

  List<RTCIceCandidate> get localCandidates => _manual.localCandidates;

  ConnectionState updatePeer(PeerConnectionInfo info) {
    return ConnectionState(peers: {...peers, info.peerId: info});
  }

  ConnectionState removePeer(String peerId) {
    final updated = Map<String, PeerConnectionInfo>.from(peers);
    updated.remove(peerId);
    return ConnectionState(peers: updated);
  }

  @override
  List<Object?> get props => [peers];
}
