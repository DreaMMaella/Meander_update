import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/core/utils/apple_nonce.dart';

/// Соответствие клиентского nonce-хеша тому, что считает бэкенд.
///
/// Это единственная часть Apple-входа, которую можно проверить без устройства:
/// живой sheet попросит Mac. Эталон берём у самого Node (`crypto` из backend),
/// поэтому тест падает, если Dart-хелпер отъедет от серверного — а такой
/// отъезд выглядит как «Неверный токен Apple» на каждом входе.
void main() {
  final nodeAvailable = Process.runSync('node', ['--version']).exitCode == 0;

  /// `digest('base64url')` из Node — ровно та строка, которую бэкенд сверяет
  /// с полем `nonce` identity токена.
  String nodeHash(String input) {
    final script =
        "process.stdout.write("
        "require('crypto').createHash('sha256')"
        ".update(process.argv[1], 'utf8').digest('base64url'))";
    final r = Process.runSync('node', ['-e', script, input]);
    expect(r.exitCode, 0, reason: 'node -e failed: ${r.stderr}');
    return r.stdout.toString();
  }

  group('hashAppleNonce', () {
    test('совпадает с эталоном Node (эталон бэкенда)', () {
      for (final raw in [
        'abcDEF123-._~',
        'meander-apple-nonce-0001',
        generateAppleNonce(),
      ]) {
        expect(hashAppleNonce(raw), nodeHash(raw), reason: 'nonce=$raw');
      }
    }, skip: !nodeAvailable);

    test('это base64url без паддинга, а не обычный base64', () {
      // Паддинг или символы '+'/'/' — и серверная сверка отваливается: Node
      // даёт base64url, а `==` он обрезает.
      final raw = generateAppleNonce(
        length: 33,
      ); // не кратен 3 → был бы паддинг
      final hash = hashAppleNonce(raw);
      expect(hash, isNot(contains('=')));
      expect(hash, isNot(contains('+')));
      expect(hash, isNot(contains('/')));
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(hash), isTrue);
      // SHA-256 = 32 байта = 43 знака в base64 без паддинга.
      expect(hash.length, 43);
    });
  });

  group('generateAppleNonce', () {
    test('длина и алфавит как у Apple-разрешённых символов', () {
      final nonce = generateAppleNonce();
      expect(nonce.length, 32);
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(nonce), isTrue);
    });

    test('два вызова дают разные значения', () {
      expect(generateAppleNonce(), isNot(generateAppleNonce()));
    });
  });
}
