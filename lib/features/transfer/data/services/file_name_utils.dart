import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

const Set<String> _windowsReservedNames = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// Делает из имени, пришедшего от другого пира, безопасное имя файла Windows:
/// без путей, запрещённых символов, зарезервированных имён и хвостовых
/// точек/пробелов.
String sanitizeFileName(String raw) {
  // p.windows понимает оба разделителя (/ и \) независимо от платформы.
  var name = p.windows.basename(raw);

  name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  name = name.replaceAll(RegExp(r'[. ]+$'), '');

  if (name.isEmpty || name == '.' || name == '..') {
    name = 'file';
  }

  final stem = name.split('.').first.toLowerCase();
  if (_windowsReservedNames.contains(stem)) {
    name = '_$name';
  }

  if (name.length > 200) {
    final ext = p.extension(name);
    final keep = ext.length <= 20 ? ext : '';
    final base = p.basenameWithoutExtension(name);
    name = base.substring(0, math.min(base.length, 200 - keep.length)) + keep;
  }

  return name;
}

/// Возвращает несуществующий файл в [dir]: если имя занято, добавляет
/// " (1)", " (2)" и т. д. перед расширением.
Future<File> uniqueFile(Directory dir, String fileName) async {
  var candidate = File(p.join(dir.path, fileName));
  if (!await candidate.exists()) return candidate;

  final ext = p.extension(fileName);
  final stem = p.basenameWithoutExtension(fileName);

  for (var i = 1; i < 10000; i++) {
    candidate = File(p.join(dir.path, '$stem ($i)$ext'));
    if (!await candidate.exists()) return candidate;
  }

  throw FileSystemException('Не удалось подобрать имя файла', dir.path);
}

/// Путь недокачанного файла. Он определяется только именем и fileId, поэтому
/// докачка находит свой .part без отдельного хранения путей.
File partFileFor(Directory dir, String name, String fileId) {
  final safeName = sanitizeFileName(name);
  return File(p.join(dir.path, '$safeName.${fileId.substring(0, 12)}.part'));
}
