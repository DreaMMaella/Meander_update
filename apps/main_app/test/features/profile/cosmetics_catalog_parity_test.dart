import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';

/// Бэкенд держит собственную копию каталога (id → слот и редкость) и по ней
/// проверяет выдачи и экипировку. Если клиент добавит предмет, а бэк — нет,
/// сервер начнёт отвечать «Неизвестное оформление» на ровно тот же экран,
/// который приложение показывает как доступный. Этот тест не даёт им разъехаться.
void main() {
  final tsFile = File.fromUri(
    // Тесты гоняются из корня пакета apps/main_app: два шага вверх — это репозиторий.
    Uri.directory(Directory.current.path).resolve(
      '../../backend/src/services/cosmetics.ts',
    ),
  );

  test('каталог на бэкенде совпадает с клиентским по id, слоту и редкости', () {
    if (!tsFile.existsSync()) {
      // Сборка клиента без соседней папки backend/ (CI только по apps/).
      markTestSkipped('нет исходника бэкенда рядом: ${tsFile.path}');
      return;
    }

    final rows = RegExp(
      r"\['([a-z0-9_]+)',\s*'([a-z_]+)',\s*'([a-z_]+)'\]",
    ).allMatches(tsFile.readAsStringSync()).toList();
    expect(rows, isNotEmpty, reason: 'не разобрал ROWS в косметике бэкенда');

    final backend = <String, (String, String)>{
      for (final m in rows)
        m.group(1)!: (m.group(2)!, m.group(3)!),
    };

    expect(
      backend.keys.toSet(),
      kCosmeticIds,
      reason: 'наборы id разъехались: ${_diff(backend.keys.toSet(), kCosmeticIds)}',
    );

    for (final def in kCosmeticIds.map((id) => cosmeticById(id)!)) {
      final (slot, tier) = backend[def.id]!;
      expect(slot, def.slot.wireName, reason: 'слот у ${def.id}');
      expect(tier, def.tier.wireName, reason: 'редкость у ${def.id}');
    }
  });
}

String _diff(Set<String> a, Set<String> b) =>
    'только на бэке: ${a.difference(b)}; только в клиенте: ${b.difference(a)}';
