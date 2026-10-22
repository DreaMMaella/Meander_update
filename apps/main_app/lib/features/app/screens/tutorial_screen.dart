import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

// ============================================================================
//  АКАДЕМИЯ — Material 3 редизайн (в едином стиле с Маркетом и Профилем)
// ============================================================================

class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Не удалось открыть ссылку'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: AdaptiveContent(
        maxWidth: 900,
        child: SafeArea(
          bottom: false,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                pinned: false,
                floating: true,
                snap: true,
                // Кнопка «назад»: экран живёт какroute из «Ещё», а не как
                // вкладка — без стрелки из него не выйти ничем, кроме Esc.
                automaticallyImplyLeading: true,
                toolbarHeight: 64,
                titleSpacing: 16,
                title: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.school_rounded,
                        color: scheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      tr('Академия'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorColor: scheme.primary,
                    labelColor: scheme.primary,
                    unselectedLabelColor: scheme.onSurfaceVariant,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    tabs: [
                      Tab(text: tr('Гайды')),
                      Tab(text: tr('Контент')),
                      Tab(text: tr('Сообщество')),
                    ],
                  ),
                  background: scheme.surface,
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _GuidesTab(onOpenUrl: _openUrl),
                _ContentTab(onOpenUrl: _openUrl),
                _CommunityTab(onOpenUrl: _openUrl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  ДЕЛЕГАТ ЗАКРЕПЛЁННОГО TAB BAR
// ============================================================================

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;

  _TabBarDelegate(this.tabBar, {required this.background});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: background, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.background != background;
  }
}

// ============================================================================
//  ЗАГОЛОВОК СЕКЦИИ (в стиле маркета)
// ============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 2),
              child: Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
//  МОДЕЛИ
// ============================================================================

class _VideoItem {
  final String title;
  final String videoId;

  const _VideoItem({required this.title, required this.videoId});
}

class _CommunityItem {
  final String title;
  final String description;
  final String url;
  final IconData icon;
  final Color iconColor;
  final String tag;

  const _CommunityItem({
    required this.title,
    required this.description,
    required this.url,
    required this.icon,
    required this.iconColor,
    required this.tag,
  });
}

// ============================================================================
//  ТАБЫ
// ============================================================================

class _GuidesTab extends StatelessWidget {
  final Function(String) onOpenUrl;

  const _GuidesTab({required this.onOpenUrl});

  /// Геттер, а не `static final`: заголовки карточек строятся под текущий
  /// язык, застывший список не перекрасился бы при переключении.
  static List<_VideoItem> get _items => [
    _VideoItem(title: tr('Основы переменных'), videoId: 'WC8cMgfcGnw'),
    _VideoItem(title: tr('Условия и рандом'), videoId: '0-bxFFPlLTA'),
    _VideoItem(title: tr('Визуальные новеллы'), videoId: 'E3sMyMyYpQM'),
  ];

  @override
  Widget build(BuildContext context) {
    return _VideoListView(
      onOpenUrl: onOpenUrl,
      items: _items,
      sectionTitle: tr('Гайды по созданию квестов'),
      sectionIcon: Icons.play_lesson_rounded,
      sectionSubtitle: tr('Начните с первого видео и двигайтесь по порядку'),
    );
  }
}

class _ContentTab extends StatelessWidget {
  final Function(String) onOpenUrl;

  const _ContentTab({required this.onOpenUrl});

  static List<_VideoItem> get _items => [
    _VideoItem(title: tr('Динозавры и Кокосы'), videoId: 'ijPNWfE1p4I'),
    _VideoItem(title: tr('Новогоднее Чудо'), videoId: '86lhTdkvL1Q'),
    _VideoItem(title: tr('Гитарист'), videoId: 'ciJ_6pJ_Z70'),
  ];

  @override
  Widget build(BuildContext context) {
    return _VideoListView(
      onOpenUrl: onOpenUrl,
      items: _items,
      sectionTitle: tr('Контент по Meander'),
      sectionIcon: Icons.movie_rounded,
      sectionSubtitle: tr('Примеры и обзоры квестов от сообщества'),
    );
  }
}

class _CommunityTab extends StatelessWidget {
  final Function(String) onOpenUrl;

  const _CommunityTab({required this.onOpenUrl});

  static List<_CommunityItem> get _items => [
    _CommunityItem(
      title: tr('YouTube канал'),
      description: tr('Официальный канал с гайдами и прохождениями'),
      url: 'https://www.youtube.com/@meanderRU',
      icon: Icons.play_circle_rounded,
      iconColor: Color(0xFFFF0000),
      tag: 'YouTube',
    ),
    _CommunityItem(
      title: tr('Telegram — Вики'),
      description: tr('Фан-канал с материалами по Meander'),
      url: 'https://t.me/WikiMeander',
      icon: Icons.telegram_rounded,
      iconColor: Color(0xFF2AABEE),
      tag: 'Telegram',
    ),
    _CommunityItem(
      title: tr('Telegram — Форум'),
      description: tr('Задать вопрос, обсудить квесты'),
      url: 'https://t.me/mndForum',
      icon: Icons.forum_rounded,
      iconColor: Color(0xFF2AABEE),
      tag: 'Telegram',
    ),
    _CommunityItem(
      title: tr('YouTube — Фан канал'),
      description: tr('Shorts и обзоры от фанатов'),
      url: 'https://www.youtube.com/@text_adventures_channel/shorts',
      icon: Icons.play_circle_rounded,
      iconColor: Color(0xFFFF0000),
      tag: 'YouTube',
    ),
    _CommunityItem(
      title: 'YouTube — ArchAkimov',
      description: tr('Ещё один фан-канал по квестам'),
      url: 'https://www.youtube.com/@ArchAkimov',
      icon: Icons.play_circle_rounded,
      iconColor: Color(0xFFFF0000),
      tag: 'YouTube',
    ),
    _CommunityItem(
      title: tr('Simplex чат'),
      description: tr('Инсайды и билды раньше всех (нужен VPN)'),
      url:
          'https://smp10.simplex.im/g#tFj94ScyihNimJ1Nga7AXylCi7ebUvi9fsa-oxlwr4s',
      icon: Icons.chat_rounded,
      iconColor: Color(0xFF00C853),
      tag: tr('Чат'),
    ),
    _CommunityItem(
      title: 'Boosty',
      description: tr('Поддержка проекта и серверов'),
      url:
          'https://boosty.to/iilluminat/posts/8e4bc65c-f106-4560-b158-973d6e8a65f6',
      icon: Icons.favorite_rounded,
      iconColor: Color(0xFFFF6B6B),
      tag: tr('Донат'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Число колонок считается по ширине, которую список реально занял: контент
    // ограничен AdaptiveContent(maxWidth: 900), окно может быть и 1400. По
    // ширине окна сетка брала 3 колонки в 900 px — карточка выходила 282.7,
    // текст 168.7 и карточка переливалась на 4 px.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 800;
        final crossAxisCount = isWide ? (width >= 1200 ? 3 : 2) : 1;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: tr('Сообщество'),
                icon: Icons.groups_rounded,
                subtitle: tr('Найти помощь, новости и свежие билды'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              sliver: crossAxisCount == 1
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CommunityCard(
                            item: _items[index],
                            onTap: onOpenUrl,
                          ),
                        ),
                        childCount: _items.length,
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        // Запас на заголовок в одну строку, метку вторым
                        // рядом и описание в две: на 96 px карточка
                        // переливалась на 4 px.
                        mainAxisExtent: 104,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _CommunityCard(
                          item: _items[index],
                          onTap: onOpenUrl,
                        ),
                        childCount: _items.length,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
//  СПИСОК ВИДЕО (общий layout для табов Гайды/Контент)
// ============================================================================

class _VideoListView extends StatelessWidget {
  final Function(String) onOpenUrl;
  final List<_VideoItem> items;
  final String sectionTitle;
  final String sectionSubtitle;
  final IconData sectionIcon;

  const _VideoListView({
    required this.onOpenUrl,
    required this.items,
    required this.sectionTitle,
    required this.sectionSubtitle,
    required this.sectionIcon,
  });

  @override
  Widget build(BuildContext context) {
    // Та же ширина, что и у сетки карточек: окно здесь шире колонки контента.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 800;
        final crossAxisCount = isWide ? (width >= 1200 ? 3 : 2) : 1;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: sectionTitle,
                icon: sectionIcon,
                subtitle: sectionSubtitle,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              sliver: crossAxisCount == 1
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _VideoCard(
                            item: items[index],
                            onTap: onOpenUrl,
                          ),
                        ),
                        childCount: items.length,
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.15,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _VideoCard(item: items[index], onTap: onOpenUrl),
                        childCount: items.length,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
//  КАРТОЧКА ВИДЕО
// ============================================================================

class _VideoCard extends StatelessWidget {
  final _VideoItem item;
  final Function(String) onTap;

  const _VideoCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = 'https://www.youtube.com/watch?v=${item.videoId}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Material(
          color: scheme.surfaceContainerHigh,
          child: InkWell(
            onTap: () => onTap(url),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl:
                      'https://img.youtube.com/vi/${item.videoId}/hqdefault.jpg',
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.play_circle_outline,
                        color: scheme.onSurfaceVariant.withOpacity(0.4),
                        size: 44,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.play_circle_outline,
                        color: scheme.onSurfaceVariant.withOpacity(0.4),
                        size: 44,
                      ),
                    ),
                  ),
                ),
                // Затемнение снизу под подпись
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.82),
                        ],
                      ),
                    ),
                  ),
                ),
                // Play-кнопка по центру
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black87,
                      size: 36,
                    ),
                  ),
                ),
                // Название снизу
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  КАРТОЧКА СООБЩЕСТВА
// ============================================================================

class _CommunityCard extends StatelessWidget {
  final _CommunityItem item;
  final Function(String) onTap;

  const _CommunityCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(item.url),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Акцентная цветная полоса слева
              Container(width: 4, color: item.iconColor),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: item.iconColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: item.iconColor.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.tag,
                              style: TextStyle(
                                color: item.iconColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 14),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: scheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
