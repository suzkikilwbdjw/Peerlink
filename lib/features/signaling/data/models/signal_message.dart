import 'package:equatable/equatable.dart';

/// Типы сигнальных сообщений между пирами.
enum SignalType {
  /// SDP offer от инициатора соединения.
  offer,

  /// SDP answer от принимающей стороны.
  answer,

  /// Пачка ICE-кандидатов (trickle ICE, отправляются батчами).
  candidates,

  /// "Соединение закрыто": другая сторона может сразу освободить ресурсы.
  bye,
}

/// Одно сообщение из signals/{toUid}/inbox/{id}.
///
/// Писать в чужой inbox может любой вошедший пользователь, поэтому данные
/// считаются недоверенными: [tryParse] проверяет типы и размеры.
class SignalMessage extends Equatable {
  final String id;
  final String from;
  final SignalType type;

  /// Идентификатор попытки соединения. Сообщения от старых попыток
  /// (например, запоздавшие кандидаты) отбрасываются по несовпадению.
  final String sessionId;

  final Map<String, dynamic> payload;

  const SignalMessage({
    required this.id,
    required this.from,
    required this.type,
    required this.sessionId,
    required this.payload,
  });

  static SignalMessage? tryParse(String id, Map<String, dynamic>? data) {
    if (data == null) return null;

    final from = data['from'];
    final typeName = data['type'];
    final sessionId = data['sessionId'];
    final payload = data['payload'];

    if (from is! String || from.isEmpty || from.length > 128) return null;
    if (typeName is! String) return null;
    if (sessionId is! String || sessionId.isEmpty || sessionId.length > 64) {
      return null;
    }
    if (payload is! Map) return null;

    SignalType? type;
    for (final candidate in SignalType.values) {
      if (candidate.name == typeName) {
        type = candidate;
        break;
      }
    }
    if (type == null) return null;

    return SignalMessage(
      id: id,
      from: from,
      type: type,
      sessionId: sessionId,
      payload: Map<String, dynamic>.from(payload),
    );
  }

  @override
  List<Object?> get props => [id, from, type, sessionId, payload];
}
