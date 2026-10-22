/// Общие утилиты форматирования дат — переиспользуются в маркете,
/// профиле, ленте постов и т.д.

import 'package:canvas_app/core/l10n/l10n.dart';

/// Русские подписи месяцев — язык-источник, `tr` подставляет слово текущего
/// языка. Переключатель, а не таблица: ключ перевода остаётся литералом,
/// поэтому его видят и сканер покрытия словарей, и guard-тест.
String monthShort(int month) => switch (month) {
  1 => tr('янв'),
  2 => tr('фев'),
  3 => tr('мар'),
  4 => tr('апр'),
  5 => tr('мая'),
  6 => tr('июн'),
  7 => tr('июл'),
  8 => tr('авг'),
  9 => tr('сен'),
  10 => tr('окт'),
  11 => tr('ноя'),
  _ => tr('дек'),
};

/// Дата сервера приходит в UTC. Календарные поля читаем уже в местном поясе:
/// иначе вечерний пост ложится на предыдущий день, а «в сети в 04:30»
/// читается как «в 01:30».
DateTime _local(DateTime date) => date.toLocal();

/// "12 мая 2025"
String formatDayMonthYear(DateTime date) {
  final value = _local(date);
  return '${value.day} ${monthShort(value.month)} ${value.year}';
}

/// "12 мая"
String formatDayMonth(DateTime date) {
  final value = _local(date);
  return '${value.day} ${monthShort(value.month)}';
}

/// "только что", "5 мин", "2 ч", "3 дн", "2 нед", "5 мес", "1 г"
String formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  if (diff.inSeconds < 5) return tr('только что');
  if (diff.inSeconds < 60) return trf('{n} сек', {'n': diff.inSeconds});
  if (diff.inMinutes < 60) return trf('{n} мин', {'n': diff.inMinutes});
  if (diff.inHours < 24) return trf('{n} ч', {'n': diff.inHours});
  if (diff.inDays < 7) return trf('{n} дн', {'n': diff.inDays});
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 5) return trf('{n} нед', {'n': weeks});
  final months = (diff.inDays / 30).floor();
  if (months < 12) return trf('{n} мес', {'n': months});
  final years = (diff.inDays / 365).floor();
  return trf('{n} г', {'n': years});
}

/// Длинная форма с "назад": "5 минут назад", "12 мая 2025"
String formatRelativeOrDate(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  if (diff.inMinutes < 1) return tr('только что');
  if (diff.inMinutes < 60) {
    return trf('{n} мин назад', {'n': diff.inMinutes});
  }
  if (diff.inHours < 24) return trf('{n} ч назад', {'n': diff.inHours});
  if (diff.inDays < 7) return trf('{n} дн назад', {'n': diff.inDays});
  return formatDayMonthYear(dateTime);
}

/// "Был(а) в сети: вчера в 15:30" или "В сети"
String formatLastSeen(DateTime? rawDate) {
  if (rawDate == null) return tr('Давно не заходил(а)');
  final date = _local(rawDate);

  final now = DateTime.now();
  final diff = now.difference(date);

  final clock =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  if (diff.inMinutes < 5) return tr('В сети');
  if (diff.inMinutes < 60) {
    return trf('Был(а) в сети {n} мин назад', {'n': diff.inMinutes});
  }
  if (diff.inHours < 24) {
    if (now.day == date.day) {
      return trf('Был(а) в сети сегодня в {clock}', {'clock': clock});
    } else {
      return trf('Был(а) в сети вчера в {clock}', {'clock': clock});
    }
  }
  if (diff.inDays == 1 && now.day != date.day) {
    return trf('Был(а) в сети вчера в {clock}', {'clock': clock});
  }
  return trf('Был(а) в сети {date}', {'date': formatDayMonthYear(date)});
}

/// Форматирует кол-во: 1.2k / 4
String formatCompactCount(int count) {
  // 999 999 после округления — это уже миллион: без переноса разряда
  // наружу лезло «1000.0k».
  if (count >= 995000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}k';
  }
  return count.toString();
}

/// "1ч 23м" / "23м" — для cooldown-таймеров и плейтайма
String formatDurationShort(Duration d) {
  if (d.inSeconds <= 0) return tr('0с');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return m > 0 ? trf('{h}ч {m}м', {'h': h, 'm': m}) : trf('{h}ч', {'h': h});
  }
  if (m > 0) {
    return s > 0 && m < 10
        ? trf('{m}м {s}с', {'m': m, 's': s})
        : trf('{m}м', {'m': m});
  }
  return trf('{s}с', {'s': s});
}
