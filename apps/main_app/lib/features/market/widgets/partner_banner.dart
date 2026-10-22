import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:canvas_app/core/config.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Тип формата партнёрского баннера.
enum PartnerBannerFormat {
  /// Большой баннер с обложкой (для верха/между секциями).
  hero,

  /// Компактный баннер-строка (для встраивания в feed).
  compact,

  /// Баннер для sidebar (узкий вертикальный).
  sidebar,
}

/// Модель партнёрского баннера. Грузится с сервера
/// (GET /api/app/partner-banners). Локальный список [defaultPartnerBanners]
/// используется как fallback при ошибке/оффлайне.
@immutable
class PartnerBannerItem {
  final String id;
  final String title;
  final String subtitle;
  final String ctaText;
  final String url;
  final String? imageUrl;
  final IconData icon;
  final Color tint;

  /// Где этот баннер допустимо показывать.
  final Set<String> slots;

  /// Постоянный (всегда показываемый) партнёр. Имеет приоритет при
  /// случайном выборе — если в слоте есть pinned-баннеры, выбираются только они.
  final bool pinned;

  const PartnerBannerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.ctaText,
    required this.url,
    required this.slots,
    this.imageUrl,
    this.icon = Icons.campaign_outlined,
    this.tint = const Color(0xFF6750A4),
    this.pinned = false,
  });

  /// Парсит баннер из JSON-ответа бекенда.
  factory PartnerBannerItem.fromJson(Map<String, dynamic> json) {
    final slotsRaw = json['slots'];
    final slotsList = <String>{
      if (slotsRaw is List)
        for (final s in slotsRaw)
          if (s is String && s.isNotEmpty) s,
    };

    return PartnerBannerItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      ctaText: (json['ctaText'] ??
                json['cta_text'] ??
                tr('Открыть')).toString(),
      url: (json['url'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? json['image_url']) as String?,
      icon: _iconFromCode((json['icon'] ?? '').toString()),
      tint: _colorFromHex(
        (json['tintColor'] ?? json['tint_color'])?.toString(),
      ),
      slots: slotsList,
      pinned: json['pinned'] == true,
    );
  }
}

// ============================================================================
//  МАППЕРЫ для значений с сервера
// ============================================================================

/// Whitelist поддерживаемых иконок. Если сервер пришлёт неизвестный код —
/// возвращаем дефолтную campaign_outlined.
IconData _iconFromCode(String code) {
  switch (code) {
    case 'auto_awesome':
      return Icons.auto_awesome;
    case 'smart_toy':
    case 'smart_toy_outlined':
      return Icons.smart_toy_outlined;
    case 'send':
      return Icons.send;
    case 'video_library':
      return Icons.video_library;
    case 'volunteer_activism':
      return Icons.volunteer_activism;
    case 'forum':
    case 'forum_outlined':
      return Icons.forum_outlined;
    case 'chat_bubble':
    case 'chat_bubble_outline':
      return Icons.chat_bubble_outline;
    case 'campaign':
    case 'campaign_outlined':
      return Icons.campaign_outlined;
    case 'shop':
    case 'shop_rounded':
      return Icons.shop_rounded;
    case 'star':
    case 'star_rounded':
      return Icons.star_rounded;
    case 'rocket_launch':
      return Icons.rocket_launch_rounded;
    case 'celebration':
      return Icons.celebration_rounded;
    case 'extension':
      return Icons.extension_rounded;
    case 'public':
      return Icons.public_rounded;
    case 'favorite':
      return Icons.favorite_rounded;
    default:
      return Icons.campaign_outlined;
  }
}

/// Парсит hex-цвет вида `#RRGGBB`, `RRGGBB`, `#AARRGGBB` или `AARRGGBB`.
/// Возвращает дефолтный M3-фиолетовый, если строка некорректна.
Color _colorFromHex(String? raw) {
  const fallback = Color(0xFF6750A4);
  if (raw == null) return fallback;
  var s = raw.trim();
  if (s.isEmpty) return fallback;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return fallback;
  final value = int.tryParse(s, radix: 16);
  if (value == null) return fallback;
  return Color(value);
}

/// Реестр партнёрских баннеров. Просто отредактируй [defaultPartnerBanners]
/// либо передай свой список через [overridePartnerBannersProvider]
/// (например, после получения данных с бэка/Remote Config).
// Геттер, а не final-таблица: список строится под текущий язык, иначе
// переключение языка не перекрасило бы эти подписи.
List<PartnerBannerItem> get defaultPartnerBanners => [
  // ============================================================
  // ПОСТОЯННЫЕ ПАРТНЁРЫ (pinned: true) — всегда в ротации.
  // ============================================================
  PartnerBannerItem(
    id: 'mindteam_ai_bot',
    title: 'Tech',
    subtitle: tr('Telegram-бот, который генерирует квесты для Meander.'),
    ctaText: tr('Открыть в TG'),
    url: 'https://t.me/mindteamai_bot',
    icon: Icons.smart_toy_outlined,
    tint: Color(0xFF00BFA5),
    pinned: true,
    slots: {'market.top', 'market.mid', 'market.bottom', 'market.sidebar'},
  ),

  // ============================================================
  // ОБЫЧНЫЕ ПАРТНЁРЫ (показываются только если pinned-баннеров нет).
  // ============================================================
  PartnerBannerItem(
    id: 'meander_tg',
    title: tr('Официальный TG Meander'),
    subtitle: tr('Новости, релизы и анонсы квестов в Telegram.'),
    ctaText: tr('Подписаться'),
    url: 'https://t.me/meanderRU',
    icon: Icons.send,
    tint: Color(0xFF229ED9),
    slots: {'market.top', 'market.mid', 'market.bottom', 'market.sidebar'},
  ),
  PartnerBannerItem(
    id: 'meander_youtube',
    title: tr('Канал Meander на YouTube'),
    subtitle: tr('Гайды, обзоры и релизы новых квестов.'),
    ctaText: tr('Смотреть'),
    url: 'https://www.youtube.com/@meanderRU',
    icon: Icons.video_library,
    tint: Color(0xFFE53935),
    slots: {'market.top', 'market.sidebar', 'market.mid'},
  ),
  PartnerBannerItem(
    id: 'boosty_support',
    title: tr('Поддержи серверы Meander'),
    subtitle: tr('Boosty — помогает держать инфраструктуру.'),
    ctaText: tr('Поддержать'),
    url:
        'https://boosty.to/iilluminat/posts/8e4bc65c-f106-4560-b158-973d6e8a65f6',
    icon: Icons.volunteer_activism,
    tint: Color(0xFFFF7043),
    slots: {'market.bottom', 'market.mid', 'market.sidebar'},
  ),
  PartnerBannerItem(
    id: 'tg_forum',
    title: tr('Форум в Telegram'),
    subtitle: tr('Задавай вопросы и обсуждай свои квесты.'),
    ctaText: tr('Открыть'),
    url: 'https://t.me/mndForum',
    icon: Icons.forum_outlined,
    tint: Color(0xFF2AABEE),
    slots: {'market.mid', 'market.bottom'},
  ),
  PartnerBannerItem(
    id: 'wiki_meander',
    title: tr('WikiMeander в TG'),
    subtitle: tr('Новости, идеи и обсуждения сообщества.'),
    ctaText: tr('Подписаться'),
    url: 'https://t.me/WikiMeander',
    icon: Icons.chat_bubble_outline,
    tint: Color(0xFF1E88E5),
    slots: {'market.top', 'market.sidebar'},
  ),
];

/// Грузит баннеры с бэка. При ошибке возвращает локальный fallback,
/// чтобы маркет всегда что-то показывал. autoDispose не используем —
/// баннеры нужны на нескольких экранах, и постоянное перезапрашивание
/// ни к чему. Сервер уже отдаёт Cache-Control.
///
/// Эндпойнт публичный — не используем ApiService, чтобы протухший токен
/// не привёл к авто-логауту: маркет с баннерами не должен выбрасывать юзера.
final partnerBannersProvider = FutureProvider<List<PartnerBannerItem>>((
  ref,
) async {
  try {
    final uri = Uri.parse('${AppConfig.apiUrl}/api/app/partner-banners');
    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('[PartnerBanners] HTTP ${response.statusCode}');
      }
      return defaultPartnerBanners;
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      if (kDebugMode) {
        debugPrint(
          '[PartnerBanners] unexpected payload type: ${decoded.runtimeType}',
        );
      }
      return defaultPartnerBanners;
    }
    final list = <PartnerBannerItem>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        try {
          list.add(PartnerBannerItem.fromJson(item));
        } catch (e) {
          if (kDebugMode) debugPrint('[PartnerBanners] parse error: $e');
        }
      }
    }
    if (list.isEmpty) {
      if (kDebugMode) {
        debugPrint('[PartnerBanners] empty list — using fallback');
      }
      return defaultPartnerBanners;
    }
    return list;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[PartnerBanners] load failed, using fallback: $e');
      debugPrint('$st');
    }
    return defaultPartnerBanners;
  }
});

/// Возвращает упорядоченный список баннеров для слота:
///   1. PINNED-баннеры идут первыми (в порядке объявления).
///   2. Обычные — после них.
List<PartnerBannerItem> _bannersForSlot(
  List<PartnerBannerItem> all,
  String slotId, {
  Set<String>? exclude,
}) {
  final inSlot = all
      .where((b) => b.slots.contains(slotId))
      .where((b) => exclude == null || !exclude.contains(b.id))
      .toList();

  // Сохраняем порядок объявления: pinned всегда первыми.
  final pinned = inSlot.where((b) => b.pinned).toList();
  final regular = inSlot.where((b) => !b.pinned).toList();
  return [...pinned, ...regular];
}

Future<void> _openBannerUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('Не удалось открыть ссылку'))));
  }
}

Widget _buildBannerByFormat(
  BuildContext context,
  PartnerBannerItem item,
  PartnerBannerFormat format,
) {
  switch (format) {
    case PartnerBannerFormat.hero:
      return _HeroPartnerBanner(
        item: item,
        onTap: () => _openBannerUrl(context, item.url),
      );
    case PartnerBannerFormat.compact:
      return _CompactPartnerBanner(
        item: item,
        onTap: () => _openBannerUrl(context, item.url),
      );
    case PartnerBannerFormat.sidebar:
      return _SidebarPartnerBanner(
        item: item,
        onTap: () => _openBannerUrl(context, item.url),
      );
  }
}

/// Слот для партнёрского баннера. По умолчанию рендерит **карусель**
/// (все pinned + обычные партнёры для слота), которую можно свайпать.
/// Если карусель не нужен — передайте `carousel: false`.
class PartnerBannerSlot extends ConsumerStatefulWidget {
  final String slotId;
  final PartnerBannerFormat format;

  /// Можно явно указать id баннера; в этом случае показывается один статичный.
  final String? preferredId;

  /// Отступы вокруг баннера.
  final EdgeInsetsGeometry padding;

  /// Если true — рендерится карусель со свайпом между всеми
  /// подходящими баннерами (pinned первыми).
  final bool carousel;

  const PartnerBannerSlot({
    super.key,
    required this.slotId,
    this.format = PartnerBannerFormat.compact,
    this.preferredId,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.carousel = true,
  });

  @override
  ConsumerState<PartnerBannerSlot> createState() => _PartnerBannerSlotState();
}

class _PartnerBannerSlotState extends ConsumerState<PartnerBannerSlot> {
  late final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncBanners = ref.watch(partnerBannersProvider);

    // Пока грузится первый раз — не занимаем место. После загрузки
    // Riverpod кеширует значение, и баннеры появятся сразу.
    final all = asyncBanners.maybeWhen(
      data: (list) => list,
      orElse: () => const <PartnerBannerItem>[],
    );

    if (all.isEmpty) return const SizedBox.shrink();

    // Если preferredId задан — показываем только этот баннер, без карусели.
    if (widget.preferredId != null) {
      final explicit = all.where((b) => b.id == widget.preferredId).toList();
      if (explicit.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: widget.padding,
        child: _buildBannerByFormat(context, explicit.first, widget.format),
      );
    }

    final banners = _bannersForSlot(all, widget.slotId);
    if (banners.isEmpty) return const SizedBox.shrink();

    // Один баннер или carousel выключен — отдаём статично.
    if (!widget.carousel || banners.length == 1) {
      return Padding(
        padding: widget.padding,
        child: _buildBannerByFormat(context, banners.first, widget.format),
      );
    }

    return Padding(
      padding: widget.padding,
      child: _PartnerBannerCarousel(
        banners: banners,
        format: widget.format,
        pageController: _pageController,
        currentIndex: _currentIndex,
        onPageChanged: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

/// Карусель партнёрских баннеров со свайпом и индикатором страниц.
class _PartnerBannerCarousel extends StatelessWidget {
  final List<PartnerBannerItem> banners;
  final PartnerBannerFormat format;
  final PageController pageController;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  const _PartnerBannerCarousel({
    required this.banners,
    required this.format,
    required this.pageController,
    required this.currentIndex,
    required this.onPageChanged,
  });

  double _heightForFormat(BuildContext context) {
    switch (format) {
      case PartnerBannerFormat.hero:
        return 210;
      case PartnerBannerFormat.compact:
        // Compact — высота с запасом на 2 строки title + 3 строки subtitle + кнопка.
        return 170;
      case PartnerBannerFormat.sidebar:
        return 280;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = _heightForFormat(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: pageController,
            onPageChanged: onPageChanged,
            itemCount: banners.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildBannerByFormat(context, banners[i], format),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Индикатор страниц
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(banners.length, (i) {
            final isActive = i == currentIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withOpacity(0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SponsorChip extends StatelessWidget {
  const _SponsorChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tr('Партнёр'),
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HeroPartnerBanner extends StatelessWidget {
  final PartnerBannerItem item;
  final VoidCallback onTap;

  const _HeroPartnerBanner({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                item.tint.withOpacity(isDark ? 0.55 : 0.85),
                item.tint.withOpacity(isDark ? 0.25 : 0.55),
              ],
            ),
          ),
          child: Stack(
            children: [
              if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Opacity(
                      opacity: 0.35,
                      child: CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: -10,
                top: -10,
                child: Icon(
                  item.icon,
                  size: 140,
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SponsorChip(),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        softWrap: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        softWrap: true,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.ctaText,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: scheme.onSurface,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactPartnerBanner extends StatelessWidget {
  final PartnerBannerItem item;
  final VoidCallback onTap;

  const _CompactPartnerBanner({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.tint.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.tint, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            softWrap: true,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: _SponsorChip(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      softWrap: true,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        child: Text(item.ctaText),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarPartnerBanner extends StatelessWidget {
  final PartnerBannerItem item;
  final VoidCallback onTap;

  const _SidebarPartnerBanner({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                item.tint.withOpacity(0.85),
                item.tint.withOpacity(0.45),
              ],
            ),
          ),
          padding: const EdgeInsets.all(14),
          // SingleChildScrollView защищает от overflow если карточка попадёт
          // в слишком узкий контейнер — лучше прокрутка, чем "RenderFlex overflowed".
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _SponsorChip(),
                    const Spacer(),
                    Icon(
                      item.icon,
                      color: Colors.white.withOpacity(0.85),
                      size: 28,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  softWrap: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.subtitle,
                  softWrap: true,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.ctaText,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: scheme.onSurface,
                          size: 14,
                        ),
                      ],
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
