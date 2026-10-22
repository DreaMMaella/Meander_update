import 'package:canvas_app/core/utils/date_format.dart';
import 'package:canvas_app/features/forums/models/forum_models.dart';
import 'package:canvas_app/features/forums/providers/forum_provider.dart';
import 'package:canvas_app/features/forums/screens/forum_lobby_screen.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';
import 'package:canvas_app/features/profile/screens/profile_screen.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/load_more_error_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

/// Каталог сообществ: полки, куда ложатся обсуждения.
///
/// Порядок сортировки по умолчанию — «активные», а не «новые»: каталог,
/// отсортированный по дате создания, показывает кладбище, и человек приходит
/// туда, где сейчас кто-то говорит.
class ForumsCatalogScreen extends ConsumerStatefulWidget {
  const ForumsCatalogScreen({super.key, this.initialScope = 'all'});

  /// `mine` — вход из «Моих»: человек хочет свои полки, а не витрину.
  final String initialScope;

  @override
  ConsumerState<ForumsCatalogScreen> createState() =>
      _ForumsCatalogScreenState();
}

class _ForumsCatalogScreenState extends ConsumerState<ForumsCatalogScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late String _scope = widget.initialScope;
  String _sort = 'active';
  String _query = '';
  String _viewerId = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _viewerId = prefs.getString('user_id') ?? '');
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _key =>
      ForumsCatalogNotifier.buildKey(scope: _scope, sort: _sort, query: _query);

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      ref.read(forumsCatalogProvider(_key).notifier).loadMore();
    }
  }

  void _setFilters({String? scope, String? sort, String? query}) {
    setState(() {
      _scope = scope ?? _scope;
      _sort = sort ?? _sort;
      _query = query ?? _query;
    });
  }

  Future<void> _open(Forum forum) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ForumLobbyScreen(slug: forum.slug)),
    );
    if (!mounted) return;
    // Тема, вступление или настройки могли измениться, пока человек был в
    // лобби — витрине надо обновиться, а не врать до первого тапа.
    ref.read(forumsCatalogProvider(_key).notifier).load(silent: true);
  }

  Future<void> _createForum() async {
    if (_viewerId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Нужно войти в аккаунт'))));
      return;
    }
    final forum = await showAppDialog<Forum>(
      context: context,
      builder: (ctx) => _CreateForumDialog(
        catalogKey: _key,
        onCreated: (created) => Navigator.pop(ctx, created),
      ),
    );
    if (forum == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ForumLobbyScreen(slug: forum.slug)),
    );
    if (!mounted) return;
    ref.read(forumsCatalogProvider(_key).notifier).load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(forumsCatalogProvider(_key));

    return Scaffold(
      backgroundColor: scheme.surface,
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _createForum,
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(forumsCatalogProvider(_key).notifier).load(silent: true),
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar.large(
                title: Text(tr('Сообщества')),
                pinned: true,
                backgroundColor: scheme.surface,
                surfaceTintColor: scheme.surfaceTint,
              ),
              SliverToBoxAdapter(
                child: AdaptiveContent(
                  maxWidth: 900,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _filters(context),
                      const SizedBox(height: 8),
                      _body(context, state),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onSubmitted: (value) => _setFilters(query: value),
            decoration: InputDecoration(
              hintText: tr('Поиск по названию'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        _setFilters(query: '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: scheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Два независимых выбора, и показывать их десятью одинаковыми чипами
          // нельзя: «Мои · Активные» читается как один ряд, хотя это разные оси.
          _segmented(
            values: [
              if (_viewerId.isNotEmpty)
                ButtonSegment(
                  value: 'mine',
                  label: Text(tr('Мои')),
                  icon: const Icon(Icons.bookmarks_rounded, size: 16),
                ),
              ButtonSegment(
                value: 'all',
                label: Text(tr('Все')),
                icon: const Icon(Icons.public_rounded, size: 16),
              ),
            ],
            selected: {_scope},
            onChanged: (selection) => _setFilters(scope: selection.first),
          ),
          const SizedBox(height: 8),
          _segmented(
            values: [
              ButtonSegment(
                value: 'active',
                label: Text(tr('Активные')),
                icon: const Icon(Icons.whatshot_rounded, size: 16),
              ),
              ButtonSegment(
                value: 'popular',
                label: Text(tr('Крупные')),
                icon: const Icon(Icons.groups_rounded, size: 16),
              ),
              ButtonSegment(
                value: 'new',
                label: Text(tr('Новые')),
                icon: const Icon(Icons.fiber_new_rounded, size: 16),
              ),
            ],
            selected: {_sort},
            onChanged: (selection) => _setFilters(sort: selection.first),
          ),
        ],
      ),
    );
  }

  /// `SegmentedButton` в горизонтальной прокрутке: на узком экране три подписи
  /// не влезают, а `Wrap` из сегментов ломает саму контролу.
  Widget _segmented({
    required List<ButtonSegment<String>> values,
    required Set<String> selected,
    required ValueChanged<Set<String>> onChanged,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicWidth(
        child: SegmentedButton<String>(
          segments: values,
          selected: selected,
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: Theme.of(context).textTheme.labelMedium,
          ),
          onSelectionChanged: onChanged,
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ForumsCatalogState state) {
    if (state.isLoading && state.forums.isEmpty) {
      return Column(
        children: [for (var i = 0; i < 4; i++) _shimmerRow(context)],
      );
    }

    if (state.error != null && state.forums.isEmpty) {
      return _block(
        context,
        icon: Icons.error_outline_rounded,
        title: tr('Не удалось загрузить сообщества'),
        subtitle: state.error!,
        action: FilledButton.tonalIcon(
          onPressed: () =>
              ref.read(forumsCatalogProvider(_key).notifier).load(),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(tr('Повторить')),
        ),
      );
    }

    if (state.forums.isEmpty) {
      return _block(
        context,
        icon: Icons.forum_outlined,
        title: _scope == 'mine'
            ? tr('Ты пока ни в одном сообществе')
            : tr('Здесь пусто'),
        subtitle: _scope == 'mine'
            ? tr('Вступи в любое сообщество из каталога или создай своё — оно появится здесь')
            : _query.isEmpty
            ? tr('Сообщество — это место, где обсуждают тему или квест. Создай первое, и оно появится здесь')
            : trf('По запросу «{_query}» ничего не нашлось', {'_query': _query}),
        action: _scope == 'mine'
            ? FilledButton.tonal(
                onPressed: () => _setFilters(scope: 'all'),
                child: Text(tr('Открыть каталог')),
              )
            : null,
      );
    }

    return Column(
      children: [
        for (final forum in state.forums)
          _ForumTile(
            forum: forum,
            onOpen: () => _open(forum),
            onOpenCreator: forum.creator == null || forum.creator!.id.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: forum.creator!.id),
                    ),
                  ),
          ),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.error != null)
          // Список уже на экране — ошибку догрузки показываем хвостом, чтобы
          // вставшая загрузка не выглядела как «больше сообществ нет».
          LoadMoreErrorTile(
            onRetry: () =>
                ref.read(forumsCatalogProvider(_key).notifier).loadMore(),
          ),
      ],
    );
  }

  Widget _block(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }

  Widget _shimmerRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerHigh,
      child: Container(
        height: 92,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class _ForumTile extends StatelessWidget {
  const _ForumTile({
    required this.forum,
    required this.onOpen,
    this.onOpenCreator,
  });

  final Forum forum;
  final VoidCallback onOpen;
  final VoidCallback? onOpenCreator;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final creator = forum.creator;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: forum.joined
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    forum.isQuestForum
                        ? Icons.sports_esports_rounded
                        : Icons.group_work_rounded,
                    color: forum.joined
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              forum.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (forum.isRestricted) ...[
                            const SizedBox(width: 4),
                            Tooltip(
                              message: tr('Пишут только участники'),
                              child: Icon(
                                Icons.lock_rounded,
                                size: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (forum.description?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 3),
                        Text(
                          forum.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (creator != null) ...[
                            InkWell(
                              onTap: onOpenCreator,
                              borderRadius: BorderRadius.circular(8),
                              child: Row(
                                children: [
                                  CosmeticAvatar(
                                    frame: cosmeticById(
                                      creator.equipped.avatarFrame,
                                    ),
                                    radius: 9,
                                    avatarUrl: creator.avatarUrl,
                                    placeholderColor:
                                        scheme.surfaceContainerHighest,
                                  ),
                                  const SizedBox(width: 5),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 130,
                                    ),
                                    child: CosmeticNameText(
                                      name: creator.name,
                                      def: cosmeticById(
                                        creator.equipped.nameStyle,
                                      ),
                                      style: textTheme.labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            trf('{p0} уч. · {p1} топи.', {'p0': forum.memberCount, 'p1': forum.topicsCount}),
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (forum.lastActivityAt != null)
                      Text(
                        formatRelativeTime(forum.lastActivityAt!),
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (forum.joined)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          tr('Ты здесь'),
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Создание сообщества. Порог стажа и лимит на сутки проверяет сервер —
/// диалог только показывает его объяснение, а не угадывает право самому.
class _CreateForumDialog extends ConsumerStatefulWidget {
  const _CreateForumDialog({required this.catalogKey, required this.onCreated});

  final String catalogKey;
  final void Function(Forum forum) onCreated;

  @override
  ConsumerState<_CreateForumDialog> createState() => _CreateForumDialogState();
}

class _CreateForumDialogState extends ConsumerState<_CreateForumDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _slug = TextEditingController();
  bool _restricted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Кнопка «Создать» смотрит на длину названия в build: без подписки на поля
    // она не становится активной, и создание выглядит отказом.
    _name.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _slug.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref
        .read(forumsCatalogProvider(widget.catalogKey).notifier)
        .create(
          name: _name.text,
          description: _description.text,
          slug: _slug.text,
          isRestricted: _restricted,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      widget.onCreated(result.forum!);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.error ?? tr('Не удалось создать сообщество'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('Новое сообщество')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              maxLength: ForumLimits.maxNameChars,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Название')),
            ),
            TextField(
              controller: _description,
              maxLength: ForumLimits.maxDescriptionChars,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: tr('Описание'),
                hintText: tr('О чём здесь будут говорить'),
              ),
            ),
            TextField(
              controller: _slug,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: tr('Адрес (необязательно)'),
                hintText: 'goblins',
                helperText:
                    tr('Латиница, цифры и дефис. Если пусто — придумаем из названия.'),
                helperMaxLines: 2,
              ),
            ),
            SwitchListTile(
              value: _restricted,
              onChanged: (value) => setState(() => _restricted = value),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Пишут только участники')),
              subtitle: Text(
                tr('Читать по-прежнему сможет каждый'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            Text(
              trf('За сутки можно создать {p0} сообщества, и только если ты с нами {p1} дней или публиковал квест.', {'p0': ForumLimits.maxCreatedByDay, 'p1': ForumLimits.minAccountAgeDaysToCreate}),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(tr('Отмена')),
        ),
        FilledButton(
          onPressed: _busy || _name.text.trim().length < 3 ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr('Создать')),
        ),
      ],
    );
  }
}
