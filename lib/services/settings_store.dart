import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted connection settings.
///
/// The dashboard URL lives in SharedPreferences; the auth token lives in
/// the platform keychain/keystore via flutter_secure_storage, never in
/// plaintext prefs.
class ConnectionSettings {
  final String baseUrl;
  final String token;

  const ConnectionSettings({required this.baseUrl, required this.token});

  bool get isComplete => baseUrl.isNotEmpty && token.isNotEmpty;
}

class SettingsStore {
  static const _kBaseUrl = 'pantheon.base_url';
  static const _kToken = 'pantheon.token';

  final _secure = const FlutterSecureStorage();

  Future<ConnectionSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final token = await _secure.read(key: _kToken) ?? '';
    return ConnectionSettings(
      baseUrl: p.getString(_kBaseUrl) ?? '',
      token: token,
    );
  }

  Future<void> save(String baseUrl, String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBaseUrl, baseUrl.trim().replaceAll(RegExp(r'/$'), ''));
    await _secure.write(key: _kToken, value: token.trim());
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBaseUrl);
    await _secure.delete(key: _kToken);
  }
}
