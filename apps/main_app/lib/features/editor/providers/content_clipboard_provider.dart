import 'package:canvas_app/models/content_item_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Провайдер, хранящий скопированный элемент контента.
/// Если null - буфер пуст.
final contentClipboardProvider = StateProvider<ContentItem?>((ref) => null);
