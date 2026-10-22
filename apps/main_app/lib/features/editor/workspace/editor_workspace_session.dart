import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mnd_player/utils/quest_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_document.dart';
import 'package:mnd_core/utils/quest_paths.dart';

/// Хранилище сессии воркспейса: один набор вкладок на квест.
///
/// Ранее сессии были раздельные для режимов wide/narrow, и смена
/// ориентации окна (обычный ресайз на ПК) подменяла открытые вкладки
/// устаревшим набором другого режима — редактируемый документ исчезал
/// вместе с несохранённым буфером. Теперь набор вкладок один,
/// раскладка панелей адаптивна и от режима не зависит.
/// Сессия воркспейса живёт ВНУТРИ квеста (`quests/<id>/editor_session.json`)
/// — как файл проекта в Adobe/Blender: раскладка едет вместе с квестом при
/// копировании. В `.mnd`-экспорт не попадает (упаковка берёт только папки).
/// Разовое миграционное чтение legacy-ключей SharedPreferences.
class EditorWorkspaceSessionStore {
  const EditorWorkspaceSessionStore({QuestStore? store})
    : _storeOverride = store;

  final QuestStore? _storeOverride;

  static String sessionPath(String questId) =>
      QuestPaths.editorSession(questId);

  String _key(String questId) => 'editor_workspace_session:$questId';

  /// Legacy-ключи раздельных сессий (wide/narrow). Читаются один раз
  /// при миграции, больше не пишутся.
  String _legacyKey(String questId, String mode) =>
      'editor_workspace_session:$questId:$mode';

  Future<QuestStore> _store() => _storeOverride != null
      ? Future.value(_storeOverride)
      : QuestStore.defaultInstance();

  Future<void> save(String questId, EditorWorkspaceState state) async {
    // Инвариант на выходе: в файл не должны попадать дубликаты вкладок —
    // иначе следующая загрузка воспроизведёт их в дереве.
    final safe = state.sanitized();
    final payload = {
      'version': 2,
      'documents': safe.documents.map((document) => document.toJson()).toList(),
      if (safe.activeId != null) 'activeId': safe.activeId!.toJson(),
      'layout': safe.layout.toJson(),
    };
    try {
      await (await _store()).writeJson(sessionPath(questId), payload);
    } catch (e) {
      print('⚠️ [WorkspaceSession] save failed: $e');
    }
  }

  Future<EditorWorkspaceState?> load(String questId) async {
    try {
      final data = await (await _store()).readJson(sessionPath(questId));
      if (data != null) return _decodeJson(questId, data);
    } catch (_) {}

    // Миграция из SharedPreferences (старые ключи), один раз.
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_key(questId));
      raw ??= prefs.getString(_legacyKey(questId, 'wide'));
      if (raw == null || raw.isEmpty) return null;
      final state = _decode(questId, raw);
      if (state != null) {
        await save(questId, state);
      }
      await prefs.remove(_key(questId));
      await prefs.remove(_legacyKey(questId, 'wide'));
      await prefs.remove(_legacyKey(questId, 'narrow'));
      return state;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String questId) async {
    try {
      final store = await _store();
      await store.delete(sessionPath(questId));
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(questId));
      await prefs.remove(_legacyKey(questId, 'wide'));
      await prefs.remove(_legacyKey(questId, 'narrow'));
    } catch (_) {}
  }

  EditorWorkspaceState? _decode(String questId, String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return _decodeJson(questId, Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  EditorWorkspaceState? _decodeJson(String questId, Map<String, dynamic> json) {
    try {
      final documents =
          (json['documents'] is List
                  ? json['documents'] as List
                  : const <dynamic>[])
              .whereType<Map>()
              .map(
                (entry) => EditorDocumentDescriptor.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .where((document) => document.id.questId == questId)
              .toList();

      EditorDocumentId? activeId;
      final rawActive = json['activeId'];
      if (rawActive is Map) {
        final candidate = EditorDocumentId.fromJson(
          Map<String, dynamic>.from(rawActive),
        );
        if (documents.any((document) => document.id == candidate)) {
          activeId = candidate;
        }
      }

      final rawLayout = json['layout'];
      final layout = rawLayout is Map
          ? EditorDockLayout.fromJson(Map<String, dynamic>.from(rawLayout))
          : EditorDockLayout(
              rootTabs: documents.map((document) => document.id).toList(),
            );
      final validLayoutTabs = layout.rootTabs
          .where((id) => documents.any((document) => document.id == id))
          .toList();

      return EditorWorkspaceState(
        documents: List.unmodifiable(documents),
        activeId: activeId ?? (documents.isEmpty ? null : documents.first.id),
        // Дерево панелей валидируется в EditorWorkspaceController.restore
        // (листья без документа отбрасываются, активный док виден в панели).
        layout: EditorDockLayout(
          rootTabs: validLayoutTabs.isEmpty
              ? documents.map((document) => document.id).toList()
              : validLayoutTabs,
          paneTree: layout.paneTree,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Точка внедрения хранилища сессии для шелла. Тесты навигации подменяют
/// её in-memory реализацией: `QuestStore` кэширует корень приложения в
/// статике, и этот Future под fake-async отдаёт только первый тест.
final editorWorkspaceSessionStoreProvider =
    Provider<EditorWorkspaceSessionStore>(
      (ref) => const EditorWorkspaceSessionStore(),
    );
