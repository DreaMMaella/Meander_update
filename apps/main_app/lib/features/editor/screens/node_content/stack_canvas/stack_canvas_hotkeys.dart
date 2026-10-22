import 'package:flutter/material.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

/// (клавиши, что делают) — одной строкой, чтобы список читался как таблица.
typedef _Hotkey = (String, String);

class _Section {
  final String title;
  final List<_Hotkey> rows;
  const _Section(this.title, this.rows);
}

/// Клавиши Ctrl на Windows/Linux и Meta на macOS работают одинаково — в
/// редакторе их не различают, поэтому и в шпаргалке один ярлык.
/// Геттер, а не const-таблица: шпаргалка печатается на текущем языке.
List<_Section> get _sections => [
  _Section(tr('Выделение'), [
    (tr('клик'), tr('взять объект; по слою группы — всю группу')),
    (tr('клик ещё раз'), tr('сузить группу до одного слоя')),
    (tr('Shift+клик'), tr('добавить или снять слой с группой')),
    ('M', tr('режим рамки выделения')),
    (tr('Shift+рамка'), tr('добавить к выделению')),
    (tr('Alt+рамка'), tr('вычесть из выделения')),
    ('Ctrl+A', tr('выделить всё')),
    ('Esc', tr('снять выделение; бросить рамку, драг, направляющую, холст')),
  ]),
  _Section(tr('Геометрия'), [
    ('←↑↓→', tr('сдвиг на 1 px')),
    ('Shift+←↑↓→', tr('сдвиг на 10 px')),
    ('Alt+←↑↓→', tr('ресайз вместо сдвига')),
    (tr('драг объекта'), tr('переместить; группу — целиком')),
    (tr('Shift+драг объекта'), tr('строго по горизонтали или по вертикали')),
    (tr('Ctrl+драг объекта'), tr('без прилипания: объект там, где палец')),
    (
      tr('зазоры при драге'),
      tr('зазоры до соседа или края: при перемещении и ресайзе'),
    ),
    (tr('Alt+драг'), tr('дубликат за один шаг истории')),
    (tr('Shift+тяга за угол'), tr('сохранить пропорции')),
    (tr('ручка сверху'), tr('поворот; Shift — шаг 15°')),
    (tr('ручка низа холста'), tr('высота холста')),
    (tr('ручка права холста'), tr('ширина холста')),
    (tr('янтарь за краем'), tr('здесь кадр обрежется')),
    (tr('двойной тап по слою'), tr('редактор объекта')),
    (tr('двойной тап по фону'), tr('добавить слой в этой точке')),
    (tr('поля X Y W H в шапке'), tr('точные координаты и размер слоя')),
    ('Delete', tr('удалить выделенное')),
  ]),
  _Section(tr('Буфер'), [
    ('Ctrl+C / Ctrl+X', tr('копировать / вырезать')),
    ('Ctrl+V', tr('вставить со сдвигом')),
    ('Ctrl+D', tr('дублировать')),
    ('Ctrl+Alt+C / Ctrl+Alt+V', tr('скопировать или перенести стиль слоя')),
  ]),
  _Section(tr('Группы и слои'), [
    ('Ctrl+G', tr('сгруппировать выделенное')),
    ('Ctrl+Shift+G', tr('разгруппировать')),
    ('Ctrl+] / Ctrl+[', tr('на передний / задний план')),
    (tr('долгое нажатие'), tr('меню слоя: имя, видимость, замок')),
    (tr('молния у слоя'), tr('на нём скрипт или переход; правится в меню слоя')),
  ]),
  _Section(tr('Вид'), [
    (tr('колесо мыши'), tr('зум к курсору')),
    (tr('драг фона'), tr('панорама')),
    (tr('Ctrl и Ctrl+='), tr('зум с клавиатуры')),
    ('Ctrl+0', tr('вписать стек в экран')),
    ('Ctrl+1', tr('масштаб 100 %')),
    ('Ctrl+2', tr('приблизить к выделению')),
    ('Ctrl+;', tr('показать или скрыть линейки')),
  ]),
  _Section(tr('Направляющие'), [
    (tr('драг из линейки'), tr('вытянуть направляющую')),
    (tr('драг по линии'), tr('передвинуть')),
    (tr('возврат в линейку'), tr('удалить; Esc — бросить жест')),
    (tr('объект у линии'), tr('прилипает краем и центром')),
  ]),
];

/// Шпаргалка по горячим клавишам канваса стека.
///
/// Подсказки в tooltip'ах видит только тот, у кого есть мышь, а клавиш уже
/// больше двух десятков — их невозможно держать в голове и невозможно
/// прочитать в коде, не зная, где искать.
class StackCanvasHotkeysSheet extends StatelessWidget {
  const StackCanvasHotkeysSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  tr('Горячие клавиши канваса'),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final section in _sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    section.title.toUpperCase(),
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                for (final (keys, action) in section.rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 148,
                          child: Text(
                            keys,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            action,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showStackCanvasHotkeys(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showAdaptiveSheet<void>(
    context: context,
    backgroundColor: scheme.surfaceContainerHigh,
    isScrollControlled: true,
    builder: (_) => StackCanvasHotkeysSheet(),
  );
}
