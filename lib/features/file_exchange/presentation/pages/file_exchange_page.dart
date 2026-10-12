/*import 'dart:io';

import 'package:p2pchat/features/connection/presentation/bloc/web_rtc_status.dart';
import 'package:path/path.dart' as p;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:p2pchat/features/connection/presentation/bloc/connection_bloc.dart';
import 'package:p2pchat/features/connection/data/services/webrtc_services.dart';
import 'package:p2pchat/features/file_exchange/presentation/bloc/download_manager_bloc.dart';

//import 'package:url_launcher/url_launcher.dart';

class FileExchangePage extends StatefulWidget {
  final String peerId;

  const FileExchangePage({super.key, required this.peerId});

  @override
  State<FileExchangePage> createState() => _FileExchangePageState();
}

class _FileExchangePageState extends State<FileExchangePage> {
  @override
  Widget build(BuildContext context) {
    return BlocProvider<DownloadManagerBloc>(
      create: (context) => DownloadManagerBloc(
        webRTCService: context.read<WebRTCService>(),
        peerId: widget.peerId,
      )..add(const InitializeDownloadManager()),
      child: Builder(
        builder: (context) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF6675E8),
                    Color(0xFF8E67D8),
                    Color(0xFFB56BD8),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    _buildHeader(context),
                    Expanded(child: _buildContent(context)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Обмен файлами',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          _buildConnectionIndicator(context),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(BuildContext context) {
    final status = context.select(
      (ConnectionBloc bloc) => bloc.state.peer(widget.peerId).status,
    );

    final isConnected = status == WebRTCStatus.connected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            color: isConnected ? Color(0xFF72F2A2) : Colors.red,
            size: 10,
          ),
          const SizedBox(width: 7),
          Text(
            status.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //_buildPeerCard(),

            const SizedBox(height: 24),

            const Text(
              'Отправить файл',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF27273A),
              ),
            ),

            const SizedBox(height: 12),

            _buildSendFileCard(context),

            const SizedBox(height: 24),

            const Text(
              'Обмен файлами',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF27273A),
              ),
            ),

            const SizedBox(height: 12),

            _buildTransfersCard(context),

            const SizedBox(height: 24),

            _buildDisconnectButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSendFileCard(BuildContext context) {
    final List<FileProgress> files = context.select(
      (DownloadManagerBloc bloc) => bloc.state.sendFiles,
    );

    if (files.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE4E4F0)),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEAFE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.upload_file_rounded,
                color: Color(0xFF7566D8),
                size: 32,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              'Выберите файл для отправки',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF303044),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Файл будет передан другому пользователю',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),

            const SizedBox(height: 18),

            _buildAddFileButton(context),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок + кнопка добавления
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Отправляемые файлы',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF303044),
                  ),
                ),
              ),

              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: () => _pickFile(context),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Файл'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7566D8),
                    side: const BorderSide(color: Color(0xFFDCD6FA)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Список отправляемых файлов
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _SendFileTransferTile(file: files[index]);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    final PlatformFile? file = await FilePicker.pickFile();

    if (file != null && context.mounted) {
      context.read<DownloadManagerBloc>().add(SendFile(file));
    }
  }

  Widget _buildAddFileButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: () => _pickFile(context),
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text('Выбрать файл'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7566D8),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildTransfersCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E4F0)),
      ),
      child: _buildTransferState(context),
    );
  }

  Widget _buildTransferState(BuildContext context) {
    final List<FileProgress> files = context.select(
      (DownloadManagerBloc bloc) => bloc.state.downloadFiles,
    );

    // Заглушка, если файлов нет
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.folder_copy_outlined,
              size: 42,
              color: Color(0xFFB5B5C8),
            ),
            SizedBox(height: 10),
            Text(
              'Здесь появятся получаемые файлы',
              style: TextStyle(color: Color(0xFF77778A), fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Список файлов
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _FileTransferTile(file: files[index]);
      },
    );
  }

  Widget _buildDisconnectButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () {
          context.read<ConnectionBloc>().add(
            DisconnectPeer(peerId: widget.peerId),
          );
        },
        icon: const Icon(Icons.link_off_rounded),
        label: const Text('Завершить соединение'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6D6D80),
          side: const BorderSide(color: Color(0xFFD4D4E0)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _FileTransferTile extends StatelessWidget {
  const _FileTransferTile({required this.file});

  final FileProgress file;

  bool get _isFailed => file.isFailure;

  bool get _isComplete => file.isComplete && !_isFailed;

  Color get _accentColor {
    if (_isFailed) return const Color(0xFFE85D75);
    if (_isComplete) return const Color(0xFF72C99A);
    return const Color(0xFF7566D8);
  }

  IconData get _statusIcon {
    if (_isFailed) return Icons.error_outline_rounded;
    if (_isComplete) return Icons.check_circle_rounded;
    return Icons.file_download_outlined;
  }

  String get _fileName {
    if (file.file.path.isEmpty) return 'Файл';
    return p.basename(file.file.path);
  }

  File get _file => file.file;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  /// Примерная оценка оставшегося времени.
  String? get _etaLabel {
    if (_isComplete || _isFailed) return null;
    if (file.receivedBytes <= 0 || file.progress <= 0) return null;

    final remainingBytes = file.totalBytes - file.receivedBytes;
    if (remainingBytes <= 0) return null;

    const assumedBytesPerSecond = 1024 * 1024; // 1 МБ/с
    final seconds = remainingBytes / assumedBytesPerSecond;

    if (seconds < 60) return '~${seconds.ceil()} сек';
    if (seconds < 3600) return '~${(seconds / 60).ceil()} мин';
    return '~${(seconds / 3600).toStringAsFixed(1)} ч';
  }

  @override
  Widget build(BuildContext context) {
    final percent = (file.progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0);
    final eta = _etaLabel;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _accentColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onDoubleTap: () {
            _openDirectory(_file);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Верхняя строка: иконка + название + статус
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_statusIcon, color: _accentColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27273A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isFailed
                                ? 'Не удалось получить'
                                : _isComplete
                                ? 'Получение завершено'
                                : 'Получение файла...',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isFailed
                                  ? const Color(0xFFE85D75)
                                  : _isComplete
                                  ? const Color(0xFF4CAF7D)
                                  : const Color(0xFF77778A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Процент
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _isFailed ? '—' : '$percent%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _accentColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Прогресс-бар
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _isFailed ? 1.0 : file.progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E4F0),
                    color: _accentColor,
                  ),
                ),

                const SizedBox(height: 10),

                // Нижняя строка: байты + расчетное время окончания
                Row(
                  children: [
                    Icon(
                      Icons.data_usage_rounded,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatBytes(file.receivedBytes)} / ${_formatBytes(file.totalBytes)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (eta != null) ...[
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        eta,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (_isComplete) ...[
                      Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: const Color(0xFF4CAF7D),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Готово',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4CAF7D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else if (_isFailed) ...[
                      Icon(
                        Icons.refresh_rounded,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Повторить',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendFileTransferTile extends StatelessWidget {
  const _SendFileTransferTile({required this.file});

  final FileProgress file;

  bool get _isComplete => file.isComplete;

  Color get _accentColor {
    if (_isComplete) {
      return const Color(0xFF72C99A);
    }

    return const Color(0xFF7566D8);
  }

  IconData get _statusIcon {
    if (_isComplete) {
      return Icons.check_circle_rounded;
    }

    return Icons.upload_rounded;
  }

  String get _fileName {
    if (file.file.path.isEmpty) {
      return 'Файл';
    }

    return p.basename(file.file.path);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes Б';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    }

    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  String? get _etaLabel {
    if (_isComplete) {
      return null;
    }

    if (file.receivedBytes <= 0 || file.progress <= 0) {
      return null;
    }

    final remainingBytes = file.totalBytes - file.receivedBytes;

    if (remainingBytes <= 0) {
      return null;
    }

    // Пока используем примерную скорость.
    const assumedBytesPerSecond = 1024 * 1024;

    final seconds = remainingBytes / assumedBytesPerSecond;

    if (seconds < 60) {
      return '~${seconds.ceil()} сек';
    }

    if (seconds < 3600) {
      return '~${(seconds / 60).ceil()} мин';
    }

    return '~${(seconds / 3600).toStringAsFixed(1)} ч';
  }

  @override
  Widget build(BuildContext context) {
    final percent = (file.progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0);

    final eta = _etaLabel;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accentColor.withValues(alpha: 0.20)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onDoubleTap: () {
            _openDirectory(file.file);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_statusIcon, color: _accentColor, size: 22),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27273A),
                            ),
                          ),

                          const SizedBox(height: 2),

                          Text(
                            _isComplete
                                ? 'Отправка завершена'
                                : 'Отправка файла...',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isComplete
                                  ? const Color(0xFF4CAF7D)
                                  : const Color(0xFF77778A),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _accentColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: file.progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E4F0),
                    color: _accentColor,
                  ),
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Icon(
                      Icons.data_usage_rounded,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),

                    const SizedBox(width: 4),

                    Text(
                      '${_formatBytes(file.receivedBytes)} / '
                      '${_formatBytes(file.totalBytes)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const Spacer(),

                    if (eta != null) ...[
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),

                      const SizedBox(width: 4),

                      Text(
                        eta,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (_isComplete) ...[
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: Color(0xFF4CAF7D),
                      ),

                      const SizedBox(width: 4),

                      const Text(
                        'Готово',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4CAF7D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openDirectory(File file) async {
  if (!await file.exists()) {
    throw 'Файл не существует';
  }

  final String systemPath = file.path.replaceAll('/', '\\');

  if (Platform.isWindows) {
    await Process.run('explorer.exe', ['/select,', systemPath]);
  }
}
*/
