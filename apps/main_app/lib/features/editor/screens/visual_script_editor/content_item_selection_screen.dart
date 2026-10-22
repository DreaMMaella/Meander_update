import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/features/editor/providers/node_provider.dart';
import 'package:canvas_app/features/editor/screens/visual_script_editor/content_item_picker_model.dart';
import 'package:mnd_core/models/content_item.dart';
import 'package:mnd_core/utils/quest_paths.dart';
import 'package:canvas_app/features/editor/widgets/quest_resource_thumb.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

/// Пикер элементов контента квеста.
///
/// Квест — это не одна сцена: картинки живут в нодах, в рядах и слоях стеков, и
/// их в квесте десятки и сотни. Поэтому список плоский и короткий только на
/// скриншоте: здесь поиск по любому слову, фильтр по ноде и типу и сетка
/// миниатюр, где цель видно по картинке, а не по номеру строки.
///
/// [nodeId] — ограничить одной нодой (но все равно можно выйти на весь квест:
/// скрипт живёт отдельно от сцены). [allowedTypes] — фильтр по типу айтема,
/// [selectedItemId] — подсветить то, что уже выбрано.
class ContentItemSelectionScreen extends ConsumerStatefulWidget {
  final String questId;
  final String? nodeId;
  final List<String>? allowedTypes;
  final String? selectedItemId;

  const ContentItemSelectionScreen({
    super.key,
    required this.questId,
    this.nodeId,
    this.allowedTypes,
    this.selectedItemId,
  });

  @override
  ConsumerState<ContentItemSelectionScreen> createState() =>
      _ContentItemSelectionScreenState();
}

class _ContentItemSelectionScreenState
    extends ConsumerState<ContentItemSelectionScreen> {
  static const String _gridPrefKey = 'content_picker_grid';

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// null — весь квест.
  String? _scopeNodeId;
  String? _scopeType;
  bool _isGrid = true;

  late Future<Map<String, String>> _namesFuture;

  /// СборкаChoices дорогая на квесте из сотни нод, поэтому переиспользуем её,
  /// пока провайдер и имена ресурсов те же объекты.
  List<ContentItemChoice>? _cachedChoices;
  List<SavedNode>? _cachedNodes;
  Map<String, String>? _cachedNames;

  @override
  void initState() {
    super.initState();
    _scopeNodeId = widget.nodeId;
    _namesFuture = _loadResourceNames();
    _loadViewPreference();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isGrid = prefs.getBool(_gridPrefKey) ?? true);
  }

  Future<void> _toggleView() async {
    setState(() => _isGrid = !_isGrid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gridPrefKey, _isGrid);
  }

  Future<Map<String, String>> _loadResourceNames() async {
    final path = QuestPaths.metadata(widget.questId);
    if (!await FileStorage.exists(path)) return const {};
    return parseResourceNames(await FileStorage.readJsonFile(path));
  }

  List<ContentItemChoice> _choicesFor(
    List<SavedNode> nodes,
    Map<String, String> names,
  ) {
    final cached = _cachedChoices;
    if (cached != null &&
        identical(nodes, _cachedNodes) &&
        identical(names, _cachedNames)) {
      return cached;
    }
    final choices = buildContentItemChoices(
      nodes: [
        for (final node in nodes)
          PickerNode(id: node.id, title: node.title, items: _itemsOf(node)),
      ],
      allowedTypes: widget.allowedTypes,
      resourceNames: names,
    );
    _cachedChoices = choices;
    _cachedNodes = nodes;
    _cachedNames = names;
    return choices;
  }

  List<ContentItem> _itemsOf(SavedNode node) {
    final raw = node.content['items'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>) ContentItem.fromJson(item),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Text(tr('Элементы контента')),
        actions: [
          IconButton(
            tooltip: _isGrid ? tr('Списком') : tr('Сеткой'),
            onPressed: _toggleView,
            icon: Icon(
              _isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
          ),
        ],
      ),
      body: ref
          .watch(allQuestNodesProvider(widget.questId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(
                trf('Ошибка загрузки нод: {p0}', {'p0': friendlyError(err)}),
                style: TextStyle(color: scheme.error),
              ),
            ),
            data: (nodes) => FutureBuilder<Map<String, String>>(
              future: _namesFuture,
              builder: (context, snapshot) {
                final all = _choicesFor(nodes, snapshot.data ?? const {});
                return _Body(
                  questId: widget.questId,
                  all: all,
                  query: _query,
                  scopeNodeId: _scopeNodeId,
                  scopeType: _scopeType,
                  isGrid: _isGrid,
                  selectedItemId: widget.selectedItemId,
                  constrainedToNode: widget.nodeId,
                  onQuery: (value) => setState(() => _query = value),
                  searchController: _searchController,
                  onScopeNode: (id) => setState(() => _scopeNodeId = id),
                  onScopeType: (type) => setState(() => _scopeType = type),
                  onPick: (choice) => Navigator.pop(context, choice),
                  onResetFilters: () => setState(() {
                    _query = '';
                    _searchController.clear();
                    _scopeNodeId = widget.nodeId;
                    _scopeType = null;
                  }),
                );
              },
            ),
          ),
    );
  }
}

class _Body extends StatelessWidget {
  final String questId;
  final List<ContentItemChoice> all;
  final String query;
  final String? scopeNodeId;
  final String? scopeType;
  final bool isGrid;
  final String? selectedItemId;
  final String? constrainedToNode;
  final ValueChanged<String> onQuery;
  final TextEditingController searchController;
  final ValueChanged<String?> onScopeNode;
  final ValueChanged<String?> onScopeType;
  final ValueChanged<ContentItemChoice> onPick;
  final VoidCallback onResetFilters;

  const _Body({
    required this.questId,
    required this.all,
    required this.query,
    required this.scopeNodeId,
    required this.scopeType,
    required this.isGrid,
    required this.selectedItemId,
    required this.constrainedToNode,
    required this.searchController,
    required this.onQuery,
    required this.onScopeNode,
    required this.onScopeType,
    required this.onPick,
    required this.onResetFilters,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Поиск идёт первым: чипы нод и типов показывают, сколько айтемов останется
    // с текущим запросом, а не его же и фильтруют.
    final searched = query.trim().isEmpty
        ? all
        : searchContentItemChoices(all, query);
    final byType = scopeType == null
        ? searched
        : searched
              .where((c) => c.item.type == scopeType)
              .toList(growable: false);
    final nodes = groupByNode(searched);
    final visible = scopeNodeId == null
        ? byType
        : byType.where((c) => c.nodeId == scopeNodeId).toList(growable: false);
    final types = countByType(scopeNodeId == null ? searched : byType);

    if (all.isEmpty) {
      return _EmptyState(
        icon: Icons.layers_clear_rounded,
        title: tr('В квесте ещё нет элементов контента'),
        hint:
            tr('Добавьте картинку, текст или кнопку в ноду — они появятся здесь.'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: searchController,
            onChanged: onQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('Поиск по имени, ноде, типу…'),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: onResetFilters,
                      tooltip: tr('Сбросить'),
                    ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _PickerChip(
                label: trf('Все ноды · {p0}', {'p0': searched.length}),
                icon: Icons.public_rounded,
                selected: scopeNodeId == null,
                onTap: () => onScopeNode(null),
              ),
              // В одной ноде чип «эта нода» и так по умолчанию включён — дублировать
              // его незачем, но выйти на весь квест нужно.
              if (constrainedToNode != null)
                _PickerChip(
                  label: tr('Эта нода'),
                  icon: Icons.push_pin_rounded,
                  selected: scopeNodeId == constrainedToNode,
                  onTap: () => onScopeNode(constrainedToNode),
                ),
              for (final node in nodes)
                if (node.id != constrainedToNode)
                  _PickerChip(
                    label: '${node.title} · ${node.count}',
                    icon: Icons.account_tree_outlined,
                    selected: scopeNodeId == node.id,
                    onTap: () => onScopeNode(node.id),
                  ),
            ],
          ),
        ),
        if (types.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _PickerChip(
                    label: tr('Все типы'),
                    icon: Icons.category_outlined,
                    selected: scopeType == null,
                    onTap: () => onScopeType(null),
                  ),
                  for (final entry in types.entries)
                    _PickerChip(
                      label:
                          '${contentItemTypeLabel(entry.key)} · ${entry.value}',
                      icon: contentItemTypeIcon(entry.key),
                      selected: scopeType == entry.key,
                      onTap: () => onScopeType(entry.key),
                    ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Text(
                trf('Показано {p0}', {'p0': visible.length}),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              if (scopeNodeId != null)
                Expanded(
                  child: Text(
                    ' · ${_nodeTitle(nodes, scopeNodeId!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(
                  icon: Icons.search_off_rounded,
                  title: tr('Ничего не подошло'),
                  hint: tr('Смените запрос или сбросьте фильтры.'),
                  actionLabel: tr('Сбросить фильтры'),
                  onAction: onResetFilters,
                )
              : isGrid
              ? _Grid(
                  questId: questId,
                  choices: visible,
                  onPick: onPick,
                  selectedItemId: selectedItemId,
                )
              : _List(
                  questId: questId,
                  choices: visible,
                  onPick: onPick,
                  selectedItemId: selectedItemId,
                ),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  final String questId;
  final List<ContentItemChoice> choices;
  final ValueChanged<ContentItemChoice> onPick;
  final String? selectedItemId;

  const _Grid({
    required this.questId,
    required this.choices,
    required this.onPick,
    this.selectedItemId,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 150).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final choice = choices[index];
            return _ChoiceCard(
              questId: questId,
              choice: choice,
              selected: choice.item.id == selectedItemId,
              onTap: () => onPick(choice),
            );
          },
        );
      },
    );
  }
}

class _List extends StatelessWidget {
  final String questId;
  final List<ContentItemChoice> choices;
  final ValueChanged<ContentItemChoice> onPick;
  final String? selectedItemId;

  const _List({
    required this.questId,
    required this.choices,
    required this.onPick,
    this.selectedItemId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: choices.length,
      itemBuilder: (context, index) {
        final choice = choices[index];
        final selected = choice.item.id == selectedItemId;
        return ListTile(
          onTap: () => onPick(choice),
          selected: selected,
          selectedTileColor: scheme.secondaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: SizedBox(
            width: 52,
            height: 52,
            child: _ChoiceThumb(
              questId: questId,
              choice: choice,
              radius: 10,
              iconSize: 24,
            ),
          ),
          title: Text(
            choice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${choice.location} · ${choice.typeLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (choice.hasFormula)
                _Badge(
                  icon: Icons.functions_rounded,
                  tooltip: tr('Источник — формула'),
                ),
              if (choice.isHidden)
                _Badge(
                  icon: Icons.visibility_off_rounded,
                  tooltip: tr('Скрыт в игре'),
                ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String questId;
  final ContentItemChoice choice;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.questId,
    required this.choice,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ChoiceThumb(questId: questId, choice: choice),
              Align(
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          choice.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          choice.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(top: 6, left: 6, child: _TypePill(choice: choice)),
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (choice.hasFormula)
                      _Badge(
                        icon: Icons.functions_rounded,
                        tooltip: tr('Источник — формула'),
                      ),
                    if (choice.isHidden)
                      _Badge(
                        icon: Icons.visibility_off_rounded,
                        tooltip: tr('Скрыт в игре'),
                      ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final ContentItemChoice choice;

  const _TypePill({required this.choice});

  @override
  Widget build(BuildContext context) {
    final icon = contentItemTypeIcon(choice.item.type);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: contentItemTypeColor(choice.item.type)),
            const SizedBox(width: 4),
            Text(
              choice.typeLabel,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String tooltip;

  const _Badge({required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon, size: 13, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Миниатюра айтема: картинка с диска либо иконка типа.
class _ChoiceThumb extends StatelessWidget {
  final String questId;
  final ContentItemChoice choice;
  final double radius;
  final double iconSize;

  const _ChoiceThumb({
    required this.questId,
    required this.choice,
    this.radius = 0,
    this.iconSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return QuestResourceThumb(
      questId: questId,
      source: choice.thumbnailSource,
      radius: radius,
      fallback: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            contentItemTypeIcon(choice.item.type),
            size: iconSize,
            color: contentItemTypeColor(choice.item.type),
          ),
        ),
      ),
    );
  }
}

/// Заголовок ноды в строке «Показано N · …». Пустой, если с текущим поиском в
/// ней ничего не осталось — иначе подпись ссылалась бы на заголовок, которого
/// среди чипов нет.
String _nodeTitle(
  List<({String id, String title, int count})> nodes,
  String id,
) {
  for (final node in nodes) {
    if (node.id == id) return node.title;
  }
  return '';
}

class _PickerChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PickerChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.transparent : scheme.outlineVariant,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
