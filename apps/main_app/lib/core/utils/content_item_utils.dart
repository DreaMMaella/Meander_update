import 'package:canvas_app/models/content_item_model.dart';
import 'package:uuid/uuid.dart';

class ContentItemUtils {
  static const _uuid = Uuid();

  /// Создает полную копию элемента с новыми ID для него и всех вложенных детей.
  ///
  /// Правила для шаблонов:
  /// * **Мастер-элемент** при копировании теряет связь с шаблоном и
  ///   становится обычным snapshot'ом — иначе получим два мастера одного
  ///   шаблона, что нарушит инвариант «один шаблон ↔ один мастер».
  /// * **Linked-инстанс** копируется как linked (другой id, та же ссылка).
  static ContentItem duplicate(ContentItem original) {
    // Рекурсивно копируем детей, если они есть (для Row/Column)
    List<ContentItem>? newChildren;
    if (original.children != null) {
      newChildren = original.children!
          .map((child) => duplicate(child))
          .toList();
    }

    // Если копируемый item — мастер шаблона, отвязываем копию,
    // чтобы не плодить дубликаты мастеров.
    if (original.isTemplateMasterItem) {
      return original.copyWith(
        id: _uuid.v4(),
        children: newChildren,
        clearTemplateLink: true,
      );
    }

    return original.copyWith(
      id: _uuid.v4(),
      children: newChildren,
      // Linked-инстанс остаётся linked. Прочие поля остаются как есть.
    );
  }
}
