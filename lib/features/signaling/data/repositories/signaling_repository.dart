import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:p2pchat/features/signaling/data/models/signal_message.dart';

/// Пачка новых сообщений из очередного снимка inbox.
class InboxUpdate {
  final List<SignalMessage> added;

  /// true для первого снимка с сервера: там лежит всё, что накопилось, пока
  /// мы были офлайн. Такие сообщения устарели, обрабатывать их не нужно.
  final bool isInitial;

  const InboxUpdate({required this.added, required this.isInitial});
}

/// Сигналинг на Firestore: signals/{toUid}/inbox/{autoId}.
///
/// Отправитель добавляет документ в inbox получателя, получатель слушает свой
/// inbox, обрабатывает сообщения и удаляет их.
class SignalingRepository {
  /// Через сколько неудалённое сообщение можно стереть (поле expireAt для
  /// TTL-политики Firestore на коллекционной группе "inbox").
  static const Duration messageLifetime = Duration(hours: 1);

  final FirebaseFirestore _db;

  SignalingRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _inbox(String uid) {
    return _db.collection('signals').doc(uid).collection('inbox');
  }

  /// Слушает свой inbox. Снимки из локального кэша пропускаются: для
  /// сигналинга нужен именно сервер, а по первому серверному снимку мы
  /// отличаем накопившийся хвост от свежих сообщений.
  Stream<InboxUpdate> watchInbox(String selfUid) async* {
    var first = true;

    await for (final snapshot in _inbox(
      selfUid,
    ).orderBy('createdAt').snapshots()) {
      if (snapshot.metadata.isFromCache) continue;

      final added = <SignalMessage>[];

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;

        final message = SignalMessage.tryParse(
          change.doc.id,
          change.doc.data(),
        );

        if (message == null) {
          change.doc.reference.delete().catchError((Object e) {
            debugPrint('[SIGNAL] Не удалось удалить битое сообщение: $e');
          });
          continue;
        }

        added.add(message);
      }

      yield InboxUpdate(added: added, isInitial: first);
      first = false;
    }
  }

  /// Кладёт сообщение в inbox получателя. Future завершается, когда сервер
  /// подтвердил запись (нужно, чтобы сообщения приходили в нужном порядке).
  Future<void> send({
    required String from,
    required String to,
    required SignalType type,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) {
    return _inbox(to).add({
      'from': from,
      'type': type.name,
      'sessionId': sessionId,
      'payload': payload,
      'createdAt': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromDate(DateTime.now().add(messageLifetime)),
    });
  }

  /// Удаляет обработанное сообщение. Ошибки не пробрасываются: сообщение
  /// в любом случае уже учтено, а остаток уберёт TTL.
  Future<void> consume(String selfUid, String messageId) async {
    try {
      await _inbox(selfUid).doc(messageId).delete();
    } catch (e) {
      debugPrint('[SIGNAL] Не удалось удалить сообщение $messageId: $e');
    }
  }
}
