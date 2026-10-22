// Регрессия #205: фон-видео ноды на Linux рисовало сплошной синевой вместо
// кадра (пиксель (0,13,127) — неинициализированная GL-текстура).
//
// Причина не в нашем коде: media_kit_video <= 1.3.1 создавал GdkGLContext и не
// делал его current перед `mpv_render_context_create`, а Flutter >= 3.38 живёт
// на собственном EGL-контексте. Кадр в текстуру не записывался вообще. Починка
// приехала только в 2.0.1 (upstream #1290, #1325): EGL + `eglCreateImageKHR`,
// GPU-to-GPU передача буфера.
//
// Саму GL-текстуру из Dart-теста не увидеть — её рисует нативный плагин в
// процессе. Проверяем то, что наблюдаемо из теста: версию пакета, из которого
// CMake соберёт Linux-плагин, и наличие в нём EGL-пути.
//
// Негативный контроль: на 1.3.1 проверка `eglCreateImageKHR` падает — в её
// linux/texture_gl.cc этого вызова нет ни одного (в 2.0.1 — четыре).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Каталог пакета, который реально уйдёт в сборку. `flutter build linux`
/// компилирует плагины по разрешению приложения, поэтому начинаем с
/// `apps/main_app`, а собственная паковка — только запасной вариант.
String? _packageDir(String root, String packageName) {
  for (final cfg in [
    '$root/apps/main_app/.dart_tool/package_config.json',
    '$root/.dart_tool/package_config.json',
  ]) {
    final file = File(cfg);
    if (!file.existsSync()) continue;
    final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final packages = (map['packages'] as List).cast<Map<String, dynamic>>();
    for (final entry in packages) {
      if (entry['name'] != packageName) continue;
      final rootUri = Uri.parse(entry['rootUri'] as String);
      final path = rootUri.toFilePath();
      final dir = rootUri.scheme == 'file'
          ? path
          : Uri.file(cfg).resolve(rootUri.toString()).toFilePath();
      return dir.endsWith('/') ? dir : '$dir/';
    }
  }
  return null;
}

String? _repoRoot() {
  Directory? dir = Directory.current;
  for (var hops = 0; hops < 6 && dir != null; hops++) {
    if (File('${dir.path}/apps/main_app/pubspec.yaml').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return null;
}

/// `1.3.1` < `2.0.1` — по числам, без внешних пакетов.
int _cmpVersion(String a, String b) {
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0;
    final yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi.compareTo(yi);
  }
  return 0;
}

String _versionOf(String dir) {
  final pubspec = File('${dir}pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec);
  return match?.group(1) ?? '0.0.0';
}

void main() {
  final root = _repoRoot();

  group('видео-фон ноды на Linux', () {
    test('плагин берётся из media_kit_video >= 2.0.1 с EGL-передачей кадра', () {
      if (root == null) {
        markTestSkipped('вне монорепозитория — проверять нечего');
        return;
      }
      final videoDir = _packageDir(root, 'media_kit_video');
      if (videoDir == null) {
        markTestSkipped('flutter pub get не выполнялся, разрешения нет');
        return;
      }

      final version = _versionOf(videoDir);
      expect(
        _cmpVersion(version, '2.0.1') >= 0,
        isTrue,
        reason:
            'media_kit_video $version ($videoDir): на Linux до 2.0.1 '
            'аппаратный рендер сломан — GL-контекст не делается current, '
            'фон-видео даёт синюю текстуру',
      );

      final textureGl = File(
        '${videoDir}linux/texture_gl.cc',
      ).readAsStringSync();
      expect(
        textureGl,
        contains('eglCreateImageKHR'),
        reason:
            'в texture_gl.cc нет EGLImage-пути — это пред-2.0.1 код, '
            'который и рисовал синеву',
      );
      // Make-current до mpv_render_context_create — та же причина на стороне
      // контекста, а не текстуры.
      expect(textureGl, contains('eglMakeCurrent'));
      final videoOutput = File(
        '${videoDir}linux/video_output.cc',
      ).readAsStringSync();
      expect(videoOutput, contains('eglMakeCurrent'));

      // 2.0.1 требует media_kit ^1.2.3; пара «старый media_kit + новый плагин»
      // — другой класс поломок.
      final mediaKitDir = _packageDir(root, 'media_kit');
      if (mediaKitDir != null) {
        final mk = _versionOf(mediaKitDir);
        expect(
          _cmpVersion(mk, '1.2.3') >= 0,
          isTrue,
          reason: 'media_kit $mk ниже нижней планки, которую требует 2.0.1',
        );
      }
    });

    test('сборка Linux без mpv не зависит от латки в ~/.pub-cache', () {
      if (root == null) {
        markTestSkipped('вне монорепозитория — проверять нечего');
        return;
      }
      final videoDir = _packageDir(root, 'media_kit_video');
      if (videoDir == null) {
        markTestSkipped('flutter pub get не выполнялся, разрешения нет');
        return;
      }
      final pluginCmake = File(
        '${videoDir}linux/CMakeLists.txt',
      ).readAsStringSync();
      final appCmake = File(
        '$root/apps/main_app/linux/CMakeLists.txt',
      ).readAsStringSync();

      // Свежая (непролатанная) версии плагина не важно, есть ли libmpv: она
      // линкует mpv/epoxy безусловно, и без них конфигурация падает. Право на
      // жизнь сборке на машине без mpv даёт только явный OFF в CMakeLists
      // приложения — он обязан остаться.
      if (!pluginCmake.contains('mpv_FOUND')) {
        expect(
          appCmake,
          contains('set(MEDIA_KIT_LIBS_AVAILABLE OFF'),
          reason:
              'плагин линкует mpv/epoxy безусловно, а приложение больше не '
              'выключает MEDIA_KIT_LIBS_AVAILABLE: сборка без libmpv упадёт '
              '(или кто-то снова залатает копию пакета в pub-cache)',
        );
      }
    });
  });
}
