import 'dart:typed_data';

import 'package:canvas_app/core/services/template_asset_installer.dart';
import 'package:canvas_app/core/services/template_bundler.dart';
import 'package:mnd_player/services/template_instance_resolver.dart';
import 'package:canvas_app/core/services/template_repository.dart';
import 'package:canvas_app/models/template_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Singleton-репозиторий шаблонов.
final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository();
});

/// Глобальные шаблоны (общие для всех квестов).
final globalTemplatesProvider = FutureProvider.autoDispose<List<TemplateItem>>((
  ref,
) async {
  final repo = ref.watch(templateRepositoryProvider);
  return repo.loadGlobal();
});

/// Шаблоны конкретного квеста.
final questTemplatesProvider = FutureProvider.autoDispose
    .family<List<TemplateItem>, String>((ref, questId) async {
      final repo = ref.watch(templateRepositoryProvider);
      return repo.loadForQuest(questId);
    });

/// Параметры для combined-провайдера.
class TemplateScopeFilter {
  final String? questId;

  /// Если задан — оставляем только эти типы.
  final Set<TemplateKind>? kinds;

  /// Поисковая подстрока (по имени, описанию, категории).
  final String search;

  const TemplateScopeFilter({this.questId, this.kinds, this.search = ''});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TemplateScopeFilter &&
        other.questId == questId &&
        _setEq(other.kinds, kinds) &&
        other.search == search;
  }

  static bool _setEq(Set? a, Set? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  int get hashCode =>
      Object.hash(questId, kinds == null ? 0 : Object.hashAll(kinds!), search);
}

/// Объединённый список (квест-локальные + глобальные) с фильтрацией.
final combinedTemplatesProvider = FutureProvider.autoDispose
    .family<List<TemplateItem>, TemplateScopeFilter>((ref, filter) async {
      // ignore: unused_local_variable
      // подписываемся на репозиторий неявно, через дочерние провайдеры
      List<TemplateItem> result;
      if (filter.questId != null) {
        // Подписываемся на оба под-провайдера, чтобы инвалидация работала.
        final quest = await ref.watch(
          questTemplatesProvider(filter.questId!).future,
        );
        final global = await ref.watch(globalTemplatesProvider.future);
        result = [...quest, ...global];
      } else {
        result = await ref.watch(globalTemplatesProvider.future);
      }

      // Фильтруем
      final kinds = filter.kinds;
      final q = filter.search.trim().toLowerCase();
      return result.where((t) {
        if (kinds != null && !kinds.contains(t.kind)) return false;
        if (q.isEmpty) return true;
        final hay = '${t.name} ${t.description ?? ''} ${t.category ?? ''}'
            .toLowerCase();
        return hay.contains(q);
      }).toList();
    });

/// Удобные действия. Используются из UI: после действия инвалидируют
/// связанные провайдеры, чтобы списки обновились.
class TemplateActions {
  final Ref _ref;
  TemplateActions(this._ref);

  TemplateRepository get _repo => _ref.read(templateRepositoryProvider);

  /// [sourceQuestId] — квест, из которого шаблон создаётся. Если у шаблона
  /// ещё нет упакованных файлов, они вытягиваются из этого квеста в
  /// глобальный кеш: без этого в другом квесте картинка или шрифт не
  /// найдутся (текст нарисуется дефолтным шрифтом).
  Future<void> saveAsGlobal(
    TemplateItem template, {
    Map<String, Uint8List>? bytesBySha,
    String? sourceQuestId,
  }) async {
    var toSave = template;
    if (bytesBySha == null &&
        template.assets.isEmpty &&
        sourceQuestId != null) {
      final collected = await TemplateBundler.collectAssetsForTemplate(
        template: template,
        questId: sourceQuestId,
      );
      toSave = collected.template;
      bytesBySha = collected.bytesBySha;
    }
    await _repo.upsertGlobal(toSave, bytesBySha: bytesBySha);
    _ref.invalidate(globalTemplatesProvider);
  }

  Future<void> saveToQuest(String questId, TemplateItem template) async {
    await _repo.upsertToQuest(questId, template);
    _ref.invalidate(questTemplatesProvider(questId));
  }

  Future<bool> delete(
    TemplateItem template, {
    required TemplateScope scope,
    String? questId,
  }) async {
    bool ok;
    if (scope == TemplateScope.global) {
      ok = await _repo.deleteGlobal(template.id);
      _ref.invalidate(globalTemplatesProvider);
    } else {
      if (questId == null) {
        throw ArgumentError('questId is required for quest scope');
      }
      ok = await _repo.deleteFromQuest(questId, template.id);
      _ref.invalidate(questTemplatesProvider(questId));
    }
    return ok;
  }

  Future<void> rename(
    TemplateItem template, {
    required String newName,
    required TemplateScope scope,
    String? questId,
  }) async {
    final updated = template.copyWith(name: newName);
    if (scope == TemplateScope.global) {
      await saveAsGlobal(updated);
    } else {
      if (questId == null) {
        throw ArgumentError('questId is required for quest scope');
      }
      await saveToQuest(questId, updated);
    }
  }

  Future<void> move({
    required TemplateItem template,
    required TemplateScope from,
    required TemplateScope to,
    String? questId,
  }) async {
    await _repo.moveScope(
      template: template,
      from: from,
      to: to,
      questId: questId,
    );
    _ref.invalidate(globalTemplatesProvider);
    if (questId != null) {
      _ref.invalidate(questTemplatesProvider(questId));
    }
  }

  Future<String?> exportToFile(
    TemplateItem template, {
    String? questId,
    bool includeAssets = true,
  }) => _repo.exportToFile(
    template,
    questId: questId,
    includeAssets: includeAssets,
  );

  Future<TemplateImportResult?> importFromFile() => _repo.importFromFile();

  /// «Пиннинг» (закрепление) глобального шаблона в конкретном квесте.
  ///
  /// Linked-инстансы внутри квеста должны ссылаться на мастер, который
  /// едет вместе с квестом — иначе экспорт/синхронизация сломаются.
  /// Этот метод копирует мастер (с тем же id и contentVersion) в
  /// `quests/<id>/res/templates.json` и устанавливает связанные ассеты в
  /// `quests/<id>/...` (если payload ссылается на ресурсы, которых ещё
  /// нет в квесте).
  ///
  /// Идемпотентно: если в квесте уже есть мастер с этим id и таким же
  /// payload — никаких изменений не происходит (contentVersion не растёт).
  ///
  /// Возвращает шаблон, который реально сохранён в квесте (с возможно
  /// обновлёнными путями к ассетам после ремапа при коллизиях имён).
  Future<TemplateItem> pinToQuest(TemplateItem template, String questId) async {
    // 1. Если уже есть в квесте — проверим, идентичен ли payload.
    final existingList = await _repo.loadForQuest(questId);
    final existing = existingList.where((t) => t.id == template.id).toList();
    if (existing.isNotEmpty) {
      // Просто перезапишем, _upsert сравнит payload и решит, инкрементировать
      // ли версию. Сохраняем тот же contentVersion и assets как у мастера.
      await _repo.upsertToQuest(questId, template);
      _ref.invalidate(questTemplatesProvider(questId));
      return template;
    }

    // 2. Новый шаблон в квесте — нужно скопировать ассеты (если есть)
    //    в `quests/<id>/...`. installToQuest читает их из глобального
    //    хранилища `app/templates/assets/<storageFileName>`.
    final installed = await TemplateAssetInstaller.installToQuest(
      template: template,
      questId: questId,
    );

    // 3. Сохраняем как новый шаблон квеста (с тем же id и contentVersion).
    await _repo.upsertToQuest(questId, installed.template);
    _ref.invalidate(questTemplatesProvider(questId));
    return installed.template;
  }
}

final templateActionsProvider = Provider<TemplateActions>((ref) {
  return TemplateActions(ref);
});

// ============================================================
//  Linked-templates (v2): резолвер инстансов
// ============================================================

/// Индекс мастер-шаблонов по id для указанного scope (`questId == null` —
/// только глобальные; иначе — квест-локальные + глобальные).
///
/// Этот провайдер автоматически инвалидируется при изменении любого
/// связанного `TemplateItem` (через `globalTemplatesProvider` /
/// `questTemplatesProvider`), что заставляет [templateInstanceResolverProvider]
/// перевыдать новый резолвер — и все `ConsumerWidget`-подписчики получают
/// актуальный контент инстансов.
final templatesByIdProvider = FutureProvider.autoDispose
    .family<Map<String, TemplateItem>, String?>((ref, questId) async {
      final List<TemplateItem> list;
      if (questId == null) {
        list = await ref.watch(globalTemplatesProvider.future);
      } else {
        final quest = await ref.watch(questTemplatesProvider(questId).future);
        final global = await ref.watch(globalTemplatesProvider.future);
        // Квест-локальные побеждают одноимённые глобальные.
        final map = <String, TemplateItem>{};
        for (final t in global) {
          map[t.id] = t;
        }
        for (final t in quest) {
          map[t.id] = t;
        }
        return map;
      }
      return {for (final t in list) t.id: t};
    });

/// Текущий резолвер для (опц.) квеста. Перевыдаётся при любом изменении
/// мастеров (т.к. построен на [templatesByIdProvider]).
///
/// Использование:
/// ```dart
/// final resolver = ref.watch(templateInstanceResolverProvider(questId)).valueOrNull;
/// if (resolver != null) {
///   final realItem = resolver.resolveTree(item);
/// }
/// ```
final templateInstanceResolverProvider = FutureProvider.autoDispose
    .family<TemplateInstanceResolver, String?>((ref, questId) async {
      final byId = await ref.watch(templatesByIdProvider(questId).future);
      return TemplateInstanceResolver(templatesById: byId);
    });
