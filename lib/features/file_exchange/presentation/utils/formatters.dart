import 'package:flutter/material.dart';

String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var i = 0;

  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }

  final digits = (i == 0 || value >= 100) ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[i]}';
}

String formatSpeed(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatEta(Duration? d) {
  if (d == null) return '—';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  return '${d.inSeconds}s';
}

String formatPercent(double progress) =>
    '${(progress * 100).toStringAsFixed(0)}%';

IconData iconForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

  switch (ext) {
    case 'iso':
    case 'img':
      return Icons.album_outlined;
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
      return Icons.folder_zip_outlined;
    case 'mp4':
    case 'mkv':
    case 'avi':
      return Icons.movie_outlined;
    case 'mp3':
    case 'flac':
    case 'wav':
      return Icons.music_note_outlined;
    case 'pdf':
    case 'epub':
      return Icons.menu_book_outlined;
    case 'exe':
    case 'msi':
      return Icons.apps_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}
