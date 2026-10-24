import 'dart:convert';
import 'dart:io';

import 'package:canvas_app/core/services/export_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ApkSigningMode { device, keystore }

/// Параметры офлайн-сборки APK. Пароли keystore не сохраняются между
/// сборками — только в памяти на время одной сборки.
class ApkBuildOptions {
  final String fileName;
  final String appName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final bool protectContent;

  final ApkSigningMode signingMode;
  final String certCommonName;
  final String certOrganization;
  final String certCountry;
  final int certValidityYears;

  final String? keystorePath;
  final String storePassword;
  final String keyAlias;
  final String keyPassword;

  final bool v1;
  final bool v2;
  final bool v3;

  /// Своя иконка (копия в хранилище приложения); `null` — иконка плеера.
  final String? iconPath;

  const ApkBuildOptions({
    required this.fileName,
    required this.appName,
    required this.packageName,
    this.versionName = '1.0.0',
    this.versionCode = 1,
    this.protectContent = false,
    this.signingMode = ApkSigningMode.device,
    this.certCommonName = '',
    this.certOrganization = '',
    this.certCountry = '',
    this.certValidityYears = 30,
    this.keystorePath,
    this.storePassword = '',
    this.keyAlias = '',
    this.keyPassword = '',
    this.v1 = false,
    this.v2 = true,
    this.v3 = false,
    this.iconPath,
  });

  static final RegExp _packageRegex = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
  );

  static const Set<String> _javaKeywords = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
    'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new',
    'package', 'private', 'protected', 'public', 'return', 'short', 'static',
    'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
    'transient', 'try', 'void', 'volatile', 'while', 'true', 'false', 'null',
  };

  static bool isValidPackageName(String value) =>
      value.length <= 200 &&
      _packageRegex.hasMatch(value) &&
      !value.split('.').any(_javaKeywords.contains);

  /// Уникальный ID пакета для квеста: разные квесты ставятся рядом,
  /// пересборка того же квеста обновляет уже установленный.
  static String defaultPackageFor(String questId) {
    var slug = questId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    slug = slug.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) slug = 'quest';
    if (!RegExp(r'^[a-z]').hasMatch(slug)) slug = 'q$slug';
    if (slug.length > 40) slug = slug.substring(0, 40);
    final candidate = 'sbs.meander.quest.$slug';
    return isValidPackageName(candidate) ? candidate : 'sbs.meander.quest.q$slug';
  }

  static String sanitizeFileName(String value) {
    var name = value.replaceAll(RegExp(r'[\\/*?:"<>|\x00-\x1F]'), '_').trim();
    if (name.toLowerCase().endsWith('.apk')) {
      name = name.substring(0, name.length - 4).trim();
    }
    return name.isEmpty ? 'quest' : name;
  }

  factory ApkBuildOptions.defaults({
    required String questId,
    required String questTitle,
    String? questVersion,
  }) {
    final title = questTitle.trim().isEmpty ? 'Meander Quest' : questTitle.trim();
    return ApkBuildOptions(
      fileName: sanitizeFileName(title),
      appName: title,
      packageName: defaultPackageFor(questId),
      versionName: (questVersion?.trim().isNotEmpty ?? false)
          ? questVersion!.trim()
          : '1.0.0',
    );
  }

  ApkBuildOptions copyWith({
    String? fileName,
    String? appName,
    String? packageName,
    String? versionName,
    int? versionCode,
    bool? protectContent,
    ApkSigningMode? signingMode,
    String? certCommonName,
    String? certOrganization,
    String? certCountry,
    int? certValidityYears,
    String? keystorePath,
    bool clearKeystore = false,
    String? storePassword,
    String? keyAlias,
    String? keyPassword,
    bool? v1,
    bool? v2,
    bool? v3,
    String? iconPath,
    bool clearIcon = false,
  }) {
    return ApkBuildOptions(
      fileName: fileName ?? this.fileName,
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      versionName: versionName ?? this.versionName,
      versionCode: versionCode ?? this.versionCode,
      protectContent: protectContent ?? this.protectContent,
      signingMode: signingMode ?? this.signingMode,
      certCommonName: certCommonName ?? this.certCommonName,
      certOrganization: certOrganization ?? this.certOrganization,
      certCountry: certCountry ?? this.certCountry,
      certValidityYears: certValidityYears ?? this.certValidityYears,
      keystorePath: clearKeystore ? null : (keystorePath ?? this.keystorePath),
      storePassword: storePassword ?? this.storePassword,
      keyAlias: keyAlias ?? this.keyAlias,
      keyPassword: keyPassword ?? this.keyPassword,
      v1: v1 ?? this.v1,
      v2: v2 ?? this.v2,
      v3: v3 ?? this.v3,
      iconPath: clearIcon ? null : (iconPath ?? this.iconPath),
    );
  }

  Map<String, Object?> toChannelArgs() => {
        'appName': appName.trim(),
        'packageName': packageName.trim(),
        'versionName': versionName.trim(),
        'versionCode': versionCode,
        'signingMode': signingMode.name,
        'certCommonName': certCommonName.trim(),
        'certOrganization': certOrganization.trim(),
        'certCountry': certCountry.trim(),
        'certValidityYears': certValidityYears,
        'keystorePath': keystorePath,
        'storePassword': storePassword,
        'keyAlias': keyAlias.trim(),
        'keyPassword': keyPassword,
        'v1': v1,
        'v2': v2,
        'v3': v3,
        'iconPath': iconPath,
      };

  Map<String, Object?> _toPrefsJson() => {
        'fileName': fileName,
        'appName': appName,
        'packageName': packageName,
        'versionName': versionName,
        'versionCode': versionCode,
        'protectContent': protectContent,
        'signingMode': signingMode.name,
        'certCommonName': certCommonName,
        'certOrganization': certOrganization,
        'certCountry': certCountry,
        'certValidityYears': certValidityYears,
        'keystorePath': keystorePath,
        'keyAlias': keyAlias,
        'v1': v1,
        'v2': v2,
        'v3': v3,
        'iconPath': iconPath,
      };

  ApkBuildOptions _mergePrefs(Map<String, dynamic> json) {
    String str(String key, String fallback) =>
        json[key] is String ? json[key] as String : fallback;
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    int number(String key, int fallback) =>
        json[key] is int ? json[key] as int : fallback;

    final savedKeystore = json['keystorePath'];
    final savedIcon = json['iconPath'];
    return ApkBuildOptions(
      fileName: str('fileName', fileName),
      appName: str('appName', appName),
      packageName: str('packageName', packageName),
      versionName: str('versionName', versionName),
      versionCode: number('versionCode', versionCode),
      protectContent: flag('protectContent', protectContent),
      signingMode: ApkSigningMode.values.firstWhere(
        (m) => m.name == json['signingMode'],
        orElse: () => signingMode,
      ),
      certCommonName: str('certCommonName', certCommonName),
      certOrganization: str('certOrganization', certOrganization),
      certCountry: str('certCountry', certCountry),
      certValidityYears: number('certValidityYears', certValidityYears),
      keystorePath: savedKeystore is String && File(savedKeystore).existsSync()
          ? savedKeystore
          : null,
      keyAlias: str('keyAlias', keyAlias),
      v1: flag('v1', v1),
      v2: flag('v2', v2),
      v3: flag('v3', v3),
      iconPath: savedIcon is String && File(savedIcon).existsSync()
          ? savedIcon
          : null,
    );
  }
}

class ApkBuildResult {
  final String packageName;
  final String certificateSha256;

  const ApkBuildResult({
    required this.packageName,
    required this.certificateSha256,
  });
}

/// Офлайн-сборка APK квеста прямо на устройстве (Android).
///
/// Нативная часть берёт вшитый в приложение APK плеера, подкладывает в него
/// `.mnd` квеста, правит манифест (имя, ID пакета, версия) и подписывает —
/// ключом устройства или своим keystore. Без сети и Flutter SDK.
class OfflineApkBuilder {
  OfflineApkBuilder._();

  static const MethodChannel _channel = MethodChannel('meander/offline_apk');
  static const String _prefsPrefix = 'apk_build_options_';

  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Настройки прошлой сборки этого квеста поверх значений по умолчанию.
  static Future<ApkBuildOptions> loadOptions({
    required String questId,
    required String questTitle,
    String? questVersion,
  }) async {
    final defaults = ApkBuildOptions.defaults(
      questId: questId,
      questTitle: questTitle,
      questVersion: questVersion,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$questId');
      if (raw == null) return defaults;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return defaults;
      return defaults._mergePrefs(json);
    } catch (_) {
      return defaults;
    }
  }

  static Future<void> _saveOptions(String questId, ApkBuildOptions options) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsPrefix$questId';
      String? previousIcon;
      try {
        final previous = jsonDecode(prefs.getString(key) ?? 'null');
        if (previous is Map && previous['iconPath'] is String) {
          previousIcon = previous['iconPath'] as String;
        }
      } catch (_) {}
      await prefs.setString(key, jsonEncode(options._toPrefsJson()));
      if (previousIcon != null && previousIcon != options.iconPath) {
        await deleteIcon(previousIcon);
      }
    } catch (_) {}
  }

  /// Копирует выбранный keystore в постоянное хранилище приложения —
  /// кэш file_picker система может очистить в любой момент.
  static Future<String> importKeystore(String sourcePath) async {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'keystores'),
    );
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, p.basename(sourcePath)));
    if (p.equals(target.path, sourcePath)) return target.path;
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  /// Копирует картинку иконки в постоянное хранилище. Имя каждый раз новое:
  /// иначе `FileImage` покажет из кэша прошлую картинку по тому же пути.
  static Future<String> importIcon(String sourcePath) async {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'apk_icons'),
    );
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).toLowerCase();
    final target = File(
      p.join(
        dir.path,
        'icon_${DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '.png' : ext}',
      ),
    );
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  /// Удаляет ранее импортированную иконку, если она лежит в хранилище приложения.
  static Future<void> deleteIcon(String? path) async {
    if (path == null) return;
    try {
      final dir = p.join((await getApplicationSupportDirectory()).path, 'apk_icons');
      if (!p.isWithin(dir, path)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<Map<Object?, Object?>> _invokeBuild(
    String questPath,
    String outputPath,
    ApkBuildOptions options,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>('build', {
        'questPath': questPath,
        'outputPath': outputPath,
        'options': options.toChannelArgs(),
      });
      return result ?? const {};
    } on PlatformException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Собирает APK и предлагает сохранить его. Возвращает `null`, если
  /// пользователь отменил сохранение.
  static Future<ApkBuildResult?> buildAndSave(
    String questId,
    ApkBuildOptions options,
  ) async {
    final questFile = await ExportService.createMndTempFile(
      questId,
      isProtected: options.protectContent,
    );
    final tempDir = await getTemporaryDirectory();
    final apkFile = File(
      p.join(tempDir.path, 'quest_${DateTime.now().millisecondsSinceEpoch}.apk'),
    );

    try {
      final raw = await _invokeBuild(questFile.path, apkFile.path, options);
      await _saveOptions(questId, options);

      final saved = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: apkFile.path,
          fileName: '${ApkBuildOptions.sanitizeFileName(options.fileName)}.apk',
        ),
      );
      if (saved == null) return null;
      return ApkBuildResult(
        packageName: raw['packageName'] as String? ?? options.packageName,
        certificateSha256: raw['certificateSha256'] as String? ?? '',
      );
    } finally {
      for (final f in [questFile, apkFile]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }
}
