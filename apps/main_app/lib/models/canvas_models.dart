import 'package:flutter/material.dart';

// ================================================================
// === СЕМАНТИЧЕСКИЕ РОЛИ ЦВЕТА НОДЫ (Material 3) ===
// Нода больше не хранит «сырой» ARGB. Вместо этого она ссылается на
// роль из ColorScheme. Реальный цвет вычисляется из текущей темы в
// момент отрисовки — это гарантирует, что нода всегда в гамме темы
// и перекрашивается при смене темы.
// ================================================================
enum NodeColorRole {
  surface, // нейтральная (по умолчанию)
  primary,
  secondary,
  tertiary,
  error,
}

// ================================================================
// === ТЕМА ХОЛСТА (токены цветов для CustomPainter) ===
// CustomPainter не имеет доступа к BuildContext, поэтому экран
// обновляет эти значения из ColorScheme в каждом build().
// ================================================================
class CanvasTheme {
  // --- Контейнеры ролей нод (filled-card M3) ---
  static Color roleSurfaceContainer = const Color(0xFF242424);
  static Color roleSurfaceOn = Colors.white;
  static Color rolePrimaryContainer = const Color(0xFF004A77);
  static Color rolePrimaryOn = Colors.white;
  static Color roleSecondaryContainer = const Color(0xFF3F4759);
  static Color roleSecondaryOn = Colors.white;
  static Color roleTertiaryContainer = const Color(0xFF5C3F5C);
  static Color roleTertiaryOn = Colors.white;
  static Color roleErrorContainer = const Color(0xFF8C1D18);
  static Color roleErrorOn = Colors.white;

  /// Возвращает цвет-контейнер шапки для роли.
  static Color containerForRole(NodeColorRole role) {
    switch (role) {
      case NodeColorRole.surface:
        return roleSurfaceContainer;
      case NodeColorRole.primary:
        return rolePrimaryContainer;
      case NodeColorRole.secondary:
        return roleSecondaryContainer;
      case NodeColorRole.tertiary:
        return roleTertiaryContainer;
      case NodeColorRole.error:
        return roleErrorContainer;
    }
  }

  /// Возвращает контрастный «on»-цвет для роли (текст на шапке).
  static Color onContainerForRole(NodeColorRole role) {
    switch (role) {
      case NodeColorRole.surface:
        return roleSurfaceOn;
      case NodeColorRole.primary:
        return rolePrimaryOn;
      case NodeColorRole.secondary:
        return roleSecondaryOn;
      case NodeColorRole.tertiary:
        return roleTertiaryOn;
      case NodeColorRole.error:
        return roleErrorOn;
    }
  }

  /// Текущая яркость активной темы (для генерации тональных контейнеров).
  static Brightness brightness = Brightness.dark;

  /// Кэш сгенерированных тональных схем по seed-цвету, чтобы не пересчитывать
  /// палитру на каждый кадр отрисовки.
  static final Map<int, ColorScheme> _tonalCache = {};

  static ColorScheme _tonalSchemeFor(Color seed) {
    final key = (seed.value * 31) ^ brightness.index;
    return _tonalCache.putIfAbsent(
      key,
      () => ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
    );
  }

  /// Гармоничный M3-контейнер для произвольного seed-цвета. В отличие от
  /// 5 фиксированных ролей (производных от одного seed темы) это даёт
  /// РАЗНООБРАЗНЫЕ, но всё ещё тональные (не кислотные) цвета, адаптивные
  /// к light/dark.
  static Color tonalContainerFor(Color seed) =>
      _tonalSchemeFor(seed).primaryContainer;

  /// Контрастный «on»-цвет для [tonalContainerFor].
  static Color onTonalContainerFor(Color seed) =>
      _tonalSchemeFor(seed).onPrimaryContainer;

  static Color background = const Color(0xFF1A1A1A);
  static Color grid = const Color(0xFF2F2F2F);
  static Color nodeBody = const Color(0xFF1E1E1E);
  static Color nodeHeader = const Color(0xFF242424);
  static Color nodeBorder = const Color(0xFF343434);
  static Color nodeBorderHovered = const Color(0xFF8A8A8A);
  static Color nodeTitle = Colors.white;
  static Color nodePreview = const Color(0xB3FFFFFF);
  static Color anchorBorder = Colors.white;
  static Color accent = Colors.orange;
  static Color accentTarget = Colors.greenAccent;
  static Color shadow = const Color(0x33000000);
  static Color surface = const Color(0xFF1A1A1A);
  static Color commentBody = const Color(0xFF2A2A1E);
  static Color commentText = Colors.white;
  static Color selection = Colors.blue;
  static bool isDark = true;

  // --- Цвета связей (берутся из темы) ---
  static Color connectionContent = const Color(0xFF8FB6E0);
  static Color connectionTimer = const Color(0xFFE0C46C);
  static Color connectionScript = const Color(0xFFB39DDB);

  static void update(ColorScheme scheme) {
    isDark = scheme.brightness == Brightness.dark;
    brightness = scheme.brightness;
    background = scheme.surface;
    surface = scheme.surface;
    grid = Color.lerp(scheme.surface, scheme.onSurface, 0.12) ?? scheme.onSurface;
    nodeBody = scheme.surfaceContainerHigh;
    nodeHeader = scheme.surfaceContainerHighest;
    nodeBorder = scheme.outlineVariant;
    nodeBorderHovered = scheme.primary;
    nodeTitle = scheme.onSurface;
    nodePreview = scheme.onSurfaceVariant;
    anchorBorder = scheme.surface;
    accent = scheme.primary;
    accentTarget = scheme.tertiary;
    // Тени в «трушном» M3 на холсте не используем — глубину даёт тон
    // поверхности (surfaceContainer-уровни), а не drop shadow.
    shadow = const Color(0x00000000);
    // Заметка — нейтральная «бумага» (surfaceContainerHigh), а не
    // цветной secondaryContainer (который на тёплых темах болотится).
    commentBody = scheme.surfaceContainerHigh;
    commentText = scheme.onSurface;
    selection = scheme.primary;

    // --- Роли цвета нод: семантические M3-контейнеры ---
    roleSurfaceContainer = scheme.surfaceContainerHighest;
    roleSurfaceOn = scheme.onSurface;
    rolePrimaryContainer = scheme.primaryContainer;
    rolePrimaryOn = scheme.onPrimaryContainer;
    roleSecondaryContainer = scheme.secondaryContainer;
    roleSecondaryOn = scheme.onSecondaryContainer;
    roleTertiaryContainer = scheme.tertiaryContainer;
    roleTertiaryOn = scheme.onTertiaryContainer;
    roleErrorContainer = scheme.errorContainer;
    roleErrorOn = scheme.onErrorContainer;

    // --- Связи: приглушённо, в гамме темы ---
    connectionContent = scheme.outline;
    connectionTimer = scheme.tertiary;
    connectionScript = scheme.secondary;
  }
}

// ================================================================
// === ОБРАТНАЯ СОВМЕСТИМОСТЬ: маппинг старых ARGB-цветов нод на роли ===
// Старые квесты хранят node.color как «сырой» ARGB (из прежней
// палитры NodeColors). Чтобы они не выглядели кислотно, переводим
// сохранённый цвет в ближайшую семантическую роль по оттенку (hue).
// ================================================================
NodeColorRole nodeColorRoleFromLegacyColor(Color color) {
  final hsl = HSLColor.fromColor(color);
  // Очень тёмные/серые цвета (старый «dark») → нейтральная роль.
  if (hsl.saturation < 0.15 || hsl.lightness < 0.18) {
    return NodeColorRole.surface;
  }
  final hue = hsl.hue;
  // Красные/розовые → error.
  if (hue < 20 || hue >= 330) return NodeColorRole.error;
  // Оранжевые/жёлтые/янтарные → tertiary.
  if (hue < 70) return NodeColorRole.tertiary;
  // Зелёные/бирюзовые → secondary.
  if (hue < 200) return NodeColorRole.secondary;
  // Синие/голубые/фиолетовые → primary.
  return NodeColorRole.primary;
}

// ================================================================
// === МОДЕЛЬ НОДЫ (для UI) ===
// ================================================================
class Node {
  String id;
  String? chapterId;
  Offset position;
  Size size;
  Color color;
  String label;
  String description;
  Map<String, dynamic>? content;
  String? backgroundAssetId;
  String? backgroundAudioId;
  double? backgroundAudioVolume;
  String? scriptAssetId;
  double? timerDuration;
  String? defaultActionNodeId;
  bool? timerHidden;
  bool isStartNode;

  TextPainter? _titlePainter;
  TextPainter? _descPainter;
  bool _textCacheDirty = true;

  Node({
    required this.id,
    this.chapterId,
    required this.position,
    this.size = const Size(150, 150),
    required this.color,
    required this.label,
    required this.description,
    this.content,
    this.backgroundAssetId,
    this.backgroundAudioId,
    this.backgroundAudioVolume,
    this.scriptAssetId,
    this.timerDuration,
    this.defaultActionNodeId,
    this.timerHidden,
    this.isStartNode = false,
  });

  Rect get rect =>
      Rect.fromCenter(center: position, width: size.width, height: size.height);
  Offset get topAnchor => Offset(position.dx, position.dy - size.height / 2);
  Offset get bottomAnchor => Offset(position.dx, position.dy + size.height / 2);
  Offset get leftAnchor => Offset(position.dx - size.width / 2, position.dy);
  Offset get rightAnchor => Offset(position.dx + size.width / 2, position.dy);

  Offset getClosestAnchor(Offset point) {
    final anchors = [topAnchor, bottomAnchor, leftAnchor, rightAnchor];
    double minDist = double.infinity;
    Offset closest = position;
    for (final anchor in anchors) {
      final dist = (anchor - point).distance;
      if (dist < minDist) {
        minDist = dist;
        closest = anchor;
      }
    }
    return closest;
  }

  Node copyWith({
    String? id,
    String? chapterId,
    Offset? position,
    Size? size,
    Color? color,
    String? label,
    String? description,
    Map<String, dynamic>? content,
    String? backgroundAssetId,
    String? backgroundAudioId,
    double? backgroundAudioVolume,
    String? scriptAssetId,
    double? timerDuration,
    String? defaultActionNodeId,
    bool? timerHidden,
    bool? isStartNode,
  }) {
    return Node(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      position: position ?? this.position,
      size: size ?? this.size,
      color: color ?? this.color,
      label: label ?? this.label,
      description: description ?? this.description,
      content: content ?? this.content,
      backgroundAssetId: backgroundAssetId ?? this.backgroundAssetId,
      backgroundAudioId: backgroundAudioId ?? this.backgroundAudioId,
      backgroundAudioVolume:
          backgroundAudioVolume ?? this.backgroundAudioVolume,
      scriptAssetId: scriptAssetId ?? this.scriptAssetId,
      timerDuration: timerDuration ?? this.timerDuration,
      defaultActionNodeId: defaultActionNodeId ?? this.defaultActionNodeId,
      timerHidden: timerHidden ?? this.timerHidden,
      isStartNode: isStartNode ?? this.isStartNode,
    );
  }

  void ensureTextPainters(double maxWidth) {
    if (!_textCacheDirty && _titlePainter != null) return;
    _titlePainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: CanvasTheme.nodeTitle,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);

    final items = content?['items'] as List<dynamic>? ?? [];
    Map<String, dynamic>? firstText;
    for (final item in items) {
      if (item is Map && item['type'] == 'text') {
        firstText = Map<String, dynamic>.from(item);
        break;
      }
    }
    String previewText = description;
    if (firstText != null) {
      previewText = (firstText['text'] as String? ?? '').split('\n').first;
    }

    _descPainter = TextPainter(
      text: TextSpan(
        text: previewText,
        style: TextStyle(color: CanvasTheme.nodePreview, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    _textCacheDirty = false;
  }

  TextPainter? get titlePainter => _titlePainter;
  TextPainter? get descPainter => _descPainter;
  void invalidateTextCache() => _textCacheDirty = true;
  void dispose() {
    _titlePainter?.dispose();
    _descPainter?.dispose();
  }
}

// ================================================================
// === НОВЫЕ МОДЕЛИ: ГРУППЫ И КОММЕНТАРИИ ===
// ================================================================

class CanvasGroup {
  final String id;
  final String? chapterId; // <--- ДОБАВЛЕНО
  final String label;
  final Rect rect;
  final Color color;

  CanvasGroup({
    required this.id,
    this.chapterId,
    required this.label,
    required this.rect,
    required this.color,
  });

  CanvasGroup copyWith({
    String? label,
    Rect? rect,
    Color? color,
    String? chapterId,
  }) {
    return CanvasGroup(
      id: id,
      chapterId: chapterId ?? this.chapterId,
      label: label ?? this.label,
      rect: rect ?? this.rect,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapterId': chapterId,
    'label': label,
    'x': rect.left,
    'y': rect.top,
    'w': rect.width,
    'h': rect.height,
    'color': color.value,
  };

  factory CanvasGroup.fromJson(Map<String, dynamic> json) {
    return CanvasGroup(
      id: json['id'],
      chapterId: json['chapterId'],
      label: json['label'] ?? 'Group',
      rect: Rect.fromLTWH(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['w'] as num).toDouble(),
        (json['h'] as num).toDouble(),
      ),
      color: Color(json['color'] ?? 0xFF2196F3),
    );
  }
}

class CanvasComment {
  final String id;
  final String? chapterId; // <--- ДОБАВЛЕНО
  final String text;
  final Offset position;
  final Size size;

  CanvasComment({
    required this.id,
    this.chapterId,
    required this.text,
    required this.position,
    this.size = const Size(200, 150),
  });

  Rect get rect => position & size;

  CanvasComment copyWith({
    String? text,
    Offset? position,
    Size? size,
    String? chapterId,
  }) {
    return CanvasComment(
      id: id,
      chapterId: chapterId ?? this.chapterId,
      text: text ?? this.text,
      position: position ?? this.position,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapterId': chapterId,
    'text': text,
    'x': position.dx,
    'y': position.dy,
    'w': size.width,
    'h': size.height,
  };

  factory CanvasComment.fromJson(Map<String, dynamic> json) {
    return CanvasComment(
      id: json['id'],
      chapterId: json['chapterId'],
      text: json['text'] ?? '',
      position: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      size: Size(
        (json['w'] as num?)?.toDouble() ?? 200.0,
        (json['h'] as num?)?.toDouble() ?? 150.0,
      ),
    );
  }
}

class Connection {
  final String id;
  final Node fromNode;
  final Node toNode;
  final Color color;
  final bool isVirtual;
  final ConnectionKind kind;

  Connection({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.color = Colors.cyan,
    this.isVirtual = false,
    this.kind = ConnectionKind.content,
  });
}

enum ConnectionKind { content, timer, script }

class ConnectionGeometry {
  final Offset start;
  final Offset end;
  final Offset cp1;
  final Offset cp2;
  final Rect bounds;
  final double lane;
  const ConnectionGeometry({
    required this.start,
    required this.end,
    required this.cp1,
    required this.cp2,
    required this.bounds,
    required this.lane,
  });
}

// ================================================================
// === SPATIAL HASH ===
// ================================================================
class SpatialHash {
  final double cellSize;
  final Map<String, Set<Node>> _grid = {};
  SpatialHash({this.cellSize = 200});
  String _getKey(int x, int y) => '$x,$y';
  void clear() => _grid.clear();

  void insert(Node node) {
    final rect = node.rect;
    final minX = (rect.left / cellSize).floor();
    final minY = (rect.top / cellSize).floor();
    final maxX = (rect.right / cellSize).floor();
    final maxY = (rect.bottom / cellSize).floor();
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        final key = _getKey(x, y);
        _grid.putIfAbsent(key, () => {}).add(node);
      }
    }
  }

  Node? queryPoint(Offset point) {
    final x = (point.dx / cellSize).floor();
    final y = (point.dy / cellSize).floor();
    final cells = _grid[_getKey(x, y)];
    if (cells != null) {
      for (final node in cells.toList().reversed) {
        if (node.rect.contains(point)) return node;
      }
    }
    return null;
  }

  void rebuild(List<Node> nodes) {
    clear();
    for (final node in nodes) {
      insert(node);
    }
  }

  Set<Node> query(Rect rect) {
    final result = <Node>{};
    final minX = (rect.left / cellSize).floor();
    final minY = (rect.top / cellSize).floor();
    final maxX = (rect.right / cellSize).floor();
    final maxY = (rect.bottom / cellSize).floor();
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        final cells = _grid[_getKey(x, y)];
        if (cells != null) {
          result.addAll(cells);
        }
      }
    }
    return result;
  }
}

class Indicator {
  final IconData icon;
  final Color color;
  Indicator(this.icon, this.color);
}

class NodeRenderer {
  /// Высота шапки ноды — общая для тела ноды и её подписи.
  static const double headerHeight = 44.0;

  void drawNode(
    Canvas canvas,
    Node node, {
    required bool isSelected,
    required bool isHovered,
    required bool isConnectionStart,
    required bool isConnectionTarget,
    required bool isConnectionMode,
    required List<Connection> allConnections,
    bool isDimmed = false,
    bool hasValidationIssue = false,
    bool showDetails = true,
  }) {
    final rect = node.rect;
    const radius = Radius.circular(18);
    final rrect = RRect.fromRectAndRadius(rect, radius);
    final opacity = isDimmed ? 0.3 : 1.0;

    // Тени убраны: в каноничном M3 глубину на холсте задаёт тон
    // поверхности (surfaceContainer-уровни), а не drop shadow.

    // 1. Тело карточки (surfaceContainerHigh)
    final bodyColor = CanvasTheme.nodeBody.withOpacity(opacity);
    canvas.drawRRect(rrect, Paint()..color = bodyColor);

    // 2. Шапка ноды — это M3 filled-card.
    // Цвет вычисляется из node.color: для нейтральных/тёмных цветов
    // используем surface-роль темы, для остальных — генерируем
    // ГАРМОНИЧНЫЙ tonal-контейнер из самого цвета (ColorScheme.fromSeed).
    // Это даёт РАЗНООБРАЗНЫЕ, но не кислотные цвета, адаптивные к теме.
    final headerColor = _neutralHeader(node).withOpacity(isDimmed ? 0.35 : 1.0);

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, headerHeight),
      Paint()..color = headerColor,
    );
    canvas.restore();

    // 4. Граница / состояния
    Color borderColor = CanvasTheme.nodeBorder;
    double borderWidth = 1.0;
    if (isConnectionTarget) {
      borderColor = CanvasTheme.accentTarget;
      borderWidth = 3;
    } else if (isConnectionStart) {
      borderColor = CanvasTheme.accent;
      borderWidth = 3;
    } else if (isSelected) {
      borderColor = CanvasTheme.accent;
      borderWidth = 2.5;
    } else if (isHovered) {
      borderColor = CanvasTheme.nodeBorderHovered;
      borderWidth = 2;
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    if ((isHovered || isConnectionStart) &&
        isConnectionMode &&
        !isDimmed &&
        showDetails) {
      _drawAnchors(canvas, node);
    }

    // Подпись рисует художник (см. `drawNodeTitle`): она нужна и на большом
    // отдалении, но нормируется бюджетом на кадр.
    if (!showDetails) return;
    _drawDescription(canvas, node, rect, headerHeight, opacity);
    _drawIndicators(
      canvas,
      node,
      rect,
      allConnections,
      opacity,
      hasValidationIssue: hasValidationIssue,
    );
  }

  /// Заголовок ноды. Вызывается отдельно от тела ноды: художник решает, сколько
  /// подписей влезает в кадр (`CanvasFrameCost.budgetFor`).
  void drawNodeTitle(Canvas canvas, Node node, {bool isDimmed = false}) {
    _drawTitle(
      canvas,
      node,
      node.rect,
      headerHeight,
      isDimmed ? 0.3 : 1.0,
      _headerTextColor(node),
    );
  }

  static Color _neutralHeader(Node node) {
    final hsl = HSLColor.fromColor(node.color);
    final bool isNeutral = hsl.saturation < 0.15 || hsl.lightness < 0.18;
    return isNeutral
        ? CanvasTheme.containerForRole(NodeColorRole.surface)
        : CanvasTheme.tonalContainerFor(node.color);
  }

  /// Цвет заголовка — канонический M3 «on-container» для роли.
  static Color _headerTextColor(Node node) {
    final hsl = HSLColor.fromColor(node.color);
    final bool isNeutral = hsl.saturation < 0.15 || hsl.lightness < 0.18;
    return isNeutral
        ? CanvasTheme.onContainerForRole(NodeColorRole.surface)
        : CanvasTheme.onTonalContainerFor(node.color);
  }

  void _drawTitle(
    Canvas canvas,
    Node node,
    Rect rect,
    double headerHeight,
    double opacity,
    Color titleColor,
  ) {
    final padding = 14.0;
    final titleLeft = rect.left + padding;
    final titleWidth = node.size.width - 2 * padding;
    node.ensureTextPainters(node.size.width - 2 * padding);

    final titlePainter = node.titlePainter;
    if (titlePainter == null) return;
    titlePainter.textAlign = TextAlign.left;
    titlePainter.text = TextSpan(
      text: (titlePainter.text as TextSpan).text,
      style: titlePainter.text!.style!.copyWith(
        color: titleColor.withOpacity(opacity),
      ),
    );
    titlePainter.layout(maxWidth: titleWidth);
    titlePainter.paint(
      canvas,
      Offset(titleLeft, rect.top + (headerHeight - titlePainter.height) / 2),
    );
  }

  void _drawDescription(
    Canvas canvas,
    Node node,
    Rect rect,
    double headerHeight,
    double opacity,
  ) {
    final descWidth = node.size.width - 2 * 14.0;
    node.ensureTextPainters(descWidth);

    final descPainter = node.descPainter;
    if (descPainter == null) return;
    final oldColor = descPainter.text!.style!.color!;
    descPainter.text = TextSpan(
      text: (descPainter.text as TextSpan).text,
      style: descPainter.text!.style!.copyWith(
        color: oldColor.withOpacity(opacity),
      ),
    );
    descPainter.layout(maxWidth: descWidth);
    descPainter.paint(
      canvas,
      Offset(rect.left + 14, rect.top + headerHeight + 12),
    );
  }

  void _drawIndicators(
    Canvas canvas,
    Node node,
    Rect rect,
    List<Connection> allConnections,
    double opacity, {
    bool hasValidationIssue = false,
  }) {
    final List<Indicator> indicators = [];
    final contentItems = (node.content?['items'] as List<dynamic>? ?? []);

    // Иконки-индикаторы используют единую приглушённую M3 tonal-палитру
    // (tone ~70) вместо ярких *Accent-цветов — это убирает «радужную кашу»
    // и держит холст в одном визуальном тоне.
    const indicatorStart = Color(0xFF7FCFA0); // green 70 — старт
    const indicatorStop = Color(0xFFE49592); // red 70 — финал
    const indicatorTimer = Color(0xFFE0C46C); // amber 70 — таймер
    const indicatorScript = Color(0xFF8FB6E0); // blue 70 — скрипт
    const indicatorImage = Color(0xFF7FCFB6); // teal 70 — изображение
    const indicatorAudio = Color(0xFFD79BC0); // pink 70 — аудио
    const indicatorButton = Color(0xFFB39DDB); // violet 70 — кнопка

    if (node.isStartNode) {
      indicators.add(
        Indicator(Icons.play_circle_filled_rounded, indicatorStart),
      );
    }
    if (!allConnections.any((c) => c.fromNode.id == node.id) &&
        !node.isStartNode) {
      indicators.add(Indicator(Icons.stop_circle_rounded, indicatorStop));
    }

    if (node.timerDuration != null && node.timerDuration! > 0) {
      indicators.add(Indicator(Icons.timer_rounded, indicatorTimer));
    }
    if (contentItems.any((i) => i['type'] == 'script')) {
      indicators.add(Indicator(Icons.code_rounded, indicatorScript));
    }

    if (contentItems.any((i) => i['type'] == 'text')) {
      indicators.add(
        Indicator(Icons.text_fields_rounded, CanvasTheme.nodePreview),
      );
    }
    if (contentItems.any((i) => i['type'] == 'image')) {
      indicators.add(Indicator(Icons.image_rounded, indicatorImage));
    }
    if (contentItems.any((i) => i['type'] == 'audio')) {
      indicators.add(Indicator(Icons.audiotrack_rounded, indicatorAudio));
    }
    if (contentItems.any((i) => i['type'] == 'button')) {
      indicators.add(Indicator(Icons.smart_button_rounded, indicatorButton));
    }
    if (hasValidationIssue) {
      indicators.add(Indicator(Icons.error_rounded, indicatorStop));
    }

    if (indicators.isEmpty) return;

    final iconSize = 15.0;
    final iconGap = 8.0;
    final hPad = 8.0;
    final pillHeight = 26.0;
    final totalIcons =
        indicators.length * iconSize + (indicators.length - 1) * iconGap;
    final pillWidth = totalIcons + hPad * 2;

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left + (rect.width - pillWidth) / 2,
        rect.bottom - pillHeight - 10,
        pillWidth,
        pillHeight,
      ),
      const Radius.circular(13),
    );

    // M3-«таблетка» под иконками индикаторов
    canvas.drawRRect(
      pillRect,
      Paint()..color = CanvasTheme.nodeHeader.withOpacity(opacity * 0.9),
    );
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = CanvasTheme.nodeBorder.withOpacity(opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    double startX = pillRect.left + hPad;
    final iconY = pillRect.top + (pillHeight - iconSize) / 2;

    for (final indicator in indicators) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(indicator.icon.codePoint),
          style: TextStyle(
            fontSize: iconSize,
            fontFamily: indicator.icon.fontFamily,
            color: indicator.color.withOpacity(opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      iconPainter.paint(canvas, Offset(startX, iconY));
      startX += iconSize + iconGap;
    }
  }

  void _drawAnchors(Canvas canvas, Node node) {
    final anchors = [
      node.topAnchor,
      node.bottomAnchor,
      node.leftAnchor,
      node.rightAnchor,
    ];
    final anchorPaint = Paint()
      ..color = CanvasTheme.accent
      ..style = PaintingStyle.fill;
    final anchorBorderPaint = Paint()
      ..color = CanvasTheme.anchorBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final anchor in anchors) {
      canvas.drawCircle(anchor, 6, anchorPaint);
      canvas.drawCircle(anchor, 6, anchorBorderPaint);
    }
  }
}
