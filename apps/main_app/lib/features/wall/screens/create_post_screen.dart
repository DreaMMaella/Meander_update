import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:canvas_app/core/services/api_service.dart';
import 'package:canvas_app/core/services/post_media_service.dart';
import 'package:canvas_app/core/utils/error_text.dart';
import 'package:canvas_app/features/wall/providers/wall_paginated_provider.dart';
import 'package:canvas_app/models/wall_post_model.dart';
import 'package:canvas_app/providers/wall_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_app/shared/widgets/app_markdown_config.dart';
import 'package:canvas_app/shared/entity_links/entity_ref_card.dart';
import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/widgets/adaptive_ui.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  final WallPost? postToEdit;

  const CreatePostScreen({super.key, this.postToEdit});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isPosting = false;
  bool _isPreviewMode = false;
  bool _isUploadingImage = false;
  
  // Мы оставляем existingImages только для обратной совместимости при редактировании старых постов
  final List<String> _existingImages = [];

  @override
  void initState() {
    super.initState();
    if (widget.postToEdit != null) {
      _controller.text = widget.postToEdit!.content;
      _existingImages.addAll(widget.postToEdit!.mediaUrls);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    setState(() => _isUploadingImage = true);
    try {
      final url = await PostMediaUpload.pickAndUpload();
      if (url != null) insertImageAtCursor(_controller, url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(trf('Ошибка загрузки фото: {p0}', {'p0': friendlyError(e)}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty && _existingImages.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final authorId = prefs.getString('user_id');
      if (authorId == null) throw Exception('Not authorized');

      if (widget.postToEdit != null) {
        await ref.read(wallNotifierProvider.notifier).editPost(
              widget.postToEdit!.authorId,
              widget.postToEdit!.id,
              content,
              _existingImages, // Старые картинки сохраняем, если были
            );
        
        final updatedPost = widget.postToEdit!.copyWith(
          content: content,
          mediaUrls: _existingImages,
        );
        ref.read(wallPaginatedProvider(widget.postToEdit!.authorId).notifier).updatePostLocally(updatedPost);
      } else {
        final api = ref.read(apiServiceProvider);
        await api.post(
          'api/author-walls/$authorId/posts',
          body: {
            'content': content,
            'media_urls': [], // Новые посты хранят фото только в Markdown
          },
        );
        ref.read(wallPaginatedProvider(authorId).notifier).loadPosts();
      }
      
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: scheme.errorContainer,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = (_controller.text.trim().isNotEmpty || _existingImages.isNotEmpty) && !_isPosting && !_isUploadingImage;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.postToEdit != null ? tr('Редактирование') : tr('Новый пост')),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonal(
              onPressed: canSubmit ? _submit : null,
              child: _isPosting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Отправить')),
            ),
          ),
        ],
      ),
      body: AdaptiveContent(maxWidth: 760, child: Column(
        children: [
          Container(
            color: scheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isPreviewMode = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: !_isPreviewMode ? scheme.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          tr('Редактирование'),
                          style: TextStyle(
                            color: !_isPreviewMode ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: !_isPreviewMode ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      _focusNode.unfocus();
                      setState(() => _isPreviewMode = true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _isPreviewMode ? scheme.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          tr('Предпросмотр'),
                          style: TextStyle(
                            color: _isPreviewMode ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: _isPreviewMode ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _isPreviewMode 
                  ? _buildPreview(scheme)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: null,
                          minLines: 5,
                          style: TextStyle(fontSize: 16, color: scheme.onSurface),
                          decoration: InputDecoration(
                            hintText: tr('Что у вас нового? (Поддерживается Markdown и #теги)'),
                            hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        if (_existingImages.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _existingImages.map((url) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      url,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _existingImages.remove(url);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                      ],
                    ),
            ),
          ),
          if (!_isPreviewMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isUploadingImage ? null : _pickAndUploadImage,
                    icon: _isUploadingImage 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                        : const Icon(Icons.image_outlined),
                    color: scheme.primary,
                    tooltip: tr('Вставить картинку'),
                  ),
                  const Spacer(),
                  Text(
                    tr('Поддерживается Markdown'),
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  )
                ],
              ),
            ),
        ],
      )),
    );
  }

  Widget _buildPreview(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_controller.text.trim().isNotEmpty)
          MeanderEntityMarkdown(
            data: _controller.text.trim(),
            config: AppMarkdown.getConfig(context),
          ),
        if (_existingImages.isNotEmpty) ...[
          if (_controller.text.trim().isNotEmpty) const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _existingImages.map((url) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              );
            }).toList(),
          ),
        ],
        if (_controller.text.trim().isEmpty && _existingImages.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                tr('Предпросмотр пуст'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}
