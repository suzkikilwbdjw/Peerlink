part of 'download_manager_bloc.dart';

abstract class DownloadManagerEvent extends Equatable {
  const DownloadManagerEvent();

  @override
  List<Object?> get props => [];
}

class InitializeDownloadManager extends DownloadManagerEvent {
  const InitializeDownloadManager();

  @override
  List<Object?> get props => [];
}

class SendString extends DownloadManagerEvent {
  final String message;

  const SendString(this.message);

  @override
  List<Object?> get props => [message];
}

class SendUint8List extends DownloadManagerEvent {
  final Uint8List uint8list;

  const SendUint8List(this.uint8list);

  @override
  List<Object?> get props => [uint8list];
}

class OnDataReceived extends DownloadManagerEvent {
  final String peerId;
  final RTCDataChannelMessage message;

  const OnDataReceived({required this.peerId, required this.message});

  @override
  List<Object?> get props => [peerId, message];
}

class SendFile extends DownloadManagerEvent {
  final PlatformFile file;

  const SendFile(this.file);

  @override
  List<Object?> get props => [file];
}
