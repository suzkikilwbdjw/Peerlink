part of 'download_manager_bloc.dart';

class FileProgress {
  final File file;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  const FileProgress({
    required this.file,
    required this.receivedBytes,
    required this.totalBytes,
    this.error,
  });

  double get progress {
    if (totalBytes == 0) {
      return 0.0;
    }

    return receivedBytes / totalBytes;
  }

  bool get isComplete {
    return receivedBytes >= totalBytes;
  }

  bool get isFailure {
    return error != null;
  }

  FileProgress copyWith({
    File? file,
    int? receivedBytes,
    int? totalBytes,
    String? error,
  }) {
    return FileProgress(
      file: file ?? this.file,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
    );
  }
}

class DownloadManagerState extends Equatable {
  final List<FileProgress> downloadFiles;
  final List<FileProgress> sendFiles;

  const DownloadManagerState({
    this.downloadFiles = const [],
    this.sendFiles = const [],
  });

  DownloadManagerState copyWith({
    List<FileProgress>? downloadFiles,
    List<FileProgress>? sendFiles,
  }) {
    return DownloadManagerState(
      downloadFiles: downloadFiles ?? this.downloadFiles,
      sendFiles: sendFiles ?? this.sendFiles,
    );
  }

  @override
  List<Object?> get props => [downloadFiles, sendFiles];
}
