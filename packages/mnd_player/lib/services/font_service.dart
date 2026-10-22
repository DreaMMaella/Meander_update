import 'dart:io';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:flutter/services.dart';
import 'package:mnd_core/utils/quest_paths.dart';

class FontService {
  /// Инлайн-тег шрифта в markdown-тексте: `[font=res/fonts/xx.ttf]текст[/font]`.
  /// Путь может быть любым непустым (до первого `]`), включая `res/fonts/...`.
  static final RegExp inlineFontTag = RegExp(
    r'\[font=([^\]]+)\](.*?)\[\/font\]',
    dotAll: true,
  );

  /// Все пути шрифтов, упомянутые в инлайн-тегах [inlineFontTag] текста.
  static Iterable<String> extractInlineFontPaths(String text) sync* {
    for (final m in inlineFontTag.allMatches(text)) {
      final path = m.group(1)?.trim();
      if (path != null && path.isNotEmpty) yield path;
    }
  }

  /// Путь ресурса → детерминированное family-имя (или как есть, если путь
  /// не похож на ресурс, а уже является family-именем).
  static String? resolveFamily(String questId, String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.contains('/')) return familyNameFor(questId, value);
    return value;
  }

  /// Детерминированное family-имя шрифта ресурса. Синхронное и чистое — его
  /// можно использовать в рендере (GlassButton) без ожидания загрузки:
  /// family-имя совпадает с тем, что вернёт [loadQuestFont] после
  /// `FontLoader.load()`. [fileName] — имя файла (может быть полным путём
  /// ресурса, берётся basename).
  static String familyNameFor(String questId, String fileName) {
    final base = fileName.contains('/')
        ? fileName.substring(fileName.lastIndexOf('/') + 1)
        : fileName;
    final safeQuestId = questId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final safeFileName = base.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'Font_${safeQuestId}_$safeFileName';
  }

  /// Все пути шрифтов, разбросанные по сырому JSON квеста (нода, шаблон,
  /// конфиг): `fontFamily` на любой глубине — у кнопки, слоя стека, элемента
  /// модалки — плюс инлайн-теги `[font=…]` внутри текстов. Типизированный
  /// обход `ContentItem` этих полей не видит: часть доживает только в
  /// исходном JSON, а мастер шаблона лежит в `res/templates.json` вообще.
  static Set<String> collectFontRefsFromJson(dynamic json) {
    final found = <String>{};

    void add(String? raw) {
      final value = raw?.trim() ?? '';
      if (value.isNotEmpty && _looksLikeFontFile(value)) found.add(value);
    }

    void walk(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          walk(entry.value);
        }
        return;
      }
      if (value is List) {
        for (final entry in value) {
          walk(entry);
        }
        return;
      }
      if (value is! String) return;
      final text = value.trim();
      if (text.isEmpty) return;
      if (_looksLikeFontFile(text)) {
        found.add(text);
        return;
      }
      for (final path in inlineFontTag.allMatches(text)) {
        add(path.group(1));
      }
    }

    walk(json);
    return found;
  }

  static final RegExp _fontFileExtension = RegExp(
    r'\.(ttf|otf|woff2?)$',
    caseSensitive: false,
  );

  static bool _looksLikeFontFile(String value) =>
      _fontFileExtension.hasMatch(value);

  static Future<String?> loadQuestFont(String questId, String fileName) async {
    try {
      final base = fileName.contains('/')
          ? fileName.substring(fileName.lastIndexOf('/') + 1)
          : fileName;
      final fontPath = QuestPaths.resFont(questId, base);
      final fullPath = await FileStorage.getFilePath(fontPath);
      final file = File(fullPath);

      if (!await file.exists()) {
        print('⚠️ Шрифт не найден: $fullPath');
        return null;
      }

      final fontFamilyName = familyNameFor(questId, base);

      final loader = FontLoader(fontFamilyName);

      final fontData = file.readAsBytes().then((bytes) {
        return ByteData.view(bytes.buffer);
      });

      loader.addFont(fontData);
      await loader.load();

      return fontFamilyName;
    } catch (e) {
      if (!e.toString().contains('already loaded')) {
        print('Ошибка загрузки шрифта: $e');
      }
      return familyNameFor(questId, fileName);
    }
  }
}
