import 'package:flutter/material.dart';
import 'package:mnd_core/models/content_item.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Нода в том виде, в каком она нужна пикеру: заголовок и уже распарсенные
/// айтемы. Нужна только чтобы чистые правила пикера можно было тестировать без
/// провайдера нод и файлового слоя.
class PickerNode {
  final String id;
  final String title;
  final List<ContentItem> items;

  const PickerNode({
    required this.id,
    required this.title,
    this.items = const [],
  });
}

/// Один вариант выбора: айтем плюс всё, чем он подписан в списке.
///
/// Подпись и хлебные крошки считаются один раз при сборке — экран фильтрует
/// тысячи айтемов на каждый символ поиска и пересчитывать их в `build` было бы
/// заметно.
class ContentItemChoice {
  final ContentItem item;
  final String nodeId;
  final String nodeTitle;

  /// Где лежит внутри ноды: `Стек › Ряд`. Пусто у корневых айтемов.
  final List<String> trail;
  final String label;
  final String typeLabel;

  /// Источник, из которого пикер рисует миниатюру (для картинок).
  final String? thumbnailSource;
  final bool hasFormula;
  final bool isHidden;

  const ContentItemChoice({
    required this.item,
    required this.nodeId,
    required this.nodeTitle,
    required this.label,
    required this.typeLabel,
    this.trail = const [],
    this.thumbnailSource,
    this.hasFormula = false,
    this.isHidden = false,
  });

  /// `Новая нода › Стек` — одна строка подписи там, где карточка не двухстрочная.
  String get location {
    if (trail.isEmpty) return nodeTitle;
    return '$nodeTitle › ${trail.join(' › ')}';
  }

  /// Всё, что ловит поиск: имя, нода, где лежит, тип и сам источник.
  String get searchText {
    final parts = [label, nodeTitle, ...trail, typeLabel];
    final source = item.resourceExpr ?? item.resourcePath;
    if (source != null) parts.add(source);
    // Ё в поиске — норма для русской раскладки, отличать его от Е бессмысленно.
    return parts.join(' ').toLowerCase().replaceAll('ё', 'е');
  }
}

/// Русская подпись типа айтема — она же заголовок группы в фильтре типов.
String contentItemTypeLabel(String type) => switch (type) {
  'image' => tr('Картинка'),
  'text' => tr('Текст'),
  'button' => tr('Кнопка'),
  'audio' => tr('Аудио'),
  'video' => tr('Видео'),
  'script' => tr('Скрипт'),
  'row' => tr('Ряд'),
  'stack' => tr('Стек'),
  'container' => tr('Контейнер'),
  'modal' => tr('Окно'),
  'timer' => tr('Таймер'),
  'delay' => tr('Задержка'),
  'variable' => tr('Переменная'),
  'plugin' => tr('Плагин'),
  _ => tr('Элемент'),
};

/// Иконка типа для чипов и заглушек миниатюр.
IconData contentItemTypeIcon(String type) => switch (type) {
  'image' => Icons.image_rounded,
  'text' => Icons.text_snippet_rounded,
  'button' => Icons.smart_button_rounded,
  'audio' => Icons.audiotrack_rounded,
  'video' => Icons.movie_rounded,
  'script' => Icons.code_rounded,
  'row' => Icons.view_agenda_rounded,
  'stack' => Icons.layers_rounded,
  'container' => Icons.grid_view_rounded,
  'modal' => Icons.crop_square_rounded,
  'timer' => Icons.timer_outlined,
  'delay' => Icons.hourglass_empty_rounded,
  'variable' => Icons.functions_rounded,
  'plugin' => Icons.extension_rounded,
  _ => Icons.category_outlined,
};

/// Собирает все айтемы квеста с подписями.
///
/// Обход идёт вместе с вложенностью (ряды, слои стека, контейнеры): картинка,
/// спрятанная в третьем ряду, — всё равно законная цель для `set_image`, и
/// прятать её от автора значит загнать его в ручной поиск по JSON.
List<ContentItemChoice> buildContentItemChoices({
  required List<PickerNode> nodes,
  List<String>? allowedTypes,
  Map<String, String> resourceNames = const {},
}) {
  final choices = <ContentItemChoice>[];
  for (final node in nodes) {
    _collect(node.items, node, const [], allowedTypes, resourceNames, choices);
  }
  return choices;
}

void _collect(
  List<ContentItem> items,
  PickerNode node,
  List<String> trail,
  List<String>? allowedTypes,
  Map<String, String> names,
  List<ContentItemChoice> out,
) {
  // Номер — только когда рядом несколько однотипных: «Ряд 2» отличим от
  // «Ряд 3», а «Стек 1» в единственном стеке — просто шум.
  final totals = <String, int>{};
  for (final item in items) {
    totals[item.type] = (totals[item.type] ?? 0) + 1;
  }
  final counters = <String, int>{};
  for (final item in items) {
    final index = counters.update(item.type, (n) => n + 1, ifAbsent: () => 1);
    if (allowedTypes == null || allowedTypes.contains(item.type)) {
      out.add(_choice(item, node, trail, names));
    }
    final children = item.children;
    if (children == null || children.isEmpty) continue;
    _collect(
      children,
      node,
      [...trail, _crumb(item, index, totals[item.type] ?? 1)],
      allowedTypes,
      names,
      out,
    );
  }
}

/// Подпись родителя для хлебных крошек: именованный слой — по имени, безымянный
/// — по типу и порядку.
String _crumb(ContentItem item, int index, int total) {
  final name = item.layerName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final typeLabel = contentItemTypeLabel(item.type);
  return total > 1 ? '$typeLabel $index' : typeLabel;
}

ContentItemChoice _choice(
  ContentItem item,
  PickerNode node,
  List<String> trail,
  Map<String, String> names,
) {
  final source = item.resourceExpr ?? item.resourcePath;
  final typeLabel = contentItemTypeLabel(item.type);
  return ContentItemChoice(
    item: item,
    nodeId: node.id,
    nodeTitle: node.title,
    trail: trail,
    typeLabel: typeLabel,
    label: _label(item, source, names, typeLabel),
    // Формула резолвится только в игре и с состоянием — в пикере её показать
    // картинкой нельзя, остаётся иконка типа и бейдж формулы.
    thumbnailSource: item.type == 'image' && !item.hasResourceExpr
        ? source
        : null,
    hasFormula: item.hasResourceExpr,
    isHidden: item.isHidden,
  );
}

/// Человекочитаемое имя айтема. У картинок имени в модели нет — поэтому берём
/// имя из библиотеки, а уже его производное от файла.
String _label(
  ContentItem item,
  String? source,
  Map<String, String> names,
  String typeLabel,
) {
  final text = item.text?.trim();
  if (text != null && text.isNotEmpty) {
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }
  final layer = item.layerName?.trim();
  if (layer != null && layer.isNotEmpty) return layer;
  if (source == null || source.isEmpty)
    return trf('{p0} без источника', {'p0': typeLabel});
  // Формулу показываем как есть: `res/{level}.png` — это задумка автора, а не
  // имя файла, и сокращать её до `{level}` значит лишить подпись смысла.
  if (item.hasResourceExpr) {
    return source.length > 60 ? '${source.substring(0, 60)}…' : source;
  }
  return resourceNameLabel(source, names);
}

/// Имя ресурса из библиотеки по пути (или по голому имени), иначе файл без
/// расширения. Совпадает с тем, что показывает редактор контента.
String resourceNameLabel(String source, Map<String, String> names) {
  final file = source.split('/').last;
  return names[file] ??
      (file.contains('.') ? file.substring(0, file.lastIndexOf('.')) : file);
}

/// `res/metadata.json` → `имя файла → имя автора`. Ключ-папки (`__folders__`)
/// не ресурсы, их отбрасываем.
Map<String, String> parseResourceNames(Map<String, dynamic> metadata) {
  final names = <String, String>{};
  metadata.forEach((key, value) {
    if (key.startsWith('__')) return;
    if (value is String) {
      if (value.trim().isNotEmpty) names[key] = value.trim();
      return;
    }
    if (value is Map) {
      final name = value['name']?.toString().trim();
      if (name != null && name.isNotEmpty) names[key] = name;
    }
  });
  return names;
}

/// Акцент типа — чтобы картинка, аудио и скрипт различались боковым зрением.
Color contentItemTypeColor(String type) => switch (type) {
  'image' => const Color(0xFF42A5F5),
  'video' => const Color(0xFF7E57C2),
  'audio' => const Color(0xFFFFA726),
  'text' => const Color(0xFF66BB6A),
  'button' => const Color(0xFFEC407A),
  'script' => const Color(0xFF26C6DA),
  _ => const Color(0xFF9E9E9E),
};

/// Ноды, в которых есть подходящие айтемы, с числом айтемов — по ним строится
/// фильтр области.
List<({String id, String title, int count})> groupByNode(
  List<ContentItemChoice> choices,
) {
  final counts = <String, int>{};
  final titles = <String, String>{};
  for (final choice in choices) {
    counts[choice.nodeId] = (counts[choice.nodeId] ?? 0) + 1;
    titles[choice.nodeId] = choice.nodeTitle;
  }
  return [
    for (final id in counts.keys)
      (id: id, title: titles[id] ?? '', count: counts[id]!),
  ];
}

/// То же для типов: `image` → сколько картинок в выборке.
Map<String, int> countByType(List<ContentItemChoice> choices) {
  final counts = <String, int>{};
  for (final choice in choices) {
    counts[choice.item.type] = (counts[choice.item.type] ?? 0) + 1;
  }
  return counts;
}

/// Поиск по всем словам сразу: «одинокая дерево» finds «Одинокое дерево».
///
/// Порядок слов не важен, регистр и Ё/Е — нет. Пустая строка — всё.
List<ContentItemChoice> searchContentItemChoices(
  List<ContentItemChoice> choices,
  String query,
) {
  final tokens =
      query.trim().toLowerCase().replaceAll('ё', 'е').split(RegExp(r'\s+'))
        ..removeWhere((t) => t.isEmpty);
  if (tokens.isEmpty) return choices;
  return choices
      .where((choice) {
        final haystack = choice.searchText;
        return tokens.every(haystack.contains);
      })
      .toList(growable: false);
}
