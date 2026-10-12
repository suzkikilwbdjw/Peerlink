import 'package:firebase_auth/firebase_auth.dart';

/// Анонимный вход в Firebase. Его uid служит peerId в сети.
class AuthService {
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  /// Возвращает uid текущего пользователя, при необходимости создавая
  /// анонимного. Пока сессия сохраняется между запусками, uid остаётся
  /// прежним.
  Future<String> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing.uid;

    final credential = await _auth.signInAnonymously();
    final user = credential.user;

    if (user == null) {
      throw StateError('Анонимный вход не вернул пользователя');
    }

    return user.uid;
  }

  String? get currentUid => _auth.currentUser?.uid;
}
