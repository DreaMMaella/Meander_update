import 'package:canvas_app/core/services/post_media_service.dart';
import 'package:canvas_app/features/forums/providers/forum_provider.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/core/utils/error_text.dart';

/// Редактор топика: заголовок обязателен, тело — как в стене (тот же
/// markdown). Фото живёт в тексте картинкой `![подпись](ссылка)`: кнопка
/// загружает файл и подставляет ссылку, потому что скриншот к вопросу о баге
/// — обычный случай, а вставлять url руками никто не будет.
class ForumTopicComposerScreen extends ConsumerStatefulWidget {
  const ForumTopicComposerScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<ForumTopicComposerScreen> createState() =>
      _ForumTopicComposerScreenState();
}

class _ForumTopicComposerScreenState
    extends ConsumerState<ForumTopicComposerScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    // Кнопка «Опубликовать» читает текст полей прямо в build. Без подписки
    // экран не перерисовывается от набора, и кнопка навсегда остаётся серой —
    // выглядит как «публика не работает», хотя валидация проходит.
    _title.addListener(_onTextChanged);
    _body.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  bool get _ready =>
      _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty;

  Future<void> _attachPhoto() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final url = await PostMediaUpload.pickAndUpload();
      if (url != null) insertImageAtCursor(_body, url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(trf('Фото не прикреплено: {p0}', {'p0': friendlyError(e)}))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    final error = await ref
        .read(forumLobbyProvider(widget.slug).notifier)
        .addTopic(title: _title.text, body: _body.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      // Текст не выбрасываем: кулдаун и «нужно вступить» — это на несколько
      // секунд, а сочинение заново человек писать не обязан.
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

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(tr('Новое обсуждение')),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        actions: [
          IconButton(
            onPressed: _uploading || _busy ? null : _attachPhoto,
            tooltip: tr('Прикрепить фото'),
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _ready && !_busy ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Опубликовать')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          AdaptiveContent(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: _title,
                  maxLength: ForumLimits.maxTitleChars,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: tr('Заголовок'),
                    hintText: tr('О чём говорим'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _body,
                  maxLength: ForumLimits.maxBodyChars,
                  maxLines: null,
                  minLines: 6,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText:
                        tr('Тело обсуждения. Поддерживается markdown и #теги.'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Следующее обсуждение можно будет не сразу: пауза считается по всем постам, а не по одному сообществу.'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
