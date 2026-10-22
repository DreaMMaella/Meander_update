import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

/// Нонсы Sign in with Apple.
///
/// Отдельным файлом не для красоты: соответствие хеша тому, что считает
/// бэкенд, — единственное, что можно проверить без живого устройства
/// (test/features/auth/apple_nonce_test.dart гоняет эталон через node).
const _nonceAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

String generateAppleNonce({int length = 32}) {
  final random = Random.secure();
  return List.generate(
    length,
    (_) => _nonceAlphabet[random.nextInt(_nonceAlphabet.length)],
  ).join();
}

/// SHA-256 в base64url без паддинга — побайтово то же, что делает бэкенд своим
/// `crypto.createHash('sha256').digest('base64url')`. Паддинг и алфавит здесь
/// важны: любое расхождение = Apple-вход не проходит.
String hashAppleNonce(String rawNonce) {
  final digest = crypto.sha256.convert(utf8.encode(rawNonce));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}
