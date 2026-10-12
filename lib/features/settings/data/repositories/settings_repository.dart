import 'package:shared_preferences/shared_preferences.dart';

/// Пользовательские настройки приложения (shared_preferences).
class SettingsRepository {
  static const String _autoSeedKey = 'settings_auto_seed_downloads';

  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  /// Автоматически раздавать скачанные (и проверенные) файлы.
  /// По умолчанию включено.
  bool get autoSeedDownloads => _prefs.getBool(_autoSeedKey) ?? true;

  Future<void> setAutoSeedDownloads(bool value) async {
    await _prefs.setBool(_autoSeedKey, value);
  }
}
