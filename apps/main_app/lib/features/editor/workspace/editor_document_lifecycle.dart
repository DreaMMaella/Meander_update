import 'editor_document.dart';
import 'editor_workspace_controller.dart';
import 'editor_workspace_scope.dart';
import 'package:flutter/widgets.dart';

/// Захваченная ссылка на документ воркспейса.
///
/// Позволяет вызывать [markDirty]/[registerRuntime]/[unregisterRuntime]
/// БЕЗ lookup'ов по BuildContext.
///
/// Мотивация: таймеры автосейва, future-колбэки и dispose() переживают
/// деактивацию элемента; в этом окне обращение к предкам через context
/// запрещено фреймворком («Looking up a deactivated widget's ancestor is
/// unsafe»). Хэндл захватывается один раз в didChangeDependencies — там
/// элемент гарантированно активен — и дальше вызывает прямые ссылки на
/// колбэки scope.
class EditorDocumentHandle {
  final EditorDocumentId id;
  final void Function(EditorDocumentId id, bool dirty) _markDirty;
  final void Function(EditorDocumentId id, EditorDocumentRuntime runtime)
  _registerRuntime;
  final void Function(EditorDocumentId id) _unregisterRuntime;

  bool _valid = true;

  /// Тестовый и общий конструктор: продакшн-путь — [EditorDocumentLifecycle.capture].
  // ignore: avoid_unused_constructor_parameters
  EditorDocumentHandle({
    required this.id,
    required void Function(EditorDocumentId, bool) markDirty,
    required void Function(EditorDocumentId, EditorDocumentRuntime)
    registerRuntime,
    required void Function(EditorDocumentId) unregisterRuntime,
  }) : _markDirty = markDirty,
       _registerRuntime = registerRuntime,
       _unregisterRuntime = unregisterRuntime;

  /// Отвязать хэндл (вызывать при dispose документа или смене id).
  /// Последующие вызовы методов становятся no-op.
  // ignore: avoid_setters_without_getters
  set invalidated(bool value) => _valid = false;

  void markDirty(bool dirty) {
    if (!_valid) return;
    try {
      _markDirty(id, dirty);
    } catch (_) {
      // Воркспейс мог уже разобрать контроллер — молча игнорируем.
    }
  }

  void registerRuntime(EditorDocumentRuntime runtime) {
    if (!_valid) return;
    try {
      _registerRuntime(id, runtime);
    } catch (_) {}
  }

  void unregisterRuntime() {
    if (!_valid) return;
    try {
      _unregisterRuntime(id);
    } catch (_) {}
  }
}

class EditorDocumentLifecycle {
  const EditorDocumentLifecycle._();

  /// Захватить хэндл текущего документа. Возвращает null вне воркспейса
  /// (режим отдельного маршрута). Вызывать только из активного состояния:
  /// build/didChangeDependencies/пользовательские жесты.
  static EditorDocumentHandle? capture(BuildContext context) {
    final document = EditorDocumentContext.maybeOf(context);
    final workspace = EditorWorkspaceScope.maybeOf(context);
    if (document == null || workspace == null) return null;
    return EditorDocumentHandle(
      id: document.id,
      markDirty: workspace.markDirty,
      registerRuntime: workspace.registerRuntime,
      unregisterRuntime: workspace.unregisterRuntime,
    );
  }

  static void register(
    BuildContext context, {
    required EditorDocumentRuntime runtime,
  }) {
    final document = EditorDocumentContext.maybeOf(context);
    final workspace = EditorWorkspaceScope.maybeOf(context);
    if (document == null || workspace == null) return;
    workspace.registerRuntime(document.id, runtime);
  }

  static void unregister(BuildContext context) {
    final document = EditorDocumentContext.maybeOf(context);
    final workspace = EditorWorkspaceScope.maybeOf(context);
    if (document == null || workspace == null) return;
    workspace.unregisterRuntime(document.id);
  }

  static void markDirty(BuildContext context, bool dirty) {
    final document = EditorDocumentContext.maybeOf(context);
    final workspace = EditorWorkspaceScope.maybeOf(context);
    if (document == null || workspace == null) return;
    workspace.markDirty(document.id, dirty);
  }
}
