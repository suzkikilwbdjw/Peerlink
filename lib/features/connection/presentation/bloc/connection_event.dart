part of 'connection_bloc.dart';

abstract class ConnectionEvent extends Equatable {
  const ConnectionEvent();

  @override
  List<Object?> get props => [];
}

class InitializePeer extends ConnectionEvent {
  final String peerId;

  const InitializePeer({this.peerId = 'manual'});

  @override
  List<Object?> get props => [peerId];
}

class CreateOffer extends ConnectionEvent {
  final String peerId;

  const CreateOffer({this.peerId = 'manual'});

  @override
  List<Object?> get props => [peerId];
}

class CreateAnswer extends ConnectionEvent {
  final String peerId;
  final String offerJson;

  const CreateAnswer({this.peerId = 'manual', required this.offerJson});

  @override
  List<Object?> get props => [peerId, offerJson];
}

class SetAnswer extends ConnectionEvent {
  final String peerId;
  final String answerJson;

  const SetAnswer({this.peerId = 'manual', required this.answerJson});

  @override
  List<Object?> get props => [peerId, answerJson];
}

class AddIceCandidates extends ConnectionEvent {
  final String peerId;
  final String candidatesJson;

  const AddIceCandidates({
    this.peerId = 'manual',
    required this.candidatesJson,
  });

  @override
  List<Object?> get props => [peerId, candidatesJson];
}

class DisconnectPeer extends ConnectionEvent {
  final String peerId;

  const DisconnectPeer({this.peerId = 'manual'});

  @override
  List<Object?> get props => [peerId];
}

class LocalIceCandidateReceivedForPeer extends ConnectionEvent {
  final String peerId;
  final RTCIceCandidate candidate;

  const LocalIceCandidateReceivedForPeer(this.peerId, this.candidate);

  @override
  List<Object?> get props => [peerId, candidate];
}

class PeerConnectionStatusChanged extends ConnectionEvent {
  final String peerId;
  final RTCPeerConnectionState connectionState;

  const PeerConnectionStatusChanged(this.peerId, this.connectionState);

  @override
  List<Object?> get props => [peerId, connectionState];
}

class PeerIceConnectionStateChanged extends ConnectionEvent {
  final String peerId;
  final RTCIceConnectionState iceState;

  const PeerIceConnectionStateChanged(this.peerId, this.iceState);

  @override
  List<Object?> get props => [peerId, iceState];
}
