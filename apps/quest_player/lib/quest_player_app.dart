import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mnd_player/screens/game_screen.dart';

import 'quest_installer.dart';

/// Название приложения из сборщика (`--dart-define=QUEST_APP_NAME=...`).
const String kQuestAppName = String.fromEnvironment(
  'QUEST_APP_NAME',
  defaultValue: 'Meander Quest',
);

const Color _background = Color(0xFF151312);
const Color _accent = Color(0xFFE0B872);

class QuestPlayerApp extends StatelessWidget {
  const QuestPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kQuestAppName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
          surface: _background,
        ),
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
      home: const _QuestLauncher(),
    );
  }
}

class _QuestLauncher extends StatefulWidget {
  const _QuestLauncher();

  @override
  State<_QuestLauncher> createState() => _QuestLauncherState();
}

class _QuestLauncherState extends State<_QuestLauncher> {
  late Future<String> _install = QuestInstaller.installBundledQuest();

  void _retry() {
    setState(() => _install = QuestInstaller.installBundledQuest(force: true));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _install,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StatusView(
            title: 'Не удалось открыть квест',
            message: '${snapshot.error}',
            onRetry: _retry,
          );
        }
        final questId = snapshot.data;
        if (questId == null) {
          return const _StatusView(title: kQuestAppName, loading: true);
        }
        return GameScreen(
          questId: questId,
          onExit: () => SystemNavigator.pop(),
        );
      },
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.title,
    this.message,
    this.loading = false,
    this.onRetry,
  });

  final String title;
  final String? message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                if (loading)
                  const CircularProgressIndicator(color: _accent)
                else ...[
                  if (message != null)
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Повторить'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
