import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Helper terpusat untuk simpan/baca/hapus token JWT.
///
/// Sebelumnya token disimpan pakai SharedPreferences, yang di Android
/// tersimpan sebagai file XML POLOS (tidak terenkripsi) -- bisa dibaca
/// langsung kalau device di-root. Sekarang pakai flutter_secure_storage,
/// yang di Android disimpan lewat Keystore (terenkripsi) dan di iOS lewat
/// Keychain.
///
/// Semua bagian aplikasi yang butuh baca/tulis/hapus token HARUS lewat
/// class ini, supaya konsisten -- jangan akses storage langsung dari
/// screen atau provider lain.
class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'token';
  static const _roleKey = 'role';

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  static Future<void> saveRole(String role) async {
    await _storage.write(key: _roleKey, value: role);
  }

  static Future<String?> getRole() async {
    return await _storage.read(key: _roleKey);
  }

  static Future<void> deleteRole() async {
    await _storage.delete(key: _roleKey);
  }
}
