import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:canvas_app/shared/dialogs/show_app_dialog.dart';

/// Экраны действия и сервер живут без гостя: жалоба, лайк, отзыв или
/// публикация требуют сессии. Без проверки новичок либо получает сырой
/// «Ошибка: Unauthorized: {…}», либо заполняет обречённую форму целиком.
///
/// Возвращает true, если действие можно продолжать.
Future<bool> ensureAccount(BuildContext context, {required String why}) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return false;
  final token = prefs.getString('jwt_token');
  if (token != null && token.isNotEmpty) return true;
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr('Нужен аккаунт')),
      content: Text(why),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(tr('Понятно')),
        ),
      ],
    ),
  );
  return false;
}

/// Публикация в общий каталог: проверяем сессию на тапе, а не после сборки
/// файла и заполнения формы.
Future<bool> ensurePublishAccount(BuildContext context) => ensureAccount(
  context,
  why:
      tr('В общий каталог ресурсы добавляют авторы с аккаунтом. Войдите на вкладке «Вход» — и загрузка станет доступной.'),
);
