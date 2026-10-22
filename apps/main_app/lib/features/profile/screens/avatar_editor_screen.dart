import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/config.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/features/profile/providers/profile_provider.dart';
import 'package:canvas_app/core/utils/error_text.dart';

const double kAvatarCropSide = 300;
const int kAvatarExportPx = 512;

/// Выбрать картинку и открыть кадрирование. Возвращает true, если аватар
/// сменился — вызывающий экран на это инвалидирует кэш профиля.
Future<bool> pickAndUploadAvatar(BuildContext context, String userId) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 90,
  );
  if (picked == null) return false;
  if (!context.mounted) return false;

  return await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AvatarEditorScreen(imagePath: picked.path, userId: userId),
        ),
      ) ??
      false;
}

class AvatarEditorScreen extends ConsumerStatefulWidget {
  const AvatarEditorScreen({
    super.key,
    required this.imagePath,
    required this.userId,
  });

  final String imagePath;
  final String userId;

  /// Квадрат кадрирования в пикселях исходной картинки. null — если пользователь
  /// уехал трансформацией так, что пересечения нет (тесты ловят это как границу).
  static Rect? cropSourceRect({
    required Size imageSize,
    required Size baseSize,
    required Matrix4 transform,
    required double side,
  }) {
    final drawn = Rect.fromLTWH(0, 0, baseSize.width, baseSize.height);
    final onScreen = MatrixUtils.transformRect(transform, drawn);
    final viewport = Rect.fromLTWH(0, 0, side, side);
    if (!onScreen.overlaps(viewport)) return null;
    final visible = viewport.intersect(onScreen);
    if (visible.width < 1 || visible.height < 1) return null;

    double px(double x) =>
        (x - onScreen.left) / onScreen.width * imageSize.width;
    double py(double y) =>
        (y - onScreen.top) / onScreen.height * imageSize.height;

    return Rect.fromLTRB(
      px(visible.left),
      py(visible.top),
      px(visible.right),
      py(visible.bottom),
    );
  }

  @override
  ConsumerState<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends ConsumerState<AvatarEditorScreen> {
  final TransformationController _transform = TransformationController();
  ui.Image? _image;
  Size _base = Size.zero;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (!mounted) return;
      // Картинка заполняет квадрат целиком (cover) — кадрирование начинается
      // без пустых углов, остаётся только сдвиг и зум.
      final scale =
          kAvatarCropSide /
          (image.width > image.height ? image.height : image.width);
      setState(() {
        _image = image;
        _base = Size(image.width * scale, image.height * scale);
      });
      _centerInitial();
    } catch (_) {
      if (mounted) setState(() => _error = tr('Не удалось открыть эту картинку'));
    }
  }

  void _centerInitial() {
    _transform.value = Matrix4.identity()
      ..translate(
        -(_base.width - kAvatarCropSide) / 2,
        -(_base.height - kAvatarCropSide) / 2,
      );
  }

  Future<Uint8List?> _export() async {
    final image = _image;
    if (image == null) return null;
    final src = AvatarEditorScreen.cropSourceRect(
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      baseSize: _base,
      transform: _transform.value,
      side: kAvatarCropSide,
    );
    if (src == null) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(
        0,
        0,
        kAvatarExportPx.toDouble(),
        kAvatarExportPx.toDouble(),
      ),
      paint,
    );
    final rendered = await recorder.endRecording().toImage(
      kAvatarExportPx,
      kAvatarExportPx,
    );
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    return data?.buffer.asUint8List();
  }

  Future<String> _upload(Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    // Multipart нельзя гонять через ApiService — путь собираем вручную, и
    // префикс здесь тот же, что у `$baseUrl/$endpoint` в api_service.dart.
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${AppConfig.apiUrl}/profiles/me/avatar'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            // Тип части указываем явно: редактор всегда пересобирает кадр в
            // PNG-байты, а `MultipartFile.fromBytes` без contentType шлёт
            // `application/octet-stream`, которое серверный fileFilter режет
            // как «не картинка» — какой бы файл ни выбрали в галерее.
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: 'avatar.png',
              contentType: http.MediaType('image', 'png'),
            ),
          );

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_reasonFrom(body, response.statusCode));
    }
    final decoded = jsonDecode(body);
    return (decoded is Map ? decoded['avatar_url'] : null)?.toString() ?? '';
  }

  /// Причина отказа приходит с сервера по-русски — показываем её как есть,
  /// иначе «422» выглядит как упавшее приложение.
  String _reasonFrom(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return trf('Аватар не загружен (код {p0})', {'p0': status});
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _export();
      if (bytes == null) {
        throw Exception(
          tr('Слишком сильно отодвинули картинку — верните её в квадрат'),
        );
      }
      await _upload(bytes);
      ref.invalidate(userProfileProvider(widget.userId));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _image != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Новый аватар')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: ready && !_busy ? _save : null,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(tr('Поставить')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ready
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(
                          kAvatarCropSide / 2,
                        ),
                        child: SizedBox(
                          width: kAvatarCropSide,
                          height: kAvatarCropSide,
                          child: ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: InteractiveViewer(
                              transformationController: _transform,
                              boundaryMargin: EdgeInsets.zero,
                              minScale: 1,
                              maxScale: 5,
                              child: SizedBox(
                                width: _base.width,
                                height: _base.height,
                                child: RawImage(
                                  image: _image,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : (_error == null
                          ? const CircularProgressIndicator()
                          : Text(
                              _error!,
                              style: TextStyle(color: scheme.error),
                            )),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text(
                tr('Двигайте и приближайте. Картинку никто не перепроверяет: аватар сразу увидят все, и на него можно пожаловаться.'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (_error != null && ready)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
