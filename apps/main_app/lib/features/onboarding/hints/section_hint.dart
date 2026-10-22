import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Мини-подсказки в разделах: одна короткая плашка на экране, которую человек
/// закрывает сам и которая больше не возвращается.
///
/// Интерактивный тур по созданию квеста сейчас выключен (он сырой, точка
/// входа в «Настройках» скрыта), поэтому единственное обучение, которое
/// новичок реально видит, — «Академия» в настройках, то есть ссылка на
/// сторонние видео. Здесь — почва для второго канала: объяснение на месте,
/// ровно там, где человек о нём спотыкается, без запуска тура на полэкрана.
class SectionHints {
  SectionHints._();

  /// «Мои квесты», библиотека пуста — первый экран нового человека.
  static const libraryEmpty = 'library_empty';

  /// Хаб — непонятно, что это за раздел и зачем скачивать «пресеты».
  static const hub = 'hub';

  /// Геттер, а не `static final`: текст подсказки берётся под текущий язык.
  static Map<String, String> get texts => {
    libraryEmpty:
        tr('Пока здесь пусто. Создайте квест кнопкой «Создать квест» — или добавьте уже готовый файл через «Импорт» в карточке выше.'),
    hub:
        tr('Хаб — это готовые стройматериалы: фоны, музыка, звуки, шрифты и пресеты кнопок. Скачанное попадает в «Мою библиотеку», откуда его видно в редакторе квеста.'),
  };
}

/// «Показано один раз» живит в SharedPreferences: список закрытых подсказок.
class SectionHintService {
  SectionHintService._();

  static const dismissedKey = 'section_hints_dismissed';

  static Future<bool> isDismissed(String hintId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(dismissedKey)?.contains(hintId) ?? false;
  }

  static Future<void> dismiss(String hintId) async {
    final prefs = await SharedPreferences.getInstance();
    final closed = List<String>.from(prefs.getStringList(dismissedKey) ?? []);
    if (closed.contains(hintId)) return;
    closed.add(hintId);
    await prefs.setStringList(dismissedKey, closed);
  }

  /// Сброс — для отладки и для «показать обучение заново» в настройках.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(dismissedKey);
  }
}

/// Плашка-напоминалка над содержимым раздела. Пока не известно, закрыта ли
/// она, места не занимаем вовсе: иначе при каждом входе в раздел текст
/// мигает на кадр.
class SectionHintBanner extends StatefulWidget {
  final String hintId;

  const SectionHintBanner({super.key, required this.hintId});

  @override
  State<SectionHintBanner> createState() => _SectionHintBannerState();
}

class _SectionHintBannerState extends State<SectionHintBanner> {
  bool _closed = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dismissed = await SectionHintService.isDismissed(widget.hintId);
    if (!mounted) return;
    setState(() => _closed = dismissed);
  }

  Future<void> _close() async {
    setState(() => _closed = true);
    await SectionHintService.dismiss(widget.hintId);
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = SectionHints.texts[widget.hintId];
    if (text == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 16,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            onPressed: _close,
            iconSize: 18,
            tooltip: tr('Больше не показывать'),
            color: scheme.onSecondaryContainer,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
