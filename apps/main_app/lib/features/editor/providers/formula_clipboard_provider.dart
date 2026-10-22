import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Провайдер, хранящий скопированную формулу.
/// Если null - буфер пуст.
final formulaClipboardProvider = StateProvider<String?>((ref) => null);
