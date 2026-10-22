import 'package:canvas_app/features/editor/screens/visual_script_editor/block_models.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:flutter/material.dart';

/// Раздел справочника по таблицам.
class TableGuideSection {
  final String title;
  final List<String> bullets;

  const TableGuideSection({required this.title, required this.bullets});
}

/// Единый текст подсказок о таблицах: его читают и шпаргалка в редакторе
/// таблицы, и подсказка под блоком «Данные». Держим в одном месте, чтобы
/// справочник не разошёлся с тем, что реально делает движок.
///
/// [exampleTable] — имя таблицы в примерах; лучше передавать настоящую, тогда
/// автор видит готовую к копированию строку.
List<TableGuideSection> tableGuideSections({String? exampleTable}) {
  // Имя таблицы в примерах: своё не трогаем, вместо пустого — демонстрационное
  // под текущий язык.
  final t = (exampleTable == null || exampleTable.isEmpty)
      ? tr('лавка')
      : exampleTable;
  return [
    TableGuideSection(
      title: tr('Два хранилища в одной таблице'),
      bullets: [
        tr('Сетка — столбцы и строки, которые вы видите и редактируете в таблице.'),
        tr('Хранилище скриптов — пары «ключ → значение». Именно с ним работает блок «Данные», его же читают формулы вида таблица[\'ключ\'].'),
        tr('Сетка в хранилище не попадает: «Удалить» в блоке не стирает ячейку, а стирает ключ хранилища. И наоборот — запись в хранилище не меняет ряды.'),
      ],
    ),
    TableGuideSection(
      title: tr('Как достать значение'),
      bullets: [
        trf('Ячейка сетки — ссылкой {{table}["цена"][3]}: имя таблицы, колонка в кавычках, потом номер строки в своих скобках (с 1). Без скобок — {{table}["цена"]3} — номер съедается молча и приходит весь столбец. Такую ссылку можно вставить тапом по ячейке в режиме выбора.', {'table': t}),
        trf('Ключ хранилища — из формулы {table}[\'открыто\'] или блоком «Данные» → «Получить» в переменную.', {'table': t}),
        tr('Для сетки есть готовые функции: table_min, table_max, table_find, table_where, table_has, table_text — их список показывает редактор формул в разделе «Таблицы».'),
      ],
    ),
    TableGuideSection(
      title: tr('Операции блока «Данные»'),
      bullets: [
        for (final op in TableOperation.values)
          trf('{label} — {description}', {
            'label': op.label,
            'description': op.description,
          }),
      ],
    ),
    TableGuideSection(
      title: tr('Частые промахи'),
      bullets: [
        tr('Пустой путь. «Получить» тогда отдаёт запасное значение из поля «Значение», а «Записать»/«Добавить»/«Удалить» не делают ничего. Ядро пишет об этом строку в лог скрипта — смотрите его первым.'),
        tr('Опечатка в имени таблицы. В логе появится список доступных имён — сверяйте регистр и пробелы.'),
        tr('Нужно убрать элемент из списка по значению — берите «Удалить значение» (Путь = список, Значение = что убрать). «Удалить» работает по ключу или индексу и значение не ищет.'),
        tr('«Добавить» дописывает только в список. Если по пути лежит число, строка или словарь — пишите через «Записать».'),
        tr('Проверить наличие значения и не потерять результат: у «Содержит?» и «Получить» обязательно поле «В переменную».'),
        tr('Индексация разная: строки сетки и ссылки {…["колонка"][3]} — с 1, а элементы массива — с 0: и в функциях (split, table_where), и в пути блока «Данные» (items[1] — второй элемент).'),
        tr('Фигурные скобки — только для ссылок. {лавка["цена"][1] + 5} теряет «+ 5», а {table_cell(лавка, "цена", 1)} не вычисляется вовсе: функцию пишут в поле без обёртки — table_cell(лавка, "цена", 1) + 5.'),
        tr('«Цикл (таблица)» идёт по рядам сетки и ключи хранилища не видит; наоборот — «Данные» не перебирает ряды.'),
        tr('Экспорт CSV вмещает только сетку: ключи хранилища в файл не пишутся. Полный слепок таблицы — XLSX (лист «Данные») или JSON.'),
      ],
    ),
  ];
}

/// Шпаргалка по таблицам в виде шита/диалога.
Future<void> showTableGuide(BuildContext context, {String exampleTable = ''}) {
  final sections = tableGuideSections(exampleTable: exampleTable);
  return showAdaptiveSheet<void>(
    context: context,
    title: tr('Как устроена таблица'),
    builder: (context) => _TableGuideSheet(sections: sections),
  );
}

class _TableGuideSheet extends StatelessWidget {
  final List<TableGuideSection> sections;

  const _TableGuideSheet({required this.sections});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        for (final s in sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              s.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
          for (final b in s.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      b,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Компактная строка-напоминание над таблицей или блоком: коротко о том, что
/// сетка и хранилище скриптов — разные вещи, плюс вход в шпаргалку.
class TableHintBanner extends StatelessWidget {
  final String text;
  final VoidCallback? onDetails;
  final String? detailsLabel;

  const TableHintBanner({
    super.key,
    required this.text,
    this.onDetails,
    this.detailsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.3,
              ),
            ),
          ),
          if (onDetails != null)
            TextButton(
              onPressed: onDetails,
              child: Text(detailsLabel ?? tr('Подробнее')),
            ),
        ],
      ),
    );
  }
}
