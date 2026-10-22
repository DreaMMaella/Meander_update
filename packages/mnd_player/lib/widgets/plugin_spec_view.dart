/// Рендерер декларативного UI-спека плагина.
///
/// Плагин не строит виджеты и не присылает код: он присылает JSON-дерево из
/// фиксированного набора типов (`mnd-plugin/src/spec.rs`), а рисует его этот
/// проревьюенный рендерер. Поэтому:
///
/// - неизвестный тип или слишком глубокая ветка отрисовываются заглушкой, а не
///   падают;
/// - строки проходят подстановку `{переменной}` квеста (тот же синтаксис, что и
///   в тексте квеста), так что надпись привязана к состоянию игры без кода на
///   стороне Dart;
/// - `onPress`/`onTap`/`onChange`/`onSubmit` — это **имя Lua-функции**: тап
///   уходит в `plugin_call`, а не выполняется на клиенте.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mnd_player/utils/quest_image_source.dart';

/// Максимум вложенности, который рендерер готов принять, — страховка от спека,
/// пришедшего не из ядра (например, из превью редактора после ручной правки).
const int _kMaxDepth = 24;

/// Обработчик колбэка: `(имя функции плагина, аргумент)`.
typedef PluginHandlerCallback = void Function(String handler, Object? argument);

/// Колбэк уже привязан к имени функции этого узла спека.
typedef _PluginInvoke = void Function(Object? argument);

/// Иконки по имени: плагин не может назвать `Icons.*`, только выбрать из списка.
const Map<String, IconData> kPluginIcons = {
  'heart': Icons.favorite,
  'star': Icons.star,
  'key': Icons.vpn_key,
  'lock': Icons.lock,
  'gear': Icons.settings,
  'bag': Icons.backpack,
  'book': Icons.menu_book,
  'coin': Icons.monetization_on,
  'clock': Icons.schedule,
  'check': Icons.check_circle,
  'cross': Icons.cancel,
  'eye': Icons.visibility,
  'map': Icons.map,
  'person': Icons.person,
  'sound': Icons.volume_up,
  'bulb': Icons.lightbulb,
  'fire': Icons.local_fire_department,
  'drop': Icons.water_drop,
  'flag': Icons.flag,
  'note': Icons.sticky_note_2,
};

/// Цвета по имени — той же логикой: палитра конечна и задана здесь.
const Map<String, int> kPluginColors = {
  'white': 0xFFFFFFFF,
  'black': 0xFF000000,
  'red': 0xFFE53935,
  'green': 0xFF43A047,
  'blue': 0xFF1E88E5,
  'yellow': 0xFFFDD835,
  'orange': 0xFFFB8C00,
  'purple': 0xFF8E24AA,
  'pink': 0xFFD81B60,
  'cyan': 0xFF00ACC1,
  'gray': 0xFF9E9E9E,
  'brown': 0xFF6D4C41,
  'gold': 0xFFD4AF37,
  'silver': 0xFFBFC9CC,
};

/// UI-спек плагина → виджет.
class PluginSpecView extends StatelessWidget {
  final Map<String, dynamic> spec;

  /// Переменные квеста для `{подстановки}`.
  final Map<String, dynamic> vars;

  /// Область видимости элемента списка/сетки: перекрывает `vars`.
  final Map<String, dynamic>? itemScope;
  final String? questId;
  final PluginHandlerCallback? onHandler;
  final int _depth;

  /// Разрешено ли этому узлу быть `Expanded`. Решение принимает контейнер:
  /// только он знает, ограничена ли его главная ось. В списке контента высота
  /// неограничена, и `Expanded` там — «RenderFlex children have non-zero
  /// flex…», а следом каскад assert'ов в semantics.
  final bool _expandable;

  const PluginSpecView({
    super.key,
    required this.spec,
    required this.vars,
    this.itemScope,
    this.questId,
    this.onHandler,
  }) : _depth = 0,
       _expandable = false;

  const PluginSpecView._nested({
    required this.spec,
    required this.vars,
    required this.itemScope,
    required this.questId,
    required this.onHandler,
    required int depth,
    required bool expandable,
  }) : _depth = depth,
       _expandable = expandable;

  static const List<Map<String, dynamic>> _emptyChildren = [];

  PluginSpecView _childOf(
    Map<String, dynamic> child, {
    bool expandable = false,
  }) => PluginSpecView._nested(
    spec: child,
    vars: vars,
    itemScope: itemScope,
    questId: questId,
    onHandler: onHandler,
    depth: _depth + 1,
    expandable: expandable,
  );

  @override
  Widget build(BuildContext context) {
    if (_depth > _kMaxDepth) return const SizedBox.shrink();
    final type = spec['type'] as String? ?? '';
    final theme = Theme.of(context);
    final childSpecs = _children();

    Widget body;
    switch (type) {
      case 'column':
        body = _box(_flex(Axis.vertical, childSpecs, theme));
      case 'row':
        body = _box(_flex(Axis.horizontal, childSpecs, theme));
      case 'stack':
        body = _stack();
      case 'box':
        body = _box(_merge(childSpecs, theme));
      case 'card':
        body = _card(childSpecs, theme);
      case 'scroll':
        body = SingleChildScrollView(child: _merge(childSpecs, theme));
      case 'list':
        body = _list(childSpecs, theme);
      case 'grid':
        body = _grid(childSpecs, theme);
      case 'text':
        body = _text(spec['text'], theme.textTheme.bodyMedium);
      case 'heading':
        body = _text(spec['text'], theme.textTheme.titleLarge);
      case 'caption':
        body = _text(spec['text'], theme.textTheme.bodySmall);
      case 'badge':
        body = _badge(theme);
      case 'chip':
        body = _chip(theme);
      case 'icon':
        body = _icon(theme);
      case 'image':
        body = _image();
      case 'button':
        body = _button(theme);
      case 'switch':
        body = _switch(theme);
      case 'input':
        body = _input();
      case 'slider':
        body = _slider(theme);
      case 'progress':
        body = _progress(theme);
      case 'divider':
        body = _divider();
      case 'spacer':
        body = SizedBox(height: _size('size', 12));
      default:
        body = _unknown(type);
    }

    body = _applyDecoration(body, type);
    if (_expandable && _bool('expand')) body = Expanded(child: body);
    return body;
  }

  // ---- свойства ------------------------------------------------------------

  double? _num(String name) {
    final raw = spec[name];
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final resolved = _string(raw);
      return double.tryParse(resolved);
    }
    return null;
  }

  double _size(String name, double fallback) => _num(name) ?? fallback;

  bool _bool(String name) => spec[name] == true;

  Color? _color(String name) {
    final raw = spec[name];
    if (raw is! String) return null;
    final text = _string(raw).trim();
    final named = kPluginColors[text.toLowerCase()];
    if (named != null) return Color(named);
    final hex = text.startsWith('#') ? text.substring(1) : text;
    if (hex.length == 6 || hex.length == 8) {
      final value = int.tryParse(hex, radix: 16);
      if (value == null) return null;
      return hex.length == 8 ? Color(value) : Color(0xFF000000 | value);
    }
    return null;
  }

  /// Значение свойства-строки с подстановкой `{переменных}`.
  String _string(Object? raw) => switch (raw) {
    null => '',
    _ => resolvePluginVariables('$raw', vars, itemScope),
  };

  AlignmentGeometry _alignment() => switch (spec['align'] as String?) {
    'start' => Alignment.centerLeft,
    'end' => Alignment.centerRight,
    'stretch' => Alignment.center,
    _ => Alignment.center,
  };

  // ---- дети и контейнеры ---------------------------------------------------

  List<Map<String, dynamic>> _children() {
    final raw = spec['children'];
    if (raw is! List) return _emptyChildren;
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  /// Дети без явной оси (`box`, `scroll`): колонка, если их больше одного.
  Widget _merge(List<Map<String, dynamic>> specs, ThemeData theme) =>
      specs.isEmpty
      ? const SizedBox.shrink()
      : _flex(Axis.vertical, specs, theme);

  /// Черта ориентируется по доступному месту: в Column — горизонтальная, в Row
  /// — вертикальная. Иначе `SizedBox(width: infinity)` в неограниченном
  /// родителе роняет layouts.
  Widget _divider() => LayoutBuilder(
    builder: (context, constraints) {
      final thickness = _num('thickness');
      final color = _color('color') ?? _color('background');
      if (constraints.maxWidth.isFinite) {
        return Divider(
          height: thickness ?? 1,
          thickness: thickness ?? 1,
          color: color,
        );
      }
      return VerticalDivider(
        width: thickness ?? 1,
        thickness: thickness ?? 1,
        color: color,
      );
    },
  );

  /// `stretch` даёт детям жёсткий размер поперёк оси — в Row/неограниженном
  /// родителе это «BoxConstraints forces an infinite …». Поэтому по умолчанию
  /// start, а растяжение только по явному запросу.
  CrossAxisAlignment _crossAxisAlignment({
    CrossAxisAlignment fallback = CrossAxisAlignment.start,
  }) => switch (spec['align'] as String?) {
    'end' => CrossAxisAlignment.end,
    'center' => CrossAxisAlignment.center,
    'stretch' => CrossAxisAlignment.stretch,
    _ => fallback,
  };

  Widget _flex(Axis axis, List<Map<String, dynamic>> specs, ThemeData theme) =>
      LayoutBuilder(
        builder: (context, constraints) {
          // `expand` имеет смысл только когда главной оси есть предел: иначе
          // `Expanded` в неограниченном Column — то есть в списке контента —
          // роняет раскладку всего экрана.
          final expandable = axis == Axis.vertical
              ? constraints.maxHeight.isFinite
              : constraints.maxWidth.isFinite;
          return _flexBuilt(axis, [
            for (final child in specs) _childOf(child, expandable: expandable),
          ], theme);
        },
      );

  Widget _flexBuilt(Axis axis, List<Widget> children, ThemeData theme) {
    final gap = _size('gap', 0);
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && gap > 0) {
        spaced.add(
          axis == Axis.vertical ? SizedBox(height: gap) : SizedBox(width: gap),
        );
      }
      spaced.add(children[i]);
    }
    final justify = switch (spec['justify'] as String?) {
      'center' => MainAxisAlignment.center,
      'end' => MainAxisAlignment.end,
      'space' => MainAxisAlignment.spaceBetween,
      _ => MainAxisAlignment.start,
    };
    return axis == Axis.vertical
        ? Column(
            mainAxisSize: _bool('fill') ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: justify,
            crossAxisAlignment: _crossAxisAlignment(),
            children: spaced,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: justify,
            crossAxisAlignment: _crossAxisAlignment(
              fallback: CrossAxisAlignment.center,
            ),
            children: spaced,
          );
  }

  /// `stack`: дети кладутся друг на друга; `x`/`y` (в пикселях) позиционируют
  /// ребёнка абсолютно, без них — по `align` ребёнка или контейнера.
  Widget _stack() {
    final specs = _children();
    if (specs.isEmpty) return const SizedBox.shrink();
    final height = _num('height');
    final fallback = _alignment();
    final children = <Widget>[];
    for (final child in specs) {
      final widget = _childOf(child);
      final x = child['x'] is num ? (child['x'] as num).toDouble() : null;
      final y = child['y'] is num ? (child['y'] as num).toDouble() : null;
      children.add(
        x == null && y == null
            ? Align(
                alignment: child['align'] is String
                    ? _alignmentOf(child)
                    : fallback,
                child: widget,
              )
            : Positioned(left: x, top: y, child: widget),
      );
    }
    return SizedBox(
      height: height ?? _size('minHeight', 160),
      width: _num('width'),
      child: Stack(fit: StackFit.expand, children: children),
    );
  }

  static AlignmentGeometry _alignmentOf(Map<String, dynamic> child) =>
      switch (child['align'] as String?) {
        'start' => Alignment.centerLeft,
        'end' => Alignment.centerRight,
        'top' => Alignment.topCenter,
        'bottom' => Alignment.bottomCenter,
        'topStart' => Alignment.topLeft,
        'bottomEnd' => Alignment.bottomRight,
        _ => Alignment.center,
      };

  Widget _card(List<Map<String, dynamic>> children, ThemeData theme) =>
      Container(
        decoration: BoxDecoration(
          color:
              _color('background') ?? theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(_size('radius', 14)),
          border: Border.all(color: _color('border') ?? Colors.transparent),
        ),
        padding: EdgeInsets.all(_size('padding', 14)),
        child: _flex(Axis.vertical, children, theme),
      );

  Widget _box(Widget child) {
    final hasPaint = _color('background') != null || _color('border') != null;
    if (!hasPaint)
      return Padding(
        padding: EdgeInsets.all(_size('padding', 0)),
        child: child,
      );
    return Container(
      decoration: BoxDecoration(
        color: _color('background'),
        borderRadius: BorderRadius.circular(_size('radius', 10)),
        border: Border.all(color: _color('border') ?? Colors.transparent),
      ),
      padding: EdgeInsets.all(_size('padding', 0)),
      child: child,
    );
  }

  /// Шаблон строки: явный `row`, иначе — первый ребёнок контейнера.
  Map<String, dynamic>? get _template {
    final raw = spec['row'] ?? spec['item'];
    if (raw is Map) return raw.cast<String, dynamic>();
    final kids = _children();
    return kids.isEmpty ? null : kids.first;
  }

  /// Данные списка: литерал-массив или `{имя}` переменной с массивом.
  List<Object?> get _items {
    final raw = spec['items'];
    if (raw is List) return raw;
    if (raw is String) {
      final value = lookupPluginVariable(raw, vars, itemScope);
      if (value is List) return value;
      if (value is Map) return value.values.toList();
      if (value != null) return [value];
    }
    return const [];
  }

  Widget _listChildren(
    List<Map<String, dynamic>> children,
    ThemeData theme,
    double gap,
  ) {
    final items = _items;
    if (items.isEmpty) return _flex(Axis.vertical, children, theme);
    final template = _template;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: _crossAxisAlignment(),
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: template == null
                ? Text(_string(items[i]))
                : _withScope(template, items[i], i),
          ),
      ],
    );
  }

  Widget _withScope(Map<String, dynamic> template, Object? item, int index) {
    final scope = item is Map
        ? item.cast<String, dynamic>()
        : <String, dynamic>{'value': item, 'index': index};
    return PluginSpecView._nested(
      spec: template,
      vars: vars,
      itemScope: {...?itemScope, ...scope},
      questId: questId,
      onHandler: onHandler,
      depth: _depth + 1,
      // Ячейка живёт внутри `Padding`, а не внутри Flex: `Expanded` здесь
      // был бы неверным родителем.
      expandable: false,
    );
  }

  Widget _list(List<Map<String, dynamic>> children, ThemeData theme) {
    final gap = _size('gap', 6);
    final body = _listChildren(children, theme, gap);
    return _bool('scroll') ? SingleChildScrollView(child: body) : body;
  }

  Widget _grid(List<Map<String, dynamic>> children, ThemeData theme) {
    final items = _items;
    final wanted = (_num('columns') ?? 2).clamp(1, 6).round();
    final cellWidth = _num('cellWidth');
    final gap = _size('gap', 8);
    final template = _template;
    if (items.isEmpty) return _flex(Axis.vertical, children, theme);
    final cells = [
      for (var i = 0; i < items.length; i++)
        template == null
            ? _plainCell(items[i])
            : _withScope(template, items[i], i),
    ];
    // GridView требует ограниченной ширины; в неограниченном родителе
    // (горизонтальный Row) собираем сетку столбцами.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite) {
          return _flexBuilt(Axis.horizontal, cells, theme);
        }
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // `cellWidth` — адаптивная сетка: столбцов ровно столько, сколько
          // влезает при минимальной ширине ячейки, но не больше запрошенного
          // `columns`. Без `cellWidth` колонок столько, сколько попросил
          // плагин, и на узком экране ячейки сплющиваются.
          crossAxisCount: cellWidth == null
              ? wanted
              : ((constraints.maxWidth + gap) / (cellWidth + gap))
                    .floor()
                    .clamp(1, wanted),
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: _num('ratio') ?? 1,
          children: cells,
        );
      },
    );
  }

  Widget _plainCell(Object? item) => Center(child: Text(_string(item)));

  // ---- листовые виджеты -----------------------------------------------------

  Widget _text(Object? raw, TextStyle? base) {
    final value = _string(raw);
    final size = _num('size');
    return Text(
      value,
      maxLines: (_num('maxLines') ?? 0).round() == 0
          ? null
          : (_num('maxLines')!).round(),
      overflow: TextOverflow.ellipsis,
      style: base?.copyWith(
        color: _color('color'),
        fontSize: size,
        fontWeight: _bool('bold') || spec['weight'] == 'bold'
            ? FontWeight.bold
            : null,
      ),
    );
  }

  Widget _badge(ThemeData theme) {
    final background = _color('background') ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_size('radius', 999)),
      ),
      child: Text(
        _string(spec['label'] ?? spec['text']),
        style: TextStyle(
          color: _color('color') ?? theme.colorScheme.onPrimary,
          fontSize: _num('size') ?? 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme) {
    final handler = _handler('onPress');
    return ActionChip(
      label: Text(_string(spec['label'] ?? spec['text'])),
      avatar: _iconData() == null ? null : Icon(_iconData(), size: 16),
      backgroundColor: _color('background'),
      labelStyle: TextStyle(color: _color('color')),
      onPressed: handler == null ? null : () => handler(_args()),
    );
  }

  String? _iconName() {
    final raw = spec['icon'] ?? spec['name'];
    if (raw is! String) return null;
    // Имя иконки — такие же данные, как подпись: в шаблоне ячейки оно приходит
    // из элемента (`icon = '{icon}'`), поэтому проходит подстановку.
    final name = _string(raw).trim();
    return name.isEmpty ? null : name;
  }

  IconData? _iconData() {
    final name = _iconName();
    return name == null ? null : kPluginIcons[name];
  }

  Widget _icon(ThemeData theme) => Icon(
    _iconData() ?? Icons.help_outline,
    size: _size('size', 22),
    color: _color('color') ?? theme.iconTheme.color,
  );

  Widget _image() {
    final src = _string(spec['src'] ?? spec['path'] ?? spec['asset']);
    final width = _num('width');
    final height = _num('height');
    if (src.isEmpty) return const SizedBox.shrink();
    return PluginSpecImage(
      questId: questId,
      source: src,
      width: width,
      height: height,
      radius: _size('radius', 0),
      fit: switch (spec['fit'] as String?) {
        'contain' => BoxFit.contain,
        'fill' => BoxFit.fill,
        'tile' => BoxFit.none,
        _ => BoxFit.cover,
      },
    );
  }

  Widget _button(ThemeData theme) {
    final handler = _handler('onPress') ?? _handler('onTap');
    final label = _string(spec['label'] ?? spec['text']);
    final icon = _iconData();
    // В узкой ячейке сетки (плагин попросил пять колонок на телефоне) кнопка
    // уже, чем иконка с отступом, и `Row` переполнялся. Значок здесь —
    // украшение, надпись — смысл, поэтому при нехватке места убираем значок.
    final child = LayoutBuilder(
      builder: (context, constraints) {
        final text = Text(label, overflow: TextOverflow.ellipsis);
        if (icon == null ||
            (constraints.maxWidth.isFinite && constraints.maxWidth < 64)) {
          return text;
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Flexible(child: text),
          ],
        );
      },
    );
    final onPress = handler == null ? null : () => handler(_args());
    if (spec['variant'] == 'outline') {
      return OutlinedButton(
        onPressed: onPress,
        style: OutlinedButton.styleFrom(
          foregroundColor: _color('color'),
          side: BorderSide(
            color: _color('border') ?? theme.colorScheme.primary,
          ),
        ),
        child: child,
      );
    }
    if (spec['variant'] == 'text') {
      return TextButton(onPressed: onPress, child: child);
    }
    return FilledButton(
      onPressed: onPress,
      style: FilledButton.styleFrom(
        backgroundColor: _color('background'),
        foregroundColor: _color('color'),
      ),
      child: child,
    );
  }

  Widget _switch(ThemeData theme) {
    final handler = _handler('onChange');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: _bool('checked'),
          onChanged: handler == null
              ? null
              : (value) => handler({'value': value}),
        ),
        if (spec['label'] != null)
          Flexible(
            child: Text(
              _string(spec['label']),
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget _slider(ThemeData theme) {
    final handler = _handler('onChange');
    final value = _num('value') ?? 0;
    return _boundedWidth(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: _crossAxisAlignment(
          fallback: CrossAxisAlignment.stretch,
        ),
        children: [
          if (spec['label'] != null)
            Text(_string(spec['label']), style: theme.textTheme.bodySmall),
          Slider(
            value: value.clamp(_num('min') ?? 0, _num('max') ?? 1),
            min: _num('min') ?? 0,
            max: _num('max') ?? 1,
            onChanged: handler == null
                ? null
                : (next) => handler({'value': next}),
          ),
        ],
      ),
      200,
    );
  }

  /// Поле ввода: текст игрока уходит в Lua-функцию аргументом `{value: …}`.
  /// `value` спеки — и начальное содержимое, и привязка к переменной, так что
  /// плагин может как показать подсказку, так и вернуть в поле набранное.
  Widget _input() => _boundedWidth(
    _PluginInput(
      value: _string(spec['value']),
      label: _string(spec['label']),
      placeholder: _string(spec['placeholder'] ?? spec['hint']),
      obscured: _bool('password'),
      multiline: _bool('multiline'),
      maxLength: _num('maxLength')?.round(),
      styleColor: _color('color'),
      onSubmit: _handler('onSubmit') ?? _handler('onPress'),
      onChange: _handler('onChange'),
      argumentOf: _argsWith,
    ),
    220,
  );

  /// Аргумент колбэка поля: значение плюс всё, что автор положил в `args` —
  /// на одной поверхности полей может быть несколько, и плагин обязан
  /// различать, из какого прилетел текст.
  Object? _argsWith(String value) {
    final extra = _args();
    if (extra is Map) return {...extra.cast<String, dynamic>(), 'value': value};
    if (extra is String && extra.isNotEmpty) {
      return {'args': extra, 'value': value};
    }
    return {'value': value};
  }

  /// Виджеты, растягивающиеся на всю ширину (слайдер, прогресс, поле ввода,
  /// список), в неограниченном родителе (Row) падают с «infinite width» —
  /// поэтому им подставляется хоть какая-то ширина.
  Widget _boundedWidth(Widget child, double fallback) {
    final width = _num('width');
    if (width != null) return SizedBox(width: width, child: child);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth.isFinite ? null : fallback,
        child: child,
      ),
    );
  }

  Widget _progress(ThemeData theme) {
    final value = _num('value') ?? 0;
    final max = _num('max') ?? 100;
    final ratio = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return _boundedWidth(
      ClipRRect(
        borderRadius: BorderRadius.circular(_size('radius', 8)),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: _size('height', 10),
          color: _color('color') ?? theme.colorScheme.primary,
          backgroundColor:
              _color('background') ?? theme.colorScheme.surfaceContainerHighest,
        ),
      ),
      160,
    );
  }

  Widget _unknown(String type) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.orange),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'Неизвестный виджет: $type',
      style: const TextStyle(fontSize: 12),
    ),
  );

  // ---- оформление и колбэки -------------------------------------------------

  /// Типы, которые сами красят фон/рамку/отступ и задают себе размер:
  /// декорация сверху не должна накладываться дважды.
  static const Set<String> _selfPainted = {'card', 'box', 'stack'};

  Widget _applyDecoration(Widget child, String type) {
    final own = _selfPainted.contains(type);
    var result = child;
    if (!own) {
      final padding = _num('padding');
      if (padding != null) {
        result = Padding(padding: EdgeInsets.all(padding), child: result);
      }
      final background = _color('background');
      final border = _color('border');
      final radius = _num('radius');
      if (background != null || border != null || radius != null) {
        result = Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius == null ? null : BorderRadius.circular(radius),
            border: border == null ? null : Border.all(color: border),
          ),
          child: result,
        );
      }
    }
    final opacity = _num('opacity');
    if (opacity != null) {
      result = Opacity(opacity: opacity.clamp(0.0, 1.0), child: result);
    }
    if (!own) {
      final width = _num('width');
      final height = _num('height');
      if (width != null || height != null) {
        result = SizedBox(width: width, height: height, child: result);
      }
    }
    return result;
  }

  _PluginInvoke? _handler(String prop) {
    final raw = spec[prop];
    if (raw is! String || raw.trim().isEmpty) return null;
    final callback = onHandler;
    if (callback == null) return null;
    return (argument) => callback(raw, argument);
  }

  Object? _args() {
    final raw = spec['args'];
    if (raw is Map) return raw.cast<String, dynamic>();
    // `args` шаблона строки `list`/`grid` обязан подставляться: это единственный
    // способ передать в Lua идентификатор ячейки. Без подстановки все кнопки
    // сетки звали бы одну функцию с одним и тем же аргументом.
    if (raw is String) return _string(raw);
    return raw;
  }
}

/// Картинка по пути/имени/uuid ресурса квеста — как в контенте нод.
class PluginSpecImage extends StatelessWidget {
  final String? questId;
  final String source;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;

  const PluginSpecImage({
    super.key,
    required this.questId,
    required this.source,
    this.width,
    this.height,
    this.radius = 0,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final future = questId == null
        ? Future<File?>.value()
        : QuestImageSource.resolve(questId!, source);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: FutureBuilder<File?>(
        future: future,
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file == null) {
            return SizedBox(
              width: width ?? 48,
              height: height ?? 48,
              child: const ColoredBox(color: Color(0x11000000)),
            );
          }
          return Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            cacheWidth: width == null ? null : (width! * 2).round(),
            gaplessPlayback: true,
          );
        },
      ),
    );
  }
}

/// Подстановка `{переменных}` в строке спека.
///
/// `{hp}` — значение; `{inv.slots[2].name}` — путь по полям и индексам.
/// Неизвестная переменная остаётся как есть: плагин видит опечатку в UI и в
/// `mnd.log`, а не получает пустую строку.
final RegExp _bracketIndexes = RegExp(r'\[(\d+)\]');

String resolvePluginVariables(
  String text,
  Map<String, dynamic> vars,
  Map<String, dynamic>? scope,
) {
  if (!text.contains('{')) return text;
  final buffer = StringBuffer();
  var cursor = 0;
  while (cursor < text.length) {
    final open = text.indexOf('{', cursor);
    if (open < 0) {
      buffer.write(text.substring(cursor));
      break;
    }
    final close = text.indexOf('}', open + 1);
    if (close < 0) {
      buffer.write(text.substring(cursor));
      break;
    }
    buffer.write(text.substring(cursor, open));
    final path = text.substring(open + 1, close).trim();
    if (path.isEmpty) {
      buffer.write('{}');
    } else {
      final value = lookupPath(path, vars, scope);
      buffer.write(
        value == null ? text.substring(open, close + 1) : _render(value),
      );
    }
    cursor = close + 1;
  }
  return buffer.toString();
}

/// Значение по `{выражению}` (или по имени без скобок).
Object? lookupPluginVariable(
  String raw,
  Map<String, dynamic> vars,
  Map<String, dynamic>? scope,
) {
  final trimmed = raw.trim();
  final expression = trimmed.startsWith('{') && trimmed.endsWith('}')
      ? trimmed.substring(1, trimmed.length - 1).trim()
      : trimmed;
  if (expression.isEmpty) return null;
  return lookupPath(expression, vars, scope);
}

Object? lookupPath(
  String path,
  Map<String, dynamic> vars,
  Map<String, dynamic>? scope,
) {
  Object? current = scope;
  var first = true;
  for (final segment in path.split('.')) {
    final name = StringBuffer();
    final indexes = <int>[];
    var rest = segment;
    final bracket = rest.indexOf('[');
    if (bracket >= 0) {
      name.write(rest.substring(0, bracket));
      rest = rest.substring(bracket);
      final matches = _bracketIndexes.allMatches(rest);
      for (final match in matches) {
        indexes.add(int.parse(match.group(1)!));
      }
    } else {
      name.write(rest);
    }
    final key = name.toString();
    if (first) {
      current = scope != null && scope.containsKey(key)
          ? scope[key]
          : vars[key];
      first = false;
    } else if (current is Map) {
      current = current[key];
    } else {
      return null;
    }
    for (final index in indexes) {
      if (current is List && index < current.length) {
        current = current[index];
      } else {
        return null;
      }
    }
  }
  return current;
}

String _render(Object? value) => switch (value) {
  null => '',
  num number => _renderNumber(number),
  bool flag => flag ? 'да' : 'нет',
  Map map => map.values.map(_render).join(', '),
  List list => list.map(_render).join(', '),
  _ => '$value',
};

String _renderNumber(num value) =>
    value is int || value == value.roundToDouble()
    ? value.round().toString()
    : '$value';

/// Поле ввода из спеки плагина. Отдельный виджет со своим контроллером:
/// `TextField` без него терял бы набранное на каждой перерисовке поверхности,
/// а плагин перерисовывает её после каждого `onChange`.
class _PluginInput extends StatefulWidget {
  final String value;
  final String label;
  final String placeholder;
  final bool obscured;
  final bool multiline;
  final int? maxLength;
  final Color? styleColor;
  final _PluginInvoke? onSubmit;
  final _PluginInvoke? onChange;
  final Object? Function(String text) argumentOf;

  const _PluginInput({
    required this.value,
    required this.label,
    required this.placeholder,
    required this.obscured,
    required this.multiline,
    required this.maxLength,
    required this.styleColor,
    required this.onSubmit,
    required this.onChange,
    required this.argumentOf,
  });

  @override
  State<_PluginInput> createState() => _PluginInputState();
}

class _PluginInputState extends State<_PluginInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  bool _typed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => _typed = _focus.hasFocus);
  }

  @override
  void didUpdateWidget(_PluginInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Вне фокуса содержимым владеет спека — так плагин может подставить в поле
    // текст из переменной. Показавшийся курсор посреди ввода игрока стоил бы
    // каждой опечатки, поэтому во время ввода её не трогаем.
    if (!_typed && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _send(_PluginInvoke? handler, String text) =>
      handler?.call(widget.argumentOf(text));

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      obscureText: widget.obscured,
      maxLines: widget.multiline ? 3 : 1,
      maxLength: widget.maxLength,
      style: widget.styleColor == null
          ? null
          : TextStyle(color: widget.styleColor),
      decoration: InputDecoration(
        labelText: widget.label.isEmpty ? null : widget.label,
        hintText: widget.placeholder.isEmpty ? null : widget.placeholder,
        counterText: widget.maxLength == null ? null : '',
      ),
      onChanged: widget.onChange == null
          ? null
          : (text) => _send(widget.onChange, text),
      onSubmitted: widget.onSubmit == null
          ? null
          : (text) => _send(widget.onSubmit, text),
    );
  }
}
