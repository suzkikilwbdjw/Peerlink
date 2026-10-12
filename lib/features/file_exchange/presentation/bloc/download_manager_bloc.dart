import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:bloc_concurrency/bloc_concurrency.dart';

import 'dart:math' as math;

import 'package:async/async.dart';
import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:p2pchat/features/connection/data/services/webrtc_services.dart';
import 'package:path_provider/path_provider.dart';

part 'download_manager_event.dart';
part 'download_manager_state.dart';

class DownloadManagerBloc
    extends Bloc<DownloadManagerEvent, DownloadManagerState> {
  final WebRTCService _webRTCService;
  final String peerId;

  FileProgress? _fileProgress;
  RandomAccessFile? _receivingFile;

  static const int chunkSize = 16 * 1024;
  static const int windowSize = 1024 * 1024;

  String? _activeTransferId;
  String? _activeIncomingTransferId;

  int _ackedBytes = 0;

  Completer<void>? _ackSignal;
  Completer<void>? _fileAckSignal;

  int? _expectedFileSize;

  String? _ackError;
  bool _sendingFile = false;

  DownloadManagerBloc({required this._webRTCService, required this.peerId})
    : super(const DownloadManagerState()) {
    on<InitializeDownloadManager>(_initialize);
    on<OnDataReceived>(_onDataReceived, transformer: sequential());
    on<SendFile>(_sendFile);
  }

  Future<void> _initialize(
    DownloadManagerEvent event,
    Emitter<DownloadManagerState> emit,
  ) async {
    try {
      _webRTCService.setOnDataReceived(peerId, (message) {
        add(OnDataReceived(peerId: peerId, message: message));
      });
    } catch (e, stackTrace) {
      debugPrint('[DOWNLOAD][$peerId] Initialize error: $e');
      debugPrint('$stackTrace');
    }
  }

  void _signalAck() {
    final signal = _ackSignal;

    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  void _signalFileAck() {
    final signal = _fileAckSignal;

    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  void _handleControlMessage(Map<String, dynamic> message) {
    final type = message['type'];
    final transferId = message['transferId'];

    // Игнорируем подтверждения от другой передачи.
    if (transferId != _activeTransferId) {
      return;
    }

    switch (type) {
      case 'chunk_ack':
        final receivedBytes = message['receivedBytes'];

        if (receivedBytes is! int ||
            receivedBytes < _ackedBytes ||
            receivedBytes > (_expectedFileSize ?? 0)) {
          debugPrint('[ACK] Invalid receivedBytes: $receivedBytes');
          return;
        }

        _ackedBytes = receivedBytes;
        _signalAck();

        debugPrint('[ACK] $_ackedBytes / $_expectedFileSize');
        break;

      case 'file_ack':
        final totalSize = message['totalSize'];

        if (totalSize is! int ||
            totalSize != _expectedFileSize ||
            _ackedBytes != _expectedFileSize) {
          _ackError = 'Некорректное финальное подтверждение файла';
        }

        _signalFileAck();
        _signalAck();
        break;

      case 'file_error':
        _ackError =
            message['message']?.toString() ?? 'Ошибка на стороне получателя';

        _signalAck();
        _signalFileAck();

        debugPrint('[TRANSFER] Receiver error: $_ackError');
        break;
    }
  }

  Future<void> _waitForAck(int expectedBytes) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));

    while (_ackedBytes < expectedBytes) {
      if (_ackError != null) {
        throw StateError(_ackError!);
      }

      final remaining = deadline.difference(DateTime.now());

      if (remaining <= Duration.zero) {
        throw TimeoutException('ACK timeout: $_ackedBytes / $expectedBytes');
      }

      final signal = Completer<void>();
      _ackSignal = signal;

      // Проверяем ещё раз после установки ожидания.
      if (_ackedBytes >= expectedBytes || _ackError != null) {
        if (!signal.isCompleted) signal.complete();
      }

      try {
        await signal.future.timeout(remaining);
      } finally {
        if (identical(_ackSignal, signal)) {
          _ackSignal = null;
        }
      }
    }

    if (_ackError != null) {
      throw StateError(_ackError!);
    }
  }

  Future<void> _waitForFileAck(int fileSize) async {
    final signal = Completer<void>();
    _fileAckSignal = signal;

    try {
      await signal.future.timeout(const Duration(seconds: 60));

      if (_ackError != null) {
        throw StateError(_ackError!);
      }

      if (_ackedBytes != fileSize) {
        throw StateError('Не все байты подтверждены: $_ackedBytes / $fileSize');
      }
    } finally {
      _fileAckSignal = null;
    }
  }

  Future<void> _sendFile(
    SendFile event,
    Emitter<DownloadManagerState> emit,
  ) async {
    final session = _webRTCService.getSession(peerId);

    if (session?.dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      debugPrint('[TRANSFER][$peerId] DataChannel is not open');
      return;
    }

    if (_sendingFile) {
      debugPrint('[TRANSFER] Another file is being sent');
      return;
    }

    final filePath = event.file.path;

    if (filePath == null) {
      debugPrint('[TRANSFER] File path is null');
      return;
    }

    _sendingFile = true;

    final reader = ChunkedStreamReader(event.file.readAsByteStream());

    try {
      final fileSize = await event.file.length();

      if (fileSize == null) {
        throw StateError('Не удалось определить размер файла');
      }

      final transferId = DateTime.now().microsecondsSinceEpoch.toString();

      _activeTransferId = transferId;
      _expectedFileSize = fileSize;
      _ackedBytes = 0;
      _ackError = null;

      await _webRTCService.sendDataTo(
        peerId,
        jsonEncode({
          'type': 'file_start',
          'transferId': transferId,
          'name': event.file.name,
          'totalSize': fileSize,
        }),
      );

      emit(
        state.copyWith(
          sendFiles: [
            ...state.sendFiles,
            FileProgress(
              file: File(filePath),
              receivedBytes: 0,
              totalBytes: fileSize,
            ),
          ],
        ),
      );

      var sentBytes = 0;

      while (sentBytes < fileSize) {
        final windowEnd = math.min(sentBytes + windowSize, fileSize);

        while (sentBytes < windowEnd) {
          final length = math.min(chunkSize, windowEnd - sentBytes);

          final chunk = Uint8List.fromList(await reader.readChunk(length));

          if (chunk.isEmpty) {
            throw StateError('Файл закончился раньше ожидаемого размера');
          }

          await _webRTCService.sendBytesTo(peerId, chunk);
          sentBytes += chunk.length;

          emit(
            state.copyWith(
              sendFiles: state.sendFiles.map((file) {
                if (file.file.path == filePath) {
                  return file.copyWith(receivedBytes: sentBytes);
                }
                return file;
              }).toList(),
            ),
          );
        }

        // Окно отправлено. Ждём, пока получатель запишет
        // все его байты и подтвердит накопленный размер.
        await _waitForAck(windowEnd);

        debugPrint('[TRANSFER] Confirmed: $_ackedBytes / $fileSize');
      }

      await _webRTCService.sendDataTo(
        peerId,
        jsonEncode({
          'type': 'file_end',
          'transferId': transferId,
          'totalSize': fileSize,
        }),
      );

      await _waitForFileAck(fileSize);

      debugPrint('[TRANSFER] File successfully acknowledged');

      // Здесь можно установить отдельный статус Completed,
      // если он предусмотрен в FileProgress.
    } catch (e, stackTrace) {
      debugPrint('[TRANSFER] Failed: $e');
      debugPrint('$stackTrace');

      emit(
        state.copyWith(
          sendFiles: state.sendFiles.map((file) {
            if (file.file.path == filePath) {
              return file.copyWith(error: e.toString());
            }
            return file;
          }).toList(),
        ),
      );
    } finally {
      _sendingFile = false;
      _activeTransferId = null;
      _expectedFileSize = null;
      _ackError = null;
      _ackSignal = null;
      _fileAckSignal = null;

      await reader.cancel();
    }
  }

  Future<void> _onDataReceived(
    OnDataReceived event,
    Emitter<DownloadManagerState> emit,
  ) async {
    if (event.peerId != peerId) {
      return;
    }

    try {
      // Бинарные сообщения — это части файла.
      if (event.message.isBinary) {
        final bytes = event.message.binary;

        if (_fileProgress == null || _receivingFile == null) {
          throw StateError('Получены данные до начала передачи файла');
        }

        if (_activeIncomingTransferId == null) {
          throw StateError('Не задан transferId входящей передачи');
        }

        final newReceivedBytes = _fileProgress!.receivedBytes + bytes.length;

        if (newReceivedBytes > _fileProgress!.totalBytes) {
          throw StateError('Получено больше байтов, чем заявлено в file_start');
        }

        // Сначала записываем данные.
        await _receivingFile!.writeFrom(bytes);

        // Увеличиваем счётчик только один раз.
        _fileProgress = _fileProgress!.copyWith(
          receivedBytes: newReceivedBytes,
        );

        final currentProgress = _fileProgress!;

        emit(
          state.copyWith(
            downloadFiles: state.downloadFiles.map((file) {
              return file.file.path == currentProgress.file.path
                  ? currentProgress
                  : file;
            }).toList(),
          ),
        );

        // Подтверждаем только после успешной записи.
        await _webRTCService.sendDataTo(
          peerId,
          jsonEncode({
            'type': 'chunk_ack',
            'transferId': _activeIncomingTransferId,
            'receivedBytes': currentProgress.receivedBytes,
          }),
        );

        debugPrint(
          '[RECEIVE] ${currentProgress.receivedBytes} / '
          '${currentProgress.totalBytes}',
        );

        return;
      }

      // Все управляющие сообщения приходят как текстовый JSON.
      final decoded = jsonDecode(event.message.text);

      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Некорректное управляющее сообщение');
      }

      final message = decoded;
      final type = message['type'];

      // ACK и ошибки исходящей передачи.
      if (type == 'chunk_ack' || type == 'file_ack' || type == 'file_error') {
        _handleControlMessage(message);
        return;
      }

      if (type == 'file_start') {
        final transferId = message['transferId'];
        final name = message['name'];
        final totalSize = message['totalSize'];

        if (transferId is! String ||
            transferId.isEmpty ||
            name is! String ||
            name.isEmpty ||
            totalSize is! int ||
            totalSize < 0) {
          throw FormatException('Некорректные данные file_start');
        }

        // Пока принимаем только один файл одновременно.
        if (_receivingFile != null) {
          throw StateError('Уже выполняется приём другого файла');
        }

        final directory = await getApplicationDocumentsDirectory();

        // Не позволяем имени файла подменить путь назначения.
        final safeName = p.basename(name);

        if (safeName.isEmpty || safeName == '.' || safeName == '..') {
          throw FormatException('Некорректное имя файла');
        }

        final filePath = p.join(directory.path, safeName);
        final file = File(filePath);

        if (await file.exists()) {
          await file.delete();
        }

        await file.create(recursive: true);

        _receivingFile = await file.open(mode: FileMode.writeOnly);
        _activeIncomingTransferId = transferId;

        _fileProgress = FileProgress(
          file: file,
          receivedBytes: 0,
          totalBytes: totalSize,
        );

        emit(
          state.copyWith(
            downloadFiles: [...state.downloadFiles, _fileProgress!],
          ),
        );

        debugPrint(
          '[RECEIVE] Start: $safeName, size=$totalSize, id=$transferId',
        );

        // Для файла нулевого размера сразу ждём file_end.
        return;
      }

      if (type == 'file_end') {
        if (_fileProgress == null || _receivingFile == null) {
          throw StateError('Получен file_end, но файл не был открыт');
        }

        if (message['transferId'] != _activeIncomingTransferId) {
          throw StateError('transferId в file_end не совпадает');
        }

        final declaredSize = message['totalSize'];

        if (declaredSize != _fileProgress!.totalBytes ||
            !_fileProgress!.isComplete) {
          throw StateError(
            'Файл получен не полностью: '
            '${_fileProgress!.receivedBytes} / '
            '${_fileProgress!.totalBytes}',
          );
        }

        final file = _fileProgress!.file;
        final transferId = _activeIncomingTransferId!;
        final expectedSize = _fileProgress!.totalBytes;

        await _receivingFile!.flush();
        await _receivingFile!.close();

        _receivingFile = null;

        final actualSize = await file.length();

        if (actualSize != expectedSize) {
          throw StateError(
            'Размер на диске не совпадает: '
            '$actualSize / $expectedSize',
          );
        }

        debugPrint('[RECEIVE] File saved: ${file.path}');
        debugPrint('[RECEIVE] Verified size: $actualSize');

        // Отправляем финальный ACK только после проверки файла.
        await _webRTCService.sendDataTo(
          peerId,
          jsonEncode({
            'type': 'file_ack',
            'transferId': transferId,
            'totalSize': actualSize,
          }),
        );

        _fileProgress = null;
        _activeIncomingTransferId = null;

        return;
      }

      debugPrint('[RECEIVE] Unknown message: ${event.message.text}');
    } catch (e, stackTrace) {
      debugPrint('[RECEIVE] Error: $e');
      debugPrint('$stackTrace');

      // Не оставляем отправителя ждать ACK, если известна
      // ошибка во время приёма файла.
      final transferId = _activeIncomingTransferId;

      if (transferId != null) {
        try {
          await _webRTCService.sendDataTo(
            peerId,
            jsonEncode({
              'type': 'file_error',
              'transferId': transferId,
              'message': e.toString(),
            }),
          );
        } catch (sendError) {
          debugPrint('[RECEIVE] Could not send file_error: $sendError');
        }
      }

      try {
        await _receivingFile?.close();
      } catch (_) {
        // Игнорируем ошибку закрытия после основной ошибки.
      }

      _receivingFile = null;
      _activeIncomingTransferId = null;
      _fileProgress = null;
    }
  }
}
