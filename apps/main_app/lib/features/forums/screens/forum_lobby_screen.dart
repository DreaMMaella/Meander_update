import 'package:canvas_app/core/utils/date_format.dart';
import 'package:canvas_app/features/community/screens/post_comments_screen.dart';
import 'package:canvas_app/features/forums/models/forum_models.dart';
import 'package:canvas_app/features/forums/providers/forum_provider.dart';
import 'package:canvas_app/features/forums/screens/forum_topic_composer_screen.dart';
import 'package:canvas_app/features/forums/widgets/forum_topic_tile.dart';
import 'package:canvas_app/features/market/screens/quest_market_details_screen.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_model.dart';
import 'package:canvas_app/features/profile/cosmetics/cosmetic_widgets.dart';
import 'package:canvas_app/features/profile/screens/profile_screen.dart';
import 'package:canvas_app/shared/dialogs/account_gate.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/load_more_error_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

/// Лобби сообщества: шапка, модераторы и полка топиков.
///
/// Форум — это не новый вид контента, а полка для уже существующих постов,
/// поэтому тап по топику открывает привычный экран комментариев: ответы,
/// лайки и картинки достались форуму бесплатно.
class ForumLobbyScreen extends ConsumerStatefulWidget {
  const ForumLobbyScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<ForumLobbyScreen> createState() => _ForumLobbyScreenState();
}

class _ForumLobbyScreenState extends ConsumerState<ForumLobbyScreen> {
  final ScrollController _scroll = ScrollController();

  /// С какой ширины сообщество встаёт в две колонки. Ниже — одной строкой
  /// 760 + 344 не помещаются с полями, и правая колонка только украдкой
  /// съела бы место у ленты.
  static const double _railBreakpoint = 1160;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      ref.read(forumLobbyProvider(widget.slug).notifier).loadMore();
    }
  }

  Future<void> _openTopic(ForumTopic topic) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostCommentsScreen(post: topic.toWallPost()),
      ),
    );
    if (!mounted) return;
    // Ответы и лайки в треде меняются, пока человек там — счётчики в ленте
    // обязаны честно перечитаться.
    ref.read(forumLobbyProvider(widget.slug).notifier).load(silent: true);
  }

  Future<void> _writeTopic() async {
    // Редактор отворялся и гостю: он печатал топик целиком, жал
    // «Опубликовать» и получал сырой 401 вместо сохранённого текста.
    final hasAccount = await ensureAccount(
      context,
      why:
          tr('Топики обсуждают авторы с аккаунтом — ответ должен кому-то принадлежать. Войдите на вкладке «Вход».'),
    );
    if (!hasAccount || !mounted) return;
    // Ответ здесь не нужен: редактор публикует топик через тот же провайдер
    // лобби, и список перечитывается в нём же. Ошибку редактор показывает сам,
    // чтобы не выбрасывать написанное.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForumTopicComposerScreen(slug: widget.slug),
      ),
    );
  }

  Future<String?> _toggleTopicLike(ForumTopic topic) async {
    // Плюшка на чужом топике выглядела живой и у гостя: тап, анимация,
    // откат — и текст ошибки про «Unauthorized» вместо входа.
    final hasAccount = await ensureAccount(
      context,
      why:
          tr('Отметить топик может только автор с аккаунтом. Войдите на вкладке «Вход», и сердечко останется гореть.'),
    );
    if (!hasAccount) return null;
    return ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .toggleTopicLike(topic);
  }

  Future<void> _toggleJoin() async {
    final hasAccount = await ensureAccount(
      context,
      why:
          tr('В сообщество вступают из-под аккаунта — подписки держатся на профиле. Войдите на вкладке «Вход».'),
    );
    if (!hasAccount || !mounted) return;
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .toggleJoin();
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  void _onMenu(String value) {
    switch (value) {
      case 'settings':
        _openSettings();
      case 'bans':
        _openBans();
      case 'report':
        _report();
    }
  }

  Future<void> _report() async {
    final reason = await _askReason(
      context,
      title: tr('Жалоба на сообщество'),
      hint: tr('Что здесь не так?'),
      confirmLabel: tr('Отправить'),
      mustFill: true,
    );
    if (reason == null || !mounted) return;
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .report(reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? tr('Жалоба отправлена — её разберёт команда Meander'),
        ),
      ),
    );
  }

  void _openSettings() {
    showAdaptiveSheet(
      context: context,
      title: tr('Настройки сообщества'),
      maxWidth: 460,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ForumSettingsSheet(slug: widget.slug),
    );
  }

  void _openBans() {
    showAdaptiveSheet(
      context: context,
      title: tr('Ограничения'),
      maxWidth: 460,
      showDragHandle: true,
      builder: (_) => _ForumBansSheet(slug: widget.slug),
    );
  }

  Future<void> _removeTopic(ForumTopic topic) async {
    final reason = await _askReason(
      context,
      title: tr('Снять топик?'),
      hint: tr('Причина — она уйдёт автору в уведомление'),
      confirmLabel: tr('Снять'),
    );
    if (reason == null || !mounted) return;
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .removeTopic(topic.id, reason: reason, title: topic.title);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _banAuthor(ForumPerson person) async {
    final reason = await _askReason(
      context,
      title: trf('Ограничить {p0}', {'p0': person.name}),
      hint: tr('За что — человек увидит это в уведомлении'),
      confirmLabel: tr('Ограничить'),
    );
    if (reason == null || !mounted) return;
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .ban(person, reason: reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              trf('{p0} не сможет писать в сообщество; снять — в «Ограничениях»', {'p0': person.name}),
        ),
      ),
    );
  }

  Future<void> _appointModerator(ForumPerson person) async {
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .addModerator(person.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? trf('{p0} — теперь модератор сообщества', {'p0': person.name})),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(forumLobbyProvider(widget.slug));
    final forum = state.forum;

    final canWrite =
        forum != null &&
        !forum.banned &&
        (state.canModerate || !forum.isRestricted || forum.joined);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(forum?.name ?? tr('Сообщество')),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        actions: [
          // Жалоба доступна всем: модератором человек себя считает сам, и
          // прятать единственный канал на него — значит оставить форум без
          // обратной связи.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: tr('Сообщество'),
            onSelected: _onMenu,
            itemBuilder: (_) => [
              if (state.canModerate)
                PopupMenuItem(
                  value: 'settings',
                  child: Text(tr('Настройки сообщества')),
                ),
              if (state.canModerate)
                PopupMenuItem(value: 'bans', child: Text(tr('Ограничения'))),
              PopupMenuItem(value: 'report', child: Text(tr('Пожаловаться'))),
            ],
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _writeTopic,
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('Обсуждение')),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref
              .read(forumLobbyProvider(widget.slug).notifier)
              .load(silent: true),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Правая колонка — только когда есть куда: ~760 на ленту, 320 на
              // карточку и поля. Уже — прежняя одноколоночная версия, шапка
              // остаётся над лентой.
              if (constraints.maxWidth < _railBreakpoint) {
                return _feed(context, state, forum, headerInFlow: true);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _feed(context, state, forum, headerInFlow: false),
                  ),
                  SizedBox(
                    width: 344,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 24, 24),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(
                              forum: forum,
                              mods: state.mods,
                              canModerate: state.canModerate,
                              onToggleJoin: _toggleJoin,
                            ),
                            if (forum != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: _RulesCard(forum: forum),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Лента сообщества: шапка (когда она не в правой колонке), порядок
  /// сортировки и сами топики. Один и тот же скролл на узком и широком окне,
  /// чтобы подгрузка по скроллу не завелась от раскладки.
  Widget _feed(
    BuildContext context,
    ForumLobbyState state,
    Forum? forum, {
    required bool headerInFlow,
  }) {
    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: AdaptiveContent(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                if (headerInFlow)
                  _Header(
                    forum: forum,
                    mods: state.mods,
                    canModerate: state.canModerate,
                    onToggleJoin: _toggleJoin,
                  ),
                if (forum != null && forum.banned) _BannedBanner(forum: forum),
                const SizedBox(height: 16),
                _sorts(context, state.sort),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: AdaptiveContent(maxWidth: 900, child: _topics(context, state)),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  /// Порядок выдачи топиков. `SegmentedButton`, а не россыпь чипов: выбор один
  /// из трёх, а три `ChoiceChip` на узком экране спорили за ширину и перезали
  /// строку сортировки над лентой.
  Widget _sorts(BuildContext context, String sort) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicWidth(
        child: SegmentedButton<String>(
          selected: {sort},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: Theme.of(context).textTheme.labelMedium,
          ),
          segments: [
            for (final value in ForumSorts.values)
              ButtonSegment(
                value: value,
                label: Text(ForumSorts.title(value)),
                icon: Icon(_sortIcon(value), size: 16),
              ),
          ],
          onSelectionChanged: (selection) => ref
              .read(forumLobbyProvider(widget.slug).notifier)
              .setSort(selection.first),
        ),
      ),
    );
  }

  IconData _sortIcon(String sort) => switch (sort) {
    'top' => Icons.local_fire_department_rounded,
    'discussed' => Icons.forum_rounded,
    _ => Icons.schedule_rounded,
  };

  Widget _topics(BuildContext context, ForumLobbyState state) {
    final scheme = Theme.of(context).colorScheme;

    if (state.isLoading && state.topics.isEmpty) {
      return Column(
        children: [for (var i = 0; i < 3; i++) _shimmerRow(context)],
      );
    }

    if (state.error != null && state.topics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 38,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              tr('Не удалось загрузить обсуждения'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: () =>
                  ref.read(forumLobbyProvider(widget.slug).notifier).load(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr('Повторить')),
            ),
          ],
        ),
      );
    }

    if (state.topics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
        child: Column(
          children: [
            Icon(
              Icons.mode_comment_outlined,
              size: 40,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              tr('Здесь пока тишина'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Начни обсуждение — вопрос по квесту, находка, идея.'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final topic in state.topics)
          ForumTopicTile(
            topic: topic,
            onOpen: () => _openTopic(topic),
            onLike: () => _toggleTopicLike(topic),
            menu: state.canModerate ? _topicMenu(topic, state) : null,
          ),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.error != null)
          // Топики уже перед глазами, поэтому ошибку догрузки показываем
          // хвостом списка: иначе вставшая загрузка неотличима от конца.
          LoadMoreErrorTile(
            onRetry: () => ref
                .read(forumLobbyProvider(widget.slug).notifier)
                .loadMore(),
          ),
      ],
    );
  }

  /// Меню модератора у топика. Bans и назначения ограничены тем, что знает
  /// клиент: создателя забанить нельзя, а назначает модератора только создатель.
  Widget _topicMenu(ForumTopic topic, ForumLobbyState state) {
    final author = topic.author;
    final isMe = author.id.isNotEmpty && author.id == state.viewerId;
    final authorIsCreator = author.id == state.forum?.creatorId;
    final authorIsMod = state.mods.any((m) => m.id == author.id && m.moderator);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      tooltip: tr('Действия модератора'),
      onSelected: (value) {
        if (value == 'remove') _removeTopic(topic);
        if (value == 'ban') _banAuthor(author);
        if (value == 'mod') _appointModerator(author);
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'remove', child: Text(tr('Снять топик'))),
        if (author.id.isNotEmpty && !isMe && !authorIsCreator)
          PopupMenuItem(value: 'ban', child: Text(tr('Ограничить автора'))),
        if (state.isCreator &&
            author.id.isNotEmpty &&
            !isMe &&
            !authorIsCreator &&
            !authorIsMod)
          PopupMenuItem(
            value: 'mod',
            child: Text(tr('Назначить модератором')),
          ),
      ],
    );
  }

  Widget _shimmerRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerHigh,
      child: Container(
        height: 84,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.forum,
    required this.mods,
    required this.canModerate,
    required this.onToggleJoin,
  });

  final Forum? forum;
  final List<ForumPerson> mods;
  final bool canModerate;
  final VoidCallback onToggleJoin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final forum = this.forum;
    if (forum == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: LinearProgressIndicator(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Обложка: тонированная полоса с аватаром, именем и вступлением —
            // чтобы сообщество узнавалось в ленте так же, как квест в витрине.
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer.withOpacity(0.65),
                    scheme.tertiaryContainer.withOpacity(0.45),
                  ],
                ),
              ),
              child: LayoutBuilder(
                builder: (context, cover) {
                  final identity = <Widget>[
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        forum.isQuestForum
                            ? Icons.sports_esports_rounded
                            : Icons.group_work_rounded,
                        color: scheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              forum.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '/${forum.slug}',
                              style: textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ];
                  final button = _JoinButton(
                    forum: forum,
                    onPressed: onToggleJoin,
                  );
                  // В правой колонке карточка тонкая: кнопка рядом с ником
                  // не помещается и лезет за край, поэтому она своей строкой.
                  if (cover.maxWidth >= 320) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...identity,
                        const SizedBox(width: 8),
                        button,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: identity,
                      ),
                      const SizedBox(height: 10),
                      button,
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      _Stat(
                        icon: Icons.diversity_3_rounded,
                        label:
                            trf('{p0} участников', {'p0': formatCompactCount(forum.memberCount)}),
                      ),
                      _Stat(
                        icon: Icons.mode_comment_outlined,
                        label: trf('{p0} обсужд.', {'p0': formatCompactCount(forum.topicsCount)}),
                      ),
                      if (forum.createdAt != null)
                        _Stat(
                          icon: Icons.event_rounded,
                          label: trf('с {p0}', {'p0': formatDayMonth(forum.createdAt!)}),
                        ),
                    ],
                  ),
                  if (forum.description != null &&
                      forum.description!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      forum.description!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (forum.isRestricted)
                        _Tag(
                          icon: Icons.lock_rounded,
                          label: tr('Пишут только участники'),
                        ),
                      if (canModerate)
                        _Tag(
                          icon: Icons.shield_moon_rounded,
                          label: tr('Ты модератор'),
                        ),
                      if (forum.isQuestForum && forum.questId != null)
                        _QuestTag(forum: forum),
                    ],
                  ),
                  if (mods.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      tr('Модераторы'),
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        for (final mod in mods)
                          InkWell(
                            onTap: mod.id.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ProfileScreen(userId: mod.id),
                                    ),
                                  ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CosmeticAvatar(
                                  frame: cosmeticById(mod.equipped.avatarFrame),
                                  radius: 11,
                                  avatarUrl: mod.avatarUrl,
                                  placeholderColor:
                                      scheme.surfaceContainerHighest,
                                ),
                                const SizedBox(width: 5),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 140,
                                  ),
                                  child: CosmeticNameText(
                                    name: mod.name,
                                    def: cosmeticById(mod.equipped.nameStyle),
                                    style: textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Что здесь разрешено и почему сообщение не вышло. Правила живут рядом с
/// лентой, а не в отдельном экране: человек читает их в тот момент, когда
/// собирается написать, а не после отказа.
///
/// Всё перечислимое: пороги беруться из тех же констант, по которым проверяет
/// бэкенд, никаких оценок «достойно ли» тут нет.
class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.forum});

  final Forum forum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rules = <(IconData, String)>[
      (
        Icons.title_rounded,
        trf('Заголовок обязателен, до {p0} символов', {
          'p0': ForumLimits.maxTitleChars,
        }),
      ),
      (
        Icons.notes_rounded,
        trf('Тело — до {p0} символов, поддерживается markdown и #теги', {
          'p0': ForumLimits.maxBodyChars,
        }),
      ),
      if (forum.isRestricted)
        (
          Icons.lock_rounded,
          tr('Писать могут только участники — вступитесь'),
        ),
      (
        Icons.timelapse_rounded,
        tr('Пауза между публикациями считается по всем постам, а не по одному сообществу'),
      ),
      (
        Icons.flag_rounded,
        tr('Пожаловаться на сообщество — в меню сверху'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Правила'),
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final (icon, text) in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Вступление — главное действие сообщества, поэтому оно залито цветом, а не
/// прячется в чип: «вы участник» должно читаться без чтения подписи.
class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.forum, required this.onPressed});

  final Forum forum;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (forum.banned) {
      return OutlinedButton(
        onPressed: null,
        child: Text(tr('Ограничен')),
      );
    }
    if (forum.joined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.check_rounded, size: 18, color: scheme.primary),
        label: Text(tr('Участник')),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
      label: Text(tr('Вступить')),
    );
  }
}

/// Обсуждение квеста ведёт на страницу квеста: без этой кнопки форум-саб
/// оставался тупиком — человек не мог вернуться к игре из её обсуждения.
class _QuestTag extends StatelessWidget {
  const _QuestTag({required this.forum});

  final Forum forum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MarketQuestLoaderScreen(questId: forum.questId!),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_esports_rounded, size: 13, color: scheme.primary),
            const SizedBox(width: 5),
            Text(
              trf('Квест: {p0}', {'p0': forum.questTitle ?? tr('открыть')}),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BannedBanner extends StatelessWidget {
  const _BannedBanner({required this.forum});

  final Forum forum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.block_rounded, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Тебя ограничили в этом сообществе: читать можно, писать и вступать — нет.'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Причина действия — она нужна и жалобе, и снятию топика, и бану: бэк отвечает
/// на отказ готовой русской строкой, и показывать её удобнее там же, где
/// человек уже печатает.
Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  bool mustFill = false,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      hint: hint,
      confirmLabel: confirmLabel,
      mustFill: mustFill,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.mustFill,
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final bool mustFill;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.mustFill && value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 3,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (value) =>
            setState(() => _hasText = value.trim().isNotEmpty),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hint,
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Отмена')),
        ),
        FilledButton(
          onPressed: (!widget.mustFill || _hasText) ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Правила форума правит тот же, кто их завёл: название, описание и «пишут
/// только участники». Слаг не меняется — по нему уже живут ссылки.
class _ForumSettingsSheet extends ConsumerStatefulWidget {
  const _ForumSettingsSheet({required this.slug});

  final String slug;

  @override
  ConsumerState<_ForumSettingsSheet> createState() =>
      _ForumSettingsSheetState();
}

class _ForumSettingsSheetState extends ConsumerState<_ForumSettingsSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late bool _restricted;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final forum = ref.read(forumLobbyProvider(widget.slug)).forum;
    _name = TextEditingController(text: forum?.name ?? '');
    _description = TextEditingController(text: forum?.description ?? '');
    _restricted = forum?.isRestricted ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .saveSettings(
          name: _name.text,
          description: _description.text,
          isRestricted: _restricted,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            maxLength: ForumLimits.maxNameChars,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Название'),
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            maxLength: ForumLimits.maxDescriptionChars,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Описание'),
              counterText:
                  '${_description.value.text.length}/${ForumLimits.maxDescriptionChars}',
              counterStyle: TextStyle(color: scheme.onSurfaceVariant),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: _restricted,
            onChanged: (value) => setState(() => _restricted = value),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Пишут только участники')),
            subtitle: Text(
              tr('Читать сообщения всё равно сможет любой, кто зашёл по ссылке.'),
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? tr('Сохраняем…') : tr('Сохранить')),
          ),
        ],
      ),
    );
  }
}

/// Список ограничений: забанить без возможности разбанить было бы действие,
/// которое отменяет только админ через базу.
class _ForumBansSheet extends ConsumerStatefulWidget {
  const _ForumBansSheet({required this.slug});

  final String slug;

  @override
  ConsumerState<_ForumBansSheet> createState() => _ForumBansSheetState();
}

class _ForumBansSheetState extends ConsumerState<_ForumBansSheet> {
  late Future<({List<ForumBan> bans, String? error})> _bans;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _bans = ref.read(forumLobbyProvider(widget.slug).notifier).bans();
  }

  Future<void> _unban(ForumBan ban) async {
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .unban(ban.person.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: FutureBuilder<({List<ForumBan> bans, String? error})>(
        future: _bans,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: LinearProgressIndicator(),
            );
          }
          final result = snap.data ?? (bans: const <ForumBan>[], error: null);
          final bans = result.bans;
          if (bans.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text(
                // Пустой список и «бэк не ответил» — разные вещи: иначе
                // модератор решит, что ограничений нет, когда их просто не
                // удалось прочитать.
                result.error ?? tr('Никто не ограничен.'),
                style: textTheme.bodyMedium?.copyWith(
                  color: result.error == null
                      ? scheme.onSurfaceVariant
                      : scheme.error,
                ),
              ),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: bans.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final ban = bans[i];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CosmeticAvatar(
                    frame: cosmeticById(ban.person.equipped.avatarFrame),
                    radius: 14,
                    avatarUrl: ban.person.avatarUrl,
                    placeholderColor: scheme.surfaceContainerHighest,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CosmeticNameText(
                          name: ban.person.name,
                          def: cosmeticById(ban.person.equipped.nameStyle),
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (ban.reason.isNotEmpty)
                          Text(
                            ban.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _unban(ban),
                    child: Text(tr('Снять')),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
