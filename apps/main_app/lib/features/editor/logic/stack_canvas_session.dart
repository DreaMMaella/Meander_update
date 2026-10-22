import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'package:canvas_app/features/editor/logic/stack_canvas_ops.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/models/content_item_model.dart';

// ============================================================================
//  СЕССИЯ РЕДАКТИРОВАНИЯ СТЕКА
//
//  Всё, что меняет документ (дети, высота, фон) и выделение, живёт здесь, а не
//  в State экрана: экрану остаются гесты и отрисовка. Так правки становятся
//  тестируемыми чистыми функциями, а undo/redo и мультивыбор не расползаются по
//  жестовым обработчикам (именно так разъехался UI админ-действий в хабе).
//
//  Модель отмены — снимки всего документа, а не обратные операции: детей в
//  стеке десятки, копия дешёвая, а обратная операция для каждой правки — это
//  N мест, где можно ошибиться.
// ============================================================================

/// Тип правки — для склейки мелкий однотипных шагов (стрелки, слайдер) в одну
/// запись истории и для подсказки «Отменить: …».
enum StackEditKind {
  nudge,
  move,
  resize,
  add,
  remove,
  duplicate,
  paste,
  reorder,
  zOrder,
  align,
  style,
  text,
  group,
  guide,
}

class StackEdit {
  final StackEditKind kind;

  /// Человекочитаемое имя для подсказки кнопки отмены.
  final String label;

  /// Снимок ДО правки — то, что вернёт undo.
  final ContentItem before;

  final DateTime at;

  const StackEdit({
    required this.kind,
    required this.label,
    required this.before,
    required this.at,
  });
}

/// Ключ склейки: одинаковый `kind` в пределах окна времени — одна правка.
const Duration kStackEditCoalesceWindow = Duration(milliseconds: 700);

/// Глубина истории: дальше память начинает стоить дороже пользы.
const int kStackEditHistoryLimit = 120;

/// Поля холста стека. Границы и дефолты — из модели (`mnd_core`), чтобы
/// редактор не запрещал и не дорисовывал то, по-другому считает плеер:
/// раньше редактор не давал холст уже 240 px при том, что игра умела от 60.
const double kStackHeightMin = kStackCanvasHeightMin;
const double kStackHeightMax = kStackCanvasHeightMax;
const double kStackWidthMin = kStackCanvasWidthMin;
const double kStackWidthMax = kStackCanvasWidthMax;

/// Квант позиции направляющей в px стека: линии хранятся округлёнными до него,
/// поэтому две «разные» направляющие в одной точке невозможны, а поиск по
/// значению при перетаскивании остаётся однозначным.
const double kStackGuideQuantum = 0.5;

class StackCanvasSession extends ChangeNotifier {
  ContentItem _stack;
  final List<StackEdit> _undo = [];
  final List<StackEdit> _redo = [];

  /// Выделение по id, а не по индексу: индекс живёт до первой вставки/удаления.
  final Set<String> _selected = <String>{};

  /// Снимок до копий Alt-драга, пока жест не завершился: см. [beginDuplicateDrag].
  ContentItem? _duplicateDragBefore;

  /// Выделение до Alt-драга: копии его забрали, а отмена жеста обязана
  /// вернуть оригиналы.
  List<String> _duplicateDragSelection = const [];

  final DateTime Function() _clock;

  StackCanvasSession({required ContentItem stack, DateTime Function()? clock})
    : _stack = stack,
      _clock = clock ?? DateTime.now;

  ContentItem get stack => _stack;
  List<ContentItem> get children => _stack.children ?? const [];

  /// Высота холста — из модели: тот же дефолт и те же пределы, что у плеера.
  double get stackHeight => _stack.stackCanvasHeight;

  /// Ширина холста: то, относительно чего ребёнок считает `anchor * W`, и то,
  /// во что стек ужмётся в игре. Дефолт — дизайн-ширина.
  double get stackWidth => _stack.stackCanvasWidth;

  Set<String> get selection => Set<String>.unmodifiable(_selected);
  bool isSelected(String id) => _selected.contains(id);

  /// Первый выделенный id — удобной точкой отсчёта для панелей.
  String? get primaryId => _selected.isEmpty ? null : _selected.first;

  ContentItem? get primaryChild {
    final id = primaryId;
    if (id == null) return null;
    for (final child in children) {
      if (child.id == id) return child;
    }
    return null;
  }

  List<String> get selectedIdsInZOrder =>
      children.where((c) => _selected.contains(c.id)).map((c) => c.id).toList();

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// Только для тестов и отладки: глубина стека отмен.
  int get undoDepth => _undo.length;

  int? indexOf(String id) {
    final list = children;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == id) return i;
    }
    return null;
  }

  // ── Правки ───────────────────────────────────────────────────────

  /// Заменяет документ целиком, записав предыдущее состояние в историю.
  ///
  /// [coalesce] — склеить с предыдущей правкой того же [kind] (стрелки,
  /// перетаскивание ползунка): иначе 40 нажатий на стрелку дают 40 шагов undo.
  void commit(
    ContentItem next, {
    required StackEditKind kind,
    String? label,
    bool coalesce = false,
  }) {
    if (identical(next, _stack)) return;
    final editLabel = label ?? _defaultLabel(kind);
    if (coalesce && _shouldCoalesce(kind, editLabel)) {
      // Затягиваем окно: длинный драг или серия стрелок остаются одним шагом,
      // даже если длятся больше окна.
      final last = _undo.removeLast();
      _undo.add(
        StackEdit(
          kind: last.kind,
          label: editLabel,
          before: last.before,
          at: _clock(),
        ),
      );
      _redo.clear();
      _stack = next;
      _pruneSelection();
      notifyListeners();
      return;
    }
    _undo.add(
      StackEdit(
        kind: kind,
        label: editLabel,
        before: _stack,
        at: _clock(),
      ),
    );
    if (_undo.length > kStackEditHistoryLimit) _undo.removeAt(0);
    _redo.clear();
    _stack = next;
    _pruneSelection();
    notifyListeners();
  }

  /// Правка одного ребёнка (геометрия, текст, стиль) — остальное как было.
  void commitChild(
    String id,
    ContentItem Function(ContentItem child) update, {
    required StackEditKind kind,
    String? label,
    bool coalesce = false,
  }) {
    final index = indexOf(id);
    if (index == null) return;
    final next = List<ContentItem>.from(children);
    next[index] = update(next[index]);
    commit(
      _stack.copyWith(children: next),
      kind: kind,
      label: label,
      coalesce: coalesce,
    );
  }

  // ── Групповые правки ─────────────────────────────────────────────

  /// Удалить выделенных детей одним шагом истории. Id, которых больше нет,
  /// выпадают из выделения сами — `_pruneSelection`.
  void removeSelected() {
    final ids = Set<String>.from(_selected);
    if (ids.isEmpty) return;
    final next = [
      for (final c in children)
        if (!ids.contains(c.id)) c,
    ];
    if (next.length == children.length) return;
    commit(
      _stack.copyWith(children: next),
      kind: StackEditKind.remove,
      label: ids.length == 1
          ? tr('удаление')
          : trf('удаление {n} объектов', {'n': ids.length}),
    );
  }

  /// Копии выделенных детей со смещением; копии забирают выделение, как в
  /// Figma, — иначе Ctrl+D дважды подряд клонирует одну и ту же исходную
  /// копию поверх самой себя.
  void duplicateSelected({
    required String Function() idFactory,
    Offset offset = const Offset(16, 16),
    double? width,
  }) {
    final ids = selectedIdsInZOrder;
    if (ids.isEmpty) return;
    final idSet = ids.toSet();
    final renamed = <String, String>{};
    final next = <ContentItem>[];
    final copies = <String>[];
    for (final c in children) {
      next.add(c);
      if (!idSet.contains(c.id)) continue;
      final copyId = idFactory();
      copies.add(copyId);
      next.add(_copyChild(c, copyId: copyId, renamed: renamed));
    }
    _selected
      ..clear()
      ..addAll(copies);
    commit(
      _stack.copyWith(
        children: translateChildren(
          children: next,
          ids: copies.toSet(),
          delta: offset,
          height: stackHeight,
          width: width ?? stackWidth,
        ),
      ),
      kind: StackEditKind.duplicate,
    );
  }

  /// Alt-драг: копии появляются в документе сразу, но шаг истории откроется
  /// только в [finishDuplicateDrag]. Иначе «дубликат» и «перемещение» были бы
  /// двумя нажатиями undo вместо одного. Копии забирают выделение — именно их
  /// и поведёт жест.
  List<String> beginDuplicateDrag({required String Function() idFactory}) {
    final ids = selectedIdsInZOrder;
    if (ids.isEmpty) return const [];
    final idSet = ids.toSet();
    final renamed = <String, String>{};
    final next = <ContentItem>[];
    final copies = <String>[];
    for (final c in children) {
      next.add(c);
      if (!idSet.contains(c.id)) continue;
      final copyId = idFactory();
      copies.add(copyId);
      next.add(_copyChild(c, copyId: copyId, renamed: renamed));
    }
    _duplicateDragBefore = _stack;
    _duplicateDragSelection = List.of(_selected);
    _stack = _stack.copyWith(children: next);
    _selected
      ..clear()
      ..addAll(copies);
    notifyListeners();
    return copies;
  }

  /// Итог Alt-драга: сдвиг копий на [delta] и одна запись истории — тем,
  /// что было до появления копий.
  void finishDuplicateDrag(Offset delta) {
    final before = _duplicateDragBefore;
    _duplicateDragBefore = null;
    _duplicateDragSelection = const [];
    if (before == null) return;
    final next = _stack.copyWith(
      children: translateChildren(
        children: children,
        ids: _selected,
        delta: delta,
        width: stackWidth,
        height: stackHeight,
      ),
    );
    _undo.add(
      StackEdit(
        kind: StackEditKind.duplicate,
        label: _defaultLabel(StackEditKind.duplicate),
        before: before,
        at: _clock(),
      ),
    );
    if (_undo.length > kStackEditHistoryLimit) _undo.removeAt(0);
    _redo.clear();
    _stack = next;
    notifyListeners();
  }

  /// Escape посреди Alt-драга: копии были только превью жеста — шаг истории
  /// ещё не открыт. Возвращаем и документ, и выделение оригиналов.
  void abortDuplicateDrag() {
    final before = _duplicateDragBefore;
    _duplicateDragBefore = null;
    final selection = _duplicateDragSelection;
    _duplicateDragSelection = const [];
    if (before == null) return;
    _stack = before;
    _selected
      ..clear()
      ..addAll(selection);
    notifyListeners();
  }

  /// Вставить копии (Ctrl+V): новые id, передний план, смещение — иначе
  /// вставка легла бы ровно под оригинал и её нельзя было бы поймать.
  /// Копии забирают выделение, как дубликат.
  void insertCopies(
    List<ContentItem> items, {
    required String Function() idFactory,
    Offset offset = Offset.zero,
  }) {
    if (items.isEmpty) return;
    final copies = <ContentItem>[];
    final ids = <String>[];
    final renamed = <String, String>{};
    for (final item in items) {
      final copyId = idFactory();
      ids.add(copyId);
      copies.add(_copyChild(item, copyId: copyId, renamed: renamed));
    }
    _selected
      ..clear()
      ..addAll(ids);
    commit(
      _stack.copyWith(
        children: [
          ...children,
          if (offset == Offset.zero)
            ...copies
          else
            ...translateChildren(
              children: copies,
              ids: ids.toSet(),
              delta: offset,
              width: stackWidth,
              height: stackHeight,
            ),
        ],
      ),
      kind: StackEditKind.paste,
      label: items.length == 1
          ? tr('вставка')
          : trf('вставка {n} объектов', {'n': items.length}),
    );
  }

  /// Поднять/опустить выделенных детей, сохраняя их взаимный порядок.
  void zOrder({required bool toFront}) {
    final ids = selectedIdsInZOrder.toSet();
    if (ids.isEmpty || ids.length == children.length) return;
    final moved = [
      for (final c in children)
        if (ids.contains(c.id)) c,
    ];
    final rest = [
      for (final c in children)
        if (!ids.contains(c.id)) c,
    ];
    commit(
      _stack.copyWith(
        children: toFront ? [...rest, ...moved] : [...moved, ...rest],
      ),
      kind: StackEditKind.zOrder,
    );
  }

  /// Поднять/опустить ребёнка на одну позицию по z-порядку — стрелки панели
  /// слоёв. `forward: true` ближе к переднему плану (к концу списка).
  /// Возвращает false, если id неизвестен или двигать некуда: панель по этому
  /// же признаку гасит неактивную стрелку.
  bool moveChild(String id, {required bool forward}) {
    final index = indexOf(id);
    if (index == null) return false;
    final target = forward ? index + 1 : index - 1;
    if (target < 0 || target >= children.length) return false;
    final next = List<ContentItem>.from(children);
    next[index] = next[target];
    next[target] = children[index];
    commit(
      _stack.copyWith(children: next),
      kind: StackEditKind.reorder,
      label: tr('порядок слоёв'),
    );
    return true;
  }

  /// Ширина холста. Правила те же, что у [setStackHeight]: ребёнок держит
  /// отступы от своих якорей, поэтому при 360 px объект, прижатый к правому
  /// краю, остаётся у правого края.
  ///
  /// [scaleContent] — вместе с холстом масштабируются слои и направляющие:
  /// размер макета меняют, чтобы он остался тем же макетом, а не набором
  /// объектов в старых пикселях. По умолчанию правится только рамка.
  bool setStackWidth(
    double width, {
    StackContentScale scaleContent = StackContentScale.keep,
  }) {
    // Целое число px: драг за край холста давал 289.98624028596936 в json,
    // а поле ввода показывало «290» — документ расходился с тем, что видно.
    final next = width.clamp(kStackWidthMin, kStackWidthMax).roundToDouble();
    if ((next - stackWidth).abs() < 0.5) return false;
    commit(
      _canvasResized(next, stackHeight, scaleContent: scaleContent),
      kind: StackEditKind.resize,
      label: scaleContent == StackContentScale.keep
          ? tr('ширина стека')
          : tr('размер стека'),
    );
    return true;
  }

  /// Высота холста. Якоря детей считаются от краёв, поэтому холст тянется,
  /// а объекты остаются при своих отступах — править их геометрию не нужно.
  /// Меньше клада или то же значение — правки нет (false).
  bool setStackHeight(
    double height, {
    StackContentScale scaleContent = StackContentScale.keep,
  }) {
    final next = height.clamp(kStackHeightMin, kStackHeightMax).roundToDouble();
    if ((next - stackHeight).abs() < 0.5) return false;
    commit(
      _canvasResized(stackWidth, next, scaleContent: scaleContent),
      kind: StackEditKind.resize,
      label: scaleContent == StackContentScale.keep
          ? tr('высота стека')
          : tr('размер стека'),
    );
    return true;
  }

  /// Новый документ с другим размером холста. Содержимое пересчитывается тут же
  /// и в том же `commit`: одним шагом, чтобы undo вернул и рамку, и геометрию
  /// сразу — два отдельных шага означали бы «отменил размер, объекты остались
  /// новыми».
  ContentItem _canvasResized(
    double width,
    double height, {
    required StackContentScale scaleContent,
  }) {
    if (scaleContent == StackContentScale.keep) {
      return _stack.copyWith(stackWidth: width, stackHeight: height);
    }
    final factors = stackContentFactors(
      fromWidth: stackWidth,
      fromHeight: stackHeight,
      toWidth: width,
      toHeight: height,
      mode: scaleContent,
    );
    final children = _stack.children;
    return _stack.copyWith(
      stackWidth: width,
      stackHeight: height,
      children: children == null
          ? null
          : scaleStackContent(
              children: children,
              fromWidth: stackWidth,
              fromHeight: stackHeight,
              toWidth: width,
              toHeight: height,
              mode: scaleContent,
            ),
      guidesX: scaleStackGuides(guides: guidesX, factor: factors.x),
      guidesY: scaleStackGuides(guides: guidesY, factor: factors.y),
    );
  }

  // ── Направляющие ────────────────────────────────────────────────

  /// Направляющие редактора в px от левого/верхнего края холста: [guidesX] —
  /// вертикальные, [guidesY] — горизонтальные. Лежат в самом стеке как
  /// редакторский слой: плеер их не рисует и не должен.
  List<double> get guidesX => _stack.guidesX ?? const [];
  List<double> get guidesY => _stack.guidesY ?? const [];

  /// Добавить направляющую по x (vertical=true) или по y. Уже стоит там же —
  /// правки нет: лишний клик по линейке не должен множить шаги undo.
  bool addGuide({required bool vertical, required double position}) {
    final current = _guides(vertical);
    final at = _guidePosition(vertical, position);
    if (current.contains(at)) return false;
    return _commitGuides(vertical, [...current, at]);
  }

  /// Переставить направляющую. Ищем по значению, а не по индексу: список
  /// отсортирован, и пересортица посреди драга уронила бы перетаскивание на
  /// чужую линию.
  bool moveGuide({
    required bool vertical,
    required double from,
    required double to,
  }) {
    final current = _guides(vertical);
    final index = current.indexOf(_guidePosition(vertical, from));
    if (index < 0) return false;
    final at = _guidePosition(vertical, to);
    if (at == current[index]) return false;
    final rest = [...current]..removeAt(index);
    // Сошлись две линии — остаётся одна: дубликат в документе бесполезен.
    return _commitGuides(vertical, rest.contains(at) ? rest : [...rest, at]);
  }

  bool removeGuide({required bool vertical, required double position}) {
    final current = _guides(vertical);
    final index = current.indexOf(_guidePosition(vertical, position));
    if (index < 0) return false;
    return _commitGuides(vertical, [...current]..removeAt(index));
  }

  List<double> _guides(bool vertical) => vertical ? guidesX : guidesY;

  /// Позиция на сетке кванта и в пределах холста: за его край направляющую
  /// уносить нечего, а без округления две «разные» линии встанут в одной точке.
  /// Поиск по значению идёт уже через неё — индекс после сортировки ничего не
  /// обещает.
  double _guidePosition(bool vertical, double raw) {
    final max = vertical ? stackWidth : stackHeight;
    final clamped = raw.clamp(0.0, max);
    return (clamped / kStackGuideQuantum).round() * kStackGuideQuantum;
  }

  /// Хранятся направляющие отсортированными — так линейке и рендеру не нужно
  /// думать о порядке, а поиск по значению остаётся однозначным.
  bool _commitGuides(bool vertical, List<double> guides) {
    final current = _guides(vertical);
    final sorted = [...guides]..sort();
    if (listEquals(sorted, current)) return false;
    final next = vertical
        ? _stack.copyWith(guidesX: sorted, clearGuidesX: sorted.isEmpty)
        : _stack.copyWith(guidesY: sorted, clearGuidesY: sorted.isEmpty);
    commit(
      next,
      kind: StackEditKind.guide,
      label: vertical
          ? tr('вертикальная направляющая')
          : tr('горизонтальная направляющая'),
    );
    return true;
  }

  // ── Группы слоёв ─────────────────────────────────────────────────

  /// Группа — минимум два слоя: из одного она ничего не даёт, кроме путаницы.
  bool get canGroup => _selected.length >= 2;

  /// Есть ли среди выделенных слой с именем группы — по этому же признаку
  /// меню и горячая клавиша понимают, активна ли «Разгруппировать».
  bool get canUngroup =>
      children.any((c) => c.groupName != null && _selected.contains(c.id));

  ContentItem? childById(String id) {
    final index = indexOf(id);
    return index == null ? null : children[index];
  }

  /// Имя группы, с которой работает панель: группа первого выделенного слоя.
  /// При выделении из двух групп правка достаёт ту, что взяли первой.
  String? get selectedGroupName => primaryChild?.groupName;

  /// Имена всех групп документа — по ним строится счётчик «Группа N».
  Set<String> get groupNames => {
    for (final c in children)
      if (c.groupName != null) c.groupName!,
  };

  /// Id членов группы, к которой принадлежит слой; у слоя вне группы — он сам.
  List<String> groupIdsOf(String id) {
    final name = childById(id)?.groupName;
    if (name == null) return [id];
    return [
      for (final c in children)
        if (c.groupName == name) c.id,
    ];
  }

  /// «Группа N» — первое свободное имя. [extra] учитываются имена, которые
  /// ещё не в документе, но уже выданы в текущей операции (копии группы).
  String nextGroupName({Set<String> extra = const {}}) {
    final taken = {...groupNames, ...extra};
    String name(int n) => trf('Группа {p0}', {'p0': n});
    var n = 1;
    while (taken.contains(name(n))) {
      n++;
    }
    return name(n);
  }

  /// Ctrl+G: выделенные слои получают общее имя группы. Меньше двух выделять
  /// нечего — группа из одного слоя только мешает.
  /// Возвращает имя группы либо null, если правки не было.
  String? groupSelected() {
    final ids = selectedIdsInZOrder;
    if (ids.length < 2) return null;
    final name = nextGroupName();
    final idSet = ids.toSet();
    commit(
      _stack.copyWith(
        children: [
          for (final c in children)
            if (idSet.contains(c.id)) c.copyWith(groupName: name) else c,
        ],
      ),
      kind: StackEditKind.group,
    );
    return name;
  }

  /// Ctrl+Shift+G: снять имя со всех выделенных слоёв — и с тех, что попали в
  /// выделение вместе с группой, иначе «разгруппировать» оставило бы хвост.
  bool ungroupSelected() {
    if (!canUngroup) return false;
    final ids = _selected;
    commit(
      _stack.copyWith(
        children: [
          for (final c in children)
            if (ids.contains(c.id) && c.groupName != null)
              c.copyWith(clearGroupName: true)
            else
              c,
        ],
      ),
      kind: StackEditKind.group,
      label: tr('разгруппировка'),
    );
    return true;
  }

  /// Разгруппировать группу, в которую входит слой [id]: имя снимается со
  /// всех её слоёв. Выделение здесь ни при чём — меню слоя вызывают и по
  /// невыделенному объекту, а попытка «выделить и разгруппировать» через
  /// [select] схлопнула бы группу до одного слоя и оставила бы хвост.
  bool ungroupLayer(String id) {
    final name = childById(id)?.groupName;
    if (name == null) return false;
    commit(
      _stack.copyWith(
        children: [
          for (final c in children)
            if (c.groupName == name) c.copyWith(clearGroupName: true) else c,
        ],
      ),
      kind: StackEditKind.group,
      label: tr('разгруппировка'),
    );
    return true;
  }

  /// Переименовать группу: [from] — теперешнее имя, [to] — новое. Имя и есть
  /// идентичность группы, поэтому совпало с другой группой — они сливаются
  /// (отдельной операции «переместить слой в группу» в модели нет).
  /// Пустое или то же самое имя правки не делает.
  bool renameGroup(String from, String to) {
    final name = to.trim();
    if (name.isEmpty || name == from) return false;
    if (!children.any((c) => c.groupName == from)) return false;
    commit(
      _stack.copyWith(
        children: [
          for (final c in children)
            if (c.groupName == from) c.copyWith(groupName: name) else c,
        ],
      ),
      kind: StackEditKind.group,
      label: tr('имя группы'),
    );
    return true;
  }

  /// Дать слою имя (или снять его пустой строкой). Имя нужно панели слоёв:
  /// без него подпись строится из текста/имени файла, и в списке десять
  /// «Картинка» подряд. Одно нажатие «Переименовать» — один шаг истории.
  bool renameLayer(String id, String to) {
    final child = childById(id);
    if (child == null) return false;
    final name = to.trim();
    if (name == (child.layerName ?? '')) return false;
    commitChild(
      id,
      (c) => name.isEmpty
          ? c.copyWith(clearLayerName: true)
          : c.copyWith(layerName: name),
      kind: StackEditKind.text,
      label: tr('имя слоя'),
    );
    return true;
  }

  /// Копия слоя для дубликата/вставки. Группа у копии всегда новая: копия
  /// всей группы становится своей группой ([renamed] держит соответствие
  /// «старое имя → новое», чтобы несколько слоёв одной группы получили одно
  /// имя), а слой, скопированный из группы в одиночку, остаётся один в своей.
  /// В исходную группу копия не попадает ни в каком виде — иначе дубликат
  /// был бы привязан к оригиналам.
  ///
  /// Имя слоя копия тоже теряет: два «Шапка» в списке слоёв различить
  /// нельзя, а подписи из текста/файла у копий всегда разные.
  ContentItem _copyChild(
    ContentItem src, {
    required String copyId,
    required Map<String, String> renamed,
  }) {
    final name = src.groupName;
    if (name == null) return src.copyWith(id: copyId, clearLayerName: true);
    return src.copyWith(
      id: copyId,
      clearLayerName: true,
      groupName: renamed[name] ??= nextGroupName(extra: renamed.values.toSet()),
    );
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    // Ctrl+Z посреди Alt-драга: снимок копий больше не актуален, и завершать
    // им историю нельзя.
    _duplicateDragBefore = null;
    _duplicateDragSelection = const [];
    final edit = _undo.removeLast();
    _redo.add(
      StackEdit(
        kind: edit.kind,
        label: edit.label,
        before: _stack,
        at: _clock(),
      ),
    );
    _stack = edit.before;
    _pruneSelection();
    notifyListeners();
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final edit = _redo.removeLast();
    _undo.add(
      StackEdit(
        kind: edit.kind,
        label: edit.label,
        before: _stack,
        at: _clock(),
      ),
    );
    _stack = edit.before;
    _pruneSelection();
    notifyListeners();
    return true;
  }

  /// Склейка: тот же тип правки, та же цель и предыдущая запись свежая. Цель
  /// важна: без неё два разных ползунка, дёрнутых подряд (прозрачность →
  /// поворот), склеивались в один шаг и отменялись вместе. Подсказка
  /// переписывается на последнюю метку, чтобы «Отменить: сдвиг» не превращалось
  /// в «Отменить: дубликат» посреди серии шагов.
  bool _shouldCoalesce(StackEditKind kind, String label) {
    if (_undo.isEmpty) return false;
    final last = _undo.last;
    if (last.kind != kind || last.label != label) return false;
    return _clock().difference(last.at) <= kStackEditCoalesceWindow;
  }

  /// Метка правки для подсказки undo/redo: язык подключается на месте, чтобы
  /// ключ перевода оставался литералом и его видел сканер покрытия.
  static String _defaultLabel(StackEditKind kind) => switch (kind) {
    StackEditKind.nudge => tr('сдвиг'),
    StackEditKind.move => tr('перемещение'),
    StackEditKind.resize => tr('изменение размера'),
    StackEditKind.add => tr('добавление'),
    StackEditKind.remove => tr('удаление'),
    StackEditKind.duplicate => tr('дубликат'),
    StackEditKind.paste => tr('вставка'),
    StackEditKind.reorder => tr('перестановка'),
    StackEditKind.zOrder => tr('порядок слоёв'),
    StackEditKind.align => tr('выравнивание'),
    StackEditKind.style => tr('оформление'),
    StackEditKind.text => tr('текст'),
    StackEditKind.group => tr('группировка'),
    StackEditKind.guide => tr('направляющая'),
  };

  // ── Выделение ────────────────────────────────────────────────────

  void select(String? id, {bool additive = false}) {
    if (id == null) {
      clearSelection();
      return;
    }
    if (additive) {
      // Снять выделение можно и с заблокированного — иначе layer-панель
      // заперла бы объект в выделении намертво.
      if (_selected.remove(id)) {
        _selected.removeAll(groupIdsOf(id));
        notifyListeners();
        return;
      }
      if (!_selectable(id)) return;
      _selected.addAll(_groupToSelect(id));
    } else {
      // Клик по слою берёт всю группу, а повторный — сужает выделение до
      // одного слоя: иначе группа становится клеткой, из которой не выбраться.
      // На канвасе этот путь закрыт сам (тап по выделенному не перетирает
      // выделение, чтобы можно было начать драг), поэтому он для панели слоёв.
      if (_selected.contains(id) && _selected.containsAll(_groupToSelect(id))) {
        _selected
          ..clear()
          ..add(id);
        notifyListeners();
        return;
      }
      if (!_selectable(id)) return;
      _selected
        ..clear()
        ..addAll(_groupToSelect(id));
    }
    notifyListeners();
  }

  /// Слой вместе с его группой, но только из выделяемых членов: замок не должен
  /// превращаться в способ протащить заблокированный слой в выделении.
  List<String> _groupToSelect(String id) =>
      groupIdsOf(id).where(_selectable).toList();

  /// Выделяемый ли слой: заблокированные не попадают ни в один способ
  /// выделения, поэтому ни drag, ни стрелки, ни Delete до них не доходят.
  bool _selectable(String id) {
    final index = indexOf(id);
    return index != null && !children[index].locked;
  }

  /// Выделить диапазон по z-порядку между [anchor] и [id] (Shift+клик).
  void selectRange(String id) {
    final anchor = primaryId;
    if (anchor == null || anchor == id) {
      select(id);
      return;
    }
    final a = indexOf(anchor);
    final b = indexOf(id);
    if (a == null || b == null) return;
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    _selected
      ..clear()
      ..addAll(
        children.sublist(lo, hi + 1).where((c) => !c.locked).map((c) => c.id),
      );
    notifyListeners();
  }

  /// Результат рамки выделения: [additive] — добавить к существующему
  /// выделению (Shift+драг), [subtractive] — вычесть (Alt+драг), иначе —
  /// заменить. Рамка, зацепившая один слой группы, берёт группу целиком: иначе
  /// «выделил и перетащил» разъединяло бы то, что пользователь только что
  /// собрал вместе — и вычитывает она тоже группу целиком.
  void selectMany(
    Iterable<String> ids, {
    bool additive = false,
    bool subtractive = false,
  }) {
    final selected = {
      for (final id in ids)
        if (_selectable(id)) ..._groupToSelect(id),
    };
    if (additive) {
      _selected.addAll(selected);
    } else if (subtractive) {
      _selected.removeAll(selected);
    } else {
      _selected
        ..clear()
        ..addAll(selected);
    }
    notifyListeners();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll(
        children.where((c) => !c.isHidden && !c.locked).map((c) => c.id),
      );
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// После удаления/undo — забыть id, которых больше нет. Заблокированный
  /// слой выпадает отсюда же: поставить замок на уже выделенный объект —
  /// нормально, оставить его в выделении — значит дать стрелкам и Delete
  /// обход блокировки.
  void _pruneSelection() {
    if (_selected.isEmpty) return;
    final alive = {
      for (final c in children)
        if (!c.locked) c.id,
    };
    _selected.removeWhere((id) => !alive.contains(id));
  }
}
