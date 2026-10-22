import 'package:flutter/material.dart';
import 'package:mnd_core/mnd_core.dart';
import 'package:canvas_app/core/l10n/l10n.dart';

/// Справка по стеку прямо в его настройках: шесть правил, без которых параметры
/// читаются как набор цифр, и готовые примеры рамки закрепления.
///
/// Примеры меняют только рамку: вёрстка слоёв не трогается, потому что дети
/// прижаты к углам холста своими отступами. Холст остаётся авторский — кому
/// нужна полоса пониже, тот правит «Высоту холста» выше.
class StackHelpPanel extends StatefulWidget {
  const StackHelpPanel({
    super.key,
    required this.stack,
    required this.viewport,
    required this.onApply,
  });

  final ContentItem stack;

  /// Вьюпорт плеера — тот же, что считает [StackPinBoxEditor.viewportOf].
  final Size viewport;

  /// Новый документ стека: коммит и шаг истории делает вызывающий код.
  final ValueChanged<ContentItem> onApply;

  /// Правила и готовые рамки наружу: тесты проверяют ровно то, что видит автор.
  /// Геттер, а не const-список: строки берутся под текущий язык.
  static List<String> get rules => [
    tr('Размеры — в пикселях холста, не экрана. Холст 720 — это проекция на ширину телефона: на узком экране стек ужимается целиком, пропорции и места слоёв сохраняются.'),
    tr('Слои прижаты к краям холста своими отступами. Поэтому холст тянут за край или правят полями «Ширина/Высота холста» — слои остаются при своих отступах и сами не разъезжаются.'),
    tr('Без закрепления стек — обычный элемент контента: прокручивается вместе с нодой. С закреплением — слой над прокруткой: панель, шторка или окно.'),
    tr('Якоря рамки работают по осям независимо. Схлопнутая ось (левый якорь равен правому) задаёт позицию: 0 — у левого/верхнего края, 0.5 — центр, 1 — у противоположного. Растянутая ось задаёт размер: бокс от якоря до якоря, и поле «Ш/В» показывает тогда экранную ширину, а не холст.'),
    tr('Модальное окно — это закрепление плюс затемнение. Тап вне рамки его закрывает, если разрешено; скрипт блоком «показать» вернёт окно обратно, даже если игрок уже его закрыл.'),
    tr('«Сверху», «Центр», «Экран» — готовые позиции: тап по ним прижимает рамку к этой точке и сбрасывает вашу. «Рамка» — тот же самый режим, но без пресета: рамку задают поля позиции и размера либо перетаскивание прямо на канвасе, и никто её не перезаписывает. Окно «320×200 по центру» делают через «Рамку», а не через «Центр» с смещениями.'),
  ];

  static List<StackFrameExample> get examples => [
    StackFrameExample(
      name: tr('Плашка внизу экрана'),
      description: tr(
        'Полоса на всю ширину у нижнего края: реплика, подпись, статус.',
      ),
      anchors: [0, 1, 1, 1],
    ),
    StackFrameExample(
      name: tr('Шапка-шторка сверху'),
      description: tr(
        'Полоса на всю ширину у верхнего края: счёт, таймер, название главы.',
      ),
      anchors: [0, 0, 1, 0],
    ),
    StackFrameExample(
      name: tr('Окно по центру'),
      description: tr(
        'Посреди экрана, с затемнением под ним и закрытием по тапу мимо.',
      ),
      anchors: [0.5, 0.5, 0.5, 0.5],
      modal: true,
    ),
    StackFrameExample(
      name: tr('Слой в правом нижнем углу'),
      description: tr(
        'Маленький плавающий слой у края: кнопка меню, подсказка, «пауза».',
      ),
      anchors: [1, 1, 1, 1],
    ),
  ];

  @override
  State<StackHelpPanel> createState() => _StackHelpPanelState();
}

class _StackHelpPanelState extends State<StackHelpPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('stack_help_toggle'),
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_less : Icons.help_outline,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _open ? tr('Свернуть справку') : tr('Как это работает'),
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          for (final rule in StackHelpPanel.rules) _Bullet(text: rule),
          Text(
            tr('Примеры — готовые рамки. Слои внутри стека остаются на своих местах, правка отменяется (Ctrl+Z).'),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 6),
          for (final example in StackHelpPanel.examples)
            _ExampleRow(
              example: example,
              onApply: () =>
                  widget.onApply(example.apply(widget.stack, widget.viewport)),
            ),
        ],
      ],
    );
  }
}

/// Готовая рамка закрепления: позиция/растяжение по осям и модалка.
class StackFrameExample {
  const StackFrameExample({
    required this.name,
    required this.description,
    required this.anchors,
    this.modal = false,
  });

  final String name;
  final String description;

  /// l, t, r, b в долях вьюпорта.
  final List<double> anchors;
  final bool modal;

  ContentItem apply(ContentItem stack, Size viewport) {
    final pinned = stack.stackPinWithAnchors(anchors, viewport);
    if (!modal) return pinned;
    return pinned.copyWith(stackModal: true, stackDismissOnTapOutside: true);
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleRow extends StatelessWidget {
  const _ExampleRow({required this.example, required this.onApply});

  final StackFrameExample example;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  example.name,
                  style: TextStyle(color: scheme.onSurface, fontSize: 13),
                ),
                Text(
                  example.description,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('stack_help_apply_${example.name}'),
            onPressed: onApply,
            child: Text(tr('Применить')),
          ),
        ],
      ),
    );
  }
}
