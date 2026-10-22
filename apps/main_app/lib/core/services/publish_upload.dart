/// Чистая логика публикации квеста: лимиты, честный прогресс отправки и
/// перевод кода отказа в понятную строку.
///
/// Причина выноса: экран публикации раньше «знал» про лимиты только из
/// английского текста ошибки, а прогресс — из таймера на 4 секунды. Человек
/// видел 99% и ждал, пока сервер честно скажет «нельзя», хотя размер пакета
/// был известен клиенту ДО отправки.
library;

import 'package:canvas_app/core/l10n/l10n.dart';
import 'package:http/http.dart' as http;

/// Multipart с отсчётом отправленных байтов.
///
/// У `package:http` нет `onSendProgress`: прогресс загрузки виден только если
/// считать байты самого тела. [onSent] вызывается на каждый чанк — уже после
/// того, как он ушёл в транспорт.
class ProgressMultipartRequest extends http.MultipartRequest {
  ProgressMultipartRequest(super.method, super.url, this.onSent);

  final void Function(int sentBytes, int totalBytes)? onSent;

  @override
  http.ByteStream finalize() {
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(
      super.finalize().map((chunk) {
        sent += chunk.length;
        onSent?.call(sent, total);
        return chunk;
      }),
    );
  }
}

/// Лимиты совпадают с backend/src/services/publish_errors.ts.
class PublishLimits {
  static const int regularBytes = 100 * 1024 * 1024;
  static const int verifiedBytes = 500 * 1024 * 1024;

  static int forVerified(bool isVerified) =>
      isVerified ? verifiedBytes : regularBytes;

  static String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}

/// Отсев до загрузки.
///
/// Сервер узнаёт о превышении лимита, только когда байты уже доехали: при
/// 200 МБ это минута ожидания ради отказа. Здесь тот же отказ считается по
/// локальному размеру пакета.
String? preflightSizeRejection(int sizeBytes, bool isVerified) {
  final limitBytes = PublishLimits.forVerified(isVerified);
  if (sizeBytes <= limitBytes) return null;
  final buffer = isVerified
      ? tr('Убери лишнее из ресурсов квеста — картинки, звук и видео занимают больше всего места.')
      : tr('С лимитом верифицированного автора (500 МБ) такой пакет опубликуется — запроси верификацию в профиле.');
  return trf(
    'Пакет квеста весит {p0} МБ, а лимит {p1} — {p2} МБ. Загрузку не начинаем: сервер отклонил бы её в конце. {p3}',
    {
      'p0': PublishLimits.mb(sizeBytes),
      'p1': isVerified
          ? tr('верифицированного автора')
          : tr('обычного автора'),
      'p2': PublishLimits.mb(limitBytes),
      'p3': buffer,
    },
  );
}

/// Доля отправленного пакета, 0..1. `null` — если сервер/транспорт не назвал
/// полный размер: тогда показываем неопределённую шкалу, а не выдуманную.
double? sentFraction(int sent, int total) {
  if (total <= 0 || sent < 0) return null;
  return (sent / total).clamp(0.0, 1.0);
}

/// Сообщение по ответу сервера.
///
/// Ключ — поле `code` (backend/src/services/publish_errors.ts): по нему клиент
/// отличает свою вину от поломки сервера. Возвращает `null`, если кода нет или
/// он незнаком — вызывающий тогда разбирает старый текстовый ответ.
String? describePublishFailure(Map<String, dynamic> body, int statusCode) {
  final code = body['code'];
  if (code is! String) {
    // Прод до пересборки отвечает без кодов — не оставляем человека с голым
    // статусом.
    if (statusCode == 401) {
      return tr('Сессия истекла. Перезайди в аккаунт и опубликуй заново.');
    }
    return null;
  }
  switch (code) {
    case 'file_too_large':
      final sizeMb = _asDouble(body['size_mb']);
      final limitMb = _asDouble(body['limit_mb']);
      if (sizeMb == null || limitMb == null) {
        return tr('Пакет квеста больше разрешённого размера.');
      }
      return trf(
        'Сервер принял {p0} МБ при лимите {p1} МБ. Больше всего места занимают картинки, звук и видео — начни с них.',
        {
          'p0': sizeMb.toStringAsFixed(1),
          'p1': limitMb.toStringAsFixed(0),
        },
      );
    case 'quest_file_required':
      return tr('Файл квеста не дошёл до сервера — похоже, связь оборвалась во время загрузки. Публикацию не записали, попробуй ещё раз.');
    case 'quest_owned_by_other_author':
      return tr('У этого квеста уже есть публикация другого автора: он создан как копия из маркета и сохранил её идентификатор. Публиковать нужно под новым идентификатором — тогда твоя работа встанет отдельно и не заденет чужую.');
    case 'duplicate_file':
      return tr('Такой файл уже лежит в магазине у другого автора. Измени содержание и опубликуй заново.');
    case 'archive_unreadable':
      return tr('Сервер не смог разобрать пакет. Обычно это обрыв при сборке .mnd: пересобери квест (сохрани и выйди из редактора) и опубликуй заново.');
    case 'content_policy_violation':
      final reason = body['reason'];
      return trf(
        'Публикация отклонена по правилам магазина: {p0}.\nРабота осталась у тебя в черновиках — правки можно внести и опубликовать снова.',
        {
          'p0': (reason is String && reason.trim().isNotEmpty)
              ? reason.trim()
              : tr('см. описание правил'),
        },
      );
    case 'publish_failed':
      return tr('Сервер не смог обработать публикацию. Это не твоя ошибка: попробуй позже, если повторяется — напиши в поддержку.');
    default:
      return null;
  }
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
