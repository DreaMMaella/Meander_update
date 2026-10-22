/// Текст markdown-сообщения для мест, где markdown не верстается: строка
/// обсуждения, список, уведомление.
///
/// Пост written в markdown, но показать его надо одной-двумя строками обычного
/// текста. Без этого человек читает `![Фото](https://…/4a83….jpg)` — то есть
/// служебный синтаксис вместо сообщения. Картинки здесь не теряются: их адрес
/// отдаёт `markdownImageUrls`, и список рисует из него миниатюру.
library;

final RegExp _image = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)');
final RegExp _link = RegExp(r'(?<!!)\[([^\]]*)\]\(([^)\s]+)\)');

/// Все адреса картинок из тела — и в markdown, и голыми ссылками.
List<String> markdownImageUrls(String body) {
  if (body.isEmpty) return const [];
  return [
    for (final match in _image.allMatches(body))
      if (match.group(2)?.trim().isNotEmpty ?? false) match.group(2)!.trim(),
  ];
}

/// Markdown → сплошной текст для превью.
String markdownPlainText(String body) {
  if (body.isEmpty) return '';
  var out = body.replaceAll(_image, ' ');
  out = out.replaceAllMapped(_link, (match) {
    final label = match.group(1)?.trim() ?? '';
    return label.isEmpty ? (match.group(2) ?? '') : label;
  });
  out = out
      // Маркеры строк: заголовки, цитаты, списки.
      .replaceAll(RegExp(r'^\s{0,3}(?:#{1,6}|>+)\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      // Выделение и моноширинный текст: символы служебные, слово остаётся.
      .replaceAll(RegExp(r'[*_]{1,3}'), '')
      .replaceAll('`', '')
      .replaceAll(RegExp(r'\s*\n\s*'), ' ')
      .trim();
  return out;
}
