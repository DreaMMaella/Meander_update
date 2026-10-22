import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/services/github_builder_service.dart';
import 'package:mnd_core/utils/quest_paths.dart';

enum BuilderStep {
  idle,
  authDeviceCode,
  authWaiting,
  authDone,
  forking,
  forkDone,
  uploadingQuest,
  uploadingIcon,
  uploadDone,
  dispatching,
  building,
  downloading,
  done,
  error,
}

class BuilderState {
  final BuilderStep step;
  final String statusText;
  final String? deviceCode;
  final String? verificationUri;
  final int? expiresIn;
  final String? errorMessage;
  final String? downloadedFilePath;
  final String? buildLog;
  final String? buildUrl;

  const BuilderState({
    this.step = BuilderStep.idle,
    this.statusText = '',
    this.deviceCode,
    this.verificationUri,
    this.expiresIn,
    this.errorMessage,
    this.downloadedFilePath,
    this.buildLog,
    this.buildUrl,
  });

  BuilderState copyWith({
    BuilderStep? step,
    String? statusText,
    String? deviceCode,
    String? verificationUri,
    int? expiresIn,
    String? errorMessage,
    String? downloadedFilePath,
    String? buildLog,
    String? buildUrl,
  }) {
    return BuilderState(
      step: step ?? this.step,
      statusText: statusText ?? this.statusText,
      deviceCode: deviceCode ?? this.deviceCode,
      verificationUri: verificationUri ?? this.verificationUri,
      expiresIn: expiresIn ?? this.expiresIn,
      errorMessage: errorMessage ?? this.errorMessage,
      downloadedFilePath: downloadedFilePath ?? this.downloadedFilePath,
      buildLog: buildLog ?? this.buildLog,
      buildUrl: buildUrl ?? this.buildUrl,
    );
  }
}

class CloudBuilderNotifier extends StateNotifier<BuilderState> {
  CloudBuilderNotifier() : super(const BuilderState());

  final _service = GithubBuilderService();

  Future<void> startBuild({
    required String questId,
    required String appName,
    required String packageName,
    required String platform,
    String? iconPath,
  }) async {
    state = state.copyWith(
      step: BuilderStep.authDeviceCode,
      statusText: tr('Проверка авторизации GitHub...'),
    );

    try {
      final hasToken = await _service.hasToken;
      if (!hasToken) {
        state = state.copyWith(statusText: tr('Запрос кода авторизации...'));

        Map<String, dynamic> authData;
        try {
          authData = await _service.startDeviceAuth();
        } catch (e) {
          state = state.copyWith(
            step: BuilderStep.error,
            errorMessage:
                tr('Не удалось подключиться к GitHub. Проверьте интернет.'),
          );
          return;
        }

        final code = authData['user_code'] as String;
        final uri = authData['verification_uri'] as String;
        final expiresIn = authData['expires_in'] as int;

        state = state.copyWith(
          step: BuilderStep.authWaiting,
          statusText: tr('Введите код на GitHub'),
          deviceCode: code,
          verificationUri: uri,
          expiresIn: expiresIn,
        );

        final success = await _service.pollDeviceAuth(
          authData['device_code'] as String,
        );

        if (!success) {
          state = state.copyWith(
            step: BuilderStep.error,
            errorMessage: tr('Авторизация GitHub не пройдена или истекло время.'),
          );
          return;
        }
      }

      state = state.copyWith(
        step: BuilderStep.authDone,
        statusText: tr('Авторизация пройдена.'),
      );

      // Fork
      state = state.copyWith(
        step: BuilderStep.forking,
        statusText: tr('Создание репозитория...'),
      );
      await _service.forkRepo();

      state = state.copyWith(
        step: BuilderStep.forkDone,
        statusText: tr('Репозиторий готов.'),
      );

      // Upload quest
      state = state.copyWith(
        step: BuilderStep.uploadingQuest,
        statusText: tr('Загрузка квеста...'),
      );

      final questDir = p.join(
        (await getApplicationDocumentsDirectory()).path,
        QuestPaths.questsDir,
        questId,
      );
      final mndBytes = await _createMndArchive(questDir);
      await _service.uploadFile('assets/quest.mnd', base64Encode(mndBytes));

      // Upload icon if provided
      if (iconPath != null && File(iconPath).existsSync()) {
        state = state.copyWith(
          step: BuilderStep.uploadingIcon,
          statusText: tr('Загрузка иконки...'),
        );
        await _service.uploadFile(
          'assets/icon.png',
          base64Encode(await File(iconPath).readAsBytes()),
        );
      }

      state = state.copyWith(
        step: BuilderStep.uploadDone,
        statusText: tr('Файлы загружены.'),
      );

      // Dispatch build
      state = state.copyWith(
        step: BuilderStep.dispatching,
        statusText: tr('Запуск сборки...'),
      );
      final username = await _service.getUsername();
      state = state.copyWith(
        buildUrl: 'https://github.com/$username/mnd-standalone-builder/actions',
      );

      // Poll for result
      state = state.copyWith(
        step: BuilderStep.building,
        statusText: tr('Сборка приложения (2–4 минуты)...'),
      );

      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory(p.join(appDir.path, 'builds'));
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final fileName = platform == 'android-apk'
          ? '${appName}_android.apk'
          : '${appName}_${platform}.zip';
      final outputFile = File(p.join(downloadsDir.path, fileName));

      final result = await _service.pollAndDownload(
        appName: appName,
        onProgress: (status, detail) {
          if (status == 'building') {
            state = state.copyWith(statusText: detail, buildLog: detail);
          } else if (status == 'completed') {
            state = state.copyWith(
              step: BuilderStep.downloading,
              statusText: tr('Скачивание сборки...'),
            );
          }
        },
      );

      if (result != null) {
        await outputFile.writeAsBytes(base64Decode(result));
        state = state.copyWith(
          step: BuilderStep.done,
          statusText: tr('Сборка завершена!'),
          downloadedFilePath: outputFile.path,
        );
      } else {
        state = state.copyWith(
          step: BuilderStep.error,
          errorMessage:
              tr('Сборка не вернула файл. Проверьте статус в GitHub Actions.'),
        );
      }
    } catch (e) {
      final errorStr = e.toString();
      // If Actions are disabled (fork safety), extract URL from error
      if (errorStr.contains('Actions disabled')) {
        final urlMatch = RegExp(
          r'(https://github\.com/[^\s]+)',
        ).firstMatch(errorStr);
        final actionsUrl = urlMatch?.group(1);
        state = state.copyWith(
          step: BuilderStep.error,
          errorMessage:
              tr('Actions отключены в форке GitHub.\n\nЭто стандартная мера безопасности — GitHub отключает автоматический запуск скриптов в скопированных репозиториях.\n\nНажмите кнопку ниже, откройте страницу и нажмите зелёную кнопку "I understand my workflows, go ahead and enable them".\n\nПосле этого вернитесь и нажмите «Собрать в облаке» ещё раз.'),
          buildUrl: actionsUrl,
        );
      } else {
        state = state.copyWith(step: BuilderStep.error, errorMessage: errorStr);
      }
    }
  }

  Future<List<int>> _createMndArchive(String questDir) async {
    final archive = BytesBuilder();
    archive.add(utf8.encode('MND_ZIP_'));
    // Use simple JSON concatenation — same format as template expects
    final config = File(p.join(questDir, 'config.json'));
    if (await config.exists()) {
      archive.add(utf8.encode(await config.readAsString()));
    }
    // Add a separator
    archive.add(utf8.encode('\n'));
    final nodes = File(p.join(questDir, 'nodes.json'));
    if (await nodes.exists()) {
      archive.add(utf8.encode(await nodes.readAsString()));
    }
    return archive.toBytes();
  }

  bool get isRunning =>
      state.step != BuilderStep.idle &&
      state.step != BuilderStep.done &&
      state.step != BuilderStep.error;

  void reset() {
    state = const BuilderState();
  }
}

final cloudBuilderProvider =
    StateNotifierProvider<CloudBuilderNotifier, BuilderState>(
      (ref) => CloudBuilderNotifier(),
    );
