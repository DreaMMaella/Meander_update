import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_languages.dart';
import 'dictionaries/en.dart';
import 'l10n.dart';
import 'language_pack.dart';

/// Хранилище импортированных языков: файлы `<код>.json` в отдельном каталоге
/// документов и их регистрация в `L10n`.
///
/// Файл языка — настройка пользователя, а не данные квеста: чистка квестов его
/// не касается, а перенос настроек на другое устройство забирает его с собой.
class CustomLanguageStore {
  CustomLanguageStore({Future<Directory> Function()? root})
    : _root = root ?? _documentsRoot;

  static const String dirName = 'languages';

  final Future<Directory> Function() _root;

  static Future<Directory> _documentsRoot() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, dirName));
  }

  /// Каталог языков, создаётся при первом обращении.
  Future<Directory> directory() async {
    final dir = await _root();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileOf(String code) async =>
      File(p.join((await directory()).path, '$code.json'));

  /// Зарегистрировать все лежащие языки, до первого кадра.
  ///
  /// Возвращает имена файлов, которые не читаются: на старте их не показывают,
  /// но без записи в лог молча исчезнувший язык неотличим от удалённого.
  Future<List<String>> loadAll() async {
    final broken = <String>[];
    final dir = await _root();
    if (!await dir.exists()) return broken;
    final builtin = supportedLanguages.map((language) => language.code).toSet();
    final loaded = <String>{};
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (builtin.contains(name)) continue;
      try {
        final pack = decodeLanguagePack(
          await _readText(entity),
          takenCodes: {...builtin, ...loaded},
        );
        L10n.register(pack.language);
        loaded.add(pack.language.code);
      } on Object catch (error) {
        broken.add(name);
        debugPrint('[l10n] языковой пакет $name.json не загружен: $error');
      }
    }
    return broken;
  }

  /// Импортировать текст пакета: проверить, сохранить копию в хранилище и
  /// зарегистрировать.
  ///
  /// Повторный импорт того же кода заменяет словарь на месте — так правят
  /// перевод, не плодя «немецкий-2».
  Future<LanguagePack> importText(String raw) async {
    final pack = decodeLanguagePack(
      raw,
      takenCodes: supportedLanguages.map((language) => language.code).toSet(),
    );
    await (await _fileOf(pack.language.code)).writeAsString(raw, flush: true);
    L10n.register(pack.language);
    return pack;
  }

  /// Удалить язык: файл и регистрацию. `false` — если язык не пользовательский
  /// (вшитый удалять нельзя) или его нет.
  Future<bool> remove(String code) async {
    if (!L10n.isCustom(code)) return false;
    final file = await _fileOf(code);
    if (await file.exists()) await file.delete();
    L10n.unregister(code);
    return true;
  }

  /// Шаблон со всеми строками интерфейса — его отдаёт кнопка «шаблон для
  /// перевода». Ключи берём из английского словаря: он покрывает весь
  /// интерфейс, а гард на мёртвые ключи не даёт ему отстать.
  String templateJson() => buildLanguageTemplate(
    stringKeys: enStrings.keys,
    pluralLemmas: enPlurals.keys,
  );

  /// Тот же шаблон байтами — `FilePicker.saveFile` просит именно байты.
  Uint8List templateBytes() => Uint8List.fromList(utf8.encode(templateJson()));

  Future<String> _readText(File file) async {
    if (await file.length() > kLanguagePackMaxBytes) {
      throw LanguagePackException(LanguagePackIssue.tooLarge);
    }
    return file.readAsString();
  }
}

final CustomLanguageStore customLanguageStore = CustomLanguageStore();
