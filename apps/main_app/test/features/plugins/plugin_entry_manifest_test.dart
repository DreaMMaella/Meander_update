// Экран «Плагины» читает из манифеста только то, что показывает в списке, —
// права, хуки и лимиты проверяет ядро при установке. Здесь проверяется именно
// этот разбор: чтобы карточка установки не врала про id и версию.

import 'dart:io';

import 'package:canvas_app/features/plugins/models/plugin_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PluginEntry parse(String manifestJson) => PluginEntry.fromManifestJson(
    manifestJson: manifestJson,
    fallbackId: 'local.fallback',
    fallbackName: 'fallback',
    localPath: '/tmp/pkg',
  );

  test('манифест нового формата даёт полную карточку установки', () {
    final entry = parse('''
    {
      "id": "mnd.examples.shop",
      "name": "Лавка",
      "version": "1.0.0",
      "sdk": "1",
      "entry": "main.lua",
      "description": "Полноэкранный интерфейс лавки",
      "author": "Meander",
      "icon": "payments",
      "tags": ["экономика", "магазин"],
      "permissions": ["ui", "quest", "storage", "audio"],
      "hooks": ["quest_start", "node_enter"],
      "slots": [{ "id": "chip", "area": "drawer", "priority": 10 }]
    }
    ''');

    expect(entry.id, 'mnd.examples.shop');
    expect(entry.name, 'Лавка');
    expect(entry.version, '1.0.0');
    expect(entry.description, 'Полноэкранный интерфейс лавки');
    expect(entry.author, 'Meander');
    expect(entry.icon, 'payments');
    expect(entry.tags, ['экономика', 'магазин']);
    expect(entry.localPath, '/tmp/pkg');
    expect(entry.enabled, isTrue, reason: 'импортированный плагин включается сам');
  });

  test('незаполненные поля не ломают разбор и не превращаются в пустые строки', () {
    final entry = parse('''
    {
      "id": "com.author.minimal",
      "name": "Минимум",
      "version": "0.1.0",
      "sdk": "1",
      "entry": "main.lua",
      "description": "   ",
      "tags": []
    }
    ''');

    expect(entry.id, 'com.author.minimal');
    expect(entry.description, isNull);
    expect(entry.author, isNull);
    expect(entry.icon, isNull);
    expect(entry.tags, isEmpty);
  });

  test('манифест без имени остаётся на резервных значениях импорта', () {
    final entry = parse('{"id": "com.author.noname", "version": "1"}');
    expect(entry.id, 'com.author.noname');
    expect(entry.name, isNotEmpty);
  });

  test('каждый эталонный плагин читается клиентом', () {
    final examples = Directory('../../plugins/examples');
    if (!examples.existsSync()) return; // пакета нет (CI без репозитория целиком)
    for (final dir in examples.listSync().whereType<Directory>()) {
      final manifest = File('${dir.path}/plugin.json');
      if (!manifest.existsSync()) continue;
      final entry = parse(manifest.readAsStringSync());
      expect(
        entry.id,
        isNotEmpty,
        reason: '${dir.path}: карточка установки без id не имеет смысла',
      );
      expect(entry.name, isNotEmpty, reason: entry.id);
      expect(entry.version, isNotEmpty, reason: entry.id);
    }
  });
}
