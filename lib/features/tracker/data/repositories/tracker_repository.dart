import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:p2pchat/features/seeding/data/models/seed_file.dart';
import 'package:p2pchat/features/tracker/data/models/peer_announcement.dart';

/// "Трекер" на Firestore.
///
/// Схема данных: один документ на пира, peers/{uid}:
///   lastSeen  — серверное время последнего heartbeat;
///   expireAt  — когда документ можно удалить (для TTL-политики Firestore);
///   files     — `{ "<sha256>": { name, size } }`.
///
/// Один документ на пира (а не по документу на каждый файл) нужен, чтобы
/// heartbeat стоил одну запись независимо от числа раздаваемых файлов.
class TrackerRepository {
  /// Больше файлов в один документ не кладём (лимит документа — 1 МБ).
  static const int maxFilesPerPeer = 2000;

  /// Через сколько после последней активности документ можно удалять.
  static const Duration docLifetime = Duration(days: 1);

  /// Грубая граница запроса: старее документы вообще не скачиваем.
  /// Точная проверка "онлайн ли пир" делается на клиенте по TTL.
  static const Duration discoveryWindow = Duration(hours: 1);

  final FirebaseFirestore _db;

  TrackerRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _peers =>
      _db.collection('peers');

  Timestamp _expireAt() => Timestamp.fromDate(DateTime.now().add(docLifetime));

  /// Полностью заменяет анонс пира (список файлов + lastSeen).
  Future<void> publish(String uid, List<SeedFile> files) {
    final limited = files.take(maxFilesPerPeer);

    return _peers.doc(uid).set({
      'lastSeen': FieldValue.serverTimestamp(),
      'expireAt': _expireAt(),
      'files': {
        for (final f in limited) f.id: {'name': f.name, 'size': f.size},
      },
    });
  }

  /// Обновляет только "я онлайн". Если документа нет, бросает
  /// FirebaseException с кодом not-found.
  Future<void> heartbeat(String uid) {
    return _peers.doc(uid).update({
      'lastSeen': FieldValue.serverTimestamp(),
      'expireAt': _expireAt(),
    });
  }

  /// Убирает пира из сети (раздавать больше нечего или приложение закрыто).
  Future<void> withdraw(String uid) => _peers.doc(uid).delete();

  /// Разовый запрос анонсов (без подписки). Нужен, чтобы найти раздающих
  /// конкретного файла при возобновлении загрузки.
  Future<List<PeerAnnouncement>> fetchPeers() async {
    final since = Timestamp.fromDate(DateTime.now().subtract(discoveryWindow));
    final snapshot = await _peers.where('lastSeen', isGreaterThan: since).get();

    return snapshot.docs
        .map((doc) => PeerAnnouncement.tryParse(doc.id, doc.data()))
        .whereType<PeerAnnouncement>()
        .toList(growable: false);
  }

  /// Живой поток анонсов недавно активных пиров.
  ///
  /// Каждый heartbeat любого пира приходит подписчикам как изменение
  /// документа и тратит чтения, поэтому подписывайтесь только пока
  /// открыта вкладка со списком файлов.
  Stream<List<PeerAnnouncement>> watchPeers() {
    final since = Timestamp.fromDate(DateTime.now().subtract(discoveryWindow));

    return _peers
        .where('lastSeen', isGreaterThan: since)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PeerAnnouncement.tryParse(doc.id, doc.data()))
              .whereType<PeerAnnouncement>()
              .toList(growable: false),
        );
  }
}
