import 'package:equatable/equatable.dart';
import 'package:p2pchat/features/tracker/data/models/peer_announcement.dart';

/// Файл из каталога сети: один fileId, собранный из анонсов нескольких пиров.
class NetworkFile extends Equatable {
  final String id;
  final String name;
  final int size;

  /// uid пиров, у которых файл есть прямо сейчас.
  final List<String> seederIds;

  const NetworkFile({
    required this.id,
    required this.name,
    required this.size,
    required this.seederIds,
  });

  int get seeders => seederIds.length;

  @override
  List<Object?> get props => [id, name, size, seederIds];
}

/// Собирает каталог из анонсов пиров. Чистая функция, её легко тестировать.
///
/// - свой собственный анонс (selfUid) не учитывается;
/// - пир считается онлайн, если его lastSeen не старше [ttl];
/// - если пиры заявляют для одного fileId разные размеры, берётся самый
///   частый, а расходящиеся анонсы отбрасываются. Это простая защита от
///   подделки: настоящий хеш у файла только один, а размер у него один;
/// - имя берётся самое частое среди согласных пиров.
List<NetworkFile> buildCatalog({
  required List<PeerAnnouncement> peers,
  required String selfUid,
  required DateTime now,
  required Duration ttl,
}) {
  final byId = <String, List<(String uid, AnnouncedFile file)>>{};

  for (final peer in peers) {
    if (peer.uid == selfUid) continue;
    if (now.difference(peer.lastSeen) > ttl) continue;

    for (final entry in peer.files.entries) {
      byId.putIfAbsent(entry.key, () => []).add((peer.uid, entry.value));
    }
  }

  final result = <NetworkFile>[];

  for (final entry in byId.entries) {
    final announcements = entry.value;

    final size = _mostCommon(announcements.map((a) => a.$2.size));
    final agreeing = announcements.where((a) => a.$2.size == size).toList();
    final name = _mostCommon(agreeing.map((a) => a.$2.name));

    result.add(
      NetworkFile(
        id: entry.key,
        name: name,
        size: size,
        seederIds: agreeing.map((a) => a.$1).toList(growable: false),
      ),
    );
  }

  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

T _mostCommon<T>(Iterable<T> values) {
  final counts = <T, int>{};

  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }

  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
