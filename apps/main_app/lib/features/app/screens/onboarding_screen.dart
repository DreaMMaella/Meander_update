// Файл: lib/screens/onboarding_screen.dart

import 'package:canvas_app/core/services/onboarding_service.dart';
import 'package:canvas_app/features/shell/screens/menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// Финальный экран с развилкой вместо промо-листалки.
  bool _choosing = false;

  final List<Map<String, dynamic>> _pages = [
    {
      "title": tr("Создавай миры"),
      "desc":
          tr("Пиши захватывающие текстовые квесты с разветвленным сюжетом в удобном редакторе."),
      "icon": Icons.edit_note_rounded,
    },
    {
      "title": tr("Управляй логикой"),
      "desc":
          tr("Используй визуальный редактор скриптов, добавляй переменные, условия и случайные события."),
      "icon": Icons.account_tree_rounded,
    },
    {
      "title": tr("Играй и Делись"),
      "desc":
          tr("Публикуй свои игры в маркете, получай отзывы и проходи квесты других авторов."),
      "icon": Icons.rocket_launch_rounded,
    },
  ];

  /// Запоминаем ответ и уходим в оболочку: по нему гость приземлится либо на
  /// вход, либо в «Мои», но не в «Хаб» с ресурсами.
  Future<void> _finish(String intent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_onboarding', true);
    await prefs.setString(OnboardingService.kIntentKey, intent);

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => MenuScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_choosing) return _buildChoice(context);
    final scheme = Theme.of(context).colorScheme;
    final accents = [scheme.primary, scheme.secondary, scheme.tertiary];
    return Scaffold(
      backgroundColor: scheme.surface,
      body: AdaptiveContent(
        maxWidth: 760,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) => setState(() => _currentPage = idx),
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    final accent = accents[index];
                    return Padding(
                      // Промо-страница — первое, что видит человек, и на
                      // маленьком телефоне с крупным системным шрифтом она
                      // не влезала: Column с фиксированными 80 px иконкой и
                      // отступами давал жёлтые полосы прямо на онбординге.
                      padding: const EdgeInsets.all(32.0),
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(30),
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  page['icon'],
                                  size: 80,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(height: 40),
                              Text(
                                page['title'],
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  color: scheme.onSurface,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                page['desc'],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Индикаторы страниц
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: _currentPage == index ? 24 : 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? scheme.primary
                          : scheme.onSurface.withOpacity(0.24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Кнопка
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_currentPage < _pages.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        setState(() => _choosing = true);
                      }
                    },
                    child: Text(
                      _currentPage == _pages.length - 1
                          ? tr('Продолжить')
                          : tr('Далее'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Развилка: «пройти» ведёт ко входу (каталог открывается только с
  /// аккаунтом), «создать» — в «Мои», где живёт кнопка «Создать квест».
  Widget _buildChoice(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cards = [
      _IntentCard(
        icon: Icons.sports_esports_rounded,
        title: tr('Пройти квест'),
        desc:
            tr('Найти историю другого автора в каталоге и запустить её. Нужен аккаунт — так сохраняются прохождения.'),
        accent: scheme.primary,
        onTap: () => _finish(OnboardingService.intentPlay),
      ),
      _IntentCard(
        icon: Icons.edit_note_rounded,
        title: tr('Создать квест'),
        desc:
            tr('Открыть редактор и собрать свою первую историю. Аккаунт не нужен — всё сохраняется на устройстве.'),
        accent: scheme.tertiary,
        onTap: () => _finish(OnboardingService.intentCreate),
      ),
    ];
    return Scaffold(
      backgroundColor: scheme.surface,
      body: AdaptiveContent(
        maxWidth: 760,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                // Stretch: карточки должны быть во всю ширину, иначе на
                // телефоне сожмутся по самой длинной строке текста.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('С чего начнём?'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      color: scheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Этот выбор решает только первый экран: квесты открываются со входа, редактор — из «Мои». Табы никуда не деваются — передумаешь в один тап.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (isDesktopWidth(context))
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 16),
                        Expanded(child: cards[1]),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cards[0],
                        const SizedBox(height: 16),
                        cards[1],
                      ],
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

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: accent.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 40, color: accent),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.manrope(
                  color: scheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                desc,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
